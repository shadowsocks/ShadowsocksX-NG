import Foundation

struct UserPluginRecord: Codable, Equatable, Identifiable, Sendable {
  var id: UUID = UUID()
  var names: [String]
  var path: String
  var arguments: [String] = []
}

struct PluginConfiguration: Codable, Equatable, Sendable {
  var userPlugins: [UserPluginRecord] = []
  /// Keys are fixed managed-record identities, independent of their aliases.
  var managedArguments: [String: [String]] = [:]

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
  var fileURL = RuntimePaths.runtimeDirectory().appendingPathComponent("plugins.json")

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
