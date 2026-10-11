import Foundation

@testable import ShadowsocksX_NG2

// Fixture conveniences keep older behavior tests on the record-based catalog interface.
extension PluginCatalog {
  var testMappings: [String: String] {
    Dictionary(
      uniqueKeysWithValues: userRecords.flatMap { record in
        record.names.map { ($0, record.path) }
      })
  }

  @MainActor func addPlugin(program: String, path: String) throws {
    try commit([.save(UserPluginRecord(names: [program], path: path))])
  }

  @MainActor func updatePlugin(program: String, path: String) throws {
    guard var record = userRecords.first(where: { $0.names.contains(program) }) else {
      throw PluginMappingError.nameMissing
    }
    record.path = path
    try commit([.save(record)])
  }

  @MainActor func removePlugin(program: String) throws {
    guard let record = userRecords.first(where: { $0.names.contains(program) }) else {
      throw PluginMappingError.nameMissing
    }
    try commit([.remove(record.id)])
  }

  @MainActor func renamePlugin(program: String, newProgram: String, path: String) throws {
    guard var record = userRecords.first(where: { $0.names.contains(program) }) else {
      throw PluginMappingError.nameMissing
    }
    record.names = [newProgram]
    record.path = path
    try commit([.save(record)])
  }

  @MainActor func replaceTestMappings(_ mappings: [String: String]) throws {
    try replaceConfiguration(PluginConfiguration(mappings: mappings))
  }
}

extension PluginConfiguration {
  init(mappings: [String: String]) {
    self.init(
      userPlugins: mappings.sorted { $0.key < $1.key }.map {
        UserPluginRecord(names: [$0.key], path: $0.value)
      })
  }
}

extension PluginMappingFileStore {
  func save(_ mappings: [String: String]) throws {
    try save(PluginConfiguration(mappings: mappings))
  }
}

extension PluginCatalogSnapshot {
  init(
    mappings: [String: String],
    managed: BundleManagedPluginProvider = BundleManagedPluginProvider(),
    generation: Int = 0, mappingsUnreadable: Bool = false
  ) {
    self.init(
      configuration: PluginConfiguration(mappings: mappings), managed: managed,
      generation: generation, mappingsUnreadable: mappingsUnreadable)
  }
}
