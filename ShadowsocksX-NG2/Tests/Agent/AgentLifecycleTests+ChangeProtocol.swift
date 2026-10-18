import Darwin
import XCTest

@testable import ShadowsocksX_NG2

final class AgentLifecycleChangeProtocolTests: AgentLifecycleTests {
  // MARK: 变更协议

  func testSIGUSR1WithServerOnlyChangeIsForwardedToSslocal() throws {
    try writeContract(ProxyRuntimeFixture.makeDocument(serverAddress: "203.0.113.7"))
    let wrapper = try launchWrapper(behavior: "run")
    XCTAssertTrue(
      try waitUntil { self.stateLog().contains("invoked:") }, "等待首次拉起")

    try writeContract(ProxyRuntimeFixture.makeDocument(serverAddress: "198.51.100.9"))
    kill(wrapper.processIdentifier, SIGUSR1)

    XCTAssertTrue(
      try waitUntil { self.stateLog().contains("SIGUSR1") },
      "仅服务器列表变化应转发 SIGUSR1 热重载（上游只替换配置来源服务器）")
    XCTAssertTrue(pidAlive(wrapper.processIdentifier), "热重载不重启 wrapper")
    XCTAssertFalse(stateLog().contains("SIGTERM"), "热重载不触发子进程重启")

    kill(wrapper.processIdentifier, SIGTERM)
    XCTAssertEqual(try waitForExit(wrapper), 0)
  }

  func testSIGUSR1WithListenChangePerformsGracefulRestart() throws {
    try writeContract(ProxyRuntimeFixture.makeDocument(localPort: 1086))
    let wrapper = try launchWrapper(behavior: "run")
    XCTAssertTrue(
      try waitUntil { self.stateLog().contains("invoked:") }, "等待首次拉起")

    try writeContract(ProxyRuntimeFixture.makeDocument(localPort: 2086))
    kill(wrapper.processIdentifier, SIGUSR1)

    XCTAssertTrue(
      try waitUntil {
        self.stateLog().contains("SIGTERM")
          && self.stateLog().components(separatedBy: "invoked:").count >= 3
      },
      "监听结构变化走优雅重启：先 SIGTERM 旧实例再以新契约拉起，实际：\(stateLog())")
    XCTAssertTrue(pidAlive(wrapper.processIdentifier), "重启后 wrapper 常驻")

    XCTAssertFalse(stateLog().contains("OVERLAPPING CHILD"), "新实例启动时旧实例必须已退出")
    // 重启后的实例也要能被显式停止。
    kill(wrapper.processIdentifier, SIGTERM)
    XCTAssertEqual(try waitForExit(wrapper), 0)
    XCTAssertEqual(
      stateLog().components(separatedBy: "SIGTERM").count - 1, 2,
      "两次停止各转发一次 SIGTERM")
  }

  func testSIGUSR1WithACLChangeRestartsSslocalWithoutUnreadyReceipt() throws {
    let runtimeStore = RuntimeFileStore(fileURL: contractURL)
    let previous = ProxyRuntimeFixture.makeDocument()
    try writeContract(previous)
    let wrapper = try launchWrapper(behavior: "run")
    XCTAssertTrue(
      try waitUntil {
        runtimeStore.readRuntimeReceipt()?.deploymentID
          == runtimeStore.receiptIdentity(for: previous)
      }, "首次实例启动后应发布运行回执")
    let previousProcessID = try XCTUnwrap(runtimeStore.readRuntimeReceipt()?.processID)

    let next = previous.replacingACL(.direct(at: runtimeStore.aclFileURL))
    try writeContract(next)
    XCTAssertEqual(kill(wrapper.processIdentifier, SIGUSR1), 0, "SIGUSR1 应送达 wrapper")

    XCTAssertTrue(
      try waitUntil {
        return self.agentLog().contains("reload: listen change, restarting sslocal")
          && self.stateLog().components(separatedBy: "invoked:").count >= 3
      },
      "ACL 摘要变化应完整重启 sslocal；agent: \(agentLog())"
    )
    // 再发送 server-only reload，让就绪检查完成后给出明确的拒绝信号。
    let serverReload = ProxyRuntimeFixture.makeDocument(serverAddress: "198.51.100.9")
      .replacingACL(.direct(at: runtimeStore.aclFileURL))
    try writeContract(serverReload)
    XCTAssertEqual(kill(wrapper.processIdentifier, SIGUSR1), 0)
    XCTAssertTrue(
      try waitUntil { self.agentLog().contains("reload deferred until listeners are ready") },
      "未绑定监听的重启实例应拒绝发布回执并推迟重载")
    XCTAssertFalse(stateLog().contains("SIGUSR1"), "未就绪时不能转发 server-only reload")
    XCTAssertNil(
      runtimeStore.readRuntimeReceipt(),
      "stub 未绑定代理端口时，不得为直连实例发布回执（旧 pid=\(previousProcessID)）")

    kill(wrapper.processIdentifier, SIGTERM)
    XCTAssertEqual(try waitForExit(wrapper), 0)
  }
}

final class AgentLifecycleStaleListenerTests: AgentLifecycleTests {
  func testACLReceiptIsNotPublishedWhenOnlyStaleListenersAreReachable() throws {
    let staleSocksListener = try TCPListenerFixture()
    let staleHTTPListener = try TCPListenerFixture()
    let runtimeStore = RuntimeFileStore(fileURL: contractURL)
    let listen = SslocalListenSettings(
      socksPort: staleSocksListener.port,
      httpPort: staleHTTPListener.port)
    let directDocument = SslocalRuntimeDocument(servers: [], listen: listen)
      .replacingACL(.direct(at: runtimeStore.aclFileURL))
    try writeContract(directDocument)

    for local in directDocument.locals {
      XCTAssertEqual(
        EndpointHealthProbe.probe(host: local.probeHost, port: local.localPort, timeout: 0.2),
        .reachable,
        "旧实例应让 \(local.inboundProtocol) 端口可连通")
    }

    let wrapper = try launchWrapper(behavior: "run")

    XCTAssertTrue(
      try waitUntil { self.stateLog().contains("invoked:") },
      "等待候选子进程启动后验证监听归属")

    let server = try XCTUnwrap(ProxyRuntimeFixture.makeDocument().servers.first)
    let serverReload = SslocalRuntimeDocument(
      servers: [server], listen: listen, acl: directDocument.aclRuntime)
    try writeContract(serverReload)
    XCTAssertEqual(kill(wrapper.processIdentifier, SIGUSR1), 0, "server-only reload 应送达")

    XCTAssertTrue(
      try waitUntil { self.agentLog().contains("reload deferred until listeners are ready") },
      "未就绪的直连实例应推迟 server-only reload")
    XCTAssertFalse(stateLog().contains("SIGUSR1"), "旧监听不能让候选通过就绪门并转发重载")
    XCTAssertTrue(
      pidAlive(wrapper.processIdentifier),
      "候选 wrapper 应继续监管；agent log: " + agentLog() + "; child log: " + stateLog())
    XCTAssertNil(
      runtimeStore.readRuntimeReceipt(),
      "候选没有绑定端口时，旧监听和 server-only reload 都不能发布直连回执")
  }
}

final class AgentLifecycleListenDeadlineTests: AgentLifecycleTests {
  // MARK: 监听建立判定

  func testListenDeadlinePersistsFailureAndStopsChild() throws {
    // stub sslocal 不监听任何端点：超时后应记 error 日志点名端点，且监管继续。
    try writeContract(ProxyRuntimeFixture.makeDocument())
    let wrapper = try launchWrapper(behavior: "run")

    let agentLogURL = workDir.appendingPathComponent("agent.log")
    XCTAssertTrue(
      try waitUntil {
        guard let log = try? String(contentsOf: agentLogURL, encoding: .utf8) else {
          return false
        }
        return log.contains("listen not established within deadline")
      },
      "3 秒未建立监听应以 error 日志点名（D10），实际 agent.log：\(agentLog())")
    XCTAssertEqual(try waitForExit(wrapper), 0)
    XCTAssertNotNil(RuntimeFileStore(fileURL: contractURL).readFailure())
    XCTAssertTrue(stateLog().contains("SIGTERM"))
  }
}

private final class TCPListenerFixture {
  let port: Int
  private let descriptor: Int32

  init() throws {
    let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard socketDescriptor >= 0 else { throw POSIXError(.ENOTSOCK) }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    address.sin_port = 0
    let bindResult = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(
          socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bindResult == 0, listen(socketDescriptor, 4) == 0 else {
      close(socketDescriptor)
      throw POSIXError(.EADDRINUSE)
    }

    var boundAddress = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        getsockname(socketDescriptor, $0, &length)
      }
    }
    guard nameResult == 0 else {
      close(socketDescriptor)
      throw POSIXError(.EINVAL)
    }

    descriptor = socketDescriptor
    port = Int(CFSwapInt16BigToHost(boundAddress.sin_port))
  }

  deinit {
    close(descriptor)
  }
}
