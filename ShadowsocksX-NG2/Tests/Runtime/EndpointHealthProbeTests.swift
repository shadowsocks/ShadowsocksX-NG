import XCTest

@testable import ShadowsocksX_NG2

/// 端点健康探测：真实 socket 上验证「监听即连通」「未监听
/// 即拒绝」，失败原因可供「启动失败」点名端点与端口。
final class EndpointHealthProbeTests: XCTestCase {
  /// 绑定回环临时端口；调用方负责 close 返回的描述符。
  private func bindLoopbackListener() throws -> (descriptor: Int32, port: Int) {
    let socketFD = socket(AF_INET, SOCK_STREAM, 0)
    _ = try XCTUnwrap(socketFD >= 0 ? socketFD : nil, "创建探测用 socket 失败")

    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
    address.sin_port = 0
    let bindResult = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        Darwin.bind(socketFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    XCTAssertEqual(bindResult, 0, "绑定回环失败")
    XCTAssertEqual(listen(socketFD, 1), 0)

    var boundAddress = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        getsockname(socketFD, sockaddrPointer, &length)
      }
    }
    XCTAssertEqual(nameResult, 0)
    return (socketFD, Int(CFSwapInt16BigToHost(boundAddress.sin_port)))
  }

  func testProbeReachesBoundLoopbackListener() throws {
    let (descriptor, port) = try bindLoopbackListener()
    defer { close(descriptor) }

    let outcome = EndpointHealthProbe.probe(host: "127.0.0.1", port: port, timeout: 2)

    XCTAssertEqual(outcome, .reachable, "监听中的端点应可连通")
  }

  func testProbeRefusesClosedLoopbackPort() throws {
    // 绑定后立即释放：端口大概率无人监听，连接应立即被拒而非超时。
    let (descriptor, port) = try bindLoopbackListener()
    close(descriptor)

    let outcome = EndpointHealthProbe.probe(host: "127.0.0.1", port: port, timeout: 2)

    guard case .refused = outcome else {
      XCTFail("未监听端口应为 refused，实际 \(outcome)")
      return
    }
  }
}
