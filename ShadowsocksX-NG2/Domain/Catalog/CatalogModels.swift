import Foundation

/// 服务器叶子字段。密码与插件参数只持凭据引用，秘密值在
/// Keychain；插件程序引用原样保留，是否可用由激活校验判定。
struct ServerFields: Codable, Equatable, Sendable {
  var address: String
  var port: Int
  var encryptionMethod: String
  var passwordRef: CredentialReference
  var remark: String
  var pluginProgram: String?
  var pluginOptionsRef: CredentialReference?

  init(
    address: String,
    port: Int,
    encryptionMethod: String,
    passwordRef: CredentialReference,
    remark: String = "",
    pluginProgram: String? = nil,
    pluginOptionsRef: CredentialReference? = nil
  ) {
    self.address = address
    self.port = port
    self.encryptionMethod = encryptionMethod
    self.passwordRef = passwordRef
    self.remark = Self.name(remark, address: address, port: port)
    self.pluginProgram = pluginProgram
    self.pluginOptionsRef = pluginOptionsRef
  }

  /// 导入与字段构造共用名称规则；非空名称原样保留，缺名时生成并保存端点名。
  /// 后续修改地址或端口不改变已经保存的名称。`remark` 保留既有存储字段名。
  private static func name(_ supplied: String, address: String, port: Int) -> String {
    guard supplied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return supplied
    }
    let host =
      address.hasPrefix("[") && address.hasSuffix("]")
      ? String(address.dropFirst().dropLast()) : address
    return host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
  }
}

/// 分组：命名的有序容器，显式持有子节点顺序（GLOSSARY.md「Configuration group」）。
struct GroupFields: Codable, Equatable, Sendable {
  var name: String
  var children: [NodeID]

  init(name: String, children: [NodeID] = []) {
    self.name = name
    self.children = children
  }
}

/// 目录树节点：公共字段（身份、来源、节点时间戳）+ 服务器叶子/分组形态。
struct CatalogEntry: Codable, Equatable, Sendable {
  enum Kind: Codable, Equatable, Sendable {
    case server(ServerFields)
    case group(GroupFields)
  }

  let id: NodeID
  var source: NodeSource
  var kind: Kind
  /// 节点进入目录的时刻；历史文档未记录时为 nil（未知，不回填，ADR-0031）。
  let createdAt: Date?
  /// 节点自身资料、或分组的直接子节点集合与顺序最后一次变化的时刻；未知为 nil。
  var updatedAt: Date?

  private enum CodingKeys: String, CodingKey {
    case id, source, enabled, kind, createdAt, updatedAt
  }

  init(id: NodeID, source: NodeSource, kind: Kind, createdAt: Date?, updatedAt: Date?) {
    self.id = id
    self.source = source
    self.kind = kind
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  /// Reads the removed `enabled` field from v1/v2 documents only for migration;
  /// its value has no meaning in the current domain model. Node timestamps are
  /// absent in v1–v4 documents and decode as nil (unknown, never backfilled).
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(NodeID.self, forKey: .id)
    source = try container.decode(NodeSource.self, forKey: .source)
    _ = try container.decodeIfPresent(Bool.self, forKey: .enabled)
    kind = try container.decode(Kind.self, forKey: .kind)
    createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
    updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(source, forKey: .source)
    try container.encode(kind, forKey: .kind)
    try container.encodeIfPresent(createdAt, forKey: .createdAt)
    try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
  }
}

extension CatalogEntry {
  /// 行显示名（主窗口侧栏与菜单栏级联共用口径）：服务器使用已保存的名称，
  /// 导入缺名已在字段构造时补全；分组用名称。
  var displayName: String {
    switch kind {
    case .group(let fields):
      return fields.name
    case .server(let fields):
      return fields.remark
    }
  }
}
