import Darwin
import Foundation

// MARK: - 动作

/// 规则动作：目标经 Shadowsocks 代理，或直连。独立于 PAC、ACL 文本与
/// 系统代理设置。
enum RuleAction: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
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
enum RuleMatch: Equatable, Hashable, Codable, Sendable {
  private enum CodingKeys: String, CodingKey {
    case kind, value
  }

  private enum Kind: String, Codable {
    case domainExact, domainSuffix, ipv4CIDR, ipv6CIDR
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let value = try container.decode(String.self, forKey: .value)
    switch try container.decode(Kind.self, forKey: .kind) {
    case .domainExact:
      try self.init(domainExact: value)
    case .domainSuffix:
      try self.init(nationalDomainSuffix: value)
    case .ipv4CIDR:
      try self.init(ipv4CIDR: value)
    case .ipv6CIDR:
      try self.init(ipv6CIDR: value)
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .domainExact(let value):
      try container.encode(Kind.domainExact, forKey: .kind)
      try container.encode(value, forKey: .value)
    case .domainSuffix(let value):
      try container.encode(Kind.domainSuffix, forKey: .kind)
      try container.encode(value, forKey: .value)
    case .ipv4CIDR(let value):
      try container.encode(Kind.ipv4CIDR, forKey: .kind)
      try container.encode(value, forKey: .value)
    case .ipv6CIDR(let value):
      try container.encode(Kind.ipv6CIDR, forKey: .kind)
      try container.encode(value, forKey: .value)
    }
  }

  /// 完整域名精确匹配（`full:`）。
  case domainExact(String)
  /// 域名后缀匹配：域名本身及其所有子域（`domain:` / 裸域名）。
  case domainSuffix(String)
  /// IPv4 CIDR（规范化后的 `a.b.c.d/len`）。
  case ipv4CIDR(String)
  /// IPv6 CIDR（规范化后的压缩形式）。
  case ipv6CIDR(String)

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
    self = .domainExact(value)
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
    self = .domainSuffix(value)
  }

  /// 允许 `cn` 作为显式引入的国家后缀。
  init(nationalDomainSuffix raw: String) throws {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard value == "cn" else {
      // 回退到普通后缀校验。
      try self.init(domainSuffix: raw)
      return
    }
    self = .domainSuffix(value)
  }

  init(ipv4CIDR raw: String) throws {
    let normalized = try Self.normalizeIPv4CIDR(raw)
    self = .ipv4CIDR(normalized)
  }

  init(ipv6CIDR raw: String) throws {
    let normalized = try Self.normalizeIPv6CIDR(raw)
    self = .ipv6CIDR(normalized)
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

/// Source-independent routing identity; custom UUIDs continue to identify edits.
/// Callers supply valid RuleMatch values; decoding and input constructors validate them.
struct RuleIdentity: Codable, Equatable, Hashable, Sendable {
  let action: RuleAction
  let match: RuleMatch

  init(action: RuleAction, match: RuleMatch) {
    self.action = action
    switch match {
    case .domainExact(let value):
      self.match = (try? RuleMatch(domainExact: value)) ?? match
    case .domainSuffix(let value):
      self.match = (try? RuleMatch(nationalDomainSuffix: value)) ?? match
    case .ipv4CIDR(let value):
      self.match = (try? RuleMatch(ipv4CIDR: value)) ?? match
    case .ipv6CIDR(let value):
      self.match = (try? RuleMatch(ipv6CIDR: value)) ?? match
    }
  }

  var contentToken: String { "\(action.rawValue)|\(String(describing: match))" }
}

// MARK: - 来源身份

/// 内置规则来源身份。
enum RuleSourceKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
  case geolocationCN = "geolocation-cn"
  case chinaIPv4 = "china-ipv4"
  case gfwlist = "gfwlist"
  case custom = "custom"
}

/// 规则来源身份：固定来源类别 + 上游版本 + 展示标签。自定义条目与快照元数据
/// 共用此身份。
struct RuleSourceIdentity: Codable, Equatable, Hashable, Sendable {
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
struct ProxyRule: Codable, Equatable, Hashable, Sendable {
  let action: RuleAction
  let match: RuleMatch

  init(
    action: RuleAction,
    match: RuleMatch
  ) {
    self.action = action
    self.match = match
  }

  var identity: RuleIdentity { RuleIdentity(action: action, match: match) }

  /// sslocal ACL 单行表示（ASCII）。域名后缀 `||host`、完整域名 `|host`、
  /// CIDR 原样写入。
  var aclLine: String {
    switch identity.match {
    case .domainExact(let domain):
      return "|\(domain)"
    case .domainSuffix(let domain):
      return "||\(domain)"
    case .ipv4CIDR(let cidr), .ipv6CIDR(let cidr):
      return cidr
    }
  }
}
