import Foundation
import Testing

@testable import ShadowsocksX_NG2

struct BundledDependencyCatalogTests {
  @Test func installedCatalogIncludesReadableTextsAndForkProvenance() throws {
    let catalog = try BundledDependencyCatalog(bundleURL: AppArtifact.bundleURL)
    #expect(catalog.dependencies.count == 7)
    for dependency in catalog.dependencies {
      #expect(!dependency.version.isEmpty)
      #expect(!dependency.licenses.isEmpty)
      for reference in dependency.licenses + dependency.notices {
        #expect(try !catalog.text(at: reference).isEmpty)
      }
    }
    let sslocal = try #require(catalog.dependencies.first { $0.id == "sslocal" })
    #expect(sslocal.projectURL == "https://github.com/shadowsocks/shadowsocks-rust")
    #expect(sslocal.sourceURL == "https://github.com/qiuyuzhou/shadowsocks-rust")
    #expect(sslocal.distributionURL.hasPrefix(sslocal.sourceURL + "/releases/"))
    let plugins = ManagedPluginCatalog.plugins(in: AppArtifact.bundleURL)
    #expect(plugins.count == 2)
    for plugin in plugins {
      #expect(plugin.dependency == catalog.dependencies.first { $0.id == plugin.program })
    }
  }

  @Test func metadataFailureDoesNotDisableExecutableResolution() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let executable = root.appendingPathComponent("Contents/Helpers/Plugins/v2ray-plugin")
    try FileManager.default.createDirectory(
      at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("#!/bin/sh\nexit 99\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let provider = BundleManagedPluginProvider(bundleURL: root)
    for contents in [nil, Data("broken".utf8)] {
      if let contents {
        let catalogURL = root.appendingPathComponent("Contents/Resources/ThirdParty/catalog.json")
        try FileManager.default.createDirectory(
          at: catalogURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: catalogURL)
      }
      #expect(throws: (any Error).self) { try BundledDependencyCatalog(bundleURL: root) }
      #expect(ManagedPluginCatalog.plugins(in: root).allSatisfy { $0.dependency == nil })
      #expect(provider.resolve(program: "v2ray-plugin-v1")?.path == executable.path)
      #expect(provider.resolve(program: "v2ray-plugin")?.arguments == ["-disableAccessLog"])
      let snapshot = PluginCatalogSnapshot(configuration: PluginConfiguration(), managed: provider)
      #expect(snapshot.resolve(program: "v2ray-plugin")?.path == executable.path)
      #expect(snapshot.entry(for: "v2ray-plugin")?.managedInfo?.dependency == nil)
    }
  }
}
