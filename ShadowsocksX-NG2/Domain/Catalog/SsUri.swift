import Foundation

/// SIP002 `ss://` URI 模型（https://shadowsocks.org/doc/sip002.html）。
/// 插件字段持 SIP003 `SS_PLUGIN_OPTIONS` 形态的原样字符串（如
/// `mode=websocket;host=example.com`）：URI 编解码只做 RFC 3986 百分号编码层，
/// 反斜杠转义按原样透传（插件自解），往返保持 `plugin=name;opts` 逐字节同构。
struct SsUri: Equatable, Sendable {
  var method: String
  var password: String
  var host: String
  var port: Int
  /// 插件程序名；无插件为 `nil`。
  var pluginProgram: String?
  /// 插件参数（SS_PLUGIN_OPTIONS 原样形态）；无插件或仅有程序名为 `nil`。
  var pluginOptions: String?
  /// 备注（URI fragment）；缺失或空为 `nil`。
  var remark: String?

  init(
    method: String,
    password: String,
    host: String,
    port: Int,
    pluginProgram: String? = nil,
    pluginOptions: String? = nil,
    remark: String? = nil
  ) {
    self.method = method
    self.password = password
    self.host = host
    self.port = port
    self.pluginProgram = pluginProgram
    self.pluginOptions = pluginOptions
    self.remark = remark
  }
}

/// 解码失败原因：输入不是可解析的 `ss://` URI。
enum SsUriError: Error, Equatable {
  /// 不以 `ss://` 开头。
  case notSsUri
  /// scheme 正确但结构或字段非法（缺端口、base64 解不开、端口越界等）。
  case malformed(detail: String)
}

// MARK: - 解码

extension SsUri {
  /// 解码单个 URI 行。同时接受：
  /// - SIP002 形态：`ss://userinfo@host:port/?plugin=…#tag`（userinfo 为
  /// base64url(`method:password`) 或百分号编码明文——AEAD-2022 规定明文）。
  /// - Legacy 兼容形态：`ss://base64(method:password@host:port)#tag`（无 `@`，
  /// 密码明文，非 RFC 3986）。
  static func decode(_ rawInput: String) throws -> SsUri {
    let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
    let schemePrefix = "ss://"
    guard input.lowercased().hasPrefix(schemePrefix) else { throw SsUriError.notSsUri }
    var rest = String(input.dropFirst(schemePrefix.count))

    // fragment（备注）：base64 字母表与百分号编码都不含裸 `#`，取首个裸 `#` 安全。
    var remark: String?
    if let hashIndex = rest.firstIndex(of: "#") {
      remark = percentDecode(String(rest[rest.index(after: hashIndex)...]))
      rest = String(rest[..<hashIndex])
    }

    if rest.contains("@") {
      return try decodeSIP002(rest, remark: remark)
    }
    return try decodeLegacy(rest, remark: remark)
  }

  /// SIP002 形态：在最后一个 `@` 处分离 userinfo 与 host:port（+query）。
  private static func decodeSIP002(_ rest: String, remark: String?) throws -> SsUri {
    guard let atSign = rest.lastIndex(of: "@") else {
      throw SsUriError.malformed(detail: "missing userinfo separator")
    }
    let userInfo = String(rest[..<atSign])
    var hostPort = String(rest[rest.index(after: atSign)...])

    var query: String?
    if let queryIndex = hostPort.firstIndex(of: "?") {
      query = String(hostPort[hostPort.index(after: queryIndex)...])
      hostPort = String(hostPort[..<queryIndex])
    }
    hostPort = hostPort.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let (host, port) = try parseHostPort(hostPort)
    let (method, password) = try parseUserInfo(userInfo)
    let plugin = parsePluginQuery(query)

    return SsUri(
      method: method, password: password, host: host, port: port,
      pluginProgram: plugin?.program, pluginOptions: plugin?.options, remark: remark)
  }

  /// userinfo 解析：先按 base64url（补齐 padding、兼容两种字母表）；解不出或
  /// 不含分隔冒号时回退百分号编码明文（SIP022 形态）。
  private static func parseUserInfo(_ userInfo: String) throws -> (String, String) {
    if let decoded = base64FlexibleDecode(userInfo), let separator = decoded.firstIndex(of: ":") {
      let method = String(decoded[..<separator])
      let password = String(decoded[decoded.index(after: separator)...])
      guard !method.isEmpty, !password.isEmpty else {
        throw SsUriError.malformed(detail: "method or password is empty")
      }
      return (method, password)
    }
    guard let plain = percentDecode(userInfo), let separator = plain.firstIndex(of: ":") else {
      throw SsUriError.malformed(
        detail: "userinfo is neither base64 nor percent-encoded method:password")
    }
    let method = String(plain[..<separator])
    let password = String(plain[plain.index(after: separator)...])
    guard !method.isEmpty, !password.isEmpty else {
      throw SsUriError.malformed(detail: "method or password is empty")
    }
    return (method, password)
  }

  /// Legacy 形态：整体 base64 → `method:password@host:port`。密码为明文
  /// （可能含 `@` 与 `:`），故 host:port 侧用「最后一个 @」切分。
  private static func decodeLegacy(_ rest: String, remark: String?) throws -> SsUri {
    let trimmed = rest.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard let decoded = base64FlexibleDecode(trimmed) else {
      throw SsUriError.malformed(detail: "legacy payload is not valid base64")
    }
    guard let atSign = decoded.lastIndex(of: "@") else {
      throw SsUriError.malformed(detail: "legacy payload missing @")
    }
    let credentials = String(decoded[..<atSign])
    let hostPort = String(decoded[decoded.index(after: atSign)...])
    guard let colon = credentials.firstIndex(of: ":") else {
      throw SsUriError.malformed(detail: "legacy payload missing method separator")
    }
    let (host, port) = try parseHostPort(hostPort)
    let method = String(credentials[..<colon])
    let password = String(credentials[credentials.index(after: colon)...])
    guard !method.isEmpty, !password.isEmpty else {
      throw SsUriError.malformed(detail: "method or password is empty")
    }
    return SsUri(
      method: method,
      password: password,
      host: host, port: port, remark: remark)
  }

  /// host:port 解析：IPv6 必须为方括号形态；否则以最后一个冒号分离端口。
  private static func parseHostPort(_ hostPort: String) throws -> (String, Int) {
    let host: String
    let portText: String
    if hostPort.hasPrefix("[") {
      guard let closing = hostPort.firstIndex(of: "]") else {
        throw SsUriError.malformed(detail: "unclosed IPv6 bracket")
      }
      host = String(hostPort[hostPort.index(hostPort.startIndex, offsetBy: 1)..<closing])
      let remainder = hostPort[hostPort.index(after: closing)...]
      guard remainder.hasPrefix(":") else {
        throw SsUriError.malformed(detail: "missing port after IPv6 bracket")
      }
      portText = String(remainder.dropFirst())
    } else {
      guard let colon = hostPort.lastIndex(of: ":") else {
        throw SsUriError.malformed(detail: "missing port")
      }
      host = String(hostPort[..<colon])
      portText = String(hostPort[hostPort.index(after: colon)...])
    }
    guard let port = Int(portText), (1...65_535).contains(port) else {
      throw SsUriError.malformed(detail: "invalid port \(portText)")
    }
    guard !host.isEmpty else { throw SsUriError.malformed(detail: "empty host") }
    return (host, port)
  }

  /// query 中的 `plugin` 参数：百分号解码后为 `name;opts`，首个 `;` 切分；
  /// opts 原样保留。`plugin=` 空值视为无插件。
  private static func parsePluginQuery(
    _ query: String?
  ) -> (program: String, options: String?)? {
    guard let query else { return nil }
    var pluginValue: String?
    for pair in query.split(separator: "&") {
      let name: String
      let value: String
      if let equals = pair.firstIndex(of: "=") {
        name = String(pair[..<equals])
        value = String(pair[pair.index(after: equals)...])
      } else {
        name = String(pair)
        value = ""
      }
      if percentDecode(name) == "plugin" { pluginValue = percentDecode(value) }
    }
    guard let pluginValue, !pluginValue.isEmpty else { return nil }
    let program: String
    let options: String?
    if let semicolon = pluginValue.firstIndex(of: ";") {
      program = String(pluginValue[..<semicolon])
      let rest = String(pluginValue[pluginValue.index(after: semicolon)...])
      options = rest.isEmpty ? nil : rest
    } else {
      program = pluginValue
      options = nil
    }
    guard !program.isEmpty else { return nil }
    return (program, options)
  }
}

// MARK: - 编码

extension SsUri {
  /// 规范 SIP002 形态：`ss://userinfo@host:port[/?plugin=…][#remark]`。
  /// AEAD-2022（SIP022，`2022-blake3-*`）按规范用百分号编码明文 userinfo，
  /// 其余用 base64url（无 padding）。
  func encode() -> String {
    let userInfo: String
    if method.hasPrefix("2022-blake3-") {
      userInfo = "\(Self.percentEncode(method)):\(Self.percentEncode(password))"
    } else {
      userInfo = Self.base64URLEncodeNoPadding("\(method):\(password)")
    }
    var uri = "ss://\(userInfo)@\(encodedHost):\(port)"
    if let program = pluginProgram {
      let pluginValue = pluginOptions.map { "\(program);\($0)" } ?? program
      uri += "/?plugin=\(Self.percentEncode(pluginValue))"
    }
    if let remark, !remark.isEmpty {
      uri += "#\(Self.percentEncode(remark))"
    }
    return uri
  }

  /// 解码得到的 IPv6（裸冒号形态）编码时重新加方括号。
  private var encodedHost: String {
    host.contains(":") ? "[\(host)]" : host
  }
}

// MARK: - base64 与百分号编码工具

extension SsUri {
  /// base64url 无 padding（SIP002 userinfo 的规范形态）。
  static func base64URLEncodeNoPadding(_ text: String) -> String {
    Data(text.utf8)
      .base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  /// 宽容 base64 解码：兼容标准/url-safe 两种字母表与缺失 padding
  /// （社区分享链接普遍省略 padding）。
  static func base64FlexibleDecode(_ text: String) -> String? {
    var normalized =
      text
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
      .replacingOccurrences(of: "\n", with: "")
      .replacingOccurrences(of: "\r", with: "")
      .trimmingCharacters(in: .whitespaces)
    let remainder = normalized.count % 4
    if remainder == 1 { return nil }  // 不可能是合法 base64 长度
    if remainder > 0 { normalized.append(String(repeating: "=", count: 4 - remainder)) }
    guard let data = Data(base64Encoded: normalized) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// 百分号编码：仅保留 RFC 3986 unreserved（字母数字与 `-._~`），其余全部
  /// 转义——与官方示例的 `obfs-local%3Bobfs%3Dhttp` 形态一致。
  static func percentEncode(_ text: String) -> String {
    let allowed = CharacterSet(
      charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
  }

  private static func percentDecode(_ text: String) -> String? {
    text.removingPercentEncoding
  }
}
