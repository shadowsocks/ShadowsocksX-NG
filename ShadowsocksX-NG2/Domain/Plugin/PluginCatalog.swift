import Combine
import Foundation

/// Owns mapping intent, publication and asynchronous post-commit work.
/// File availability is captured anew for each derivation, not cached for the session.
final class PluginCatalog: ObservableObject, PluginExecutableResolving {
  enum Change {
    case save(UserPluginRecord)
    case remove(UUID)
    case managedArguments(program: String, arguments: [String])
    case managedMode(program: String, mode: PluginTransportMode)
  }

  private struct State {
    var configuration: PluginConfiguration
    var generation = 0
    var unreadable: Bool
  }

  private let lock = NSLock()
  private var state: State
  private let store: any PluginMappingStoring
  private let managed: BundleManagedPluginProvider
  private let inspector: any PluginInspecting
  @MainActor @Published private(set) var securityFacts: [String: PluginSecurityFacts] = [:]
  @MainActor private var inspectionTasks: [String: Task<Void, Never>] = [:]
  let didCommit = PassthroughSubject<Int, Never>()
  @MainActor private var invalidateRuntime: (() -> Void)?
  @MainActor private var revalidate: (() -> Void)?
  @MainActor private var converge: (() async -> Void)?

  /// Composition-only wiring. UI submits mapping intent rather than scheduling effects.
  @MainActor
  func connect(
    invalidateRuntime: @escaping () -> Void,
    revalidate: @escaping () -> Void,
    converge: @escaping () async -> Void
  ) {
    self.invalidateRuntime = invalidateRuntime
    self.revalidate = revalidate
    self.converge = converge
  }

  init(
    store: any PluginMappingStoring = PluginMappingFileStore(),
    managed: BundleManagedPluginProvider = BundleManagedPluginProvider(),
    inspector: any PluginInspecting = MacOSPluginInspection()
  ) {
    self.store = store
    self.managed = managed
    self.inspector = inspector
    do {
      state = State(configuration: try store.load(), unreadable: false)
    } catch {
      state = State(configuration: PluginConfiguration(), unreadable: true)
    }
  }

  func catalogSnapshot() -> PluginCatalogSnapshot {
    let captured = lock.withLock { state }
    return PluginCatalogSnapshot(
      configuration: captured.configuration, managed: managed, generation: captured.generation,
      mappingsUnreadable: captured.unreadable)
  }

  func resolve(program: String) -> ResolvedPlugin? {
    catalogSnapshot().resolve(program: program)
  }

  var userRecords: [UserPluginRecord] { lock.withLock { state.configuration.userPlugins } }

  @MainActor
  func commit(_ changes: [Change]) throws {
    let captured = lock.withLock { state }
    guard !captured.unreadable else { throw PluginMappingError.unreadable }
    var proposed = captured.configuration
    for change in changes {
      switch change {
      case .save(var record):
        record.names = record.names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        record.path = try validatedPath(record.path)
        if let index = proposed.userPlugins.firstIndex(where: { $0.id == record.id }) {
          proposed.userPlugins[index] = record
        } else {
          proposed.userPlugins.append(record)
        }
      case .remove(let id):
        guard let index = proposed.userPlugins.firstIndex(where: { $0.id == id }) else {
          throw PluginMappingError.nameMissing
        }
        proposed.userPlugins.remove(at: index)
      case .managedMode(let program, let mode):
        guard ManagedPluginCatalog.plugins.contains(where: { $0.program == program }) else {
          throw PluginMappingError.nameMissing
        }
        if mode == .tcpOnly {
          proposed.managedModes.removeValue(forKey: program)
        } else {
          proposed.managedModes[program] = mode
        }
      case .managedArguments(let program, let arguments):
        guard ManagedPluginCatalog.plugins.contains(where: { $0.program == program }) else {
          throw PluginMappingError.nameMissing
        }
        if arguments.isEmpty {
          proposed.managedArguments.removeValue(forKey: program)
        } else {
          proposed.managedArguments[program] = arguments
        }
      }
    }
    try proposed.validate()
    guard proposed != captured.configuration else { return }
    try publishAfterSaving(proposed)
  }

  /// Explicit repair; a corrupt store never silently becomes empty user intent.
  @MainActor
  func replaceConfiguration(_ configuration: PluginConfiguration) throws {
    try configuration.validate()
    for record in configuration.userPlugins { _ = try validatedPath(record.path) }
    try publishAfterSaving(configuration)
  }

  @MainActor
  private func publishAfterSaving(_ proposed: PluginConfiguration) throws {
    try store.save(proposed)
    publish(proposed)
  }

  /// Retry a failed initial read without replacing or writing user intent.
  @MainActor
  func retryReadingMappings() throws {
    guard lock.withLock({ state.unreadable }) else { return }
    let mappings = try store.load()
    publish(mappings)
  }

  @MainActor
  private func publish(_ proposed: PluginConfiguration) {
    objectWillChange.send()
    let generation = lock.withLock {
      state.configuration = proposed
      state.unreadable = false
      state.generation += 1
      return state.generation
    }
    invalidateRuntime?()
    revalidate?()
    didCommit.send(generation)
    refreshSecurityFacts()
    if let converge {
      Task { @MainActor [weak self] in
        guard let self, self.catalogSnapshot().generation == generation else { return }
        await converge()
      }
    }
  }

  /// Explicit refresh also serves activation and startup failure diagnostics.
  @discardableResult
  @MainActor
  func refreshSecurityFacts() -> Task<Void, Never> {
    for task in inspectionTasks.values { task.cancel() }
    inspectionTasks.removeAll()
    securityFacts.removeAll()
    let snapshot = catalogSnapshot()
    var inspected = Set<UUID>()
    for entry in snapshot.entries where entry.source == .user {
      guard let recordID = entry.recordID, inspected.insert(recordID).inserted else { continue }
      let names = snapshot.entries.filter { $0.recordID == recordID }.map(\.program)
      guard let path = entry.path, let identity = PluginFileIdentity(path: path) else { continue }
      let inspector = inspector
      inspectionTasks[entry.program] = Task { @MainActor [weak self] in
        guard !Task.isCancelled else { return }
        let facts = await inspector.inspect(URL(fileURLWithPath: path))
        guard let self, !Task.isCancelled,
          self.catalogSnapshot().generation == snapshot.generation,
          self.catalogSnapshot().entry(for: entry.program)?.path == path,
          PluginFileIdentity(path: path) == identity
        else { return }
        for name in names { self.securityFacts[name] = facts }
        self.inspectionTasks.removeValue(forKey: entry.program)
      }
    }
    let tasks = Array(inspectionTasks.values)
    return Task { @MainActor in
      for task in tasks { await task.value }
    }
  }

  private func validatedPath(_ path: String) throws -> String {
    guard path.hasPrefix("/"), !path.contains("\0") else { throw PluginMappingError.invalidPath }
    var isDirectory: ObjCBool = false
    guard managed.fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
      !isDirectory.boolValue, managed.fileManager.isExecutableFile(atPath: path)
    else { throw PluginMappingError.unavailableFile }
    return path
  }
}
