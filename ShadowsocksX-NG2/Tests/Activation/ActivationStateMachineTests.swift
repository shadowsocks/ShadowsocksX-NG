import XCTest

@testable import ShadowsocksX_NG2

/// 激活主缝测试：单服务器激活、组展开顺序与无效候选过滤、
/// 原子失败点名原因、组目标身份保持。重展开与清除停止见 ActivationReexpansionTests。
final class ActivationStateMachineTests: XCTestCase {
  private var machine = ActivationStateMachine()

  @discardableResult
  private func activate(
    _ target: NodeID, in catalog: ConfigurationCatalog, credentials: CredentialStoring
  ) throws -> RuntimeConfiguration {
    try ActivationFixture.activate(&machine, target, in: catalog, credentials: credentials)
  }

  // MARK: 激活

  func testActivateSingleServerSelectsItAndResolvesCredentialAtDerivationTime() throws {
    var catalog = ConfigurationCatalog()
    let passwordRef = CredentialReference(rawValue: "ref-password")
    let server = try catalog.addServer(
      ActivationFixture.plainFields(remark: "香港 01", passwordRef: passwordRef))
    let credentials = try ActivationFixture.makeCredentials([passwordRef: "SECRET-密码"])

    let configuration = try activate(server, in: catalog, credentials: credentials)

    XCTAssertEqual(machine.activeTargetID, server, "单服务器激活即单选")
    XCTAssertEqual(configuration.targetID, server)
    XCTAssertEqual(configuration.document.servers.count, 1)
    let entry = configuration.document.servers[0]
    XCTAssertEqual(entry.id, server.rawValue)
    XCTAssertEqual(entry.server, "203.0.113.7")
    XCTAssertEqual(entry.serverPort, 8388)
    XCTAssertEqual(entry.method, "aes-256-gcm")
    XCTAssertEqual(entry.password, "SECRET-密码", "密码在派生时从凭据存储解析")
    XCTAssertNil(entry.plugin, "无插件时 plugin 字段整体省略")
    XCTAssertNil(entry.pluginOpts)
    XCTAssertEqual(configuration.document.socksAddress, "127.0.0.1")
    XCTAssertEqual(configuration.document.socksPort, 11086)
    XCTAssertEqual(configuration.document.socksLocal?.inboundProtocol, "socks")
    XCTAssertEqual(configuration.document.socksMode, "tcp_and_udp")
  }

  func testActivateGroupExpandsValidLeavesInExplicitOrderAndKeepsGroupIdentity() throws {
    var catalog = ConfigurationCatalog()
    let credentials = InMemoryCredentialStore()
    let group = try catalog.addGroup("自用")
    let first = try ActivationFixture.addPlainServer(
      "a", to: group, in: &catalog, credentials: credentials)
    let invalidLeaf = try ActivationFixture.addPlainServer(
      "b", to: group, in: &catalog, credentials: credentials)
    var invalidFields = try ActivationFixture.serverFields(of: invalidLeaf, in: catalog)
    invalidFields.encryptionMethod = "future-cipher"
    try catalog.updateServer(invalidLeaf, with: invalidFields)
    let nested = try catalog.addGroup("嵌套", to: group)
    let deepFirst = try ActivationFixture.addPlainServer(
      "c", to: nested, in: &catalog, credentials: credentials)
    let deepInvalid = try ActivationFixture.addPlainServer(
      "d", to: nested, in: &catalog, credentials: credentials)
    var deepInvalidFields = try ActivationFixture.serverFields(of: deepInvalid, in: catalog)
    deepInvalidFields.encryptionMethod = "future-cipher"
    try catalog.updateServer(deepInvalid, with: deepInvalidFields)
    let last = try ActivationFixture.addPlainServer(
      "e", to: group, in: &catalog, credentials: credentials)

    let configuration = try activate(group, in: catalog, credentials: credentials)

    XCTAssertEqual(machine.activeTargetID, group)
    XCTAssertEqual(
      configuration.targetID, group, "组目标保持组 UUID，不被 sslocal 实际选中的后代替换")
    XCTAssertEqual(
      configuration.document.servers.map(\.id),
      [first.rawValue, deepFirst.rawValue, last.rawValue],
      "显式子序深度优先展开，已知无效叶子被跳过")
    XCTAssertEqual(
      configuration.skippedServers.map(\.id), [invalidLeaf, deepInvalid])
  }

  func testActivateGroupWithAllInvalidLeavesIsRejected() throws {
    var catalog = ConfigurationCatalog()
    let credentials = InMemoryCredentialStore()
    let group = try catalog.addGroup("组")
    let leaf = try ActivationFixture.addPlainServer(
      "a", to: group, in: &catalog, credentials: credentials)
    var fields = try ActivationFixture.serverFields(of: leaf, in: catalog)
    fields.encryptionMethod = "future-cipher"
    try catalog.updateServer(leaf, with: fields)

    ActivationFixture.assertThrows(.targetExpandsToNothing(group)) {
      try activate(group, in: catalog, credentials: credentials)
    }
    XCTAssertNil(machine.activeTargetID)
  }

  func testActivateEmptyGroupIsRejected() throws {
    var catalog = ConfigurationCatalog()
    let credentials = InMemoryCredentialStore()
    let group = try catalog.addGroup("空组")

    ActivationFixture.assertThrows(.targetExpandsToNothing(group)) {
      try activate(group, in: catalog, credentials: credentials)
    }
    XCTAssertNil(machine.activeTargetID)
  }

  func testActivateGroupWhoseLeavesAreAllInvalidIsRejected() throws {
    var catalog = ConfigurationCatalog()
    let credentials = InMemoryCredentialStore()
    let group = try catalog.addGroup("组")
    let leaf = try ActivationFixture.addPlainServer(
      "a", to: group, in: &catalog, credentials: credentials)
    var fields = try ActivationFixture.serverFields(of: leaf, in: catalog)
    fields.encryptionMethod = "future-cipher"
    try catalog.updateServer(leaf, with: fields)

    ActivationFixture.assertThrows(.targetExpandsToNothing(group)) {
      try activate(group, in: catalog, credentials: credentials)
    }
  }

  func testActivateServerWithUnprovidedPluginIsRejectedNamingProgram() throws {
    var catalog = ConfigurationCatalog()
    let credentials = InMemoryCredentialStore()
    let leaf = try ActivationFixture.addPlainServer("a", in: &catalog, credentials: credentials)
    var fields = try ActivationFixture.serverFields(of: leaf, in: catalog)
    fields.pluginProgram = "kcptun"
    try catalog.updateServer(leaf, with: fields)

    ActivationFixture.assertThrows(
      .invalidLeaf(node: leaf, reason: .pluginNotProvided(program: "kcptun"))
    ) {
      try activate(leaf, in: catalog, credentials: credentials)
    }
    XCTAssertNil(machine.activeTargetID, "拒绝激活，不产生目标")
  }

  func testActivateGroupContainingUnprovidedPluginLeafSkipsIt() throws {
    var catalog = ConfigurationCatalog()
    let credentials = InMemoryCredentialStore()
    let group = try catalog.addGroup("组")
    let valid = try ActivationFixture.addPlainServer(
      "a", to: group, in: &catalog, credentials: credentials)
    let broken = try ActivationFixture.addPlainServer(
      "b", to: group, in: &catalog, credentials: credentials)
    var brokenFields = try ActivationFixture.serverFields(of: broken, in: catalog)
    brokenFields.pluginProgram = "kcptun"
    try catalog.updateServer(broken, with: brokenFields)
    let configuration = try activate(group, in: catalog, credentials: credentials)

    XCTAssertEqual(configuration.document.servers.map(\.id), [valid.rawValue])
    XCTAssertEqual(
      configuration.skippedServers,
      [SkippedServer(id: broken, reason: .pluginNotProvided(program: "kcptun"))])
    XCTAssertEqual(machine.activeTargetID, group)
  }

  func testActivateServerWithManagedPluginWritesBundlePathAndResolvesOptions() throws {
    var catalog = ConfigurationCatalog()
    let passwordRef = CredentialReference(rawValue: "ref-pw-x")
    let optionsRef = CredentialReference(rawValue: "ref-options")
    let credentials = try ActivationFixture.makeCredentials([passwordRef: "pw"])
    try credentials.save("loglevel=none", for: optionsRef)
    let leaf = try catalog.addServer(
      ServerFields(
        address: "203.0.113.7",
        port: 8388,
        encryptionMethod: "aes-256-gcm",
        passwordRef: passwordRef,
        remark: "带插件",
        pluginProgram: "v2ray-plugin",
        pluginOptionsRef: optionsRef
      ))

    let configuration = try activate(leaf, in: catalog, credentials: credentials)

    let entry = configuration.document.servers[0]
    XCTAssertEqual(entry.plugin, "/bundle/Helpers/Plugins/v2ray-plugin", "受管集提供 bundle 内路径")
    XCTAssertEqual(entry.pluginOpts, "loglevel=none", "插件参数同样派生时解析")
  }

  func testActivateUnknownTargetIsRejected() throws {
    var catalog = ConfigurationCatalog()
    let credentials = InMemoryCredentialStore()
    _ = try ActivationFixture.addPlainServer("a", in: &catalog, credentials: credentials)

    ActivationFixture.assertThrows(.targetNotFound(NodeID(rawValue: "ghost"))) {
      try activate(NodeID(rawValue: "ghost"), in: catalog, credentials: credentials)
    }
  }

  func testActivateServerWithMissingCredentialIsRejectedNamingReference() throws {
    var catalog = ConfigurationCatalog()
    let credentials = InMemoryCredentialStore()
    let missingRef = CredentialReference(rawValue: "ref-missing")
    let leaf = try catalog.addServer(
      ActivationFixture.plainFields(remark: "a", passwordRef: missingRef))

    ActivationFixture.assertThrows(
      .invalidLeaf(node: leaf, reason: .credentialUnresolved(missingRef))
    ) {
      try activate(leaf, in: catalog, credentials: credentials)
    }
  }

  func testActivateServerWithFailingCredentialReadIsRejectedNamingReference() throws {
    var catalog = ConfigurationCatalog()
    let failingRef = CredentialReference(rawValue: "ref-failing")
    let leaf = try catalog.addServer(
      ActivationFixture.plainFields(remark: "a", passwordRef: failingRef))

    ActivationFixture.assertThrows(
      .invalidLeaf(node: leaf, reason: .credentialReadFailed(failingRef))
    ) {
      try activate(leaf, in: catalog, credentials: ActivationFixture.FailingCredentialStore())
    }
  }

  func testReactivateReplacesTarget() throws {
    var catalog = ConfigurationCatalog()
    let credentials = InMemoryCredentialStore()
    let first = try ActivationFixture.addPlainServer("a", in: &catalog, credentials: credentials)
    let second = try ActivationFixture.addPlainServer("b", in: &catalog, credentials: credentials)
    try activate(first, in: catalog, credentials: credentials)

    try activate(second, in: catalog, credentials: credentials)

    XCTAssertEqual(machine.activeTargetID, second)
  }
}
