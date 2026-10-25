import CryptoKit
import Foundation

/// SIP-008 服务器记录的已校验明文形态（凭据尚未入存储）。
struct RemoteServerRecord: Equatable, Sendable {
  var address: String
  var port: Int
  var encryptionMethod: String
  var password: String
  var remark: String
  var pluginProgram: String?
  var pluginOptions: String?
}

/// 解析完成的订阅快照：SIP-008 `version: 1` 扁平
/// `servers` + 可选私有扩展 `x_shadowsocksx_ng`。身份已按订阅作用域限定
/// （服务器引用复用 `servers[].id`；无稳定 ID 的记录用地址端口指纹，
/// 相同端点延续身份）；结构、顺序、名称全部远端权威。扩展缺失/未知/
/// 无效时回退标准扁平列表（根分组无名称，由调用方以 URL host 兜底）。
struct SubscriptionSnapshot: Equatable, Sendable {
  struct ServerLeaf: Equatable, Sendable {
    let id: NodeID
    let record: RemoteServerRecord
  }

  /// 有序子引用：顺序即远端 `children` 的用户可见顺序（不按类型拆分）。
  enum Child: Equatable, Sendable {
    case group(Group)
    case server(ServerLeaf)
  }

  struct Group: Equatable, Sendable {
    /// 分组身份（按订阅作用域限定）。根分组的 `id` 不参与挂载——订阅固定
    /// 分组身份客户端所有，应用时由 `groupID` 入参决定。
    let id: NodeID
    let name: String
    var children: [Child]
  }

  /// 根分组内容：落入订阅固定分组（固定分组身份客户端所有，不取自远端）。
  let root: Group
  var information = SubscriptionInformation()
  var autoUpdatePolicy: SubscriptionUpdatePolicyResult = .absent
}

/// 快照解析失败（整份拒绝，不做部分提交； 刷新失败族）。
enum SubscriptionParseError: Error, Equatable, Sendable {
  /// 正文不是合法 JSON 或顶层结构与 SIP-008 不符。
  case decodingFailure
  /// `version` 缺失或不是本客户端支持的版本。
  case unsupportedSchemaVersion
  /// `servers` 缺失或不是数组。
  case missingServers
  /// 单条服务器记录校验失败（地址/端口/加密/密码/ID 形态）。
  case recordValidation(index: Int, reason: String)
  /// `servers[].id` 重复（身份不复用）。
  case duplicateServerID(id: String)
}

/// SIP-008 v1 文档解析器。先按标准解析并校验根 `version` 与 `servers` 建立
/// 扁平候选集，再尝试私有扩展建树；扩展任何无效都不影响标准列表（回退扁平）。
enum SubscriptionDocumentParser {
  static func parse(_ data: Data, subscriptionID: NodeID) throws -> SubscriptionSnapshot {
    let root: RootDTO
    do {
      root = try JSONDecoder().decode(RootDTO.self, from: data)
    } catch {
      throw SubscriptionParseError.decodingFailure
    }
    guard root.version == 1 else { throw SubscriptionParseError.unsupportedSchemaVersion }
    guard let serverDTOs = root.servers else { throw SubscriptionParseError.missingServers }

    // 标准 `servers` 列表先独立解析为扁平候选集（保持数组顺序）。
    var leaves: [KeyedLeaf] = []
    var recordsByID: [String: RemoteServerRecord] = [:]
    for (index, dto) in serverDTOs.enumerated() {
      let record = try validatedRecord(dto, index: index)
      let key = remoteKey(dto, record: record)
      guard !leaves.contains(where: { $0.key == key }) else {
        throw SubscriptionParseError.duplicateServerID(id: key)
      }
      let id = NodeID(rawValue: "\(subscriptionID.rawValue):\(key)")
      leaves.append(KeyedLeaf(key: key, leaf: .init(id: id, record: record)))
      recordsByID[key] = record
    }

    guard let tree = resolveExtension(root.extensionNS?.value, records: recordsByID) else {
      return SubscriptionSnapshot(
        root: SubscriptionSnapshot.Group(
          id: NodeID(rawValue: "\(subscriptionID.rawValue):root"),
          name: "", children: leaves.map { .server($0.leaf) }),
        information: SubscriptionInformation.parse(data),
        autoUpdatePolicy: root.extensionNS?.policy ?? .absent)
    }
    var snapshot = buildSnapshot(tree: tree, leaves: leaves, subscriptionID: subscriptionID)
    snapshot.information = SubscriptionInformation.parse(data)
    snapshot.autoUpdatePolicy = root.extensionNS?.policy ?? .absent
    return snapshot
  }

  // MARK: - 服务器记录校验与身份

  /// 带命名空间键的叶子：键优先为供应商稳定 ID（`id:<uuid>`）；无稳定 ID 的
  /// 记录用地址端口指纹（`content:<sha256>`）。
  private struct KeyedLeaf {
    var key: String
    var leaf: SubscriptionSnapshot.ServerLeaf
  }

  /// 单条记录校验：必填字段与取值范围；任一失败整份快照拒绝。
  private static func validatedRecord(_ dto: ServerDTO, index: Int) throws -> RemoteServerRecord {
    guard let address = dto.server, !address.isEmpty else {
      throw SubscriptionParseError.recordValidation(index: index, reason: "server 缺失或为空")
    }
    guard let port = dto.serverPort, (1...65_535).contains(port) else {
      throw SubscriptionParseError.recordValidation(
        index: index, reason: "server_port 缺失或超出 1–65535")
    }
    guard let method = dto.method, !method.isEmpty else {
      throw SubscriptionParseError.recordValidation(index: index, reason: "method 缺失或为空")
    }
    guard let password = dto.password, !password.isEmpty else {
      throw SubscriptionParseError.recordValidation(index: index, reason: "password 缺失或为空")
    }
    if let id = dto.id, UUID(uuidString: id) == nil {
      throw SubscriptionParseError.recordValidation(index: index, reason: "id 不是合法 UUID")
    }
    return RemoteServerRecord(
      address: address,
      port: port,
      encryptionMethod: method,
      password: password,
      remark: dto.remarks ?? "",
      pluginProgram: (dto.plugin?.isEmpty == false) ? dto.plugin : nil,
      pluginOptions: dto.pluginOpts)
  }

  /// 记录的命名空间键：优先供应商稳定 ID；无 ID 时相同地址和端口延续身份。
  private static func remoteKey(_ dto: ServerDTO, record: RemoteServerRecord) -> String {
    if let id = dto.id { return "id:\(id)" }
    return "content:\(endpointFingerprint(record))"
  }

  /// 无稳定 ID 记录的端点指纹：地址与端口长度前缀拼接后 SHA-256，避免拼接歧义。
  /// 名称、密码、加密方式和插件不参与，远端更新这些值不改变身份。
  private static func endpointFingerprint(_ record: RemoteServerRecord) -> String {
    let parts = [record.address, String(record.port)]
    let canonical = parts.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
    let digest = SHA256.hash(data: Data(canonical.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  // MARK: - 私有扩展

  /// 扩展树解析结果；解析函数返回 `nil` 即扩展缺失/未知/无效 → 回退扁平列表。
  private struct ExtensionTree {
    var rootGroupID: String
    var groups: [String: ExtensionGroup]
  }

  private struct ExtensionGroup {
    var name: String
    var children: [ExtensionChild]
  }

  private enum ExtensionChild {
    case group(String)
    case server(String)
  }

  /// 扩展校验：schema_version 支持、分组 ID 唯一且与服务器 ID 不冲突、根存在、
  /// 子引用可解析、单父且无环。任一不满足即返回 `nil` 回退扁平（不抛错——
  /// 私有字段损坏不能丢掉标准服务器；解析失败时回退到扁平列表。
  private static func resolveExtension(
    _ dto: ExtensionDTO?, records: [String: RemoteServerRecord]
  ) -> ExtensionTree? {
    guard let dto else { return nil }
    guard dto.schemaVersion == 1 else { return nil }
    guard let rootGroupID = dto.rootGroupID, !rootGroupID.isEmpty else { return nil }
    guard let groupDTOs = dto.groups else { return nil }

    var groups: [String: ExtensionGroup] = [:]
    for groupDTO in groupDTOs {
      guard let parsed = extensionGroup(from: groupDTO, existing: groups, records: records) else {
        return nil
      }
      groups[parsed.id] = parsed.group
    }
    guard groups[rootGroupID] != nil else { return nil }
    guard isSingleParentTree(rootedAt: rootGroupID, groups: groups, records: records) else {
      return nil
    }
    return ExtensionTree(rootGroupID: rootGroupID, groups: groups)
  }

  /// 单个分组 DTO → 带唯一 ID 的分组；ID 缺失、与已有分组或服务器 ID 冲突、
  /// 子引用类型未知即拒绝（分组 ID 与服务器 ID 在整个扩展文档内保持唯一，
  /// 子引用类型未知时拒绝该扩展。
  private static func extensionGroup(
    from groupDTO: GroupDTO, existing: [String: ExtensionGroup],
    records: [String: RemoteServerRecord]
  ) -> (id: String, group: ExtensionGroup)? {
    guard let id = groupDTO.id, !id.isEmpty else { return nil }
    guard existing[id] == nil, records["id:\(id)"] == nil else { return nil }
    var children: [ExtensionChild] = []
    for childDTO in groupDTO.children ?? [] {
      guard let childID = childDTO.id, !childID.isEmpty else { return nil }
      switch childDTO.type {
      case "group": children.append(.group(childID))
      case "server": children.append(.server(childID))
      default: return nil
      }
    }
    return (id, ExtensionGroup(name: groupDTO.name ?? "", children: children))
  }

  /// 单父 + 无环：从根出发遍历，重复到达即共享父或环；服务器子引用复用
  /// `servers[].id`，无稳定 ID 的记录没有可引用身份（作为「未引用」落根分组）。
  private static func isSingleParentTree(
    rootedAt rootGroupID: String,
    groups: [String: ExtensionGroup],
    records: [String: RemoteServerRecord]
  ) -> Bool {
    var visited = Set<String>()
    func walk(_ groupID: String) -> Bool {
      guard visited.insert(groupID).inserted else { return false }
      guard let group = groups[groupID] else { return false }
      for child in group.children {
        switch child {
        case .group(let id):
          guard walk(id) else { return false }
        case .server(let id):
          guard records["id:\(id)"] != nil else { return false }
        }
      }
      return true
    }
    return walk(rootGroupID)
  }

  // MARK: - 快照组装

  private static func buildSnapshot(
    tree: ExtensionTree, leaves: [KeyedLeaf], subscriptionID: NodeID
  ) -> SubscriptionSnapshot {
    let leavesByKey = Dictionary(
      leaves.map { ($0.key, $0.leaf) }, uniquingKeysWith: { first, _ in first })
    var root = buildGroup(
      tree.groups[tree.rootGroupID]!, id: tree.rootGroupID, tree: tree,
      leavesByKey: leavesByKey, subscriptionID: subscriptionID)
    // 未被树引用的服务器仍在标准列表中：按 `servers` 数组顺序追加在根分组，
    // 不丢弃未被树引用的服务器；身份不变，被引用后即可自然归位。
    let referenced = collectReferencedServerKeys(tree)
    for keyed in leaves where !referenced.contains(keyed.key) {
      root.children.append(.server(keyed.leaf))
    }
    return SubscriptionSnapshot(root: root)
  }

  private static func buildGroup(
    _ group: ExtensionGroup, id providerID: String, tree: ExtensionTree,
    leavesByKey: [String: SubscriptionSnapshot.ServerLeaf], subscriptionID: NodeID
  ) -> SubscriptionSnapshot.Group {
    var children: [SubscriptionSnapshot.Child] = []
    for child in group.children {
      switch child {
      case .group(let id):
        guard let nested = tree.groups[id] else { continue }
        children.append(
          .group(
            buildGroup(
              nested, id: id, tree: tree, leavesByKey: leavesByKey,
              subscriptionID: subscriptionID)))
      case .server(let id):
        if let leaf = leavesByKey["id:\(id)"] {
          children.append(.server(leaf))
        }
      }
    }
    // 分组身份：供应商分组 ID 按订阅作用域限定；`g:` 前缀与服务器键形态区分。
    let groupID = NodeID(rawValue: "\(subscriptionID.rawValue):g:\(providerID)")
    return SubscriptionSnapshot.Group(id: groupID, name: group.name, children: children)
  }

  private static func collectReferencedServerKeys(_ tree: ExtensionTree) -> Set<String> {
    var referenced = Set<String>()
    for group in tree.groups.values {
      for child in group.children {
        if case .server(let id) = child {
          referenced.insert("id:\(id)")
        }
      }
    }
    return referenced
  }
}

// MARK: - SIP-008 DTO（全部字段宽松可选，严格校验在解析器内逐条点名）

private struct RootDTO: Decodable {
  var version: Int?
  var servers: [ServerDTO]?
  /// 扩展字段形状损坏（不是对象）不构成 SIP-008 失败：宽松解码为 nil 后
  /// 走「扩展无效 → 回退扁平」。
  var extensionNS: LenientExtension?

  enum CodingKeys: String, CodingKey {
    case version, servers
    case extensionNS = "x_shadowsocksx_ng"
  }
}

private struct ServerDTO: Decodable {
  var id: String?
  var remarks: String?
  var server: String?
  var serverPort: Int?
  var password: String?
  var method: String?
  var plugin: String?
  var pluginOpts: String?

  enum CodingKeys: String, CodingKey {
    case id, remarks, server, password, method, plugin
    case serverPort = "server_port"
    case pluginOpts = "plugin_opts"
  }
}

private struct LenientExtension: Decodable {
  var value: ExtensionDTO?
  var policy: SubscriptionUpdatePolicyResult = .invalid

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case autoUpdate = "auto_update"
  }

  init(from decoder: Decoder) throws {
    value = try? ExtensionDTO(from: decoder)
    guard let container = try? decoder.container(keyedBy: CodingKeys.self),
      (try? container.decode(Int.self, forKey: .schemaVersion)) == 1
    else { return }
    guard container.contains(.autoUpdate) else {
      policy = .absent
      return
    }
    if let parsed = try? container.decode(SubscriptionUpdatePolicy.self, forKey: .autoUpdate) {
      policy = .valid(parsed)
    }
  }
}

private struct ExtensionDTO: Decodable {
  var schemaVersion: Int?
  var rootGroupID: String?
  var groups: [GroupDTO]?

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case rootGroupID = "root_group_id"
    case groups
  }
}

private struct GroupDTO: Decodable {
  var id: String?
  var name: String?
  var children: [ChildDTO]?
}

private struct ChildDTO: Decodable {
  var type: String?
  var id: String?
}
