import Darwin
import Foundation

// MARK: - 动作

/// 规则动作：目标经 Shadowsocks 代理，或直连。独立于 PAC、ACL 文本与
/// 系统代理设置。
enum RuleAction: String, CaseIterable, Equatable, Hashable, Sendable {
  case proxy
  case direct
}

/// 规则模式的未匹配默认动作：未命中规则时走代理或直连。
/// 出厂默认「未匹配时代理」。
enum RuleDefaultAction: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
  case proxyWhenUnmatched = "proxy-when-unmatched"
  case directWhenUnmatched = "direct-when-unmatched"

  var label: String {
    switch self {
    case .proxyWhenUnmatched: String(localized: "代理")
    case .directWhenUnmatched: String(localized: "直连")
    }
  }

  func expresses(_ action: RuleAction) -> Bool {
    self != .proxyWhenUnmatched || action == .direct
  }

  /// 域名优先匹配下，未命中时的默认动作。
  var fallbackAction: RuleAction {
    switch self {
    case .proxyWhenUnmatched: .proxy
    case .directWhenUnmatched: .direct
    }
  }
}

// MARK: - 匹配条件

/// 规则匹配条件。完整域名、域名后缀与 IPv4/IPv6 CIDR 是可运行的统一类型；
/// 不把 URL 路径、协议、关键字或正则纳入。
struct RuleMatch: Equatable, Hashable, Sendable {
  /// Read-only pattern; raw strings cannot be used to construct a RuleMatch.
  enum Pattern: Equatable, Hashable, Sendable {
    case domainExact(String)
    case domainSuffix(String)
    case ipv4CIDR(String)
    case ipv6CIDR(String)
  }

  let pattern: Pattern

  private init(pattern: Pattern) { self.pattern = pattern }

  static let localSuffix = RuleMatch(pattern: .domainSuffix("local"))
  static let localhostSuffix = RuleMatch(pattern: .domainSuffix("localhost"))

  var isFixedLocalSuffix: Bool { self == Self.localSuffix || self == Self.localhostSuffix }

  init(domainExact raw: String) throws {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !value.isEmpty else { throw RuleMatchError.emptyDomain }
    guard !value.hasPrefix("."), !value.hasPrefix("*") else {
      throw RuleMatchError.invalidDomain(raw)
    }
    guard !value.hasSuffix(".") else { throw RuleMatchError.invalidDomain(raw) }
    guard value.allSatisfy({ Self.isDomainLabelCharacter($0) || $0 == "." }) else {
      throw RuleMatchError.invalidDomain(raw)
    }
    self.init(pattern: .domainExact(value))
  }

  init(domainSuffix raw: String) throws {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    while value.hasPrefix(".") { value.removeFirst() }
    guard !value.isEmpty else { throw RuleMatchError.emptyDomain }
    guard !value.hasPrefix("*"), !value.hasSuffix(".") else {
      throw RuleMatchError.invalidDomain(raw)
    }
    guard value.allSatisfy({ Self.isDomainLabelCharacter($0) || $0 == "." }) else {
      throw RuleMatchError.invalidDomain(raw)
    }
    // 单标签后缀（如 `com`）过宽；`cn` 作为国家后缀由吸收流程单独引入并显式允许。
    let labels = value.split(separator: ".")
    guard labels.count >= 2 else { throw RuleMatchError.invalidDomain(raw) }
    self.init(pattern: .domainSuffix(value))
  }

  /// 允许 `cn` 作为显式引入的国家后缀。
  init(nationalDomainSuffix raw: String) throws {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard value == "cn" else {
      // 回退到普通后缀校验。
      try self.init(domainSuffix: raw)
      return
    }
    self.init(pattern: .domainSuffix(value))
  }

  init(ipv4CIDR raw: String) throws {
    let normalized = try Self.normalizeIPv4CIDR(raw)
    self.init(pattern: .ipv4CIDR(normalized))
  }

  init(ipv6CIDR raw: String) throws {
    let normalized = try Self.normalizeIPv6CIDR(raw)
    self.init(pattern: .ipv6CIDR(normalized))
  }

  private static func isDomainLabelCharacter(_ character: Character) -> Bool {
    character.isASCII && (character.isLetter || character.isNumber || character == "-")
  }

  private static func normalizeIPv4CIDR(_ raw: String) throws -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw RuleMatchError.invalidCIDR(raw) }
    let parts = trimmed.split(separator: "/", maxSplits: 1)
    let addressPart = String(parts.first ?? "")
    let prefixLength: Int
    if parts.count == 2 {
      guard let parsed = Int(parts[1]), (0...32).contains(parsed) else {
        throw RuleMatchError.invalidCIDR(raw)
      }
      prefixLength = parsed
    } else {
      prefixLength = 32
    }
    var address = in_addr()
    let converted = addressPart.withCString { inet_pton(AF_INET, $0, &address) }
    guard converted == 1 else {
      // 确认不是 IPv6。
      var probe = in6_addr()
      if addressPart.withCString({ inet_pton(AF_INET6, $0, &probe) }) == 1 {
        throw RuleMatchError.invalidCIDR(raw)
      }
      throw RuleMatchError.invalidCIDR(raw)
    }
    let host = UInt32(bigEndian: address.s_addr)
    let mask: UInt32 = prefixLength == 0 ? 0 : UInt32.max << (32 - prefixLength)
    let network = host & mask
    var networkAddress = in_addr(s_addr: network.bigEndian)
    var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
    guard inet_ntop(AF_INET, &networkAddress, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
      throw RuleMatchError.invalidCIDR(raw)
    }
    guard let dotted = Self.string(from: buffer) else {
      throw RuleMatchError.invalidCIDR(raw)
    }
    return "\(dotted)/\(prefixLength)"
  }

  private static func normalizeIPv6CIDR(_ raw: String) throws -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw RuleMatchError.invalidCIDR(raw) }
    let parts = trimmed.split(separator: "/", maxSplits: 1)
    let addressPart = String(parts.first ?? "")
    let prefixLength: Int
    if parts.count == 2 {
      guard let parsed = Int(parts[1]), (0...128).contains(parsed) else {
        throw RuleMatchError.invalidCIDR(raw)
      }
      prefixLength = parsed
    } else {
      prefixLength = 128
    }
    var address = in6_addr()
    let converted = addressPart.withCString { inet_pton(AF_INET6, $0, &address) }
    guard converted == 1 else {
      var probe = in_addr()
      if addressPart.withCString({ inet_pton(AF_INET, $0, &probe) }) == 1 {
        throw RuleMatchError.invalidCIDR(raw)
      }
      throw RuleMatchError.invalidCIDR(raw)
    }
    // 按 16-bit 组掩码到前缀长度。
    var bytes = withUnsafeBytes(of: address) { Array($0) }
    for index in 0..<16 {
      let bitStart = index * 8
      if prefixLength >= bitStart + 8 { continue }
      if prefixLength <= bitStart {
        bytes[index] = 0
      } else {
        let keep = prefixLength - bitStart
        let mask = UInt8.max << (8 - keep)
        bytes[index] &= mask
      }
    }
    var networkAddress = bytes.withUnsafeBytes { rawPointer in
      rawPointer.load(as: in6_addr.self)
    }
    var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
    guard inet_ntop(AF_INET6, &networkAddress, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil else {
      throw RuleMatchError.invalidCIDR(raw)
    }
    guard let address = Self.string(from: buffer) else {
      throw RuleMatchError.invalidCIDR(raw)
    }
    return "\(address)/\(prefixLength)"
  }

  private static func string(from buffer: [CChar]) -> String? {
    let bytes = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
    return String(bytes: bytes, encoding: .utf8)
  }
}

enum RuleMatchError: Error, Equatable, Sendable {
  case emptyDomain
  case invalidDomain(String)
  case invalidCIDR(String)
}

// MARK: - 来源身份

/// 内置规则来源身份。
enum RuleSourceKind: String, CaseIterable, Equatable, Hashable, Sendable {
  case geolocationCN = "geolocation-cn"
  case chinaIPv4 = "china-ipv4"
  case gfwlist = "gfwlist"
  case custom = "custom"
}

/// 内置快照的来源类别、上游版本与展示标签。
struct RuleSourceIdentity: Equatable, Hashable, Sendable {
  let kind: RuleSourceKind
  let upstreamVersion: String
  let label: String

  init(kind: RuleSourceKind, upstreamVersion: String, label: String) {
    self.kind = kind
    self.upstreamVersion = upstreamVersion
    self.label = label
  }

  var id: String { kind.rawValue }
}

// MARK: - 规则

/// 一条来源无关的代理规则。
struct ProxyRule: Equatable, Hashable, Sendable {
  let action: RuleAction
  let match: RuleMatch

  init(
    action: RuleAction,
    match: RuleMatch
  ) {
    self.action = action
    self.match = match
  }

  /// Stable historical token, independent of Swift's debug representation.
  var contentToken: String {
    let kind: String
    let value: String
    switch match.pattern {
    case .domainExact(let raw): (kind, value) = ("domainExact", raw)
    case .domainSuffix(let raw): (kind, value) = ("domainSuffix", raw)
    case .ipv4CIDR(let raw): (kind, value) = ("ipv4CIDR", raw)
    case .ipv6CIDR(let raw): (kind, value) = ("ipv6CIDR", raw)
    }
    return "\(action.rawValue)|\(kind)(\(String(reflecting: value)))"
  }

  /// sslocal ACL 单行表示（ASCII）。域名后缀 `||host`、完整域名 `|host`、
  /// CIDR 原样写入。
  var aclLine: String {
    switch match.pattern {
    case .domainExact(let domain):
      return "|\(domain)"
    case .domainSuffix(let domain):
      return "||\(domain)"
    case .ipv4CIDR(let cidr), .ipv6CIDR(let cidr):
      return cidr
    }
  }
}
