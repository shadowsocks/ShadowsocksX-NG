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

  func testACLReloadIsDeferredWithoutRestartUntilListenersAreReady() throws {
    let runtimeStore = RuntimeFileStore(fileURL: contractURL)
    let previous = ProxyRuntimeFixture.makeDocument()
      .replacingACL(.global(at: runtimeStore.aclFileURL))
    try writeContract(previous)
    let wrapper = try launchWrapper(behavior: "run")
    XCTAssertTrue(try waitUntil { self.stateLog().contains("invoked:") })

    let next = previous.replacingACL(.direct(at: runtimeStore.aclFileURL))
    try writeContract(next)
    XCTAssertEqual(kill(wrapper.processIdentifier, SIGUSR1), 0)
    XCTAssertTrue(
      try waitUntil { self.agentLog().contains("reload deferred until listeners are ready") })
    XCTAssertFalse(stateLog().contains("SIGUSR1"))
    XCTAssertFalse(stateLog().contains("SIGUSR2"))
    XCTAssertFalse(stateLog().contains("SIGTERM"))
    XCTAssertEqual(stateLog().components(separatedBy: "invoked:").count - 1, 1)
    XCTAssertNil(runtimeStore.readRuntimeReceipt())

    kill(wrapper.processIdentifier, SIGTERM)
    XCTAssertEqual(try waitForExit(wrapper), 0)
  }

}

final class AgentLifecycleStaleListenerTests: AgentLifecycleTests {
  func testACLReceiptIsNotPublishedWhenOnlyStaleListenersAreReachable() throws {
    let staleSocksListener = try TCPListenerFixture()
    let staleHTTPListener = try TCPListenerFixture()
    let runtimeStore = RuntimeFileStore(fileURL: contractURL)
    let listen = ProxyListeningConfiguration(
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
    XCTAssertTrue(
      try waitUntil(timeout: 20) { self.agentLog().contains("check=ownership") },
      "超时日志应区分端口可连接但不属于当前子进程：\(agentLog())")
    XCTAssertEqual(try waitForExit(wrapper), 0)
    XCTAssertTrue(agentLog().contains("endpoint=socks 127.0.0.1:\(staleSocksListener.port)"))
  }
}

final class AgentLifecycleListenDeadlineTests: AgentLifecycleTests {
  // MARK: 监听建立判定

  func testListenDeadlinePersistsFailureAndStopsChild() throws {
    // stub sslocal 不监听任何端点：超时日志应包含失败检查与等待耗时。
    try writeContract(ProxyRuntimeFixture.makeDocument())
    let wrapper = try launchWrapper(behavior: "run")

    let agentLogURL = workDir.appendingPathComponent("agent.log")
    XCTAssertTrue(
      try waitUntil(timeout: 20) {
        guard let log = try? String(contentsOf: agentLogURL, encoding: .utf8) else {
          return false
        }
        return log.contains("listen not established within deadline")
      },
      "15 秒未建立监听应以 error 日志点名，实际 agent.log：\(agentLog())")
    XCTAssertEqual(try waitForExit(wrapper), 0)
    let log = try XCTUnwrap(
      agentLog().components(separatedBy: "\n").first {
        $0.contains("listen not established within deadline")
      })
    XCTAssertTrue(log.contains("endpoint=socks 127.0.0.1:"), log)
    XCTAssertTrue(log.contains("check=connect outcome=refused"), log)
    XCTAssertTrue(log.contains("pid="), log)
    XCTAssertTrue(log.contains("elapsed="), log)
    XCTAssertTrue(log.contains("deadline=15.000s"), log)
    XCTAssertNotNil(RuntimeFileStore(fileURL: contractURL).readFailure())
    XCTAssertTrue(stateLog().contains("SIGTERM"))
  }
}

private final class TCPListenerFixture {
  let port: Int
  private let source: DispatchSourceRead

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

    guard fcntl(socketDescriptor, F_SETFL, O_NONBLOCK) == 0 else {
      close(socketDescriptor)
      throw POSIXError(.EINVAL)
    }
    port = Int(CFSwapInt16BigToHost(boundAddress.sin_port))
    source = DispatchSource.makeReadSource(fileDescriptor: socketDescriptor, queue: .global())
    source.setEventHandler {
      while true {
        let connection = accept(socketDescriptor, nil, nil)
        guard connection >= 0 else { return }
        close(connection)
      }
    }
    source.setCancelHandler { close(socketDescriptor) }
    source.resume()
  }

  func closeListener() {
    source.cancel()
  }

  deinit {
    closeListener()
  }
}
