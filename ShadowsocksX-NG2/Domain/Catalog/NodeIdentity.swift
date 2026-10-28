import Foundation

/// 节点来源：手动子树与订阅子树严格分离（GLOSSARY.md「Relationships and invariants」）。
enum NodeSource: String, Codable, Equatable, Sendable {
  case manual
  case subscription
}

/// 节点持久身份：不透明字符串。手动节点每次新建生成全新 UUID，身份不随
/// 显示名、位置或父节点变化，也不复用于其他逻辑节点；订阅节点使用供应商
/// 稳定 ID（作用域限本订阅，由订阅数据保证唯一），此处仅供夹具使用。
struct NodeID: Hashable, Codable, Sendable {
  let rawValue: String

  init(rawValue: String) { self.rawValue = rawValue }

  /// 手动新建节点身份。
  static func fresh() -> NodeID { NodeID(rawValue: UUID().uuidString.lowercased()) }

  init(from decoder: Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(String.self)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}
