import Combine
import Foundation

struct PluginEditorSession: Identifiable {
  let id = UUID()
  let recordID: UUID?
  let managedProgram: String?
  let isEditing: Bool
  let initialNames: [String]
  let initialPath: String
  let initialArguments: [String]
}

struct PluginManagementRow: Identifiable {
  let id: String
  let recordID: UUID?
  let managedProgram: String?
  let names: [String]
  let overriddenNames: [String]
  let path: String?
  let availability: PluginCatalogSnapshot.Availability?
  let securityProgram: String?
  let overridesManaged: Bool
}

@MainActor
final class PluginManagementModel: ObservableObject {
  let catalog: PluginCatalog
  @Published private(set) var snapshot: PluginCatalogSnapshot
  private var subscription: AnyCancellable?

  init(catalog: PluginCatalog) {
    self.catalog = catalog
    snapshot = catalog.catalogSnapshot()
    subscription = catalog.didCommit.sink { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.snapshot = self.catalog.catalogSnapshot()
      }
    }
  }

  var rows: [PluginManagementRow] {
    let managed = ManagedPluginCatalog.plugins.map { info in
      let effective = snapshot.managedRecords[info.program]
      return PluginManagementRow(
        id: "managed:" + info.program, recordID: nil, managedProgram: info.program,
        names: info.names,
        overriddenNames: info.names.filter { snapshot.entry(for: $0)?.source == .user },
        path: effective?.path, availability: effective?.availability, securityProgram: nil,
        overridesManaged: false)
    }
    let user = catalog.userRecords.map { record in
      let entry = record.names.first.flatMap { snapshot.entry(for: $0) }
      return PluginManagementRow(
        id: record.id.uuidString, recordID: record.id, managedProgram: nil,
        names: record.names, overriddenNames: [], path: record.path,
        availability: entry?.availability, securityProgram: record.names.first,
        overridesManaged: record.names.contains { ManagedPluginCatalog.info(forProgram: $0) != nil }
      )
    }
    return managed + user
  }

  func beginAdding() -> PluginEditorSession {
    PluginEditorSession(
      recordID: UUID(), managedProgram: nil, isEditing: false,
      initialNames: [""], initialPath: "", initialArguments: [])
  }

  func beginEditing(_ id: UUID) -> PluginEditorSession? {
    guard !snapshot.mappingsUnreadable,
      let record = catalog.userRecords.first(where: { $0.id == id })
    else { return nil }
    return PluginEditorSession(
      recordID: id, managedProgram: nil, isEditing: true,
      initialNames: record.names, initialPath: record.path, initialArguments: record.arguments)
  }

  func beginOverriding(_ program: String) -> PluginEditorSession? {
    guard !snapshot.mappingsUnreadable, snapshot.entry(for: program)?.source == .managed else {
      return nil
    }
    return PluginEditorSession(
      recordID: UUID(), managedProgram: nil, isEditing: false,
      initialNames: [program], initialPath: "", initialArguments: [])
  }

  func beginManagedArguments(_ program: String) -> PluginEditorSession? {
    guard !snapshot.mappingsUnreadable,
      let info = ManagedPluginCatalog.plugins.first(where: { $0.program == program })
    else { return nil }
    return PluginEditorSession(
      recordID: nil, managedProgram: program, isEditing: true,
      initialNames: info.names, initialPath: "",
      initialArguments: snapshot.managedArguments[program] ?? [])
  }

  func namesIssue(_ names: [String], session: PluginEditorSession) -> PluginMappingError? {
    let names = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    if names.isEmpty || names.contains(where: { $0.isEmpty || $0.contains("\0") }) {
      return .invalidName
    }
    if Set(names).count != names.count { return .nameExists }
    let occupied = Set(catalog.userRecords.filter { $0.id != session.recordID }.flatMap(\.names))
    return names.contains(where: { occupied.contains($0) }) ? .nameExists : nil
  }

  func pathIssue(_ path: String) -> PluginMappingError? {
    path.hasPrefix("/") && !path.contains("\0") ? nil : .invalidPath
  }

  func save(_ session: PluginEditorSession, names: [String], path: String, arguments: [String] = [])
    throws
  {
    if let program = session.managedProgram {
      try catalog.commit([.managedArguments(program: program, arguments: arguments)])
    } else {
      if let issue = namesIssue(names, session: session) { throw issue }
      if let issue = pathIssue(path) { throw issue }
      guard let id = session.recordID,
        !session.isEditing || catalog.userRecords.contains(where: { $0.id == id })
      else { throw PluginMappingError.nameMissing }
      try catalog.commit([
        .save(UserPluginRecord(id: id, names: names, path: path, arguments: arguments))
      ])
    }
    refresh()
  }

  func remove(_ id: UUID) throws {
    try catalog.commit([.remove(id)])
    refresh()
  }

  func clearManagedArguments(_ program: String) throws {
    try catalog.commit([.managedArguments(program: program, arguments: [])])
    refresh()
  }

  func retryReading() throws {
    try catalog.retryReadingMappings()
    refresh()
  }

  func refresh() {
    snapshot = catalog.catalogSnapshot()
    catalog.refreshSecurityFacts()
  }
}
