import XCTest

@testable import ShadowsocksX_NG2

/// 目录提交后的立即重展开缝：有效非空 → 原子更新；目标被
/// 删除/变空/单服务器变无效/无有效叶子 → 清除目标并发出停止意图；分组中的
/// 无效叶子会被跳过并保留有效子集，点名原因、无静默回退。
/// 点名原因、无静默回退。
final class ActivationReexpansionTests: XCTestCase {
  private var machine = ActivationStateMachine()

  @discardableResult
  private func activate(
    _ target: NodeID, in catalog: ConfigurationCatalog, credentials: CredentialStoring
  ) throws -> RuntimeConfiguration {
    try ActivationFixture.activate(&machine, target, in: catalog, credentials: credentials)
  }

  private func commit(
    _ catalog: ConfigurationCatalog, credentials: CredentialStoring
  ) -> ActivationEffect? {
    ActivationFixture.commit(&machine, catalog, credentials: credentials)
  }

  func testCommitWithoutActiveTargetProducesNoEffect() throws {
    var catalog = ConfigurationCatalog()
    let credentials = InMemoryCredentialStore()
    _ = try ActivationFixture.addPlainServer("a", in: &catalog, credentials: credentials)

    XCTAssertNil(commit(catalog, credentials: credentials))
  }

  func testSubtreeEditReexpandsAndDeploysUpdatedDocumentAtomically() throws {
    var catalog = ConfigurationCatalog()
    let credentials = InMemoryCredentialStore()
    let group = try catalog.addGroup("组")
    let leaf = try ActivationFixture.addPlainServer(
      "a", to: group, in: &catalog, credentials: credentials)
    try activate(group, in: catalog, credentials: credentials)

    var updatedFields = try ActivationFixture.serverFields(of: leaf, in: catalog)
    updatedFields.address = "198.51.100.9"
    updatedFields.port = 443
    try catalog.updateServer(leaf, with: updatedFields)
    try credentials.save("new-secret", for: updatedFields.passwordRef)

    let configuration = try ActivationFixture.requireDeployed(
      commit(catalog, credentials: credentials))
    XCTAssertEqual(machine.activeTargetID, group, "重展开不改变活动目标")
    XCTAssertEqual(configuration.targetID, group)
    XCTAssertEqual(configuration.document.servers[0].server, "198.51.100.9")
    XCTAssertEqual(configuration.document.servers[0].serverPort, 443)
    XCTAssertEqual(
      configuration.document.servers[0].password, "new-secret", "同一引用解析最新秘密")
  }

  func testDeleteActiveTargetClearsTargetAndEmitsStopIntent() throws {
    var catalog = ConfigurationCatalog()
    let credentials = InMemoryCredentialStore()
    let leaf = try ActivationFixture.addPlainServer("a", in: &catalog, credentials: credentials)
    try activate(leaf, in: catalog, credentials: credentials)

    try catalog.remove(leaf)

    let failure = try ActivationFixture.requireCleared(commit(catalog, credentials: credentials))
    XCTAssertEqual(failure, .targetNotFound(leaf), "点名原因")
    XCTAssertNil(machine.activeTargetID, "目标被清除")
    XCTAssertNil(commit(catalog, credentials: credentials), "清除后不再产生效应")
  }

  func testInvalidActiveServerClearsTargetAndStops() throws {
    var catalog = ConfigurationCatalog()
    let credentials = InMemoryCredentialStore()
    let leaf = try ActivationFixture.addPlainServer("a", in: &catalog, credentials: credentials)
    try activate(leaf, in: catalog, credentials: credentials)

    var fields = try ActivationFixture.serverFields(of: leaf, in: catalog)
    fields.encryptionMethod = "future-cipher"
    try catalog.updateServer(leaf, with: fields)

    let failure = try ActivationFixture.requireCleared(commit(catalog, credentials: credentials))
    XCTAssertEqual(
      failure, .invalidLeaf(node: leaf, reason: .unsupportedEncryptionMethod("future-cipher")))
    XCTAssertNil(machine.activeTargetID)
  }

  func testInvalidLeafInActiveGroupIsSkippedAndKeepsTarget() throws {
    var catalog = ConfigurationCatalog()
    let credentials = InMemoryCredentialStore()
    let group = try catalog.addGroup("组")
    let valid = try ActivationFixture.addPlainServer(
      "a", to: group, in: &catalog, credentials: credentials)
    let broken = try ActivationFixture.addPlainServer(
      "b", to: group, in: &catalog, credentials: credentials)
    try activate(group, in: catalog, credentials: credentials)

    var fields = try ActivationFixture.serverFields(of: broken, in: catalog)
    fields.encryptionMethod = "future-cipher"
    try catalog.updateServer(broken, with: fields)

    let configuration = try ActivationFixture.requireDeployed(
      commit(catalog, credentials: credentials))
    XCTAssertEqual(configuration.targetID, group)
    XCTAssertEqual(configuration.document.servers.map(\.id), [valid.rawValue])
    XCTAssertEqual(
      configuration.skippedServers,
      [SkippedServer(id: broken, reason: .unsupportedEncryptionMethod("future-cipher"))])
    XCTAssertEqual(machine.activeTargetID, group)
  }

  func testEmptyingActiveGroupClearsTargetAndStops() throws {
    var catalog = ConfigurationCatalog()
    let credentials = InMemoryCredentialStore()
    let group = try catalog.addGroup("组")
    let leaf = try ActivationFixture.addPlainServer(
      "a", to: group, in: &catalog, credentials: credentials)
    try activate(group, in: catalog, credentials: credentials)

    try catalog.remove(leaf)

    let failure = try ActivationFixture.requireCleared(commit(catalog, credentials: credentials))
    XCTAssertEqual(failure, .targetExpandsToNothing(group))
    XCTAssertNil(machine.activeTargetID)
  }

  func testUnprovidedPluginIntroducedIntoOnlyActiveGroupLeafClearsTarget() throws {
    var catalog = ConfigurationCatalog()
    let credentials = InMemoryCredentialStore()
    let group = try catalog.addGroup("组")
    let leaf = try ActivationFixture.addPlainServer(
      "a", to: group, in: &catalog, credentials: credentials)
    try activate(group, in: catalog, credentials: credentials)

    var fields = try ActivationFixture.serverFields(of: leaf, in: catalog)
    fields.pluginProgram = "kcptun"
    try catalog.updateServer(leaf, with: fields)

    let failure = try ActivationFixture.requireCleared(commit(catalog, credentials: credentials))
    XCTAssertEqual(failure, .targetExpandsToNothing(group))
    XCTAssertNil(machine.activeTargetID)
  }

  func testMissingCredentialInActiveSubtreeClearsTargetAndStops() throws {
    var catalog = ConfigurationCatalog()
    let missingRef = CredentialReference(rawValue: "ref-missing")
    let credentials = try ActivationFixture.makeCredentials([missingRef: "pw"])
    let leaf = try catalog.addServer(
      ActivationFixture.plainFields(remark: "a", passwordRef: missingRef))
    try activate(leaf, in: catalog, credentials: credentials)

    try credentials.delete(missingRef)

    let failure = try ActivationFixture.requireCleared(commit(catalog, credentials: credentials))
    XCTAssertEqual(failure, .invalidLeaf(node: leaf, reason: .credentialUnresolved(missingRef)))
    XCTAssertNil(machine.activeTargetID)
  }

  func testFailingCredentialReadInActiveSubtreeClearsTargetAndStops() throws {
    var catalog = ConfigurationCatalog()
    let failingRef = CredentialReference(rawValue: "ref-failing")
    let credentials = try ActivationFixture.makeCredentials([failingRef: "pw"])
    let leaf = try catalog.addServer(
      ActivationFixture.plainFields(remark: "a", passwordRef: failingRef))
    try activate(leaf, in: catalog, credentials: credentials)

    let failure = try ActivationFixture.requireCleared(
      commit(catalog, credentials: ActivationFixture.FailingCredentialStore()))
    XCTAssertEqual(failure, .invalidLeaf(node: leaf, reason: .credentialReadFailed(failingRef)))
    XCTAssertNil(machine.activeTargetID)
  }

  func testPriorTargetSurvivesFailedActivationAndStaysDeployableOnCommit() throws {
    var catalog = ConfigurationCatalog()
    let credentials = InMemoryCredentialStore()
    let valid = try ActivationFixture.addPlainServer("a", in: &catalog, credentials: credentials)
    let group = try catalog.addGroup("组")
    let broken = try ActivationFixture.addPlainServer(
      "b", to: group, in: &catalog, credentials: credentials)
    var brokenFields = try ActivationFixture.serverFields(of: broken, in: catalog)
    brokenFields.pluginProgram = "kcptun"
    try catalog.updateServer(broken, with: brokenFields)
    try activate(valid, in: catalog, credentials: credentials)

    ActivationFixture.assertThrows(
      .invalidLeaf(node: broken, reason: .pluginNotProvided(program: "kcptun")),
      {
        try activate(broken, in: catalog, credentials: credentials)
      })

    let configuration = try ActivationFixture.requireDeployed(
      commit(catalog, credentials: credentials))
    XCTAssertEqual(configuration.targetID, valid, "无静默回退：失败后原目标仍是活动目标")
    XCTAssertEqual(machine.activeTargetID, valid)
  }

  func testRestoredTargetRevalidatesOnNextCommit() throws {
    var catalog = ConfigurationCatalog()
    let credentials = InMemoryCredentialStore()
    let leaf = try ActivationFixture.addPlainServer("a", in: &catalog, credentials: credentials)
    let deletedID = NodeID(rawValue: "deleted")

    var restored = ActivationStateMachine(activeTargetID: leaf)
    let configuration = try ActivationFixture.requireDeployed(
      ActivationFixture.commit(&restored, catalog, credentials: credentials))
    XCTAssertEqual(configuration.targetID, leaf, "恢复的有效目标在下次提交时重放派生（D5 同步）")

    var stale = ActivationStateMachine(activeTargetID: deletedID)
    let failure = try ActivationFixture.requireCleared(
      ActivationFixture.commit(&stale, catalog, credentials: credentials))
    XCTAssertEqual(failure, .targetNotFound(deletedID), "恢复的失效目标在下次提交时清除并停止")
    XCTAssertNil(stale.activeTargetID)
  }
}
