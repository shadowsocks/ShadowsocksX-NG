import Foundation

// MARK: - 快照元数据

/// 规则快照的来源元数据：上游版本、输入摘要、抓取时间、
/// 转换器版本、许可证与归属。更新失败保留上一份有效快照。
struct RuleSnapshotMetadata: Equatable, Sendable {
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
}

// MARK: - 转换损失报告

/// 转换损失报告：已转换、已吸收、按类跳过与拒绝的分类计数。
struct RuleConversionLossReport: Equatable, Sendable {
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
struct RuleSnapshot: Equatable, Sendable {
  let metadata: RuleSnapshotMetadata
  let rules: [ProxyRule]
  let lossReport: RuleConversionLossReport

  init(
    metadata: RuleSnapshotMetadata,
    rules: [ProxyRule],
    lossReport: RuleConversionLossReport = RuleConversionLossReport()
  ) {
    self.metadata = metadata
    self.rules = rules
    self.lossReport = lossReport
  }
}
