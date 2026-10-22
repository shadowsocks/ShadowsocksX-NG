import Foundation
import Testing

@testable import ShadowsocksX_NG2

/// Server-form behavior through workflow and draft interfaces.
struct PluginFormCatalogTests {
  @Test(arguments: [
    PluginCatalogSnapshot.Availability.available, .missing, .notExecutable, .unreadable,
  ])
  @MainActor func formRetainsAvailabilityForNewlySelectedPlugin(
    availability: PluginCatalogSnapshot.Availability
  ) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let snapshot = PluginCatalogSnapshot(entries: [
      .init(
        program: "tool", path: "/private/tool", source: .user,
        availability: availability, managedInfo: nil)
    ])
    let workflow = makeCatalogWorkflow(
      coordinator: CatalogCommitCoordinator(
        fileStore: makeTestCatalogStore(fileURL: root.appendingPathComponent("catalog.json")),
        runtime: FakeCatalogRuntime()), plugins: snapshot)
    let form = workflow.newFormPluginSection(selection: .named(program: "tool"))
    #expect(form.programs.first?.source == .user)
    #expect(form.programs.first?.availability == availability)
    #expect(!form.mappingsUnreadable)
  }

  @Test @MainActor func missingUnsavedChoiceHasUnresolvedPresentation() {
    let plugin = PluginSectionState(
      selection: .named(program: "saved"),
      programs: [.init(program: "saved", source: .managed, availability: .available)],
      mappingsUnreadable: false, optionsPresent: true, options: "flag")
    let form = ServerEditForm(
      address: "127.0.0.1", port: 8388,
      encryptionMethod: "aes-256-gcm", password: "pw", remark: "Original",
      plugin: plugin, isEditable: true)
    let fields = ServerFormFields()
    fields.showServer(.fresh()) { _ in form }
    fields.pluginChoice = .named(program: "removed")
    fields.pluginOptions.load("host=unsaved")
    fields.updatePresentation(ServerFormPresentation(isEditable: true, plugin: plugin))
    #expect(fields.pluginChoice == .named(program: "removed"))
    #expect(fields.presentation?.plugin.unresolvedProgram(for: fields.pluginChoice) == "removed")
    #expect(fields.pluginOptions.composedString == "host=unsaved")
    #expect(plugin.unresolvedProgram(for: .none) == nil)
    #expect(plugin.unresolvedProgram(for: .named(program: "saved")) == nil)
  }

  @Test @MainActor func mappingRemovalAndOverrideChangesPreserveServerDraft() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try makePluginFormFixture(root: root)
    let id = try await fixture.workflow.createServer(
      ServerEditDraft(
        address: "127.0.0.1", port: 8388, encryptionMethod: "aes-256-gcm",
        password: "pw", remark: "Original", plugin: .named(program: "tool"), pluginOptions: "flag"),
      into: nil)
    let fields = ServerFormFields()
    fields.showServer(id, load: fixture.workflow.serverEditForm)
    fields.remark = "Unsaved"
    fields.pluginOptions.load("host=unsaved")
    try fixture.plugins.removePlugin(program: "tool")
    fields.updatePresentation(
      fixture.workflow.serverFormPresentation(for: id), load: fixture.workflow.serverEditForm)
    #expect(fields.pluginChoice == .unknown(program: "tool"))
    #expect(fields.pluginOptions.composedString == "host=unsaved")
    try fixture.plugins.addPlugin(program: "tool", path: fixture.managedBinary.path)
    fields.updatePresentation(
      fixture.workflow.serverFormPresentation(for: id), load: fixture.workflow.serverEditForm)
    #expect(fields.pluginChoice == .named(program: "tool"))
    #expect(fields.pluginOptions.composedString == "host=unsaved")
    #expect(try fixture.workflow.serverEditForm(for: id)?.plugin.options == "flag")
    #expect(fields.remark == "Unsaved")

    // An unsaved choice disappearing must retain a selectable unresolved reference.
    fields.pluginChoice = .named(program: "tool")
    try fixture.plugins.removePlugin(program: "tool")
    fields.updatePresentation(
      fixture.workflow.serverFormPresentation(for: id), load: fixture.workflow.serverEditForm)
    #expect(fields.presentation?.plugin.unresolvedProgram(for: .named(program: "tool")) == "tool")
    #expect(
      fixture.workflow.newFormPluginSection(selection: .named(program: "tool"))
        .unresolvedProgram(for: .named(program: "tool")) == "tool")
    #expect(fields.pluginOptions.composedString == "host=unsaved")

    fields.pluginChoice = .named(program: "v2ray-plugin")
    try fixture.plugins.addPlugin(program: "v2ray-plugin", path: fixture.managedBinary.path)
    fields.updatePresentation(
      fixture.workflow.serverFormPresentation(for: id), load: fixture.workflow.serverEditForm)
    #expect(
      fields.presentation?.plugin.programs.first { $0.program == "v2ray-plugin" }?.source == .user)
    try fixture.plugins.removePlugin(program: "v2ray-plugin")
    fields.updatePresentation(
      fixture.workflow.serverFormPresentation(for: id), load: fixture.workflow.serverEditForm)
    #expect(
      fields.presentation?.plugin.programs.first { $0.program == "v2ray-plugin" }?.source
        == .managed)
    #expect(fields.pluginChoice == .named(program: "v2ray-plugin"))
    #expect(fields.pluginOptions.composedString == "host=unsaved")
    #expect(fields.remark == "Unsaved")
  }

}

private struct PluginFormFixture {
  let managedBinary: URL
  let plugins: PluginCatalog
  let workflow: CatalogWorkflow
}

@MainActor
private func makePluginFormFixture(root: URL) throws -> PluginFormFixture {
  let managedBinary = root.appendingPathComponent("Contents/Helpers/Plugins/v2ray-plugin")
  try FileManager.default.createDirectory(
    at: managedBinary.deletingLastPathComponent(), withIntermediateDirectories: true)
  try Data("#!/bin/sh\n".utf8).write(to: managedBinary)
  try FileManager.default.setAttributes(
    [.posixPermissions: 0o755], ofItemAtPath: managedBinary.path)
  let plugins = PluginCatalog(
    store: PluginMappingFileStore(fileURL: root.appendingPathComponent("plugins.json")),
    managed: BundleManagedPluginProvider(bundleURL: root), inspector: QuietPluginInspector())
  try plugins.addPlugin(program: "tool", path: managedBinary.path)
  let workflow = makeCatalogWorkflow(
    coordinator: CatalogCommitCoordinator(
      fileStore: makeTestCatalogStore(fileURL: root.appendingPathComponent("catalog.json")),
      runtime: FakeCatalogRuntime()), plugins: plugins)
  return PluginFormFixture(managedBinary: managedBinary, plugins: plugins, workflow: workflow)
}
