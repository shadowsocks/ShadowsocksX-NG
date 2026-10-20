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

  private func installGatedListeningStub() throws {
    // 同一 PID 在显式放行后才建立监听，避免通过延时猜测启动阶段。
    let script = #"""
      #!/usr/bin/python3
      import json, os, pathlib, select, signal, socket, sys, time
      root = pathlib.Path(os.environ["SSXNG_RUNTIME_DIR"])
      state = pathlib.Path(os.environ["SSLOCAL_STUB_STATE"])
      def record(value):
          with state.open("a") as output:
              output.write(value + "\n")
      def stopped(*args):
          record("SIGTERM")
          sys.exit(0)
      signal.signal(signal.SIGTERM, stopped)
      signal.signal(signal.SIGUSR1, lambda *args: record("SIGUSR1"))
      signal.signal(signal.SIGUSR2, lambda *args: record("SIGUSR2"))
      (pathlib.Path(os.environ["SSLOCAL_STUB_PID_DIR"]) / str(os.getpid())).touch()
      record("invoked: gated listener")
      with open(sys.argv[2]) as source:
          configuration = json.load(source)
      while not (root / "release-listeners").exists():
          time.sleep(0.01)
      listeners = []
      for local in configuration["locals"]:
          listener = socket.socket()
          listener.bind((local["local_address"], local["local_port"]))
          listener.listen(128)
          listeners.append(listener)
      probe_count = 0
      while True:
          ready = select.select(listeners, [], [], 0.01)[0]
          while ready:
              for listener in ready:
                  connection, _ = listener.accept()
                  connection.close()
                  probe_count += 1
              ready = select.select(listeners, [], [], 0)[0]
          request = root / "probe-count-request"
          if request.exists():
              token = request.read_text()
              request.unlink()
              response = root / ("probe-count-" + token)
              temporary = response.with_suffix(".tmp")
              temporary.write_text(str(probe_count))
              temporary.replace(response)
      """#
    try script.write(
      to: workDir.appendingPathComponent("stub-sslocal.sh"), atomically: false, encoding: .utf8)
  }

  func testDeferredACLSignalSurvivesSubsequentServerOnlyPublication() throws {
    let runtimeStore = RuntimeFileStore(fileURL: contractURL)
    let socks = try TCPListenerFixture()
    let http = try TCPListenerFixture()
    let listen = ProxyListeningConfiguration(socksPort: socks.port, httpPort: http.port)
    socks.closeListener()
    http.closeListener()
    let previous = SslocalRuntimeDocument(
      servers: [], listen: listen, acl: .global(at: runtimeStore.aclFileURL))
    try writeContract(previous)
    try installGatedListeningStub()
    let wrapper = try launchWrapper(behavior: "run")
    XCTAssertTrue(try waitUntil { self.stateLog().contains("invoked:") })
    let next = previous.replacingACL(.direct(at: runtimeStore.aclFileURL))
    try writeContract(next)
    XCTAssertEqual(kill(wrapper.processIdentifier, SIGUSR1), 0)
    let deferred = "reload deferred until listeners are ready"
    XCTAssertTrue(try waitUntil { self.agentLog().components(separatedBy: deferred).count == 2 })
    let final = SslocalRuntimeDocument(
      servers: ProxyRuntimeFixture.makeDocument().servers, listen: listen, acl: next.aclRuntime)
    try writeContract(final)
    XCTAssertEqual(kill(wrapper.processIdentifier, SIGUSR1), 0)
    XCTAssertTrue(try waitUntil { self.agentLog().components(separatedBy: deferred).count == 3 })
    XCTAssertFalse(stateLog().contains("SIGUSR1"))
    XCTAssertFalse(stateLog().contains("SIGUSR2"))
    try Data().write(to: workDir.appendingPathComponent("release-listeners"))
    XCTAssertTrue(
      try waitUntil {
        self.stateLog().contains("SIGUSR1") && self.stateLog().contains("SIGUSR2")
          && runtimeStore.readRuntimeReceipt()?.deploymentID
            == runtimeStore.receiptIdentity(for: final)
      })
    func probeCount(_ token: Int) throws -> Int {
      let response = workDir.appendingPathComponent("probe-count-\(token)")
      try AtomicFileWriter.write(
        Data(String(token).utf8), to: workDir.appendingPathComponent("probe-count-request"))
      XCTAssertTrue(try waitUntil { FileManager.default.fileExists(atPath: response.path) })
      return try XCTUnwrap(Int(String(contentsOf: response, encoding: .utf8)))
    }
    let probesBeforeReload = try probeCount(1)
    let aclOnly = final.replacingACL(.global(at: runtimeStore.aclFileURL))
    try writeContract(aclOnly)
    XCTAssertEqual(kill(wrapper.processIdentifier, SIGUSR1), 0)
    XCTAssertTrue(
      try waitUntil {
        self.stateLog().components(separatedBy: "SIGUSR2").count == 3
          && runtimeStore.readRuntimeReceipt()?.deploymentID
            == runtimeStore.receiptIdentity(for: aclOnly)
      })
    XCTAssertEqual(
      try probeCount(2), probesBeforeReload, "健康实例热重载前后均不得重新连接监听端口")
    XCTAssertEqual(
      stateLog().components(separatedBy: "SIGUSR1").count - 1, 1,
      "仅 ACL 变化不得重新加载服务器配置")
    XCTAssertEqual(stateLog().components(separatedBy: "invoked:").count - 1, 1)
    XCTAssertFalse(stateLog().contains("SIGTERM"))
    kill(wrapper.processIdentifier, SIGTERM)
    XCTAssertEqual(try waitForExit(wrapper), 0)
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
  private var descriptor: Int32

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

  func closeListener() {
    if descriptor >= 0 { close(descriptor) }
    descriptor = -1
  }

  deinit {
    closeListener()
  }
}
