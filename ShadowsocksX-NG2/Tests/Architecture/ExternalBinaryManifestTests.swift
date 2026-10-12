import XCTest

/// Vendor 外部二进制清单的固定 schema 与锚点值。
/// 供应链脚本（fetch/sign/gate）与这里共同守护同一份事实：
/// tag + 资产 URL + 归档 SHA-256 一经固定，改动必须显式重做静态清单。
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

  func testSslocalManifestPinned() throws {
    let manifest = try manifest("sslocal")
    try assertPinnedSchema(manifest, name: "sslocal")
    XCTAssertEqual(manifest.project, "shadowsocks-rust")
    XCTAssertEqual(manifest.release, "v1.25.0")
    XCTAssertEqual(
      manifest.archiveSHA256,
      "58e0caf0cc9266c4ea226f38aa20fb28c1be12efc87a73cf5903197867555208")
    XCTAssertEqual(manifest.bundleSubpath, "Helpers")
    XCTAssertEqual(manifest.signIdentifier, Self.bundleID + ".sslocal")
  }

  func testV2rayPluginManifestPinned() throws {
    let manifest = try manifest("v2ray-plugin")
    try assertPinnedSchema(manifest, name: "v2ray-plugin")
    XCTAssertEqual(manifest.project, "v2ray-plugin")
    XCTAssertEqual(manifest.release, "v1.3.2")
    XCTAssertEqual(
      manifest.archiveSHA256,
      "357476695ec06498cdc38f3a9efd5b99e4d601db4807661117bf3bae917286ae")
    XCTAssertEqual(manifest.archiveMember, "v2ray-plugin_darwin_arm64")
    XCTAssertEqual(manifest.bundleSubpath, "Helpers/Plugins")
    // SIP003 插件的签名 identifier 形如 <bundle-id>.plugin.<name>。
    XCTAssertEqual(manifest.signIdentifier, Self.bundleID + ".plugin.v2ray-plugin")
  }
  func testCloakClientManifestPinned() throws {
    let manifest = try manifest("ck-client")
    try assertPinnedSchema(manifest, name: "ck-client")
    XCTAssertEqual(manifest.project, "Cloak")
    XCTAssertEqual(manifest.release, "v2.12.0")
    XCTAssertEqual(manifest.assetFormat, "binary")
    XCTAssertNil(manifest.archiveMember)
    XCTAssertEqual(
      manifest.archiveSHA256,
      "dbef5cd5dd1b551a046c422e07854eb4736fc958e684c6532eb7e809b593ad5c")
    XCTAssertEqual(manifest.bundleSubpath, "Helpers/Plugins")
    XCTAssertEqual(manifest.signIdentifier, Self.bundleID + ".plugin.ck-client")
  }

}
