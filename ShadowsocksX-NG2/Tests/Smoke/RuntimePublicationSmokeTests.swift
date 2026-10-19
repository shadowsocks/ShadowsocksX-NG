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

  func testLargeACLReuseAndSingleInstanceModeHandoff() throws {
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
    for _ in 0..<2 {
      let oldPID = try XCTUnwrap(store.readRuntimeReceipt()?.processID)
      let direct = source.replacingACL(.direct(at: aclFileURL))
      try store.write(direct)
      XCTAssertEqual(kill(wrapper.processIdentifier, SIGUSR1), 0)
      try assertReceiptOwnsListeners(document: direct)
      XCTAssertNotEqual(store.readRuntimeReceipt()?.processID, oldPID)
      XCTAssertNotEqual(kill(oldPID, 0), 0, "旧子进程退出后新监听才就绪")
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
      try assertPublicTargetsProxy(listen: listen, fakeSS: proxy)
      XCTAssertEqual(RuntimePublication.load(at: store.supervisionFileURL)?.acl, acl)
      XCTAssertEqual(
        try FileManager.default.attributesOfItem(atPath: aclURL.path)[.systemFileNumber]
          as? NSNumber, inode)
      XCTAssertEqual(try Data(contentsOf: aclURL), Data(large.content.utf8))
    }
    stopWrapperAndAssertCleanExit(wrapper, description: "mode wrapper exits")
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
