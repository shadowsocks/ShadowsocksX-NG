import Foundation
import Testing

@testable import ShadowsocksX_NG2

struct ThirdPartyComponentsTests {
  @Test func repeatedReferencesAppearOnceAndMissingTextRejectsEntirePresentation() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let resources = root.appendingPathComponent("Contents/Resources/ThirdParty")
    let shared = "third-party-licenses/MIT.txt"
    let extra = "third-party-licenses/additional-notices/COPYRIGHT.txt"
    for reference in ["plugin/LICENSE", "plugin/NOTICE", shared, extra] {
      let file = resources.appendingPathComponent(reference)
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try "Original text: \(reference)\n".write(to: file, atomically: true, encoding: .utf8)
    }
    let dependency = BundledDependency(
      id: "plugin", name: "Plugin", projectURL: "https://example.com/project",
      sourceURL: "https://example.com/fork", distributionURL: "https://example.com/releases",
      version: "0123456789abcdef0123456789abcdef01234567",
      licenses: ["plugin/LICENSE"], notices: ["plugin/NOTICE", shared, shared, extra])
    struct Catalog: Encodable {
      let schemaVersion = 1
      let dependencies: [BundledDependency]
    }
    let catalogURL = resources.appendingPathComponent("catalog.json")
    try JSONEncoder().encode(Catalog(dependencies: [dependency])).write(to: catalogURL)
    let contents = try ThirdPartyComponents(bundleURL: root)
    let component = try #require(contents.components.first)
    #expect(component.metadata == dependency)
    #expect(component.sharedLicenses.map(\.reference) == [shared])
    #expect(component.sharedLicenses.first?.text == "Original text: third-party-licenses/MIT.txt\n")
    #expect(component.notices.map(\.reference) == ["plugin/NOTICE", extra])

    try FileManager.default.removeItem(at: resources.appendingPathComponent(shared))
    #expect(throws: (any Error).self) { try ThirdPartyComponents(bundleURL: root) }
    try Data("broken".utf8).write(to: catalogURL)
    #expect(throws: (any Error).self) { try ThirdPartyComponents(bundleURL: root) }
    try FileManager.default.removeItem(at: catalogURL)
    #expect(throws: (any Error).self) { try ThirdPartyComponents(bundleURL: root) }
  }

  @Test func installedComponentsExposeCompleteOfflineDocuments() throws {
    let contents = try ThirdPartyComponents(bundleURL: AppArtifact.bundleURL)
    #expect(contents.components.count == 7)
    #expect(contents.components.first?.metadata.name == "AgeSwift")
    let plugin = try #require(contents.components.first { $0.id == "v2ray-plugin" })
    #expect(plugin.licenses.map(\.reference) == ["v2ray-plugin/LICENSE"])
    #expect(plugin.sharedLicenses.contains { $0.reference == "third-party-licenses/MIT.txt" })
    #expect(plugin.notices.contains { $0.reference == "v2ray-plugin/THIRD-PARTY-NOTICES" })
    #expect(plugin.notices.allSatisfy { !$0.reference.hasSuffix("/MIT.txt") })
    let catalog = try BundledDependencyCatalog(bundleURL: AppArtifact.bundleURL)
    for component in contents.components {
      let documents = component.licenses + component.notices + component.sharedLicenses
      #expect(Set(documents.map(\.reference)).count == documents.count)
      for document in documents {
        #expect(try document.text == catalog.text(at: document.reference))
      }
    }
  }
}
