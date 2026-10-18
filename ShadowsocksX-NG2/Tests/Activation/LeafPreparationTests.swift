import XCTest

@testable import ShadowsocksX_NG2

/// 叶子预检缝：一次完成激活阻塞判定与凭据/插件解析，产出供目录树呈现与
/// 运行时装配共用的事实。文档装配不在本缝。
final class LeafPreparationTests: XCTestCase {
  func testSupportedServerWithOpaquePluginOptionsIsReady() throws {
    let fields = ServerFields(
      address: "203.0.113.7",
      port: 8388,
      encryptionMethod: "aes-256-gcm",
      password: "password",
      pluginProgram: "v2ray-plugin",
      pluginOptions: "plugin-option-that-the-app-does-not-parse")

    let preparation = LeafPreparation.prepare(
      fields, plugins: ActivationFixture.plugins)

    XCTAssertEqual(preparation.issues, [])
    XCTAssertEqual(preparation.password, "password")
    XCTAssertEqual(preparation.plugin?.path, "/bundle/Helpers/Plugins/v2ray-plugin")
    XCTAssertEqual(preparation.pluginOptions, "plugin-option-that-the-app-does-not-parse")
  }

  func testUnsupportedEncryptionMethodIsAnInvalidActivationCandidate() throws {
    let fields = ServerFields(
      address: "203.0.113.7",
      port: 8388,
      encryptionMethod: "future-cipher",
      password: "password")

    let preparation = LeafPreparation.prepare(
      fields, plugins: ActivationFixture.plugins)

    XCTAssertEqual(preparation.issues, [.unsupportedEncryptionMethod("future-cipher")])
  }

  func testMissingPluginExecutableIsInvalidWithoutInspectingOptions() throws {
    let fields = ServerFields(
      address: "203.0.113.7",
      port: 8388,
      encryptionMethod: "aes-256-gcm",
      password: "password",
      pluginProgram: "unknown-plugin",
      pluginOptions: "opaque-options")

    let preparation = LeafPreparation.prepare(
      fields, plugins: NoManagedPluginProvider())

    XCTAssertEqual(
      preparation.issues,
      [.pluginNotProvided(program: "unknown-plugin")])
  }

  func testMissingPasswordIsInvalid() throws {
    let fields = ActivationFixture.plainFields(remark: "server", password: "")

    let preparation = LeafPreparation.prepare(
      fields, plugins: ActivationFixture.plugins)

    XCTAssertEqual(preparation.issues, [.missingPassword])
  }

  func testFieldAndCredentialIssuesAreAllCollected() throws {
    let fields = ServerFields(
      address: " ",
      port: 0,
      encryptionMethod: "future-cipher",
      password: "")

    let preparation = LeafPreparation.prepare(
      fields, plugins: ActivationFixture.plugins)

    XCTAssertEqual(
      preparation.issues,
      [
        .invalidAddress,
        .invalidPort(0),
        .unsupportedEncryptionMethod("future-cipher"),
        .missingPassword,
      ])
    XCTAssertNil(preparation.password)
    XCTAssertNil(preparation.plugin)
    XCTAssertNil(preparation.pluginOptions)
  }

  func testResolvedPluginFactsPassThroughForAssembly() throws {
    var fields = ActivationFixture.plainFields(remark: "带插件", password: "SECRET")
    fields.pluginProgram = "v2ray-plugin"

    let preparation = LeafPreparation.prepare(
      fields, plugins: ActivationFixture.plugins)

    XCTAssertEqual(preparation.issues, [])
    XCTAssertEqual(preparation.password, "SECRET")
    XCTAssertEqual(preparation.plugin?.path, "/bundle/Helpers/Plugins/v2ray-plugin")
    XCTAssertEqual(preparation.plugin?.arguments, [])
    XCTAssertNil(preparation.pluginOptions, "无插件选项引用时不解析选项")
  }
}
