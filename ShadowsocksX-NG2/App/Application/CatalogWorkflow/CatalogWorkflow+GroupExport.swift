import CryptoKit
import Foundation

struct ConfigurationGroupExportDraft: Equatable {
  let data: Data
  let suggestedFileName: String
  var format: Format = .json

  enum Format: Equatable {
    case json
    case uriList
  }
}

struct ConfigurationGroupShareDraft {
  let json: ConfigurationGroupExportDraft
  let uriList: ConfigurationGroupExportDraft
  let uriText: String
}

enum ConfigurationGroupExportFailure: Equatable, Error {
  enum RecordProblem: Equatable {
    case invalidAddress
    case invalidPort
    case missingEncryptionMethod
    case missingPassword
  }

  case groupNotFound
  case targetIsNotGroup
  case noServers
  case invalidServer(NodeID, RecordProblem)
  case pluginOptionsWithoutProgram(NodeID)
  case documentEncodingFailed
}

extension CatalogWorkflow {
  /// 两种分享格式从同一完整校验结果准备，任何服务器失败都不产生部分输出。
  func configurationGroupShareDraft(for groupID: NodeID) throws -> ConfigurationGroupShareDraft {
    let catalog = dependencies.coordinator.committedCatalog
    guard let root = catalog.entry(for: groupID) else {
      throw ConfigurationGroupExportFailure.groupNotFound
    }
    guard case .group(let fields) = root.kind else {
      throw ConfigurationGroupExportFailure.targetIsNotGroup
    }
    var builder = SIP008GroupExportDocumentBuilder(
      catalog: catalog)
    let json = try builder.encode(rootID: groupID)
    let text = builder.uriListText
    let name = fields.name.replacingOccurrences(of: "/", with: " ")
      .replacingOccurrences(of: ":", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    let base = name.isEmpty ? "ss-servers" : name
    return ConfigurationGroupShareDraft(
      json: ConfigurationGroupExportDraft(data: json, suggestedFileName: "\(base).json"),
      uriList: ConfigurationGroupExportDraft(
        data: Data(text.utf8), suggestedFileName: "\(base).txt", format: .uriList),
      uriText: text)
  }

  /// Prepares a complete SIP-008 v1 snapshot for one group. Credentials are resolved
  /// here so the returned draft is the only secret-bearing value passed to the exporter.
  func configurationGroupExportDraft(for groupID: NodeID) throws -> ConfigurationGroupExportDraft {
    let catalog = dependencies.coordinator.committedCatalog
    guard let root = catalog.entry(for: groupID) else {
      throw ConfigurationGroupExportFailure.groupNotFound
    }
    guard case .group(let rootFields) = root.kind else {
      throw ConfigurationGroupExportFailure.targetIsNotGroup
    }

    var document = SIP008GroupExportDocumentBuilder(
      catalog: catalog)
    let data = try document.encode(rootID: groupID)
    return ConfigurationGroupExportDraft(
      data: data, suggestedFileName: "\(rootFields.name).json")
  }
}

private struct SIP008GroupExportDocumentBuilder {
  private let catalog: ConfigurationCatalog
  private var servers: [SIP008ServerDTO] = []
  private var groups: [SIP008GroupDTO] = []
  private let identities = SIP008ExportIdentity()

  var uriListText: String {
    servers.map {
      SsUri(
        method: $0.method, password: $0.password, host: $0.server, port: $0.serverPort,
        pluginProgram: $0.plugin, pluginOptions: $0.pluginOptions,
        remark: $0.remarks.isEmpty ? nil : $0.remarks
      ).encode()
    }.joined(separator: "\n")
  }

  init(catalog: ConfigurationCatalog) {
    self.catalog = catalog
  }

  mutating func encode(rootID: NodeID) throws -> Data {
    let rootGroupID = try appendGroup(rootID)
    guard !servers.isEmpty else { throw ConfigurationGroupExportFailure.noServers }

    let document = SIP008DocumentDTO(
      version: 1,
      servers: servers,
      groupExtension: SIP008GroupExtensionDTO(
        schemaVersion: 1, rootGroupID: rootGroupID, groups: groups))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    do {
      return try encoder.encode(document)
    } catch {
      throw ConfigurationGroupExportFailure.documentEncodingFailed
    }
  }

  private mutating func appendGroup(_ id: NodeID) throws -> String {
    guard let entry = catalog.entry(for: id), case .group(let fields) = entry.kind else {
      throw ConfigurationGroupExportFailure.groupNotFound
    }

    let exportID = identities.groupID(for: id)
    var children: [SIP008ChildDTO] = []
    for childID in fields.children {
      guard let child = catalog.entry(for: childID) else {
        throw ConfigurationGroupExportFailure.groupNotFound
      }
      switch child.kind {
      case .group:
        let childExportID = try appendGroup(childID)
        children.append(SIP008ChildDTO(type: "group", id: childExportID))
      case .server(let serverFields):
        let serverID = try appendServer(child, fields: serverFields)
        children.append(SIP008ChildDTO(type: "server", id: serverID))
      }
    }

    groups.append(SIP008GroupDTO(id: exportID, name: fields.name, children: children))
    return exportID
  }

  private mutating func appendServer(_ entry: CatalogEntry, fields: ServerFields) throws -> String {
    guard !fields.address.isEmpty else {
      throw ConfigurationGroupExportFailure.invalidServer(entry.id, .invalidAddress)
    }
    guard (1...65_535).contains(fields.port) else {
      throw ConfigurationGroupExportFailure.invalidServer(entry.id, .invalidPort)
    }
    guard !fields.encryptionMethod.isEmpty else {
      throw ConfigurationGroupExportFailure.invalidServer(entry.id, .missingEncryptionMethod)
    }

    guard !fields.password.isEmpty else {
      throw ConfigurationGroupExportFailure.invalidServer(entry.id, .missingPassword)
    }
    let password = fields.password

    let pluginProgram = fields.pluginProgram.flatMap { $0.isEmpty ? nil : $0 }
    let pluginOptions = fields.pluginOptions.flatMap { $0.isEmpty ? nil : $0 }
    guard pluginProgram != nil || pluginOptions == nil else {
      throw ConfigurationGroupExportFailure.pluginOptionsWithoutProgram(entry.id)
    }

    let serverID = identities.serverID(for: entry)
    servers.append(
      SIP008ServerDTO(
        id: serverID,
        remarks: fields.remark,
        server: fields.address,
        serverPort: fields.port,
        password: password,
        method: fields.encryptionMethod,
        plugin: pluginProgram,
        pluginOptions: pluginOptions))
    return serverID
  }

}

private struct SIP008ExportIdentity {
  private static let namespace = UUID(uuidString: "0d89e9f8-8f0e-4a55-941a-77d61736eaa3")!

  func groupID(for nodeID: NodeID) -> String {
    Self.version5(name: "group:\(nodeID.rawValue)").uuidString.lowercased()
  }

  func serverID(for entry: CatalogEntry) -> String {
    if entry.source == .manual, let id = UUID(uuidString: entry.id.rawValue) {
      return id.uuidString.lowercased()
    }
    if entry.source == .subscription,
      let providerID = subscriptionServerID(entry.id), let id = UUID(uuidString: providerID)
    {
      return id.uuidString.lowercased()
    }
    return Self.version5(name: "server:\(entry.id.rawValue)").uuidString.lowercased()
  }

  private func subscriptionServerID(_ nodeID: NodeID) -> String? {
    guard let marker = nodeID.rawValue.range(of: ":id:", options: .backwards) else { return nil }
    return String(nodeID.rawValue[marker.upperBound...])
  }

  private static func version5(name: String) -> UUID {
    var bytes = withUnsafeBytes(of: namespace.uuid) { Array($0) }
    bytes.append(contentsOf: name.utf8)
    var digest = Array(Insecure.SHA1.hash(data: Data(bytes)).prefix(16))
    digest[6] = (digest[6] & 0x0f) | 0x50
    digest[8] = (digest[8] & 0x3f) | 0x80
    return UUID(
      uuid: (
        digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
        digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]
      ))
  }
}

private struct SIP008DocumentDTO: Encodable {
  let version: Int
  let servers: [SIP008ServerDTO]
  let groupExtension: SIP008GroupExtensionDTO

  enum CodingKeys: String, CodingKey {
    case version, servers
    case groupExtension = "x_shadowsocksx_ng"
  }
}

private struct SIP008ServerDTO: Encodable {
  let id: String
  let remarks: String
  let server: String
  let serverPort: Int
  let password: String
  let method: String
  let plugin: String?
  let pluginOptions: String?

  enum CodingKeys: String, CodingKey {
    case id, remarks, server, password, method, plugin
    case serverPort = "server_port"
    case pluginOptions = "plugin_opts"
  }
}

private struct SIP008GroupExtensionDTO: Encodable {
  let schemaVersion: Int
  let rootGroupID: String
  let groups: [SIP008GroupDTO]

  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case rootGroupID = "root_group_id"
    case groups
  }
}

private struct SIP008GroupDTO: Encodable {
  let id: String
  let name: String
  let children: [SIP008ChildDTO]
}

private struct SIP008ChildDTO: Encodable {
  let type: String
  let id: String
}
