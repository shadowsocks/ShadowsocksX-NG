import XCTest

@testable import ShadowsocksX_NG2

/// 叶子预检缝：一次完成激活阻塞判定与凭据/插件解析，产出供目录树呈现与
/// 运行时装配共用的事实。文档装配不在本缝。
final class LeafPreparationTests: XCTestCase {
  func testSupportedServerWithOpaquePluginOptionsIsReady() throws {
    let passwordRef = CredentialReference(rawValue: "password")
    let optionsRef = CredentialReference(rawValue: "options")
    let credentials = try ActivationFixture.makeCredentials([
      passwordRef: "password",
      optionsRef: "plugin-option-that-the-app-does-not-parse",
    ])
    let fields = ServerFields(
      address: "203.0.113.7",
      port: 8388,
      encryptionMethod: "aes-256-gcm",
      passwordRef: passwordRef,
      pluginProgram: "v2ray-plugin",
      pluginOptionsRef: optionsRef)

    let preparation = LeafPreparation.prepare(
      fields, credentials: credentials, plugins: ActivationFixture.plugins)

    XCTAssertEqual(preparation.issues, [])
    XCTAssertEqual(preparation.password, "password")
    XCTAssertEqual(preparation.plugin?.path, "/bundle/Helpers/Plugins/v2ray-plugin")
    XCTAssertEqual(preparation.pluginOptions, "plugin-option-that-the-app-does-not-parse")
  }

  func testUnsupportedEncryptionMethodIsAnInvalidActivationCandidate() throws {
    let passwordRef = CredentialReference(rawValue: "password")
    let credentials = try ActivationFixture.makeCredentials([passwordRef: "password"])
    let fields = ServerFields(
      address: "203.0.113.7",
      port: 8388,
      encryptionMethod: "future-cipher",
      passwordRef: passwordRef)

    let preparation = LeafPreparation.prepare(
      fields, credentials: credentials, plugins: ActivationFixture.plugins)

    XCTAssertEqual(preparation.issues, [.unsupportedEncryptionMethod("future-cipher")])
  }

  func testMissingPluginExecutableIsInvalidWithoutInspectingOptions() throws {
    let passwordRef = CredentialReference(rawValue: "password")
    let optionsRef = CredentialReference(rawValue: "options")
    let credentials = try ActivationFixture.makeCredentials([
      passwordRef: "password",
      optionsRef: "opaque-options",
    ])
    let fields = ServerFields(
      address: "203.0.113.7",
      port: 8388,
      encryptionMethod: "aes-256-gcm",
      passwordRef: passwordRef,
      pluginProgram: "unknown-plugin",
      pluginOptionsRef: optionsRef)

    let preparation = LeafPreparation.prepare(
      fields, credentials: credentials, plugins: NoManagedPluginProvider())

    XCTAssertEqual(
      preparation.issues,
      [.pluginNotProvided(program: "unknown-plugin")])
  }

  func testMissingPasswordIsInvalid() throws {
    let passwordRef = CredentialReference(rawValue: "password")
    let credentials = try ActivationFixture.makeCredentials([passwordRef: ""])
    let fields = ActivationFixture.plainFields(remark: "server", passwordRef: passwordRef)

    let preparation = LeafPreparation.prepare(
      fields, credentials: credentials, plugins: ActivationFixture.plugins)

    XCTAssertEqual(preparation.issues, [.credentialUnresolved(passwordRef)])
  }

  func testFieldAndCredentialIssuesAreAllCollected() throws {
    let passwordRef = CredentialReference(rawValue: "password")
    let credentials = try ActivationFixture.makeCredentials([passwordRef: ""])
    let fields = ServerFields(
      address: " ",
      port: 0,
      encryptionMethod: "future-cipher",
      passwordRef: passwordRef)

    let preparation = LeafPreparation.prepare(
      fields, credentials: credentials, plugins: ActivationFixture.plugins)

    XCTAssertEqual(
      preparation.issues,
      [
        .invalidAddress,
        .invalidPort(0),
        .unsupportedEncryptionMethod("future-cipher"),
        .credentialUnresolved(passwordRef),
      ])
    XCTAssertNil(preparation.password)
    XCTAssertNil(preparation.plugin)
    XCTAssertNil(preparation.pluginOptions)
  }

  func testResolvedPluginFactsPassThroughForAssembly() throws {
    let passwordRef = CredentialReference(rawValue: "password")
    let credentials = try ActivationFixture.makeCredentials([passwordRef: "SECRET"])
    var fields = ActivationFixture.plainFields(remark: "带插件", passwordRef: passwordRef)
    fields.pluginProgram = "v2ray-plugin"

    let preparation = LeafPreparation.prepare(
      fields, credentials: credentials, plugins: ActivationFixture.plugins)

    XCTAssertEqual(preparation.issues, [])
    XCTAssertEqual(preparation.password, "SECRET")
    XCTAssertEqual(preparation.plugin?.path, "/bundle/Helpers/Plugins/v2ray-plugin")
    XCTAssertEqual(preparation.plugin?.arguments, [])
    XCTAssertNil(preparation.pluginOptions, "无插件选项引用时不解析选项")
  }
}
