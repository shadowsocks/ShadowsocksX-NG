import Darwin
import Foundation

/// One derivation uses captured executable facts, never a live mutable mapping.
struct PluginCatalogSnapshot: PluginExecutableResolving, Equatable, Sendable {
  enum Source: String, Codable, Sendable {
    case managed
    case user
    case unknown
  }

  enum Availability: Equatable, Sendable {
    case available
    case missing
    case notExecutable
    case unreadable
  }

  struct Entry: Equatable, Sendable {
    let program: String
    let path: String?
    let source: Source
    let availability: Availability
    let managedInfo: ManagedPluginInfo?
    var arguments: [String] = []
    var mode: PluginTransportMode = .tcpOnly
    var recordID: UUID?
  }

  let entries: [Entry]
  let generation: Int
  let mappingsUnreadable: Bool
  var managedRecords: [String: Entry] = [:]
  var managedArguments: [String: [String]] = [:]

  init(
    configuration: PluginConfiguration,
    managed: BundleManagedPluginProvider = BundleManagedPluginProvider(),
    generation: Int = 0,
    mappingsUnreadable: Bool = false
  ) {
    let managedNames = ManagedPluginCatalog.plugins.flatMap(\.names)
    let userByName = Dictionary(
      uniqueKeysWithValues: configuration.userPlugins.flatMap { record in
        record.names.map { ($0, record) }
      })
    let programs = Set(managedNames).union(userByName.keys).sorted()
    self.entries = programs.map { program in
      let info = ManagedPluginCatalog.info(forProgram: program)
      let user = userByName[program]
      let source: Source = mappingsUnreadable ? .unknown : (user == nil ? .managed : .user)
      let path =
        user?.path
        ?? managed.bundleURL
        .appendingPathComponent("Contents/Helpers/Plugins")
        .appendingPathComponent(info?.executableName ?? program).path
      let arguments =
        user?.arguments
        ?? info.map {
          $0.defaultArguments + (configuration.managedArguments[$0.program] ?? [])
        } ?? []
      return Entry(
        program: program, path: path, source: source,
        availability: mappingsUnreadable
          ? .unreadable : Self.availability(at: path, fileManager: managed.fileManager),
        managedInfo: source == .managed ? info : nil, arguments: arguments,
        mode: user?.mode ?? info.flatMap { configuration.managedModes[$0.program] } ?? .tcpOnly,
        recordID: user?.id)
    }
    self.managedRecords = Dictionary(
      uniqueKeysWithValues: ManagedPluginCatalog.plugins.map { info in
        let path = managed.bundleURL.appendingPathComponent("Contents/Helpers/Plugins")
          .appendingPathComponent(info.executableName).path
        return (
          info.program,
          Entry(
            program: info.program, path: path, source: .managed,
            availability: mappingsUnreadable
              ? .unreadable : Self.availability(at: path, fileManager: managed.fileManager),
            managedInfo: info,
            arguments: info.defaultArguments + (configuration.managedArguments[info.program] ?? []),
            mode: configuration.managedModes[info.program] ?? .tcpOnly)
        )
      })
    self.managedArguments = configuration.managedArguments
    self.generation = generation
    self.mappingsUnreadable = mappingsUnreadable
  }

  init(entries: [Entry], generation: Int = 0, mappingsUnreadable: Bool = false) {
    self.entries = entries
    self.generation = generation
    self.mappingsUnreadable = mappingsUnreadable
  }

  private static func availability(at path: String, fileManager: FileManager) -> Availability {
    do {
      let target = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
      let attributes = try fileManager.attributesOfItem(atPath: target)
      if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
        // Foundation leaves broken or unresolvable links unchanged. stat follows
        // the target and preserves the distinction between absence and read failure.
        var facts = stat()
        if stat(path, &facts) != 0 {
          return errno == ENOENT || errno == ENOTDIR ? .missing : .unreadable
        } else {
          return
            (facts.st_mode & S_IFMT) == S_IFDIR
            || !fileManager.isExecutableFile(atPath: path) ? .notExecutable : .available
        }
      } else if attributes[.type] as? FileAttributeType == .typeDirectory
        || !fileManager.isExecutableFile(atPath: path)
      {
        return .notExecutable
      } else {
        return .available
      }
    } catch {
      let failure = error as NSError
      return
        failure.domain == NSCocoaErrorDomain
        && failure.code == NSFileReadNoSuchFileError ? .missing : .unreadable
    }
  }

  func entry(for program: String) -> Entry? {
    entries.first { $0.program == program }
  }

  func resolve(program: String) -> ResolvedPlugin? {
    guard !mappingsUnreadable, let entry = entry(for: program),
      entry.availability == .available, let path = entry.path
    else { return nil }
    return ResolvedPlugin(path: path, arguments: entry.arguments, mode: entry.mode)
  }

  func catalogSnapshot() -> PluginCatalogSnapshot { self }
}
