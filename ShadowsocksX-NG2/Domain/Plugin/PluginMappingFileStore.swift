import Foundation

struct UserPluginRecord: Codable, Equatable, Identifiable, Sendable {
  var id: UUID = UUID()
  var names: [String]
  var path: String
  var arguments: [String] = []
  var mode: PluginTransportMode = .tcpOnly

  enum CodingKeys: String, CodingKey {
    case id, names, path, arguments
    case mode = "plugin_mode"
  }

  init(
    id: UUID = UUID(), names: [String], path: String, arguments: [String] = [],
    mode: PluginTransportMode = .tcpOnly
  ) {
    self.id = id
    self.names = names
    self.path = path
    self.arguments = arguments
    self.mode = mode
  }

  init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    names = try values.decode([String].self, forKey: .names)
    path = try values.decode(String.self, forKey: .path)
    arguments = try values.decode([String].self, forKey: .arguments)
    mode =
      values.contains(.mode) ? try values.decode(PluginTransportMode.self, forKey: .mode) : .tcpOnly
  }
}

struct PluginConfiguration: Codable, Equatable, Sendable {
  var userPlugins: [UserPluginRecord] = []
  /// Keys are fixed managed-record identities, independent of their aliases.
  var managedArguments: [String: [String]] = [:]
  var managedModes: [String: PluginTransportMode] = [:]

  enum CodingKeys: String, CodingKey { case userPlugins, managedArguments, managedModes }

  init(
    userPlugins: [UserPluginRecord] = [], managedArguments: [String: [String]] = [:],
    managedModes: [String: PluginTransportMode] = [:]
  ) {
    self.userPlugins = userPlugins
    self.managedArguments = managedArguments
    self.managedModes = managedModes
  }

  init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    userPlugins = try values.decode([UserPluginRecord].self, forKey: .userPlugins)
    managedArguments = try values.decode([String: [String]].self, forKey: .managedArguments)
    managedModes =
      values.contains(.managedModes)
      ? try values.decode([String: PluginTransportMode].self, forKey: .managedModes) : [:]
  }

  func validate() throws {
    var names = Set<String>()
    var identities = Set<UUID>()
    for record in userPlugins {
      guard identities.insert(record.id).inserted, !record.names.isEmpty else {
        throw PluginMappingError.invalidName
      }
      for name in record.names {
        guard !name.isEmpty, name == name.trimmingCharacters(in: .whitespacesAndNewlines),
          !name.contains("\0")
        else { throw PluginMappingError.invalidName }
        guard names.insert(name).inserted else { throw PluginMappingError.nameExists }
      }
      guard record.path.hasPrefix("/"), !record.path.contains("\0") else {
        throw PluginMappingError.invalidPath
      }
      try Self.validateArguments(record.arguments)
    }
    for program in managedModes.keys {
      guard ManagedPluginCatalog.plugins.contains(where: { $0.program == program }) else {
        throw PluginMappingError.nameMissing
      }
    }
    for (program, arguments) in managedArguments {
      guard ManagedPluginCatalog.plugins.contains(where: { $0.program == program }) else {
        throw PluginMappingError.nameMissing
      }
      try Self.validateArguments(arguments)
    }
  }

  static func validateArguments(_ arguments: [String]) throws {
    guard !arguments.contains(where: { $0.contains("\0") }) else {
      throw PluginMappingError.invalidArguments
    }
  }
}

protocol PluginMappingStoring {
  func load() throws -> PluginConfiguration
  func save(_ configuration: PluginConfiguration) throws
}

enum PluginMappingError: Error, Equatable {
  case unreadable
  case unsupportedVersion
  case invalidName
  case invalidPath
  case invalidArguments
  case unavailableFile
  case nameExists
  case nameMissing
}

struct PluginMappingFileStore: PluginMappingStoring {
  var fileURL = ApplicationSupportPaths.current.pluginMappingFileURL

  private struct Version: Decodable { let version: Int }
  private struct LegacyRecord: Decodable {
    let mappings: [String: String]
  }
  private struct Record: Codable {
    let version: Int
    let configuration: PluginConfiguration
  }

  func load() throws -> PluginConfiguration {
    let data: Data
    do {
      data = try Data(contentsOf: fileURL)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return PluginConfiguration()
    } catch {
      throw PluginMappingError.unreadable
    }
    do {
      let decoder = JSONDecoder()
      let configuration: PluginConfiguration
      switch try decoder.decode(Version.self, from: data).version {
      case 1:
        let legacy = try decoder.decode(LegacyRecord.self, from: data)
        configuration = PluginConfiguration(
          userPlugins: legacy.mappings.sorted { $0.key < $1.key }.map {
            UserPluginRecord(names: [$0.key], path: $0.value)
          })
      case 2:
        configuration = try decoder.decode(Record.self, from: data).configuration
      default: throw PluginMappingError.unsupportedVersion
      }
      try configuration.validate()
      return configuration
    } catch PluginMappingError.unsupportedVersion {
      throw PluginMappingError.unsupportedVersion
    } catch {
      throw PluginMappingError.unreadable
    }
  }

  func save(_ configuration: PluginConfiguration) throws {
    try configuration.validate()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try AtomicFileWriter.write(
      try encoder.encode(Record(version: 2, configuration: configuration)), to: fileURL)
  }
}
