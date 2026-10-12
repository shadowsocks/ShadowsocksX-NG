import Foundation

// MARK: - 快照元数据

/// 规则快照的来源元数据：上游版本、输入摘要、抓取时间、
/// 转换器版本、许可证与归属。更新失败保留上一份有效快照。
struct RuleSnapshotMetadata: Codable, Equatable, Sendable {
  /// 转换器版本；快照格式或转换语义变化时递增。
  static let currentConverterVersion = "2.0.0"

  let source: RuleSourceIdentity
  /// 上游仓库/产物标识（含固定 commit 或 release tag）。
  let upstreamReference: String
  /// 原始输入的 SHA-256（规范化前的字节摘要）。
  let inputDigest: String
  /// 抓取时间（ISO-8601）。
  let fetchedAt: Date
  let converterVersion: String
  /// 许可证标识（SPDX 或上游声明）。
  let license: String
  /// 归属说明，随分发物保留。
  let attribution: String

  init(
    source: RuleSourceIdentity,
    upstreamReference: String,
    inputDigest: String,
    fetchedAt: Date,
    converterVersion: String = RuleSnapshotMetadata.currentConverterVersion,
    license: String,
    attribution: String
  ) {
    self.source = source
    self.upstreamReference = upstreamReference
    self.inputDigest = inputDigest
    self.fetchedAt = fetchedAt
    self.converterVersion = converterVersion
    self.license = license
    self.attribution = attribution
  }
}

// MARK: - 转换损失报告

/// 转换损失报告：已转换、已吸收、按类跳过与拒绝的分类计数。
struct RuleConversionLossReport: Codable, Equatable, Sendable {
  /// 成功进入规则模型的条目数。
  var convertedCount: Int
  /// 被吸收或遮蔽而不进入运行时规则的条目数（`.cn` 吸收、GFWList `@@` 遮蔽）。
  var absorbedCount: Int
  /// 按类型跳过的计数（keyword / regexp / attribute / include 等）。
  var skipped: [String: Int]
  /// 拒绝原因 → 计数。
  var rejected: [String: Int]

  init(
    convertedCount: Int = 0,
    absorbedCount: Int = 0,
    skipped: [String: Int] = [:],
    rejected: [String: Int] = [:]
  ) {
    self.convertedCount = convertedCount
    self.absorbedCount = absorbedCount
    self.skipped = skipped
    self.rejected = rejected
  }

  mutating func incrementSkipped(_ category: String, by count: Int = 1) {
    skipped[category, default: 0] += count
  }

  mutating func incrementRejected(_ reason: String, by count: Int = 1) {
    rejected[reason, default: 0] += count
  }
}

// MARK: - 规则快照

/// 规范化规则快照：元数据 + 生效规则 + 纯计数损失报告。
struct RuleSnapshot: Codable, Equatable, Sendable {
  /// 快照 schema 版本；加载时不匹配则失败。
  static let currentSchemaVersion = 2

  let schemaVersion: Int
  let metadata: RuleSnapshotMetadata
  let rules: [ProxyRule]
  let lossReport: RuleConversionLossReport

  init(
    metadata: RuleSnapshotMetadata,
    rules: [ProxyRule],
    lossReport: RuleConversionLossReport = RuleConversionLossReport()
  ) {
    self.schemaVersion = Self.currentSchemaVersion
    self.metadata = metadata
    self.rules = rules
    self.lossReport = lossReport
  }
}

// MARK: - 快照加载

enum RuleSnapshotError: Error, Equatable, Sendable {
  case missing
  case abnormalRuleCount(found: Int, minimum: Int, maximum: Int)
  case corrupt(detail: String)
  case schemaVersionMismatch(found: Int, expected: Int)
  case converterVersionMismatch(found: String, expected: String)
}

/// 本地已固定快照的离线加载器。普通构建只读本地快照，绝不抓取或转换。
struct RuleSnapshotStore {
  let fileURL: URL

  func load() throws -> RuleSnapshot {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw RuleSnapshotError.missing
    }
    let data: Data
    do {
      data = try Data(contentsOf: fileURL)
    } catch {
      throw RuleSnapshotError.corrupt(detail: String(describing: error))
    }
    let snapshot: RuleSnapshot
    do {
      snapshot = try Self.decode(data)
    } catch {
      throw RuleSnapshotError.corrupt(detail: String(describing: error))
    }
    guard snapshot.schemaVersion == RuleSnapshot.currentSchemaVersion else {
      throw RuleSnapshotError.schemaVersionMismatch(
        found: snapshot.schemaVersion, expected: RuleSnapshot.currentSchemaVersion)
    }
    guard snapshot.metadata.converterVersion == RuleSnapshotMetadata.currentConverterVersion
    else {
      throw RuleSnapshotError.converterVersionMismatch(
        found: snapshot.metadata.converterVersion,
        expected: RuleSnapshotMetadata.currentConverterVersion)
    }
    try Self.validateRuleCount(snapshot.rules.count, source: snapshot.metadata.source.kind)
    return snapshot
  }

  static func validateRuleCount(_ count: Int, source: RuleSourceKind) throws {
    let maximum = source == .geolocationCN ? 200_000 : 50_000
    guard (100...maximum).contains(count) else {
      throw RuleSnapshotError.abnormalRuleCount(
        found: count, minimum: 100, maximum: maximum)
    }
  }

  func save(_ snapshot: RuleSnapshot) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(snapshot)
    try AtomicFileWriter.write(data, to: fileURL)
  }

  static func decode(_ data: Data) throws -> RuleSnapshot {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(RuleSnapshot.self, from: data)
  }

  static func encode(_ snapshot: RuleSnapshot) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(snapshot)
  }
}
