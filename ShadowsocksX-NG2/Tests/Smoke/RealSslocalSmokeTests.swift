import Darwin
import XCTest

@testable import ShadowsocksX_NG2

/// 真实 sslocal 冒烟：wrapper 驱动 bundle 内官方 sslocal
/// v1.25.0——本地 SOCKS 端口完成监听绑定，并完成一次完整 SOCKS5 握手（方法
/// 协商 + CONNECT 请求得到按协议的应答）。远端服务器不可达只影响应答码，不
/// 影响握手本身（真实服务器功能验证属发布门槛人工检查项）。
class RealSslocalSmokeTests: XCTestCase {
  private var wrappers: [Process] = []
  private var dns: LoopbackDNSResponder!
  var usesLocalDNS: Bool { true }
  var workDir: URL!
  var contractURL: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    workDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ssxng-smoke-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    contractURL = workDir.appendingPathComponent("sslocal-active.json")
    if usesLocalDNS { dns = try LoopbackDNSResponder() }
  }

  override func tearDownWithError() throws {
    for wrapper in wrappers where wrapper.isRunning {
      stopWrapperAndAssertCleanExit(wrapper, description: "teardown wrapper exits")
    }
    wrappers.removeAll()
    dns = nil
    try? FileManager.default.removeItem(at: workDir)
    try super.tearDownWithError()
  }

  /// `RuntimeFileStore.write` 校验的 ACL sidecar 路径：ACL 文档的 `path` 必须
  /// 严格等于它，否则契约写入即抛「ACL sidecar path or digest is invalid」。
  var aclFileURL: URL {
    RuntimeFileStore(fileURL: contractURL).aclFileURL
  }

  private var sslocalURL: URL {
    get throws {
      let url = AppArtifact.bundleURL.appendingPathComponent("Contents/Helpers/sslocal")
      return try XCTUnwrap(
        FileManager.default.fileExists(atPath: url.path) ? url : nil,
        "sslocal 未嵌入 app bundle（先跑 fetch-external-binaries.sh）")
    }
  }

  /// 绑定回环临时端口拿到空闲端口号后释放。
  func grabEphemeralLoopbackPort() throws -> Int {
    let socketFD = socket(AF_INET, SOCK_STREAM, 0)
    guard socketFD >= 0 else { throw POSIXError(.ENOTSOCK) }
    defer { close(socketFD) }

    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
    address.sin_port = 0
    let bindResult = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        Darwin.bind(socketFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    XCTAssertEqual(bindResult, 0)
    XCTAssertEqual(listen(socketFD, 1), 0)

    var boundAddress = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        getsockname(socketFD, sockaddrPointer, &length)
      }
    }
    XCTAssertEqual(nameResult, 0)
    return Int(CFSwapInt16BigToHost(boundAddress.sin_port))
  }

  /// 写入给定契约并拉起 wrapper（契约内容由调用方构造：无插件与插件场景各异）。
  func launchWrapper(_ document: SslocalRuntimeDocument, publish: Bool = true) throws -> Process {
    if publish { try RuntimeFileStore(fileURL: contractURL).write(document) }

    let wrapperURL = AppArtifact.bundleURL.appendingPathComponent(
      "Contents/MacOS/ShadowsocksX-NG2Agent")
    let process = Process()
    process.executableURL = wrapperURL
    var environment = ProcessInfo.processInfo.environment
    environment["SSXNG_CONTRACT_PATH"] = contractURL.path
    if usesLocalDNS {
      // exec preserves the PID supervised by the real wrapper. Only DNS is test-owned.
      let launcher = workDir.appendingPathComponent("sslocal-with-local-dns")
      let executable = try sslocalURL.path.replacingOccurrences(of: "'", with: "'\"'\"'")
      let script = "#!/bin/sh\nexec '\(executable)' --dns udp://127.0.0.1:\(dns.port) \"$@\"\n"
      try script.write(to: launcher, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: launcher.path)
      environment["SSXNG_SSLOCAL_PATH"] = launcher.path
    } else {
      environment["SSXNG_SSLOCAL_PATH"] = try sslocalURL.path
    }
    environment["SSXNG_RUNTIME_DIR"] = workDir.path
    process.environment = environment
    try process.run()
    wrappers.append(process)
    return process
  }

  /// 对本地 SOCKS 端口做完整握手，返回 CONNECT 应答首字节（版本, 应答码）。
  func performSocksHandshake(port: Int) throws -> (version: UInt8, reply: UInt8)? {
    let socketFD = socket(AF_INET, SOCK_STREAM, 0)
    guard socketFD >= 0 else { throw POSIXError(.ENOTSOCK) }
    defer { close(socketFD) }
    var timeout = timeval(tv_sec: 5, tv_usec: 0)
    _ = setsockopt(
      socketFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
    address.sin_port = in_port_t(port).bigEndian
    let connectResult = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        connect(socketFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard connectResult == 0 else { return nil }

    // 方法协商：X'05' X'01' X'00'（一个无需认证的方法）。
    let greeting: [UInt8] = [0x05, 0x01, 0x00]
    XCTAssertEqual(try greeting.withUnsafeBytes { try writeAll(socketFD, $0) }, greeting.count)
    let methodReply = try readExactly(socketFD, count: 2)
    XCTAssertEqual(
      methodReply, [0x05, 0x00], "sslocal 应选定 NO-AUTH 方法", file: #filePath, line: #line)

    // CONNECT 127.0.0.1:1。
    let request: [UInt8] = [0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, 0x00, 0x01]
    _ = try request.withUnsafeBytes { try writeAll(socketFD, $0) }
    let replyHead = try readExactly(socketFD, count: 4)
    return (replyHead[0], replyHead[1])
  }

  func writeAll(_ descriptor: Int32, _ buffer: UnsafeRawBufferPointer) throws -> Int {
    var total = 0
    while total < buffer.count {
      let written = write(descriptor, buffer.baseAddress!.advanced(by: total), buffer.count - total)
      guard written > 0 else { throw NSError(domain: "smoke", code: 1) }
      total += written
    }
    return total
  }

  func readExactly(_ descriptor: Int32, count: Int) throws -> [UInt8] {
    var bytes: [UInt8] = []
    bytes.reserveCapacity(count)
    while bytes.count < count {
      var scratch: [UInt8] = Array(repeating: 0, count: count - bytes.count)
      let received = read(descriptor, &scratch, scratch.count)
      guard received > 0 else { throw NSError(domain: "smoke", code: 2) }
      bytes.append(contentsOf: scratch[0..<received])
    }
    return bytes
  }

  func descendantPIDs(of parent: Int32) -> [Int32] {
    let query = Process()
    query.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    query.arguments = ["-P", String(parent)]
    let pipe = Pipe()
    query.standardOutput = pipe
    query.standardError = FileHandle.nullDevice
    guard (try? query.run()) != nil else { return [] }
    guard (try? waitForCondition(timeout: 2) { !query.isRunning }) == true else {
      kill(query.processIdentifier, SIGKILL)
      return []
    }
    let children =
      (String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
      .split(whereSeparator: \.isWhitespace).compactMap { Int32($0) }
    return children + children.flatMap { descendantPIDs(of: $0) }
  }

  func waitForCondition(
    timeout: TimeInterval, _ condition: () throws -> Bool
  ) throws -> Bool {
    let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
    while DispatchTime.now().uptimeNanoseconds < deadline {
      if try condition() { return true }
      Thread.sleep(forTimeInterval: 0.1)
    }
    return try condition()
  }
}

final class RealSslocalListenerSmokeTests: RealSslocalSmokeTests {
  func testRealSslocalBindsSOCKSAndHTTPPortsAndCompletesHandshake() throws {
    var ports = Set<Int>()
    while ports.count < 2 {
      ports.insert(try grabEphemeralLoopbackPort())
    }
    let selectedPorts = Array(ports)
    let socksPort = selectedPorts[0]
    let httpPort = selectedPorts[1]
    let document = SslocalRuntimeDocument(
      servers: [
        SslocalServerDocument(
          id: "smoke-server",
          server: "127.0.0.1",
          serverPort: 1,  // 远端必然拒绝：只验证本地握手与 SSLOCAL 配置格式
          password: "smoke-password",
          method: "aes-256-gcm",
          plugin: nil,
          pluginOpts: nil)
      ],
      listen: SslocalListenSettings(
        socksPort: socksPort, httpPort: httpPort))
    let wrapper = try launchWrapper(document)

    // 两个端口同时就绪：验证 locals[] 被官方 sslocal 接受并实际绑定。
    var socksReachable = false
    var httpReachable = false
    let deadline = Date().addingTimeInterval(15)
    while (!socksReachable || !httpReachable) && Date() < deadline {
      socksReachable =
        EndpointHealthProbe.probe(host: "127.0.0.1", port: socksPort, timeout: 1) == .reachable
      httpReachable =
        EndpointHealthProbe.probe(host: "127.0.0.1", port: httpPort, timeout: 1) == .reachable
      if !socksReachable || !httpReachable {
        Thread.sleep(forTimeInterval: 0.2)
      }
    }
    XCTAssertTrue(socksReachable, "15 秒内本地 SOCKS 端口应完成监听绑定")
    XCTAssertTrue(httpReachable, "15 秒内本地 HTTP 端口应完成监听绑定")

    // 完整 SOCKS5 握手。
    let handshake = try performSocksHandshake(port: socksPort)
    let reply = try XCTUnwrap(handshake, "连接成功建立后应能完成握手")
    XCTAssertEqual(reply.version, 0x05, "应答版本应为 SOCKS5")
    // 远端不可达允许失败应答码；关键在于 sslocal 按协议给出 CONNECT 应答。

    // 显式停止：SIGTERM 链对真实 sslocal 同样成立。
    stopWrapperAndAssertCleanExit(wrapper, description: "wrapper exits")
  }

  /// 无活动服务器监听：空 `servers` 契约是合法部署——上游
  /// sslocal v1.25.0 接受空服务器列表并照常绑定 SOCKS/HTTP 入站。真实运行时
  /// 证据（系统代理写入属真实宿主验收，不在替身/回环测试范围内）。
  func testRealSslocalBindsLocalsWithEmptyServerList() throws {
    var ports = Set<Int>()
    while ports.count < 2 {
      ports.insert(try grabEphemeralLoopbackPort())
    }
    let selectedPorts = Array(ports)
    let document = SslocalRuntimeDocument(
      servers: [],
      listen: SslocalListenSettings(
        socksPort: selectedPorts[0], httpPort: selectedPorts[1]))
    XCTAssertTrue(document.isWellFormed, "空服务器列表契约有效")
    let wrapper = try launchWrapper(document)

    XCTAssertTrue(
      try waitForCondition(timeout: 15) {
        EndpointHealthProbe.probe(host: "127.0.0.1", port: selectedPorts[0], timeout: 1)
          == .reachable
      },
      "空服务器列表下本地 SOCKS 端口应完成监听绑定")
    XCTAssertTrue(
      try waitForCondition(timeout: 15) {
        EndpointHealthProbe.probe(host: "127.0.0.1", port: selectedPorts[1], timeout: 1)
          == .reachable
      },
      "空服务器列表下本地 HTTP 端口应完成监听绑定")

    stopWrapperAndAssertCleanExit(wrapper, description: "wrapper exits")
  }

}
