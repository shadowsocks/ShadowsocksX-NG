import Darwin
import Foundation

/// One server record as it appeared in the Legacy `ServerProfiles` array.
/// Optional fields are intentional: malformed records are reported and skipped
/// by the planner instead of being force-cast like the historical app did.
struct LegacyServerSnapshot: Equatable, Sendable {
  let index: Int
  let isDictionary: Bool
  let id: String?
  let address: String?
  let port: Int?
  let method: String?
  let password: String?
  let remark: String?
  let plugin: String?
  let pluginOptions: String?
}

/// Read-only snapshot of the persisted Legacy server records. Legacy
/// preferences are deliberately not part of the import projection.
struct LegacySnapshot: Equatable, Sendable {
  let profiles: [LegacyServerSnapshot]
  let hasServerRecords: Bool

  init(propertyList: [String: Any]) throws {
    if let rawProfiles = propertyList["ServerProfiles"] {
      guard let profileValues = rawProfiles as? [Any] else {
        throw LegacyImportError.malformedSnapshot
      }
      profiles = profileValues.enumerated().map { index, rawValue in
        Self.profileSnapshot(index: index, rawValue: rawValue)
      }
    } else {
      profiles = []
    }
    // An empty or preference-only Legacy domain is not an importable
    // snapshot, so first launch does not offer a misleading empty migration.
    hasServerRecords = !profiles.isEmpty
  }
}

extension LegacySnapshot {
  private static func profileSnapshot(index: Int, rawValue: Any) -> LegacyServerSnapshot {
    guard let values = rawValue as? [String: Any] else {
      return LegacyServerSnapshot(
        index: index, isDictionary: false, id: nil, address: nil, port: nil,
        method: nil, password: nil, remark: nil, plugin: nil, pluginOptions: nil)
    }
    return LegacyServerSnapshot(
      index: index,
      isDictionary: true,
      id: stringValue(values["Id"]),
      address: stringValue(values["ServerHost"]),
      port: intValue(values["ServerPort"]),
      method: stringValue(values["Method"]),
      password: stringValue(values["Password"]),
      remark: stringValue(values["Remark"]),
      plugin: stringValue(values["Plugin"]),
      pluginOptions: stringValue(values["PluginOptions"])
    )
  }

  private static func stringValue(_ value: Any?) -> String? {
    value as? String
  }

  private static func intValue(_ value: Any?) -> Int? {
    guard let value = value as? NSNumber else { return nil }
    return value.intValue
  }
}

/// Source seam for discovery and fixture injection.
protocol LegacySnapshotProviding {
  func readSnapshot() throws -> LegacySnapshot?
}

/// Reads only the persisted application domain, not registered defaults. This
/// prevents a fresh 2.0 process from mistaking registered Legacy defaults for a
/// user-owned Legacy installation.
struct UserDefaultsLegacySnapshotProvider: LegacySnapshotProviding {
  static let legacyBundleIdentifier = "com.qiuyuzhou.ShadowsocksX-NG"

  let defaults: UserDefaults
  let bundleIdentifier: String

  init(
    defaults: UserDefaults = .standard,
    bundleIdentifier: String = Self.legacyBundleIdentifier
  ) {
    self.defaults = defaults
    self.bundleIdentifier = bundleIdentifier
  }

  func readSnapshot() throws -> LegacySnapshot? {
    let values = defaults.persistentDomain(forName: bundleIdentifier) ?? [:]
    let snapshot = try LegacySnapshot(propertyList: values)
    return snapshot.hasServerRecords ? snapshot : nil
  }
}

/// Completion marker seam. `false` removes the marker rather than persisting a
/// false value, preserving the distinction between "skipped" and "completed".
protocol LegacyImportMarkerStoring {
  func isCompleted() throws -> Bool
  func setCompleted(_ completed: Bool) throws
}

struct UserDefaultsLegacyImportMarkerStore: LegacyImportMarkerStoring {
  static let key = "legacyImport.completed"

  let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func isCompleted() throws -> Bool {
    defaults.bool(forKey: Self.key)
  }

  func setCompleted(_ completed: Bool) throws {
    if completed {
      defaults.set(true, forKey: Self.key)
    } else {
      defaults.removeObject(forKey: Self.key)
    }
  }
}

protocol LegacyCatalogStoring {
  func load() throws -> CatalogDocument
  func save(_ document: CatalogDocument) throws
}

extension CatalogFileStore: LegacyCatalogStoring {}

struct LegacySkippedRecord: Equatable, Sendable {
  /// 点名跳过原因（typed，无成句文案；呈现归 presentation edge）。
  enum Reason: Error, Equatable, Sendable {
    case notDictionary
    case invalidAddress
    case invalidPort
    case invalidEncryptionMethod
    case missingPassword
  }

  let index: Int
  let description: String
  let reason: Reason
}

struct LegacyImportReport: Equatable, Sendable {
  let groupName: String
  let importedServerCount: Int
  let skippedRecords: [LegacySkippedRecord]
  let regeneratedIdentityCount: Int
}

struct LegacyImportOutcome: Equatable, Sendable {
  let groupID: NodeID
  let report: LegacyImportReport
}

enum LegacyImportError: Error, Equatable {
  case noSnapshot
  case alreadyCompleted
  case malformedSnapshot
  case commitFailed
}

struct LegacyImportPlan {
  let groupID: NodeID
  let document: CatalogDocument
  let credentials: [CredentialReference: String]
  let report: LegacyImportReport
}

/// Pure planning seam: translates one immutable Legacy snapshot into a new
/// manual subtree and credential references. No preferences or active target
/// state enter the plan.
struct LegacyImportPlanner {
  static func makePlan(
    snapshot: LegacySnapshot,
    existingDocument: CatalogDocument
  ) throws -> LegacyImportPlan {
    var catalog = existingDocument.catalog
    let now = Date()
    let groupName = nextGroupName(in: catalog)
    let groupID = try catalog.addGroup(groupName, now: now)
    let serverImport = try importServers(
      snapshot.profiles, into: &catalog, groupID: groupID, now: now)
    let report = LegacyImportReport(
      groupName: groupName,
      importedServerCount: serverImport.importedServerCount,
      skippedRecords: serverImport.skippedRecords,
      regeneratedIdentityCount: serverImport.regeneratedIdentityCount)
    return LegacyImportPlan(
      groupID: groupID,
      document: CatalogDocument(
        catalog: catalog, subscriptions: existingDocument.subscriptions,
        favoriteIDs: existingDocument.favoriteIDs),
      credentials: serverImport.credentials,
      report: report)
  }
}

extension LegacyImportPlanner {
  private struct ServerImportResult {
    let credentials: [CredentialReference: String]
    let skippedRecords: [LegacySkippedRecord]
    let regeneratedIdentityCount: Int
    let importedServerCount: Int
  }

  /// 通过逐字段校验的服务器数据（失败点由跳过记录承载）。
  private struct ValidatedServer {
    let address: String
    let port: Int
    let method: String
    let password: String
  }

  /// 单条档案的校验结果：有效数据或点名跳过记录。
  private enum ServerValidation {
    case valid(ValidatedServer)
    case skipped(LegacySkippedRecord)
  }

  private static func importServers(
    _ profiles: [LegacyServerSnapshot],
    into catalog: inout ConfigurationCatalog,
    groupID: NodeID,
    now: Date
  ) throws -> ServerImportResult {
    var credentials: [CredentialReference: String] = [:]
    var skippedRecords: [LegacySkippedRecord] = []
    var regeneratedIdentityCount = 0
    var importedServerCount = 0
    let usedLegacyIDs = legacyIDCounts(of: profiles)

    for profile in profiles {
      switch validatedServer(of: profile) {
      case .skipped(let skipped):
        skippedRecords.append(skipped)
      case .valid(let server):
        let passwordRef = CredentialReference.fresh()
        credentials[passwordRef] = server.password
        let pluginOptionsRef = storedPluginOptions(of: profile, into: &credentials)
        let nodeID: NodeID
        if let reused = reusableLegacyID(
          of: profile, usedLegacyIDs: usedLegacyIDs, in: catalog)
        {
          nodeID = reused
        } else {
          nodeID = .fresh()
          regeneratedIdentityCount += 1
        }
        let fields = ServerFields(
          address: server.address,
          port: server.port,
          encryptionMethod: server.method,
          passwordRef: passwordRef,
          remark: profile.remark ?? "",
          pluginProgram: profile.plugin?.isEmpty == false ? profile.plugin : nil,
          pluginOptionsRef: pluginOptionsRef)
        try catalog.addServer(fields, id: nodeID, to: groupID, now: now)
        importedServerCount += 1
      }
    }

    return ServerImportResult(
      credentials: credentials,
      skippedRecords: skippedRecords,
      regeneratedIdentityCount: regeneratedIdentityCount,
      importedServerCount: importedServerCount)
  }

  /// 逐字段校验并点名失败原因：非字典、地址、端口、加密方式、密码。
  private static func validatedServer(
    of profile: LegacyServerSnapshot
  ) -> ServerValidation {
    guard profile.isDictionary else {
      return .skipped(
        LegacySkippedRecord(
          index: profile.index, description: String(localized: "第 \(profile.index + 1) 条记录"),
          reason: .notDictionary))
    }
    guard let address = profile.address?.trimmingCharacters(in: .whitespacesAndNewlines),
      !address.isEmpty, isValidHost(address)
    else {
      return .skipped(
        LegacySkippedRecord(
          index: profile.index,
          description: profile.address ?? String(localized: "第 \(profile.index + 1) 条记录"),
          reason: .invalidAddress))
    }
    guard let port = profile.port, (1...65_535).contains(port) else {
      return .skipped(
        LegacySkippedRecord(index: profile.index, description: address, reason: .invalidPort))
    }
    guard let method = profile.method?.trimmingCharacters(in: .whitespacesAndNewlines),
      !method.isEmpty
    else {
      return .skipped(
        LegacySkippedRecord(
          index: profile.index, description: address, reason: .invalidEncryptionMethod))
    }
    guard let password = profile.password, !password.isEmpty else {
      return .skipped(
        LegacySkippedRecord(index: profile.index, description: address, reason: .missingPassword))
    }
    return .valid(
      ValidatedServer(address: address, port: port, method: method, password: password))
  }

  /// 插件选项非空即写入凭据存储并返回其引用；否则 nil。
  private static func storedPluginOptions(
    of profile: LegacyServerSnapshot, into credentials: inout [CredentialReference: String]
  ) -> CredentialReference? {
    guard let pluginOptions = profile.pluginOptions, !pluginOptions.isEmpty else { return nil }
    let reference = CredentialReference.fresh()
    credentials[reference] = pluginOptions
    return reference
  }

  /// 旧 UUID 可复用仅当合法、全表唯一且不与目录现有节点等价；否则 nil（发新身份）。
  private static func reusableLegacyID(
    of profile: LegacyServerSnapshot, usedLegacyIDs: [String: Int],
    in catalog: ConfigurationCatalog
  ) -> NodeID? {
    guard let rawID = profile.id, UUID(uuidString: rawID) != nil,
      usedLegacyIDs[legacyIdentityKey(rawID)] == 1, !containsEquivalentNodeID(rawID, in: catalog)
    else { return nil }
    return NodeID(rawValue: rawID)
  }

  private static func legacyIDCounts(of profiles: [LegacyServerSnapshot]) -> [String: Int] {
    var counts: [String: Int] = [:]
    for profile in profiles {
      if let id = profile.id { counts[legacyIdentityKey(id), default: 0] += 1 }
    }
    return counts
  }

  private static func legacyIdentityKey(_ rawID: String) -> String {
    UUID(uuidString: rawID)?.uuidString.lowercased() ?? rawID
  }

  private static func containsEquivalentNodeID(
    _ rawID: String,
    in catalog: ConfigurationCatalog
  ) -> Bool {
    let identityKey = legacyIdentityKey(rawID)
    return catalog.entries.keys.contains { existingID in
      existingID.rawValue == rawID || legacyIdentityKey(existingID.rawValue) == identityKey
    }
  }

  private static func nextGroupName(in catalog: ConfigurationCatalog) -> String {
    let base = String(localized: "Legacy 导入")
    let names = Set(
      catalog.entries.values.compactMap { entry -> String? in
        guard case .group(let fields) = entry.kind else { return nil }
        return fields.name
      })
    guard names.contains(base) else { return base }
    var suffix = 2
    while names.contains("\(base) \(suffix)") { suffix += 1 }
    return "\(base) \(suffix)"
  }

  private static func isValidHost(_ value: String) -> Bool {
    var ipv4 = in_addr()
    if value.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 { return true }
    var ipv6 = in6_addr()
    if value.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 { return true }
    let pattern =
      "^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\\-]*[a-zA-Z0-9])\\.)*([A-Za-z0-9]|[A-Za-z0-9][a-zA-Z0-9\\-]*[A-Za-z0-9])$"
    return value.range(of: pattern, options: .regularExpression) != nil
  }
}
