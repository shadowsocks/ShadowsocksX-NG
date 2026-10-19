import Darwin
import XCTest

@testable import ShadowsocksX_NG2

extension RealSslocalSmokeTests {
  private func connectLoopback(port: Int) throws -> Int32 {
    let socketFD = socket(AF_INET, SOCK_STREAM, 0)
    guard socketFD >= 0 else { throw POSIXError(.ENOTSOCK) }
    var timeout = timeval(tv_sec: 5, tv_usec: 0)
    _ = setsockopt(
      socketFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
    address.sin_port = in_port_t(port).bigEndian
    let connectResult = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        connect(socketFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard connectResult == 0 else {
      Darwin.close(socketFD)
      throw POSIXError(.ECONNREFUSED)
    }
    return socketFD
  }

  func performDirectSocksEcho(
    socksPort: Int, targetPort: Int, payload: [UInt8]
  ) throws -> [UInt8] {
    let socketFD = try connectLoopback(port: socksPort)
    defer { Darwin.close(socketFD) }
    let greeting: [UInt8] = [0x05, 0x01, 0x00]
    _ = try greeting.withUnsafeBytes { try writeAll(socketFD, $0) }
    XCTAssertEqual(try readExactly(socketFD, count: 2), [0x05, 0x00])

    let portBytes = UInt16(targetPort).bigEndian
    var request: [UInt8] = [0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1]
    withUnsafeBytes(of: portBytes) { request.append(contentsOf: $0) }
    _ = try request.withUnsafeBytes { try writeAll(socketFD, $0) }
    let reply = try readExactly(socketFD, count: 10)
    XCTAssertEqual(reply[1], 0, "空服务器直连模式应连接本地回环目标")

    _ = try payload.withUnsafeBytes { try writeAll(socketFD, $0) }
    return try readExactly(socketFD, count: payload.count)
  }

  func performDirectHTTPEcho(
    httpPort: Int, targetHost: String = "127.0.0.1", targetPort: Int, payload: [UInt8]
  ) throws -> [UInt8] {
    let socketFD = try connectLoopback(port: httpPort)
    defer { Darwin.close(socketFD) }
    let request =
      "CONNECT \(targetHost):\(targetPort) HTTP/1.1\r\n"
      + "Host: \(targetHost):\(targetPort)\r\n\r\n"
    let requestBytes = Array(request.utf8)
    _ = try requestBytes.withUnsafeBytes { try writeAll(socketFD, $0) }

    var response: [UInt8] = []
    while response.count < 4 || Array(response.suffix(4)) != [13, 10, 13, 10] {
      response.append(contentsOf: try readExactly(socketFD, count: 1))
      guard response.count < 4096 else { throw NSError(domain: "smoke", code: 3) }
    }
    let header = String(bytes: response, encoding: .utf8) ?? ""
    XCTAssertTrue(header.contains(" 200 "), "HTTP CONNECT 应答成功：\(header)")
    _ = try payload.withUnsafeBytes { try writeAll(socketFD, $0) }
    return try readExactly(socketFD, count: payload.count)
  }

  /// 对公网目标发起 SOCKS5 CONNECT，返回应答码；代理出口不可用时应答非 0
  /// 也算完成路由观测（不直连真实目标）。
  func performSocksConnectReply(
    socksPort: Int, targetHost: String, targetPort: Int
  ) -> UInt8? {
    var request: [UInt8] = [0x05, 0x01, 0x00, 0x03, UInt8(targetHost.utf8.count)]
    request.append(contentsOf: targetHost.utf8)
    let portBytes = UInt16(targetPort).bigEndian
    withUnsafeBytes(of: portBytes) { request.append(contentsOf: $0) }
    return performSocksConnectReply(socksPort: socksPort, request: request)
  }

  func performSocksConnectReply(socksPort: Int, request: [UInt8]) -> UInt8? {
    guard let socketFD = try? connectLoopback(port: socksPort) else { return nil }
    defer { Darwin.close(socketFD) }
    do {
      let greeting: [UInt8] = [0x05, 0x01, 0x00]
      _ = try greeting.withUnsafeBytes { try writeAll(socketFD, $0) }
      _ = try readExactly(socketFD, count: 2)
      _ = try request.withUnsafeBytes { try writeAll(socketFD, $0) }
      let reply = try readExactly(socketFD, count: 4)
      return reply[1]
    } catch {
      return nil
    }
  }

  /// 按给定 CONNECT 请求完成 SOCKS 会话并回显载荷；`successMessage` 用于
  /// 断言失败时点名场景。
  func performSocksEcho(
    socksPort: Int, request: [UInt8], payload: [UInt8], successMessage: String
  ) throws -> [UInt8] {
    let socketFD = try connectLoopback(port: socksPort)
    defer { Darwin.close(socketFD) }
    let greeting: [UInt8] = [0x05, 0x01, 0x00]
    _ = try greeting.withUnsafeBytes { try writeAll(socketFD, $0) }
    XCTAssertEqual(try readExactly(socketFD, count: 2), [0x05, 0x00])
    _ = try request.withUnsafeBytes { try writeAll(socketFD, $0) }
    let reply = try readExactly(socketFD, count: 10)
    XCTAssertEqual(reply[1], 0, successMessage)
    _ = try payload.withUnsafeBytes { try writeAll(socketFD, $0) }
    return try readExactly(socketFD, count: payload.count)
  }

  func socksDomainConnectRequest(host: String, port: Int) -> [UInt8] {
    var request: [UInt8] = [0x05, 0x01, 0x00, 0x03, UInt8(host.utf8.count)]
    request.append(contentsOf: host.utf8)
    let portBytes = UInt16(port).bigEndian
    withUnsafeBytes(of: portBytes) { request.append(contentsOf: $0) }
    return request
  }

  /// SOCKS5 CONNECT 到 IPv6 回环（ATYP=0x04）。
  func socksIPv6ConnectRequest(port: Int) -> [UInt8] {
    var request: [UInt8] = [0x05, 0x01, 0x00, 0x04]
    request.append(contentsOf: Array(repeating: 0, count: 15))
    request.append(1)  // ::1
    let portBytes = UInt16(port).bigEndian
    withUnsafeBytes(of: portBytes) { request.append(contentsOf: $0) }
    return request
  }

  /// SOCKS5 CONNECT 到 IPv4 字面量（ATYP=0x01），用于域名/IP 优先级断言。
  func socksIPv4ConnectRequest(_ octets: [UInt8], port: Int) -> [UInt8] {
    precondition(octets.count == 4, "IPv4 request needs 4 octets")
    var request: [UInt8] = [0x05, 0x01, 0x00, 0x01]
    request.append(contentsOf: octets)
    let portBytes = UInt16(port).bigEndian
    withUnsafeBytes(of: portBytes) { request.append(contentsOf: $0) }
    return request
  }

  /// 对公网目标发起 HTTP CONNECT（应答头读到即返回，不要求成功）。
  func performHTTPConnect(
    httpPort: Int, targetHost: String, targetPort: Int
  ) {
    guard let socketFD = try? connectLoopback(port: httpPort) else { return }
    defer { Darwin.close(socketFD) }
    do {
      let request =
        "CONNECT \(targetHost):\(targetPort) HTTP/1.1\r\n"
        + "Host: \(targetHost):\(targetPort)\r\n\r\n"
      let requestBytes = Array(request.utf8)
      _ = try requestBytes.withUnsafeBytes { try writeAll(socketFD, $0) }
      var response: [UInt8] = []
      while response.count < 4 || Array(response.suffix(4)) != [13, 10, 13, 10] {
        response.append(contentsOf: try readExactly(socketFD, count: 1))
        guard response.count < 4096 else { return }
      }
    } catch {
      return
    }
  }

  /// 抓取三个互不冲突且避开给定端口的临时回环端口。
  func grabThreeListenPorts(excluding occupied: [Int] = []) throws -> [Int] {
    var ports = Set<Int>()
    while ports.count < 3 {
      let port = try grabEphemeralLoopbackPort()
      if !occupied.contains(port) { ports.insert(port) }
    }
    return Array(ports)
  }

  /// Domain/CIDR probes must not pass through the fixed loopback bypass instead.
  /// Dedicated global-ACL tests cover that bypass separately.
  func ruleProbeACL(defaultAction: RuleDefaultAction, rules: [ProxyRule]) -> ProxyACLDocument {
    let compiled = ProxyACLDocument.rule(at: aclFileURL, defaultAction: defaultAction, rules: rules)
    let content =
      compiled.content.split(separator: "\n").filter { $0 != "127.0.0.0/8" }
      .joined(separator: "\n") + "\n"
    return ProxyACLDocument(path: compiled.path, summary: compiled.summary, content: content)
  }

  func assertDirectDomain(
    _ host: String, listen: ProxyListeningConfiguration, echoPort: Int,
    exit: ConnectionCountingServer
  ) throws {
    let before = exit.connectionCount
    let payload = Array("direct domain\n".utf8)
    XCTAssertEqual(
      try performSocksEcho(
        socksPort: listen.socksPort,
        request: socksDomainConnectRequest(host: host, port: echoPort), payload: payload,
        successMessage: "Domain must connect directly: \(host)"), payload)
    XCTAssertEqual(exit.connectionCount, before)
  }

  /// 优雅停止 wrapper 并断言干净退出（退出码 0）。
  func stopWrapperAndAssertCleanExit(_ wrapper: Process, description: String) {
    guard wrapper.isRunning else {
      XCTAssertEqual(wrapper.terminationStatus, 0, description)
      return
    }
    let descendants = descendantPIDs(of: wrapper.processIdentifier)
    kill(wrapper.processIdentifier, SIGTERM)
    let exited = (try? waitForCondition(timeout: 10) { !wrapper.isRunning }) == true
    XCTAssertTrue(exited, description)
    if !exited {
      for child in descendants.reversed() where kill(child, 0) == 0 { kill(child, SIGKILL) }
      kill(wrapper.processIdentifier, SIGKILL)
      XCTAssertTrue((try? waitForCondition(timeout: 2) { !wrapper.isRunning }) == true)
    }
    if !wrapper.isRunning { XCTAssertEqual(wrapper.terminationStatus, 0, description) }
  }

  /// 断言运行回执已发布、进程存活且拥有契约内全部本地监听。
  func assertReceiptOwnsListeners(document: SslocalRuntimeDocument) throws {
    let runtimeStore = RuntimeFileStore(fileURL: contractURL)
    let receiptPublished = try waitForCondition(timeout: 30) {
      guard let receipt = runtimeStore.readRuntimeReceipt() else { return false }
      return receipt.deploymentID == runtimeStore.receiptIdentity(for: document)
        && kill(receipt.processID, 0) == 0
    }
    XCTAssertTrue(receiptPublished, "应发布仍存活的 sslocal 子进程回执")
    let receipt = try XCTUnwrap(runtimeStore.readRuntimeReceipt())
    for local in document.locals {
      XCTAssertTrue(
        RuntimeSocketOwnershipProbe.process(
          receipt.processID, ownsTCPListenerOn: local.localPort),
        "回执对应的 sslocal 应拥有 \(local.inboundProtocol) TCP 监听")
    }
    XCTAssertEqual(
      runtimeStore.readRuntimeReceipt()?.deploymentID,
      runtimeStore.receiptIdentity(for: document))
  }
}

final class LoopbackEchoServer {
  private let descriptor: Int32
  let port: Int

  init() throws {
    let listener = try Self.listenOnLoopback()
    self.descriptor = listener.descriptor
    port = listener.port
    Self.echoForever(on: listener.descriptor)
  }

  deinit {
    shutdown(descriptor, SHUT_RDWR)
    Darwin.close(descriptor)
  }

  /// 建立监听 socket 并返回其描述符与实际绑定端口。
  private static func listenOnLoopback() throws -> (descriptor: Int32, port: Int) {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw POSIXError(.ENOTSOCK) }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
    address.sin_port = 0
    let bindResult = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        Darwin.bind(descriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bindResult == 0, Darwin.listen(descriptor, 4) == 0 else {
      Darwin.close(descriptor)
      throw POSIXError(.EADDRINUSE)
    }

    var boundAddress = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        getsockname(descriptor, sockaddrPointer, &length)
      }
    }
    guard nameResult == 0 else {
      Darwin.close(descriptor)
      throw POSIXError(.EINVAL)
    }
    return (descriptor, Int(CFSwapInt16BigToHost(boundAddress.sin_port)))
  }

  /// 常驻 echo 循环：逐行读入并原样写回。
  private static func echoForever(on descriptor: Int32) {
    DispatchQueue.global().async { [descriptor] in
      while true {
        let connection = accept(descriptor, nil, nil)
        guard connection >= 0 else { return }
        var bytes: [UInt8] = []
        while !bytes.contains(10) {
          var chunk = [UInt8](repeating: 0, count: 512)
          let received = chunk.withUnsafeMutableBytes { buffer in
            read(connection, buffer.baseAddress!, buffer.count)
          }
          guard received > 0 else { break }
          bytes.append(contentsOf: chunk.prefix(received))
        }
        if !bytes.isEmpty {
          bytes.withUnsafeBytes { buffer in
            _ = write(connection, buffer.baseAddress!, buffer.count)
          }
        }
        shutdown(connection, SHUT_RDWR)
        Darwin.close(connection)
      }
    }
  }
}

/// 只接受 TCP 连接并计数的假 SS 服务器：证明目标被路由进代理出口，而非
/// 真实完成 Shadowsocks 握手（数据面属发布门槛人工验收）。
final class ConnectionCountingServer {
  private let descriptor: Int32
  let port: Int
  private let counter = CounterBox()

  var connectionCount: Int { counter.value }

  init() throws {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw POSIXError(.ENOTSOCK) }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
    address.sin_port = 0
    let bindResult = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        Darwin.bind(descriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bindResult == 0, Darwin.listen(descriptor, 8) == 0 else {
      Darwin.close(descriptor)
      throw POSIXError(.EADDRINUSE)
    }

    var boundAddress = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        getsockname(descriptor, sockaddrPointer, &length)
      }
    }
    guard nameResult == 0 else {
      Darwin.close(descriptor)
      throw POSIXError(.EINVAL)
    }

    self.descriptor = descriptor
    port = Int(CFSwapInt16BigToHost(boundAddress.sin_port))
    let counter = self.counter
    DispatchQueue.global().async { [descriptor] in
      while true {
        let connection = accept(descriptor, nil, nil)
        guard connection >= 0 else { return }
        counter.increment()
        // 立刻断开：sslocal 的 SS 握手会失败，但 TCP 连接已被观察到。
        shutdown(connection, SHUT_RDWR)
        Darwin.close(connection)
      }
    }
  }

  deinit {
    shutdown(descriptor, SHUT_RDWR)
    Darwin.close(descriptor)
  }

  private final class CounterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
      lock.lock()
      defer { lock.unlock() }
      return count
    }

    func increment() {
      lock.lock()
      count += 1
      lock.unlock()
    }
  }
}
