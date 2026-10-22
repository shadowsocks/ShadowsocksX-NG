import Foundation

/// 服务器叶子字段。密码与插件参数由记录持有，随服务器库整体加密；
/// 插件程序引用原样保留，是否可用由激活校验判定。
struct ServerFields: Codable, Equatable, Sendable {
  var address: String
  var port: Int
  var encryptionMethod: String
  var password: String
  var remark: String
  var pluginProgram: String?
  var pluginOptions: String?

  init(
    address: String,
    port: Int,
    encryptionMethod: String,
    password: String,
    remark: String = "",
    pluginProgram: String? = nil,
    pluginOptions: String? = nil
  ) {
    self.address = address
    self.port = port
    self.encryptionMethod = encryptionMethod
    self.password = password
    self.remark = Self.name(remark, address: address, port: port)
    self.pluginProgram = pluginProgram
    self.pluginOptions = pluginOptions
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

  init(id: NodeID, source: NodeSource, kind: Kind, createdAt: Date?, updatedAt: Date?) {
    self.id = id
    self.source = source
    self.kind = kind
    self.createdAt = createdAt
    self.updatedAt = updatedAt
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
