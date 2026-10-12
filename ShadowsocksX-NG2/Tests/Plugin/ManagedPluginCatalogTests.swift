import XCTest

@testable import ShadowsocksX_NG2

/// 受管集静态事实表与 Vendor 供应链清单的双向锚定：
/// 插件新增/升级必须显式重做静态清单——事实表与 `Vendor/*/manifest.json`
/// 任何一侧漂移即测试失败，与 `ExternalBinaryManifestTests` 共同守护同一份事实。
final class ManagedPluginCatalogTests: XCTestCase {
  private struct Manifest: Decodable {
    var project: String
    var release: String
    var binary: String
    var bundleSubpath: String
    var signIdentifier: String
  }

  private static let vendorRoot = TestSourceTree.ng2Root().appendingPathComponent("Vendor")

  /// Vendor 下所有插件类清单（bundleSubpath 落在 Helpers/Plugins 的目录）。
  private static var vendorPluginManifests: [(directory: String, manifest: Manifest)] {
    guard
      let directories = try? FileManager.default.contentsOfDirectory(atPath: vendorRoot.path)
    else { return [] }
    return directories.sorted().compactMap { directory in
      let url = vendorRoot.appendingPathComponent(directory).appendingPathComponent("manifest.json")
      guard let data = try? Data(contentsOf: url),
        let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
        manifest.bundleSubpath == "Helpers/Plugins"
      else { return nil }
      return (directory, manifest)
    }
  }

  func testCatalogMatchesVendorPluginManifests() throws {
    let manifests = Self.vendorPluginManifests
    XCTAssertFalse(manifests.isEmpty, "Vendor 下应至少有一个插件清单")
    XCTAssertEqual(
      ManagedPluginCatalog.plugins.count, manifests.count,
      "受管事实表与 Vendor 插件清单数量不一致（升级须同步重做两处静态清单）")
    for (directory, manifest) in manifests {
      let info = try XCTUnwrap(
        ManagedPluginCatalog.plugins.first { $0.program == directory },
        "\(directory): 清单里的记录「\(directory)」不在受管事实表内")
      XCTAssertEqual(info.executableName, manifest.binary, "\(directory): 打包文件名漂移")
      XCTAssertTrue(
        info.project.hasSuffix(manifest.project),
        "\(directory): 受管事实表 project（\(info.project)）须锚定清单 project（\(manifest.project)）")
      XCTAssertEqual(info.release, manifest.release, "\(directory): release 漂移")
      XCTAssertEqual(info.signIdentifier, manifest.signIdentifier, "\(directory): 重签标识漂移")
      XCTAssertFalse(info.license.isEmpty, "\(directory): 许可证必须显式")
      let url = try XCTUnwrap(URL(string: info.projectURL), "\(directory): 项目 URL 不可解析")
      XCTAssertEqual(url.host, "github.com", "\(directory): 项目须托管在 GitHub")
    }
  }

  func testEveryCatalogEntryHasVendorManifest() {
    for info in ManagedPluginCatalog.plugins {
      let match = Self.vendorPluginManifests.first { $0.manifest.binary == info.program }
      XCTAssertNotNil(match, "「\(info.program)」在受管事实表内但缺少 Vendor 插件清单")
    }
  }

  func testProgramLookup() {
    XCTAssertEqual(ManagedPluginCatalog.info(forProgram: "v2ray-plugin")?.release, "v1.3.2")
    XCTAssertNil(ManagedPluginCatalog.info(forProgram: "obfs-local"), "集外程序名不在受管集")
    XCTAssertNil(ManagedPluginCatalog.info(forProgram: ""), "空程序名不在受管集")
  }
}
