import Foundation

enum CustomRuleStoreError: Error, Equatable, Sendable {
  case missing
  case corrupt(detail: String)
  case schemaVersionMismatch(found: Int, expected: Int)
  case ioFailure(detail: String)
}

/// 自定义规则持久化：独立 JSON 文档，原子写盘。
/// Saving intent is independent of subsequent ACL application and runtime recovery.
struct CustomRuleStore {
  static let currentSchemaVersion = 4

  let fileURL: URL
  let baseURL: URL
  let preset: RulePreset?

  init(fileURL: URL = CustomRuleStore.defaultFileURL()) {
    self.fileURL = fileURL
    self.baseURL = fileURL
    self.preset = nil
  }

  init(preset: RulePreset, baseURL: URL = CustomRuleStore.defaultFileURL()) {
    self.baseURL = baseURL
    self.preset = preset
    self.fileURL = baseURL.deletingLastPathComponent()
      .appendingPathComponent("rule-presets", isDirectory: true)
      .appendingPathComponent(preset.rawValue, isDirectory: true)
      .appendingPathComponent(baseURL.lastPathComponent)
  }

  static func defaultFileURL() -> URL {
    ApplicationSupportPaths.current.customRulesFileURL
  }

  /// 读取规则集合；文件不存在视为无自定义规则。
  func load() throws -> [CustomRule] { try loadDocument().rules }

  func loadDocument() throws -> CustomRuleDocument {
    let data: Data
    do {
      data = try Data(contentsOf: fileURL)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return CustomRuleDocument(rules: [])
    } catch {
      throw CustomRuleStoreError.ioFailure(detail: String(describing: error))
    }
    let document: CustomRuleDocument
    do {
      let stored = try JSONDecoder().decode(StoredCustomRuleDocument.self, from: data)
      let decoded = try stored.domain()
      if let preset, stored.schemaVersion < Self.currentSchemaVersion {
        document = CustomRuleDocument(
          rules: decoded.rules.filter { $0.action == preset.matchedAction },
          disabledIdentities: decoded.disabledIdentities)
      } else {
        try validateActions(decoded)
        document = decoded
      }
    } catch let error as CustomRuleStoreError {
      throw error
    } catch {
      throw CustomRuleStoreError.corrupt(detail: String(describing: error))
    }
    return document
  }

  /// 原子写入完整规则集合。
  func save(_ rules: [CustomRule]) throws {
    let old = try loadDocument()
    try saveDocument(CustomRuleDocument(rules: rules, disabledIdentities: old.disabledIdentities))
  }

  func saveDocument(_ document: CustomRuleDocument) throws {
    try validateActions(document)
    let data = try Self.encode(document)
    _ = try Self.decode(data)
    do {
      try AtomicFileWriter.write(data, to: fileURL)
    } catch {
      throw CustomRuleStoreError.ioFailure(detail: String(describing: error))
    }
  }

  private func validateActions(_ document: CustomRuleDocument) throws {
    guard let preset else { return }
    guard document.rules.allSatisfy({ $0.action == preset.matchedAction }) else {
      throw CustomRuleStoreError.corrupt(detail: "Custom rule action must match its rule scheme")
    }
  }

  /// 安全摘要：数量 + 内容版本。
  func summary() throws -> CustomRuleSummary {
    CustomRuleSummary.summarizing(try loadDocument())
  }

  static func decode(_ data: Data) throws -> CustomRuleDocument {
    try JSONDecoder().decode(StoredCustomRuleDocument.self, from: data).domain()
  }

  static func encode(_ document: CustomRuleDocument) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(StoredCustomRuleDocument(document))
  }
}

private struct StoredCustomRule: Codable {
  let id: UUID
  let rule: StoredProxyRule

  init(_ custom: CustomRule) {
    id = custom.id
    rule = StoredProxyRule(custom.rule)
  }

  private enum CodingKeys: CodingKey { case id }

  init(from decoder: Decoder) throws {
    id = try decoder.container(keyedBy: CodingKeys.self).decode(UUID.self, forKey: .id)
    rule = try StoredProxyRule(from: decoder)
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(id, forKey: .id)
    try rule.encode(to: encoder)
  }

  func domain() throws -> CustomRule {
    let value = try rule.domain()
    guard !value.match.isFixedLocalSuffix else {
      throw CustomRuleStoreError.corrupt(detail: "Fixed local suffix is not a custom rule")
    }
    return CustomRule(id: id, action: value.action, match: value.match)
  }
}

private struct StoredCustomRuleDocument: Codable {
  let schemaVersion: Int
  let rules: [StoredCustomRule]
  let disabledIdentities: [StoredProxyRule]

  init(_ document: CustomRuleDocument) {
    schemaVersion = CustomRuleStore.currentSchemaVersion
    rules = document.rules.map(StoredCustomRule.init)
    disabledIdentities = document.disabledIdentities.sorted { $0.contentToken < $1.contentToken }
      .map(StoredProxyRule.init)
  }

  private enum CodingKeys: CodingKey { case schemaVersion, rules, disabledIdentities }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
    guard (1...CustomRuleStore.currentSchemaVersion).contains(schemaVersion) else {
      throw CustomRuleStoreError.schemaVersionMismatch(
        found: schemaVersion, expected: CustomRuleStore.currentSchemaVersion)
    }
    rules = try values.decode([StoredCustomRule].self, forKey: .rules)
    disabledIdentities =
      schemaVersion == 1
      ? [] : try values.decode([StoredProxyRule].self, forKey: .disabledIdentities)
  }

  func domain() throws -> CustomRuleDocument {
    let custom = try rules.map { try $0.domain() }
    let disabled = try disabledIdentities.map { try $0.domain() }
    guard Set(custom.map(\.id)).count == custom.count,
      Set(custom.map(\.rule)).count == custom.count,
      Set(disabled).count == disabled.count
    else { throw CustomRuleStoreError.corrupt(detail: "Duplicate custom rule records") }
    return CustomRuleDocument(rules: custom, disabledIdentities: Set(disabled))
  }
}
