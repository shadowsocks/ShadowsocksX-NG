import Foundation

/// 已解析的运行时凭据只进入受保护的运行文件，不进入偏好或摘要。
struct RuntimeListenerAuthentication: Codable, Equatable, Sendable {
  let username: String
  let password: String
  let directory: String

  static func validUsername(_ value: String) -> Bool {
    validPassword(value) && !value.contains(":")
  }

  static func validPassword(_ value: String) -> Bool {
    (1...255).contains(value.utf8.count) && value.utf8.allSatisfy { (32...126).contains($0) }
  }

  var isValid: Bool {
    Self.validUsername(username) && Self.validPassword(password) && directory.hasPrefix("/")
  }

  private var identity: String {
    ProxyACLDocument.digest(Data((username + ":" + password).utf8))
  }

  var socksPath: String { path("socks") }
  var httpPath: String { path("http") }

  private func path(_ name: String) -> String {
    URL(fileURLWithPath: directory, isDirectory: true)
      .appendingPathComponent("lan-auth-\(name)-\(identity).json").path
  }

  /// 内容寻址避免覆盖仍由旧 sslocal 使用的认证文件。
  func writeFiles() throws {
    let user = ["user_name": username, "password": password]
    for (key, path) in [("password", socksPath), ("basic", httpPath)] {
      let data = try JSONSerialization.data(
        withJSONObject: [key: ["users": [user]]],
        options: [.sortedKeys])
      try AtomicFileWriter.write(data, to: URL(fileURLWithPath: path))
    }
  }
}

extension SslocalRuntimeDocument {
  func authenticatingLAN(_ authentication: RuntimeListenerAuthentication?) -> Self {
    var result = self
    result.listen.authentication = authentication
    for index in result.locals.indices where result.locals[index].localAddress != "127.0.0.1" {
      if result.locals[index].inboundProtocol == "socks" {
        result.locals[index].socks5AuthConfigPath = authentication?.socksPath
      } else {
        result.locals[index].httpAuthConfigPath = authentication?.httpPath
      }
    }
    return result
  }
}
