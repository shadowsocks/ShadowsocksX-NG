import Foundation

/// Coordinates the pure plan with the catalog, credential store, and import
/// completion marker. Preferences and activation state are intentionally absent
/// from this transaction.
final class LegacyImportService {
  private let source: LegacySnapshotProviding
  private let catalogStore: LegacyCatalogStoring
  private let credentials: CredentialStoring
  private let marker: LegacyImportMarkerStoring

  init(
    source: LegacySnapshotProviding = UserDefaultsLegacySnapshotProvider(),
    catalogStore: LegacyCatalogStoring,
    credentials: CredentialStoring = KeychainCredentialStore(),
    marker: LegacyImportMarkerStoring = UserDefaultsLegacyImportMarkerStore()
  ) {
    self.source = source
    self.catalogStore = catalogStore
    self.credentials = credentials
    self.marker = marker
  }

  func readSnapshot() throws -> LegacySnapshot? {
    try source.readSnapshot()
  }

  func isCompleted() throws -> Bool {
    try marker.isCompleted()
  }

  func importCurrentSnapshot(reimport: Bool = false) throws -> LegacyImportOutcome {
    guard let snapshot = try source.readSnapshot() else {
      throw LegacyImportError.noSnapshot
    }
    return try importSnapshot(snapshot, reimport: reimport)
  }

  func importSnapshot(_ snapshot: LegacySnapshot, reimport: Bool = false)
    throws -> LegacyImportOutcome
  {
    let wasCompleted = try marker.isCompleted()
    guard !wasCompleted || reimport else {
      throw LegacyImportError.alreadyCompleted
    }

    let originalDocument = try catalogStore.load()
    let plan = try LegacyImportPlanner.makePlan(
      snapshot: snapshot, existingDocument: originalDocument)
    let touchedReferences = Set(plan.credentials.keys)
    var originalSecrets: [CredentialReference: String?] = [:]
    for reference in touchedReferences {
      originalSecrets[reference] = try credentials.secret(for: reference)
    }

    do {
      for (reference, secret) in plan.credentials {
        try credentials.save(secret, for: reference)
      }
      try catalogStore.save(plan.document)
      try marker.setCompleted(true)
    } catch {
      _ = rollback(
        originalDocument: originalDocument,
        wasCompleted: wasCompleted,
        originalSecrets: originalSecrets)
      throw LegacyImportError.commitFailed
    }

    return LegacyImportOutcome(
      groupID: plan.groupID,
      report: plan.report)
  }
}

extension LegacyImportService {
  fileprivate func rollback(
    originalDocument: CatalogDocument,
    wasCompleted: Bool,
    originalSecrets: [CredentialReference: String?]
  ) -> [String] {
    var failures: [String] = []
    do {
      try marker.setCompleted(wasCompleted)
    } catch {
      failures.append("完成标记：\(error)")
    }
    do {
      try catalogStore.save(originalDocument)
    } catch {
      failures.append("目录：\(error)")
    }
    for (reference, secret) in originalSecrets {
      do {
        if let secret {
          try credentials.save(secret, for: reference)
        } else {
          try credentials.delete(reference)
        }
      } catch {
        failures.append("凭据 \(reference.rawValue)：\(error)")
      }
    }
    return failures
  }
}
