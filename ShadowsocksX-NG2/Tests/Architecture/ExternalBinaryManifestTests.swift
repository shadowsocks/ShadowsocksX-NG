import XCTest

/// 校验 Vendor 外部二进制清单的通用结构与稳定打包属性；发布值只在清单中维护。
final class ExternalBinaryManifestTests: XCTestCase {
  private struct Manifest: Decodable {
    var project: String
    var release: String
    var asset: String
    var url: String
    var archiveSHA256: String
    var archiveMember: String?
    var assetFormat: String?
    var binary: String
    var bundleSubpath: String
    var signIdentifier: String
  }

  private static let bundleID = "com.qiuyuzhou.ShadowsocksX-NG2"
  private static let vendorRoot = TestSourceTree.ng2Root().appendingPathComponent("Vendor")

  private func manifest(_ name: String) throws -> Manifest {
    let file = Self.vendorRoot.appendingPathComponent(name).appendingPathComponent("manifest.json")
    return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: file))
  }

  private func assertPinnedSchema(_ manifest: Manifest, name: String) throws {
    XCTAssertFalse(manifest.release.isEmpty, "\(name): release 必须显式固定")
    XCTAssertNotEqual(manifest.release, "latest", "\(name): 禁止 latest 漂移")

    let url = try XCTUnwrap(URL(string: manifest.url), "\(name): url 不可解析")
    XCTAssertEqual(url.scheme, "https", "\(name): 资产必须走 https")
    XCTAssertEqual(url.host, "github.com", "\(name): 资产必须来自官方 GitHub release")
    XCTAssertTrue(url.path.contains(manifest.release), "\(name): url 必须锚定固定 tag")
    XCTAssertEqual(url.lastPathComponent, manifest.asset, "\(name): url 与 asset 不一致")

    XCTAssertTrue(
      manifest.archiveSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
      "\(name): archiveSHA256 必须是 64 位小写十六进制")

    let format = manifest.assetFormat ?? "tar"
    XCTAssertTrue(["tar", "binary"].contains(format))
    if format == "tar" {
      XCTAssertFalse(try XCTUnwrap(manifest.archiveMember).isEmpty)
    }
    XCTAssertEqual(manifest.binary, name, "\(name): bundle 内二进制名与清单目录一致")

    XCTAssertFalse(
      manifest.bundleSubpath.hasPrefix("/") || manifest.bundleSubpath.contains(".."),
      "\(name): bundleSubpath 不得越出 bundle")
    XCTAssertTrue(
      manifest.bundleSubpath == "Helpers" || manifest.bundleSubpath.hasPrefix("Helpers/"),
      "\(name): 外部二进制按 TN2206 属嵌套代码，必须装在 Contents/Helpers 下")

    XCTAssertTrue(
      manifest.signIdentifier.hasPrefix(Self.bundleID + "."),
      "\(name): signIdentifier 必须以宿主 bundle id 为前缀")
  }

  func testSslocalManifestStructure() throws {
    let manifest = try manifest("sslocal")
    try assertPinnedSchema(manifest, name: "sslocal")
    XCTAssertEqual(manifest.project, "shadowsocks-rust")
    let url = try XCTUnwrap(URL(string: manifest.url))
    XCTAssertTrue(
      url.path.hasPrefix("/qiuyuzhou/shadowsocks-rust/releases/download/"),
      "sslocal 应固定到 ShadowsocksX-NG fork 的 release")
    XCTAssertEqual(manifest.bundleSubpath, "Helpers")
    XCTAssertEqual(manifest.signIdentifier, Self.bundleID + ".sslocal")
  }

  func testV2rayPluginManifestStructure() throws {
    let manifest = try manifest("v2ray-plugin")
    try assertPinnedSchema(manifest, name: "v2ray-plugin")
    XCTAssertEqual(manifest.project, "v2ray-plugin")
    XCTAssertEqual(manifest.archiveMember, "v2ray-plugin_darwin_arm64")
    XCTAssertEqual(manifest.bundleSubpath, "Helpers/Plugins")
    // SIP003 插件的签名 identifier 形如 <bundle-id>.plugin.<name>。
    XCTAssertEqual(manifest.signIdentifier, Self.bundleID + ".plugin.v2ray-plugin")
  }
  func testCloakClientManifestStructure() throws {
    let manifest = try manifest("ck-client")
    try assertPinnedSchema(manifest, name: "ck-client")
    XCTAssertEqual(manifest.project, "Cloak")
    XCTAssertEqual(manifest.assetFormat, "binary")
    XCTAssertNil(manifest.archiveMember)
    XCTAssertEqual(manifest.bundleSubpath, "Helpers/Plugins")
    XCTAssertEqual(manifest.signIdentifier, Self.bundleID + ".plugin.ck-client")
  }

}
