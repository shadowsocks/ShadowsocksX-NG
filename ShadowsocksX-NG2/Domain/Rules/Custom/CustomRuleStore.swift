import Foundation

/// 自定义规则持久化：独立 JSON 文档，原子写盘。
/// Saving intent is independent of subsequent ACL application and runtime recovery.
struct CustomRuleStore {
  let fileURL: URL

  init(fileURL: URL = CustomRuleStore.defaultFileURL()) {
    self.fileURL = fileURL
  }

  static func defaultFileURL() -> URL {
    RuntimePaths.customRulesFileURL()
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
      document = try Self.decode(data)
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
    let data = try Self.encode(document)
    _ = try Self.decode(data)
    do {
      try AtomicFileWriter.write(data, to: fileURL)
    } catch {
      throw CustomRuleStoreError.ioFailure(detail: String(describing: error))
    }
  }

  /// 安全摘要：数量 + 内容版本。
  func summary() throws -> CustomRuleSummary {
    CustomRuleSummary.summarizing(try loadDocument())
  }

  static func decode(_ data: Data) throws -> CustomRuleDocument {
    try JSONDecoder().decode(CustomRuleDocument.self, from: data)
  }

  static func encode(_ document: CustomRuleDocument) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(document)
  }
}

/// One saved-document owner per app process. Only successful atomic saves update
/// this fact; runtime recovery never restores an older rule document.
@MainActor
final class RuleDocumentSession {
  private let store: CustomRuleStore
  private(set) var current: CustomRuleDocument?
  private(set) var revision = 0

  init(store: CustomRuleStore) { self.store = store }

  func load() throws -> CustomRuleDocument {
    if let current { return current }
    let loaded = try store.loadDocument()
    current = loaded
    return loaded
  }

  func save(_ document: CustomRuleDocument) throws {
    try store.saveDocument(document)
    if current != document { revision += 1 }
    current = document
  }
}
