import CryptoKit
import Foundation

/// Fixed local targets bypass the system proxy. Their IP ranges and host rules
/// also enter the sslocal ACL for requests reaching either inbound.
enum FixedLocalProxyRanges {
  static let ipRanges = [
    "127.0.0.0/8",
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16",
    "169.254.0.0/16",
    "::1/128",
    "fe80::/10",
    "fc00::/7",
  ]

  static let systemProxyHostExceptions = ["localhost", "*.local"]

  static var systemProxyExceptions: [String] {
    ipRanges + systemProxyHostExceptions
  }

  static func systemProxyExceptions(including values: [String]?) -> [String] {
    var result: [String] = []
    var seen = Set<String>()
    for value in systemProxyExceptions + (values ?? []) {
      let identity = value.lowercased()
      guard seen.insert(identity).inserted else { continue }
      result.append(value)
    }
    return result
  }

  static let aclHostRules = ["||localhost", "||local", "^[^.]+$"]

  static var aclBypassRules: [String] {
    ipRanges + aclHostRules
  }
}

/// A generated sslocal ACL and its runtime identity (ADR-0011). The contract
/// carries only path/summary/sha256; `content` stays in memory for the GUI's
/// variant-file write and is never serialized. Identity equality ignores content
/// so a decoded (empty-content) document compares equal to its generated source.
struct ProxyACLDocument: Codable, Equatable, Sendable {
  let path: String
  let summary: String
  let content: String
  let sha256: String

  enum CodingKeys: String, CodingKey {
    case path, summary, sha256
  }

  init(path: String, summary: String, content: String) {
    self.init(path: path, summary: summary, content: content, sha256: Self.digest(content))
  }

  init(path: String, summary: String, content: String, sha256: String) {
    self.path = path
    self.summary = summary
    self.content = content
    self.sha256 = sha256
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    path = try container.decode(String.self, forKey: .path)
    summary = try container.decode(String.self, forKey: .summary)
    sha256 = try container.decode(String.self, forKey: .sha256)
    content = ""
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(path, forKey: .path)
    try container.encode(summary, forKey: .summary)
    try container.encode(sha256, forKey: .sha256)
  }

  static func == (lhs: ProxyACLDocument, rhs: ProxyACLDocument) -> Bool {
    lhs.path == rhs.path && lhs.summary == rhs.summary && lhs.sha256 == rhs.sha256
  }

  /// Direct mode deliberately has no `proxy_list`: `bypass_all` supplies the
  /// default, while the explicit fixed-local entries remain a safety policy
  /// shared by SOCKS and HTTP and reusable by later routing modes.
  static func direct(at fileURL: URL) -> ProxyACLDocument {
    makeDocument(
      at: fileURL, header: "[bypass_all]", summary: "direct")
  }

  /// 全局模式：公网目标默认走 Shadowsocks 代理，本地网络目标固定
  /// 直连。ACL 只含固定本地安全绕过，不混入中国列表、GFWList 或自定义规则；
  /// SOCKS、HTTP 入站与局域网共享客户端共用此策略。IPv6 系统例外不构成已验证
  /// 的绕过保证，本 ACL 才是路由兜底。
  static func global(at fileURL: URL) -> ProxyACLDocument {
    makeDocument(
      at: fileURL, header: "[proxy_all]", summary: "global")
  }

  /// 规则模式：默认动作决定 ACL 骨架，调用方按默认动作
  /// 传入对应来源的候选（两种默认动作不把全部内置来源无条件并集）。
  ///
  /// - 「未匹配时代理」：`proxy_all` + 中国域名/CIDR 直连候选进 `bypass_list`。
  /// - 「未匹配时直连」：`bypass_all` + GFWList 可生效代理规则进 `proxy_list`；
  /// 未匹配目标与无可用规则命中的 IP 字面目标直连。
  ///
  /// 固定本地绕过优先；CIDR 判定可能触发本地 DNS 查询。
  static func rule(
    at fileURL: URL,
    defaultAction: RuleDefaultAction,
    rules: [ProxyRule]
  ) -> ProxyACLDocument {
    // Select expressed actions before any coverage analysis. Keep fixed policy
    // first; equivalent source entries and array order never change ACL bytes.
    let directLines = Array(Set(rules.filter { $0.action == .direct }.map(\.aclLine)))
      .filter { !FixedLocalProxyRanges.aclBypassRules.contains($0) }.sorted()
    let proxyLines = Array(Set(rules.filter { $0.action == .proxy }.map(\.aclLine))).sorted()
    switch defaultAction {
    case .proxyWhenUnmatched:
      // proxy_all + 直连候选进 bypass_list（中国域名 / IPv4 CIDR）。
      let bypass =
        FixedLocalProxyRanges.aclBypassRules
        + directLines
      return makeDocument(
        at: fileURL, header: "[proxy_all]", summary: "rule-proxy-default",
        bypassRules: bypass, proxyRules: [])
    case .directWhenUnmatched:
      // bypass_all + GFWList 可生效规则：代理候选进 proxy_list，未遮蔽例外
      // 进 bypass_list。两种默认动作不无条件并集中国来源。
      let bypass =
        FixedLocalProxyRanges.aclBypassRules
        + directLines
      let proxy = proxyLines
      return makeDocument(
        at: fileURL, header: "[bypass_all]", summary: "rule-direct-default",
        bypassRules: bypass, proxyRules: proxy)
    }
  }

  private static func makeDocument(
    at fileURL: URL, header: String, summary: String,
    bypassRules: [String] = FixedLocalProxyRanges.aclBypassRules,
    proxyRules: [String] = []
  ) -> ProxyACLDocument {
    var lines = [header, "[bypass_list]"] + bypassRules
    if !proxyRules.isEmpty {
      lines.append("[proxy_list]")
      lines.append(contentsOf: proxyRules)
    }
    return ProxyACLDocument(
      path: fileURL.standardizedFileURL.path,
      summary: summary,
      content: lines.joined(separator: "\n") + "\n")
  }

  var isWellFormed: Bool {
    guard
      path.hasPrefix("/"),
      !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      sha256.count == 64,
      sha256.allSatisfy({ $0.isHexDigit })
    else { return false }
    // 生成侧携带 content 时自证摘要；解码侧无 content，按身份形状收下
    // （ADR-0011：Agent 不读 sidecar，摘要一致性由 GUI 写入序保证）。
    if content.isEmpty { return true }
    return content.utf8.allSatisfy { $0 < 128 }
      && sha256 == Self.digest(content)
  }

  static func digest(_ content: String) -> String {
    digest(Data(content.utf8))
  }

  static func digest(_ data: Data) -> String {
    SHA256.hash(data: data)
      .map { String(format: "%02x", $0) }
      .joined()
  }
}

/// Identifies the deployed sslocal child. The wrapper publishes ACL-backed
/// receipts only after that child owns every configured TCP listener.
struct RuntimeDeploymentReceipt: Codable, Equatable, Sendable {
  let processID: Int32
  let contractSHA256: String
}
