import Foundation

enum RuleSnapshotError: Error, Equatable, Sendable {
  case missing
  case abnormalRuleCount(found: Int, minimum: Int, maximum: Int)
  case corrupt(detail: String)
  case schemaVersionMismatch(found: Int, expected: Int)
  case converterVersionMismatch(found: String, expected: String)
}

/// Offline file adapter for maintainer-generated built-in snapshots.
struct RuleSnapshotStore {
  static let currentSchemaVersion = 2
  static let currentConverterVersion = "2.0.0"
  let fileURL: URL

  func load() throws -> RuleSnapshot {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw RuleSnapshotError.missing
    }
    let snapshot: RuleSnapshot
    do {
      snapshot = try Self.decode(Data(contentsOf: fileURL))
    } catch let error as RuleSnapshotError {
      throw error
    } catch {
      throw RuleSnapshotError.corrupt(detail: String(describing: error))
    }
    guard snapshot.metadata.converterVersion == Self.currentConverterVersion else {
      throw RuleSnapshotError.converterVersionMismatch(
        found: snapshot.metadata.converterVersion, expected: Self.currentConverterVersion)
    }
    try Self.validateRuleCount(snapshot.rules.count, source: snapshot.metadata.source.kind)
    return snapshot
  }

  static func validateRuleCount(_ count: Int, source: RuleSourceKind) throws {
    let maximum = source == .geolocationCN ? 200_000 : 50_000
    guard (100...maximum).contains(count) else {
      throw RuleSnapshotError.abnormalRuleCount(found: count, minimum: 100, maximum: maximum)
    }
  }

  func save(_ snapshot: RuleSnapshot) throws {
    try AtomicFileWriter.write(Self.encode(snapshot), to: fileURL)
  }

  static func decode(_ data: Data) throws -> RuleSnapshot {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let stored = try decoder.decode(StoredRuleSnapshot.self, from: data)
    guard stored.schemaVersion == currentSchemaVersion else {
      throw RuleSnapshotError.schemaVersionMismatch(
        found: stored.schemaVersion, expected: currentSchemaVersion)
    }
    return try stored.domain()
  }

  static func encode(_ snapshot: RuleSnapshot) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(StoredRuleSnapshot(snapshot))
  }

  /// Preserve browsing's historical metadata fingerprints without making domain
  /// models conform to the file format's encoding contract.
  static func metadataTokens(for snapshot: RuleSnapshot) throws -> [String] {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return [
      snapshot.metadata.source.kind.rawValue
        + ProxyACLDocument.digest(try encoder.encode(StoredSnapshotMetadata(snapshot.metadata))),
      ProxyACLDocument.digest(try encoder.encode(StoredConversionReport(snapshot.lossReport))),
    ]
  }
}

private struct StoredRuleSource: Codable {
  let kind: String
  let upstreamVersion: String
  let label: String

  init(_ source: RuleSourceIdentity) {
    kind = source.kind.rawValue
    upstreamVersion = source.upstreamVersion
    label = source.label
  }

  func domain() throws -> RuleSourceIdentity {
    guard let kind = RuleSourceKind(rawValue: kind) else {
      throw RuleStorageDecodingError.invalidSource(kind)
    }
    return RuleSourceIdentity(kind: kind, upstreamVersion: upstreamVersion, label: label)
  }
}

private struct StoredSnapshotMetadata: Codable {
  let source: StoredRuleSource
  let upstreamReference: String
  let inputDigest: String
  let fetchedAt: Date
  let converterVersion: String
  let license: String
  let attribution: String

  init(_ metadata: RuleSnapshotMetadata) {
    source = StoredRuleSource(metadata.source)
    upstreamReference = metadata.upstreamReference
    inputDigest = metadata.inputDigest
    fetchedAt = metadata.fetchedAt
    converterVersion = metadata.converterVersion
    license = metadata.license
    attribution = metadata.attribution
  }

  func domain() throws -> RuleSnapshotMetadata {
    RuleSnapshotMetadata(
      source: try source.domain(), upstreamReference: upstreamReference, inputDigest: inputDigest,
      fetchedAt: fetchedAt, converterVersion: converterVersion, license: license,
      attribution: attribution)
  }
}

private struct StoredConversionReport: Codable {
  let convertedCount: Int
  let absorbedCount: Int
  let skipped: [String: Int]
  let rejected: [String: Int]

  init(_ report: RuleConversionLossReport) {
    convertedCount = report.convertedCount
    absorbedCount = report.absorbedCount
    skipped = report.skipped
    rejected = report.rejected
  }

  var domain: RuleConversionLossReport {
    RuleConversionLossReport(
      convertedCount: convertedCount, absorbedCount: absorbedCount, skipped: skipped,
      rejected: rejected)
  }
}

private struct StoredRuleSnapshot: Codable {
  let schemaVersion: Int
  let metadata: StoredSnapshotMetadata
  let rules: [StoredProxyRule]
  let lossReport: StoredConversionReport

  init(_ snapshot: RuleSnapshot) {
    schemaVersion = RuleSnapshotStore.currentSchemaVersion
    metadata = StoredSnapshotMetadata(snapshot.metadata)
    rules = snapshot.rules.map(StoredProxyRule.init)
    lossReport = StoredConversionReport(snapshot.lossReport)
  }

  func domain() throws -> RuleSnapshot {
    RuleSnapshot(
      metadata: try metadata.domain(), rules: try rules.map { try $0.domain() },
      lossReport: lossReport.domain)
  }
}
