import Darwin
import Foundation

@testable import ShadowsocksX_NG2

enum ProxyRuntimeFixture {
  static func unusedLoopbackPort() throws -> Int {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw POSIXError(.ENOTSOCK) }
    defer { close(descriptor) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    let result = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard result == 0 else { throw POSIXError(.EADDRINUSE) }
    var bound = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameResult = withUnsafeMutablePointer(to: &bound) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        getsockname(descriptor, $0, &length)
      }
    }
    guard nameResult == 0 else { throw POSIXError(.EINVAL) }
    return Int(CFSwapInt16BigToHost(bound.sin_port))
  }

  /// 夹具默认监听端口：测试进程内一次性分配的空闲端口对。不能固定 11086/
  /// 11087（与 app 默认监听相同）：宿主 app 在跑时其 sslocal 占住这两个端口，
  /// wrapper 健康探测会误判「监听已建立」。进程内共享同一对端口而非逐调用
  /// 分配，保证两次默认构造之间除显式参数外无差异——「仅服务器变化」类
  /// 变更协议语义依赖这一点。
  private static let defaultListenPorts: (socks: Int, http: Int) = {
    func freePort() -> Int {
      guard let port = try? unusedLoopbackPort() else {
        preconditionFailure("夹具端口分配失败：socket 不可用（fd 耗尽？）")
      }
      return port
    }
    let socks = freePort()
    var http = freePort()
    while http == socks {
      http = freePort()
    }
    return (socks, http)
  }()

  static func makeDocument(
    serverAddress: String = "203.0.113.7",
    password: String = "resolved-password",
    pluginOpts: String? = nil,
    listenerMode: ListenerMode = .disabled,
    localPort: Int? = nil,
    inboundProtocol: String = "socks"
  ) -> SslocalRuntimeDocument {
    precondition(inboundProtocol == "socks")
    let socksPort: Int
    let httpPort: Int
    if let localPort {
      socksPort = localPort
      httpPort = ProxyListeningConfiguration.defaultHTTPPort
    } else {
      socksPort = defaultListenPorts.socks
      httpPort = defaultListenPorts.http
    }
    return SslocalRuntimeDocument(
      servers: [
        SslocalServerDocument(
          id: "server-1",
          server: serverAddress,
          serverPort: 8388,
          password: password,
          method: "aes-256-gcm",
          plugin: nil,
          pluginOpts: pluginOpts
        )
      ],
      listen: ProxyListeningConfiguration(
        listenerMode: listenerMode,
        socksPort: socksPort,
        httpPort: httpPort))
  }

}
