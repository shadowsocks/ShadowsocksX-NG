import Darwin
import XCTest

@testable import ShadowsocksX_NG2

final class RuntimePublicationSmokeTests: RealSslocalSmokeTests {
  func testStableConfigLinkReloadChangesActualProxyEgressWithoutReplacingChild() throws {
    let firstExit = try ConnectionCountingServer()
    let secondExit = try ConnectionCountingServer()
    let ports = try grabThreeListenPorts(excluding: [firstExit.port, secondExit.port])
    let listen = ProxyListeningConfiguration(socksPort: ports[0], httpPort: ports[1])
    func document(_ port: Int) -> SslocalRuntimeDocument {
      SslocalRuntimeDocument(
        servers: [
          .init(
            id: "reload", server: "127.0.0.1", serverPort: port,
            password: "smoke", method: "aes-256-gcm", plugin: nil, pluginOpts: nil)
        ], listen: listen, acl: .global(at: aclFileURL))
    }
    let first = document(firstExit.port)
    let wrapper = try launchWrapper(first)
    try assertReceiptOwnsListeners(document: first)
    let store = RuntimeFileStore(fileURL: contractURL)
    let pid = try XCTUnwrap(store.readRuntimeReceipt()?.processID)
    try assertPublicTargetsProxy(listen: listen, fakeSS: firstExit)
    let before = firstExit.connectionCount
    let next = document(secondExit.port)
    try store.write(next)
    XCTAssertEqual(kill(wrapper.processIdentifier, SIGUSR1), 0)
    try assertReceiptOwnsListeners(document: next)
    XCTAssertEqual(store.readRuntimeReceipt()?.processID, pid)
    // Receipt is only Agent evidence. Actual requests must use the second exit.
    XCTAssertTrue(
      try waitForCondition(timeout: 8) {
        self.performHTTPConnect(httpPort: listen.httpPort, targetHost: "8.8.8.8", targetPort: 53)
        return secondExit.connectionCount > 0
      })
    try assertPublicTargetsProxy(listen: listen, fakeSS: secondExit)
    XCTAssertLessThanOrEqual(firstExit.connectionCount, before + 1)
    stopWrapperAndAssertCleanExit(wrapper, description: "reload wrapper exits")
  }

  func testLargeACLReuseAndModeReloadWithoutReplacingChild() throws {
    let echo = try LoopbackEchoServer()
    let proxy = try ConnectionCountingServer()
    let ports = try grabThreeListenPorts(excluding: [echo.port, proxy.port])
    let listen = ProxyListeningConfiguration(socksPort: ports[0], httpPort: ports[1])
    let large = ProxyACLDocument(
      path: aclFileURL.path, summary: "rule-proxy-default",
      content: "[proxy_all]\n[bypass_list]\n"
        + (0..<20000).map { "||unused-\($0).example\n" }.joined())
    let source = SslocalRuntimeDocument(
      servers: [
        .init(
          id: "acl", server: "127.0.0.1", serverPort: proxy.port,
          password: "smoke", method: "aes-256-gcm", plugin: nil, pluginOpts: nil)
      ], listen: listen, acl: large)
    let wrapper = try launchWrapper(source)
    let store = RuntimeFileStore(fileURL: contractURL)
    try assertReceiptOwnsListeners(document: source)
    let snapshot = try XCTUnwrap(RuntimePublication.load(at: store.supervisionFileURL))
    let acl = try XCTUnwrap(snapshot.acl)
    let aclURL = workDir.appendingPathComponent(acl.file)
    let inode =
      try FileManager.default.attributesOfItem(atPath: aclURL.path)[.systemFileNumber] as? NSNumber
    try assertACLModeReloads(
      ACLModeReloadContext(
        wrapper: wrapper, store: store, source: source, listen: listen,
        echo: echo, proxy: proxy, acl: acl, aclURL: aclURL, inode: inode, large: large))
    stopWrapperAndAssertCleanExit(wrapper, description: "mode wrapper exits")
  }

  private func assertACLModeReloads(_ context: ACLModeReloadContext) throws {
    let wrapper = context.wrapper
    let store = context.store
    let source = context.source
    let listen = context.listen
    let echo = context.echo
    let proxy = context.proxy
    let acl = context.acl
    let aclURL = context.aclURL
    let inode = context.inode
    let large = context.large
    for _ in 0..<2 {
      let oldPID = try XCTUnwrap(store.readRuntimeReceipt()?.processID)
      let direct = source.replacingACL(.direct(at: aclFileURL))
      try store.write(direct)
      XCTAssertEqual(kill(wrapper.processIdentifier, SIGUSR1), 0)
      try assertReceiptOwnsListeners(document: direct)
      XCTAssertEqual(store.readRuntimeReceipt()?.processID, oldPID)
      // 回执不证明上游已应用 ACL；实际路由收敛后再验证两个入口。
      XCTAssertTrue(
        try waitForCondition(timeout: 8) {
          self.performSocksConnectReply(
            socksPort: listen.socksPort, targetHost: "127.0.0.1", targetPort: echo.port) == 0
        })
      let payload = Array("direct\n".utf8)
      XCTAssertEqual(
        try performDirectSocksEcho(
          socksPort: listen.socksPort, targetPort: echo.port, payload: payload), payload)
      XCTAssertEqual(
        try performDirectHTTPEcho(
          httpPort: listen.httpPort, targetPort: echo.port, payload: payload), payload)
      try store.write(source)
      XCTAssertEqual(kill(wrapper.processIdentifier, SIGUSR1), 0)
      try assertReceiptOwnsListeners(document: source)
      XCTAssertEqual(store.readRuntimeReceipt()?.processID, oldPID)
      let before = proxy.connectionCount
      XCTAssertTrue(
        try waitForCondition(timeout: 8) {
          self.performHTTPConnect(
            httpPort: listen.httpPort, targetHost: "127.0.0.1", targetPort: echo.port)
          return proxy.connectionCount > before
        })
      try assertPublicTargetsProxy(listen: listen, fakeSS: proxy)
      XCTAssertEqual(RuntimePublication.load(at: store.supervisionFileURL)?.acl, acl)
      XCTAssertEqual(
        try FileManager.default.attributesOfItem(atPath: aclURL.path)[.systemFileNumber]
          as? NSNumber, inode)
      XCTAssertEqual(try Data(contentsOf: aclURL), Data(large.content.utf8))
    }
  }

  func testCombinedServerAndRuleReloadAndDefaultActionChangesKeepChild() throws {
    let echo = try LoopbackEchoServer()
    let firstExit = try ConnectionCountingServer()
    let secondExit = try ConnectionCountingServer()
    let ports = try grabThreeListenPorts(excluding: [echo.port, firstExit.port, secondExit.port])
    let listen = ProxyListeningConfiguration(socksPort: ports[0], httpPort: ports[1])
    let source = ruleProbeDocument(
      port: firstExit.port, listen: listen,
      acl: ruleProbeACL(defaultAction: .directWhenUnmatched, rules: []))
    let wrapper = try launchWrapper(source)
    let store = RuntimeFileStore(fileURL: contractURL)
    try assertReceiptOwnsListeners(document: source)
    let pid = try assertRuleInsertionAndRemoval(
      wrapper: wrapper, store: store, listen: listen, echo: echo, secondExit: secondExit)
    try assertRuleDefaultActionReloads(
      RuleReloadContext(
        wrapper: wrapper, store: store, listen: listen, echo: echo,
        secondExit: secondExit, processID: pid))
    stopWrapperAndAssertCleanExit(wrapper, description: "rule reload wrapper exits")
  }

  private func ruleProbeDocument(
    port: Int, listen: ProxyListeningConfiguration, acl: ProxyACLDocument
  ) -> SslocalRuntimeDocument {
    SslocalRuntimeDocument(
      servers: [
        .init(
          id: "rules", server: "127.0.0.1", serverPort: port,
          password: "smoke", method: "aes-256-gcm", plugin: nil, pluginOpts: nil)
      ], listen: listen, acl: acl)
  }

  private func assertRuleInsertionAndRemoval(
    wrapper: Process, store: RuntimeFileStore, listen: ProxyListeningConfiguration,
    echo: LoopbackEchoServer, secondExit: ConnectionCountingServer
  ) throws -> Int {
    let processID = try XCTUnwrap(store.readRuntimeReceipt()?.processID)
    let custom = ruleProbeDocument(
      port: secondExit.port, listen: listen,
      acl: ruleProbeACL(
        defaultAction: .directWhenUnmatched,
        rules: [ProxyRule(action: .proxy, match: try RuleMatch(domainSuffix: "blocked.example"))]))
    try store.write(custom)
    XCTAssertEqual(kill(wrapper.processIdentifier, SIGUSR1), 0)
    try assertReceiptOwnsListeners(document: custom)
    XCTAssertTrue(
      try waitForCondition(timeout: 8) {
        self.performHTTPConnect(
          httpPort: listen.httpPort, targetHost: "blocked.example", targetPort: echo.port)
        return secondExit.connectionCount > 0
      })
    XCTAssertEqual(store.readRuntimeReceipt()?.processID, processID)

    let removed = ruleProbeDocument(
      port: secondExit.port, listen: listen,
      acl: ruleProbeACL(defaultAction: .directWhenUnmatched, rules: []))
    try store.write(removed)
    XCTAssertEqual(kill(wrapper.processIdentifier, SIGUSR1), 0)
    try assertReceiptOwnsListeners(document: removed)
    XCTAssertTrue(
      try waitForCondition(timeout: 8) {
        self.performSocksConnectReply(
          socksPort: listen.socksPort, targetHost: "blocked.example", targetPort: echo.port) == 0
      })
    let payload = Array("reloaded rule\n".utf8)
    XCTAssertEqual(
      try performDirectHTTPEcho(
        httpPort: listen.httpPort, targetHost: "blocked.example", targetPort: echo.port,
        payload: payload), payload)
    return processID
  }

  private func assertRuleDefaultActionReloads(_ context: RuleReloadContext) throws {
    let wrapper = context.wrapper
    let store = context.store
    let listen = context.listen
    let echo = context.echo
    let secondExit = context.secondExit
    let processID = context.processID
    for (acl, proxiesDomain) in [
      (ruleProbeACL(defaultAction: .proxyWhenUnmatched, rules: []), true),
      (ProxyACLDocument.global(at: aclFileURL), false),
    ] {
      let next = ruleProbeDocument(port: secondExit.port, listen: listen, acl: acl)
      let before = secondExit.connectionCount
      try store.write(next)
      XCTAssertEqual(kill(wrapper.processIdentifier, SIGUSR1), 0)
      try assertReceiptOwnsListeners(document: next)
      XCTAssertTrue(
        try waitForCondition(timeout: 8) {
          if proxiesDomain {
            self.performHTTPConnect(
              httpPort: listen.httpPort, targetHost: "blocked.example", targetPort: echo.port)
            return secondExit.connectionCount > before
          }
          return self.performSocksConnectReply(
            socksPort: listen.socksPort, targetHost: "blocked.example", targetPort: echo.port) == 0
        })
      XCTAssertEqual(store.readRuntimeReceipt()?.processID, processID)
    }
  }

}

private struct ACLModeReloadContext {
  let wrapper: Process
  let store: RuntimeFileStore
  let source: SslocalRuntimeDocument
  let listen: ProxyListeningConfiguration
  let echo: LoopbackEchoServer
  let proxy: ConnectionCountingServer
  let acl: RuntimePublication.ACL
  let aclURL: URL
  let inode: NSNumber?
  let large: ProxyACLDocument
}

private struct RuleReloadContext {
  let wrapper: Process
  let store: RuntimeFileStore
  let listen: ProxyListeningConfiguration
  let echo: LoopbackEchoServer
  let secondExit: ConnectionCountingServer
  let processID: Int32
}

extension RuntimePublicationSmokeTests {
  func testRejectedACLReloadKeepsPreviousRulesWithoutReplacingChild() throws {
    let echo = try LoopbackEchoServer()
    let ports = try grabThreeListenPorts(excluding: [echo.port])
    let listen = ProxyListeningConfiguration(socksPort: ports[0], httpPort: ports[1])
    let source = SslocalRuntimeDocument(
      servers: [], listen: listen, acl: .direct(at: aclFileURL))
    let wrapper = try launchWrapper(source)
    let store = RuntimeFileStore(fileURL: contractURL)
    try assertReceiptOwnsListeners(document: source)
    let pid = try XCTUnwrap(store.readRuntimeReceipt()?.processID)
    let next = source.replacingACL(
      ruleProbeACL(defaultAction: .proxyWhenUnmatched, rules: []))
    try store.write(next)
    let snapshot = try XCTUnwrap(RuntimePublication.load(at: store.supervisionFileURL))
    let acl = try XCTUnwrap(snapshot.acl)
    // 模拟发布后磁盘损坏；上游解析拒绝，Agent 回执无法识别这种内部失败。
    try AtomicFileWriter.write(Data("[\n".utf8), to: workDir.appendingPathComponent(acl.file))
    XCTAssertEqual(kill(wrapper.processIdentifier, SIGUSR1), 0)
    XCTAssertTrue(
      try waitForCondition(timeout: 8) {
        let log = try String(contentsOf: self.workDir.appendingPathComponent("agent.log"))
        return log.contains("ACL reload failed") && log.contains("keeping the previous rules")
      })
    try assertReceiptOwnsListeners(document: next)
    XCTAssertEqual(store.readRuntimeReceipt()?.processID, pid)
    XCTAssertNil(store.readFailure())
    let payload = Array("previous rules\n".utf8)
    XCTAssertEqual(
      try performDirectSocksEcho(
        socksPort: listen.socksPort, targetPort: echo.port, payload: payload), payload)
    stopWrapperAndAssertCleanExit(wrapper, description: "rejected ACL wrapper exits")
  }

  func testHealthyCrashReplaysCurrentDeploymentAndRecoveryFailureDoesNotLoop() throws {
    let ports = try grabThreeListenPorts(excluding: [])
    let document = SslocalRuntimeDocument(
      servers: [],
      listen: ProxyListeningConfiguration(socksPort: ports[0], httpPort: ports[1]),
      acl: .direct(at: aclFileURL))
    let wrapper = try launchWrapper(document)
    try assertReceiptOwnsListeners(document: document)
    let store = RuntimeFileStore(fileURL: contractURL)
    let oldPID = try XCTUnwrap(store.readRuntimeReceipt()?.processID)
    XCTAssertEqual(kill(oldPID, SIGKILL), 0)
    XCTAssertTrue(
      try waitForCondition(timeout: 10) {
        guard let receipt = store.readRuntimeReceipt() else { return false }
        return receipt.processID != oldPID
          && RuntimeSocketOwnershipProbe.process(receipt.processID, ownsTCPListenerOn: ports[0])
      })
    let recoveredPID = try XCTUnwrap(store.readRuntimeReceipt()?.processID)
    let snapshot = try XCTUnwrap(RuntimePublication.load(at: store.supervisionFileURL))
    // 模拟磁盘损坏，上游拒绝配置；监管资料仍完整且指向当前部署。
    try AtomicFileWriter.write(
      Data("invalid upstream JSON".utf8), to: workDir.appendingPathComponent(snapshot.configuration)
    )
    XCTAssertEqual(kill(recoveredPID, SIGKILL), 0)
    XCTAssertTrue(try waitForCondition(timeout: 10) { !wrapper.isRunning })
    XCTAssertNotNil(store.readFailure())
    let replay = try launchWrapper(document, publish: false)
    XCTAssertTrue(try waitForCondition(timeout: 5) { !replay.isRunning })
    XCTAssertNil(store.readRuntimeReceipt())
  }
}
