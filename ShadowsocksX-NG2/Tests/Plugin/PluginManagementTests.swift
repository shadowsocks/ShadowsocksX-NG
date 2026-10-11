import Foundation
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct PluginManagementTests {
  @Test func fullyOverriddenManagedRecordKeepsItsOwnFileFacts() throws {
    let fixture = try ManagementFixture()
    defer { fixture.cleanUp() }
    let model = PluginManagementModel(catalog: fixture.catalog)
    let original = try #require(model.rows.first { $0.managedProgram == "v2ray-plugin" })
    try model.save(
      model.beginAdding(), names: ["v2ray-plugin", "v2ray-plugin-v1"],
      path: fixture.first.path, arguments: ["--verbose"])
    let covered = try #require(model.rows.first { $0.managedProgram == "v2ray-plugin" })
    #expect(covered.path == original.path)
    #expect(covered.availability == original.availability)
    #expect(covered.overriddenNames == ["v2ray-plugin", "v2ray-plugin-v1"])
    #expect(covered.path != fixture.first.path)
    let edit = try #require(model.beginManagedArguments("v2ray-plugin"))
    try model.save(edit, names: edit.initialNames, path: "", arguments: ["--threads", "8"])
    #expect(model.beginManagedArguments("v2ray-plugin")?.initialArguments == ["--threads", "8"])
    #expect(model.snapshot.resolve(program: "v2ray-plugin")?.arguments == ["--verbose"])
    try model.clearManagedArguments("v2ray-plugin")
    #expect(model.beginManagedArguments("v2ray-plugin")?.initialArguments == [])
  }

  @Test func editingChangesNamesAndUpdatesExecutable() throws {
    let fixture = try ManagementFixture()
    defer { fixture.cleanUp() }
    let model = PluginManagementModel(catalog: fixture.catalog)
    let add = model.beginAdding()
    try model.save(add, names: ["custom"], path: fixture.first.path)
    let edit = try #require(model.testBeginEditing("custom"))
    #expect(edit.initialNames == ["custom"])
    #expect(edit.initialPath == fixture.first.path)
    try model.save(
      edit, names: ["renamed", "renamed-v2"], path: fixture.second.path,
      arguments: ["--verbose"])
    #expect(model.snapshot.entry(for: "custom") == nil)
    #expect(model.snapshot.entry(for: "renamed")?.path == fixture.second.path)
    #expect(model.snapshot.resolve(program: "renamed-v2")?.arguments == ["--verbose"])
    #expect(fixture.catalog.userRecords.first?.id == edit.recordID)
  }

  @Test func overrideCanBeEditedAndRestoredWithoutDeletingManagedEntry() throws {
    let fixture = try ManagementFixture()
    defer { fixture.cleanUp() }
    let model = PluginManagementModel(catalog: fixture.catalog)
    let override = try #require(model.beginOverriding("v2ray-plugin"))
    #expect(override.initialNames == ["v2ray-plugin"])
    #expect(override.initialPath.isEmpty)
    #expect(!override.isEditing)
    try model.save(override, names: ["v2ray-plugin"], path: fixture.first.path)
    #expect(model.snapshot.entry(for: "v2ray-plugin")?.source == .user)
    #expect(model.beginOverriding("v2ray-plugin") == nil)
    let edit = try #require(model.testBeginEditing("v2ray-plugin"))
    try model.save(edit, names: ["v2ray-plugin"], path: fixture.second.path)
    #expect(model.snapshot.entry(for: "v2ray-plugin")?.path == fixture.second.path)
    try model.testRemove("v2ray-plugin")
    #expect(model.snapshot.entry(for: "v2ray-plugin")?.source == .managed)
    #expect(model.testBeginEditing("v2ray-plugin") == nil)
    #expect(model.beginOverriding("v2ray-plugin") != nil)
  }

  @Test func unreadableMappingsBlockChangesUntilSuccessfulReadRetry() throws {
    let fixture = try ManagementFixture(corrupt: true)
    defer { fixture.cleanUp() }
    let model = PluginManagementModel(catalog: fixture.catalog)
    #expect(model.snapshot.mappingsUnreadable)
    #expect(model.beginOverriding("v2ray-plugin") == nil)
    #expect(throws: PluginMappingError.unreadable) {
      try model.save(model.beginAdding(), names: ["custom"], path: fixture.first.path)
    }
    #expect(throws: PluginMappingError.unreadable) { try model.retryReading() }
    #expect(model.snapshot.mappingsUnreadable)
    try fixture.store.save(["custom": fixture.first.path])
    let repairedBytes = try Data(contentsOf: fixture.store.fileURL)
    try model.retryReading()
    #expect(!model.snapshot.mappingsUnreadable)
    #expect(model.snapshot.entry(for: "custom")?.path == fixture.first.path)
    #expect(try Data(contentsOf: fixture.store.fileURL) == repairedBytes)
    #expect(model.testBeginEditing("custom") != nil)
  }

  @Test func failedSavePreservesMappingAndAllowsSameEditorToRetry() throws {
    let fixture = try ManagementFixture()
    defer { fixture.cleanUp() }
    let model = PluginManagementModel(catalog: fixture.catalog)
    try model.save(model.beginAdding(), names: ["custom"], path: fixture.first.path)
    let edit = try #require(model.testBeginEditing("custom"))
    let config = fixture.store.fileURL.deletingLastPathComponent()
    let backup = fixture.root.appendingPathComponent("backup")
    try FileManager.default.moveItem(at: config, to: backup)
    try Data("blocking file".utf8).write(to: config)
    #expect(throws: (any Error).self) {
      try model.save(edit, names: ["custom"], path: fixture.second.path)
    }
    #expect(model.snapshot.entry(for: "custom")?.path == fixture.first.path)
    #expect(model.testBeginEditing("custom")?.initialPath == fixture.first.path)
    try FileManager.default.removeItem(at: config)
    try FileManager.default.moveItem(at: backup, to: config)
    try model.save(edit, names: ["custom"], path: fixture.second.path)
    #expect(model.snapshot.entry(for: "custom")?.path == fixture.second.path)
  }

  @Test func unavailableFilesAndDuplicateNamesAreRejectedAndRemovalKeepsOtherMappings() throws {
    let fixture = try ManagementFixture()
    defer { fixture.cleanUp() }
    let model = PluginManagementModel(catalog: fixture.catalog)
    let add = model.beginAdding()
    #expect(!add.isEditing)
    #expect(add.initialPath.isEmpty)
    #expect(model.testNameIssue("", session: add) == .invalidName)
    #expect(model.pathIssue("relative") == .invalidPath)
    try model.save(add, names: ["custom"], path: fixture.first.path)
    #expect(model.testNameIssue("custom", session: model.beginAdding()) == .nameExists)
    #expect(throws: PluginMappingError.nameExists) {
      try model.save(model.beginAdding(), names: ["custom"], path: fixture.second.path)
    }
    #expect(throws: PluginMappingError.unavailableFile) {
      try model.save(
        model.beginAdding(), names: ["missing"],
        path: fixture.root.appendingPathComponent("missing").path)
    }
    try model.save(model.beginAdding(), names: ["other"], path: fixture.second.path)
    try model.testRemove("custom")
    #expect(model.snapshot.entry(for: "custom") == nil)
    #expect(model.snapshot.entry(for: "other")?.path == fixture.second.path)
    try FileManager.default.removeItem(at: fixture.second)
    model.refresh()
    #expect(model.snapshot.entry(for: "other")?.availability == .missing)
    #expect(model.testBeginEditing("other")?.initialPath == fixture.second.path)
  }

}

private struct ManagementInspector: PluginInspecting {
  func inspect(_ executable: URL) async -> PluginSecurityFacts {
    PluginSecurityFacts(quarantine: .absent, signature: .notApplicable, policy: .notApplicable)
  }
}

@MainActor
private struct ManagementFixture {
  let root: URL
  let first: URL
  let second: URL
  let store: PluginMappingFileStore
  let catalog: PluginCatalog

  init(corrupt: Bool = false) throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    first = root.appendingPathComponent("first")
    second = root.appendingPathComponent("second")
    store = PluginMappingFileStore(fileURL: root.appendingPathComponent("config/plugins.json"))
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    for binary in [first, second] {
      try Data("#!/bin/sh\n".utf8).write(to: binary)
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    }
    if corrupt { try Data("broken".utf8).write(to: store.fileURL) }
    catalog = PluginCatalog(store: store, inspector: ManagementInspector())
  }

  func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

@MainActor
extension PluginManagementModel {
  fileprivate func testBeginEditing(_ name: String) -> PluginEditorSession? {
    guard let id = catalog.userRecords.first(where: { $0.names.contains(name) })?.id else {
      return nil
    }
    return beginEditing(id)
  }

  fileprivate func testRemove(_ name: String) throws {
    guard let id = catalog.userRecords.first(where: { $0.names.contains(name) })?.id else {
      throw PluginMappingError.nameMissing
    }
    try remove(id)
  }

  fileprivate func testNameIssue(_ name: String, session: PluginEditorSession)
    -> PluginMappingError?
  {
    namesIssue([name], session: session)
  }
}
