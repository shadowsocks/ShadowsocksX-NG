import Darwin
import XCTest

@testable import ShadowsocksX_NG2

/// 端口语义主缝测试：出厂默认、占用校验、建议端口
/// 算法与点名错误。bind 探测覆盖真实回环 socket；lsof 输出解析为纯函数夹具。
final class ProxyPortSemanticsTests: XCTestCase {
  // MARK: 出厂默认（与 Legacy 隔离，任何路径不静默改端口）

  func testFactoryDefaultsAvoidLegacyPortsAndValidateClean() {
    let settings = SslocalListenSettings()

    XCTAssertEqual(settings.socksPort, 11086)
    XCTAssertEqual(settings.httpPort, 11087)
    XCTAssertTrue(settings.portValidationErrors().isEmpty)
  }

  // MARK: 配置校验与点名错误

  func testOutOfRangePortsAreRejectedNamingEndpointAndPort() {
    var settings = SslocalListenSettings()
    settings.socksPort = 0
    settings.httpPort = 65536

    XCTAssertEqual(
      settings.portValidationErrors(),
      [
        .portOutOfRange(endpoint: .socks, port: 0),
        .portOutOfRange(endpoint: .http, port: 65536),
      ])
  }

  func testDuplicateConfiguredPortsAreRejectedNamingBothEndpoints() {
    let settings = SslocalListenSettings(
      socksPort: 1086,
      httpPort: 1086)

    XCTAssertEqual(
      settings.portValidationErrors(),
      [.duplicatePort(endpoint: .socks, otherEndpoint: .http, port: 1086)],
      "两个端点的配置值都必须互异")
  }

  func testPresentationNamesEndpointAndPort() {
    XCTAssertEqual(
      AppPresentation.message(
        for: PortSettingError.portOutOfRange(endpoint: .http, port: 70000)),
      "本地 HTTP 代理 端口 70000 无效，必须是 1025–65535 之间的整数")
    XCTAssertEqual(
      AppPresentation.message(
        for: PortSettingError.duplicatePort(
          endpoint: .socks, otherEndpoint: .http, port: 1086)),
      "本地 SOCKS5 代理 端口与 本地 HTTP 代理 端口冲突（都是 1086），请为每个端点配置不同的端口")
  }

  // MARK: 建议端口算法（32768–65535 高位段，空闲且与另两端点配置值互异）

  func testSuggestionScansHighRangeAscendingSkippingExcludedAndOccupied() {
    var probed: [Int] = []
    let suggested = PortSuggestion.firstFree(
      excluding: [32768],
      isFree: { port in
        probed.append(port)
        return port != 32769
      })

    XCTAssertEqual(suggested, 32770)
    XCTAssertEqual(probed, [32769, 32770], "被排除的 32768 不探测；占用端口跳过")
  }

  func testSuggestionReturnsNilWhenWholeRangeExhausted() {
    XCTAssertNil(PortSuggestion.firstFree(excluding: [], isFree: { _ in false }))
  }

  func testSuggestedPortForEndpointExcludesOtherConfiguredValues() {
    let settings = SslocalListenSettings(
      socksPort: 40000, httpPort: 40001)
    var probed: [Int] = []
    let suggested = settings.suggestedPort(for: .http) { port in
      probed.append(port)
      return port == 40002
    }

    XCTAssertEqual(suggested, 40002)
    XCTAssertFalse(probed.contains(40000), "另个端点的配置值无论启用与否都排除")
  }

  // MARK: 占用探测（设置区即时校验的 I/O 缝；激活仍以 runtime 实际绑定的
  // 健康门禁为准，本探测只是编辑期尽力而为的提示）

  func testBindProbeReportsOccupiedThenFreeOnRealLoopbackSocket() throws {
    let held = try ListenerFixture()
    let port = held.port
    let probe = SystemPortOccupancyProbe()

    guard case .occupied = probe.occupancy(port: port, listenerMode: .disabled) else {
      return XCTFail("已被本测试进程监听的端口必须判为占用")
    }

    held.close()

    guard case .free = probe.occupancy(port: port, listenerMode: .disabled) else {
      return XCTFail("关闭监听后同一端口必须判为空闲")
    }
  }

  func testBindProbeReportsUnknownForUnresolvableAddress() {
    let outcome = SystemPortOccupancyProbe().occupancy(port: 1086, bindAddress: "not-an-ip")

    guard case .unknown = outcome else {
      return XCTFail("地址不可解析时不得冒充空闲或占用，实际 \(outcome)")
    }
  }

  func testIPv6OnlyBindCanShareAnIPv4PortWhileDualStackCannot() throws {
    let held = try ListenerFixture(listenerMode: .allIPv4Interfaces)
    defer { held.close() }
    let probe = SystemPortOccupancyProbe()

    guard case .free = probe.occupancy(port: held.port, listenerMode: .allIPv6Interfaces) else {
      return XCTFail("IPv6-only 探测不应与 IPv4 通配监听冲突")
    }
    guard
      case .occupied = probe.occupancy(
        port: held.port, listenerMode: .allIPv4AndIPv6Interfaces)
    else {
      return XCTFail("双栈探测必须覆盖 IPv4，因而与 IPv4 通配监听冲突")
    }
  }

  func testOccupierNameParsedFromLsofOutputFixture() {
    let output = """
      COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
      sslocal 12345 qiu    7u  IPv4  0xabcd      0t0  TCP 127.0.0.1:1086 (LISTEN)
      TestApp 12346 qiu    8u  IPv4  0xabce      0t0  TCP 127.0.0.1:1086 (LISTEN)
      """
    XCTAssertEqual(SystemPortOccupancyProbe.occupierProcessName(fromLsofOutput: output), "sslocal")
    XCTAssertEqual(
      SystemPortOccupancyProbe.occupierProcessIDs(fromLsofOutput: output), [12345, 12346])
    XCTAssertEqual(
      SystemPortOccupancyProbe.lsofArguments(port: 1086, addressFamily: .ipv4),
      ["-nP", "-i4TCP:1086", "-sTCP:LISTEN"])
    XCTAssertEqual(
      SystemPortOccupancyProbe.lsofArguments(port: 1086, addressFamily: .ipv6),
      ["-nP", "-i6TCP:1086", "-sTCP:LISTEN"])
    XCTAssertNil(SystemPortOccupancyProbe.occupierProcessName(fromLsofOutput: "  \n"))
    XCTAssertNil(
      SystemPortOccupancyProbe.occupierProcessName(fromLsofOutput: "COMMAND PID USER FD"),
      "只有表头（无占用进程）时解析为 nil")
  }
}

/// 测试专用回环监听器：占用一个内核分配端口，供占用探测断言真实占用。
private final class ListenerFixture {
  let descriptor: Int32
  let port: Int

  init(listenerMode: ListenerMode = .disabled) throws {
    let listenerFD = socket(AF_INET, SOCK_STREAM, 0)
    guard listenerFD >= 0 else { throw POSIXError(.ENOTSOCK) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0
    guard inet_pton(AF_INET, listenerMode.bindAddress, &address.sin_addr) == 1 else {
      Darwin.close(listenerFD)
      throw POSIXError(.EADDRNOTAVAIL)
    }
    let bindResult = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(listenerFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bindResult == 0 else {
      let error = errno
      Darwin.close(listenerFD)
      throw POSIXError(POSIXErrorCode(rawValue: error)!)
    }
    guard listen(listenerFD, 1) == 0 else {
      let error = errno
      Darwin.close(listenerFD)
      throw POSIXError(POSIXErrorCode(rawValue: error)!)
    }
    var bound = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameResult = withUnsafeMutablePointer(to: &bound) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        getsockname(listenerFD, $0, &length)
      }
    }
    guard nameResult == 0 else {
      let error = errno
      Darwin.close(listenerFD)
      throw POSIXError(POSIXErrorCode(rawValue: error)!)
    }
    descriptor = listenerFD
    port = Int(CFSwapInt16BigToHost(bound.sin_port))
  }

  func close() {
    Darwin.close(descriptor)
  }
}
