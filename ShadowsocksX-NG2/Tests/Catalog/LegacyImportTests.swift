import Foundation
import XCTest

@testable import ShadowsocksX_NG2

/// Legacy 导入主缝：用属性列表快照模拟旧版 UserDefaults，通过导入结果与持久化
/// 文档观察身份映射、服务器记录、凭据引用和事务语义；不读取或修改真实 Legacy 数据。
final class LegacyImportTests: XCTestCase {
  private var directory: URL!
  private var catalogURL: URL!
  private var activationURL: URL!
  private var settingsURL: URL!
  private var credentials: InMemoryCredentialStore!
  private var marker: TestLegacyImportMarker!
  private var provider: FixedLegacySnapshotProvider!

  override func setUpWithError() throws {
    try super.setUpWithError()
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("legacy-import-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    catalogURL = directory.appendingPathComponent("catalog.json")
    activationURL = directory.appendingPathComponent("activation.json")
    settingsURL = directory.appendingPathComponent("proxy-listening.json")
    credentials = InMemoryCredentialStore()
    marker = TestLegacyImportMarker()
    provider = FixedLegacySnapshotProvider(snapshot: try Self.makeSnapshot())
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    try super.tearDownWithError()
  }

  func testImportMapsProfilesAndCredentials() throws {
    let service = makeService()

    let outcome = try service.importCurrentSnapshot()

    XCTAssertEqual(outcome.report.importedServerCount, 4)
    XCTAssertEqual(outcome.report.skippedRecords.map(\.index), [4, 5])
    XCTAssertEqual(
      outcome.report.skippedRecords.map(\.reason),
      [.invalidAddress, .notDictionary])
    XCTAssertEqual(outcome.report.regeneratedIdentityCount, 3)
    XCTAssertTrue(marker.completed)

    let document = try makeTestCatalogStore(fileURL: catalogURL).load()
    let groupID = try XCTUnwrap(document.catalog.rootChildren.first)
    let group = try XCTUnwrap(document.catalog.entry(for: groupID))
    guard case .group(let groupFields) = group.kind else {
      return XCTFail("Legacy 导入应创建手动分组")
    }
    XCTAssertEqual(group.source, .manual)
    XCTAssertEqual(groupFields.children.count, 4)

    let first = try XCTUnwrap(document.catalog.entry(for: groupFields.children[0]))
    guard case .server(let fields) = first.kind else {
      return XCTFail("导入条目应为服务器叶子")
    }
    XCTAssertEqual(first.id, NodeID(rawValue: Self.validID))
    XCTAssertEqual(fields.pluginProgram, "unknown-plugin")
    XCTAssertEqual(
      fields.password, "password-1")
    XCTAssertEqual(
      fields.pluginOptions,
      "mode=websocket;host=example.test")
    XCTAssertNil(try ActivationStateFileStore(fileURL: activationURL).loadActiveTargetID())
  }

  func testImportIgnoresLegacyPreferencesAndActiveTarget() throws {
    var existingSettings = ProxyRuntimeSettings()
    existingSettings.listen.socksPort = 2086
    existingSettings.listen.httpPort = 2087
    existingSettings.preferredMode = .global
    let listeningStore = ProxyListeningFileStore(
      fileURL: settingsURL)
    try listeningStore.save(existingSettings.listen)

    let existingTarget = NodeID(rawValue: "existing-target")
    let activationStore = ActivationStateFileStore(fileURL: activationURL)
    try activationStore.save(activeTargetID: existingTarget)

    _ = try makeService().importCurrentSnapshot()

    XCTAssertEqual(try listeningStore.load(), existingSettings.listen)
    XCTAssertEqual(try activationStore.loadActiveTargetID(), existingTarget)
  }

  func testExplicitReimportCreatesIndependentGroupAndDoesNotRepeatAutomatically() throws {
    let service = makeService()
    let first = try service.importCurrentSnapshot()

    XCTAssertThrowsError(try service.importCurrentSnapshot()) { error in
      XCTAssertEqual(error as? LegacyImportError, .alreadyCompleted)
    }

    let second = try service.importCurrentSnapshot(reimport: true)
    let document = try makeTestCatalogStore(fileURL: catalogURL).load()
    XCTAssertEqual(document.catalog.rootChildren.count, 2)
    XCTAssertNotEqual(document.catalog.rootChildren[0], document.catalog.rootChildren[1])
    XCTAssertNotEqual(second.groupID, first.groupID)
    XCTAssertTrue(marker.completed)
  }

  func testFailedCommitRestoresCatalogCredentialsAndMarkerWithoutTouchingActivation() throws {
    let originalID = NodeID(rawValue: "existing-target")
    var originalCatalog = ConfigurationCatalog()
    let originalServer = try originalCatalog.addTestServer("原有节点", id: originalID)
    let originalFields = try XCTUnwrap(originalCatalog.entry(for: originalServer))
    guard case .server(var originalServerFields) = originalFields.kind else {
      return XCTFail("原有夹具应为服务器")
    }
    originalServerFields.password = "original-password"
    try originalCatalog.updateServer(originalServer, with: originalServerFields)
    try makeTestCatalogStore(fileURL: catalogURL).save(CatalogDocument(catalog: originalCatalog))
    try ActivationStateFileStore(fileURL: activationURL).save(activeTargetID: originalID)

    marker.failWhenSettingCompleted = true
    let service = makeService()

    XCTAssertThrowsError(try service.importCurrentSnapshot()) { error in
      guard case .commitFailed = error as? LegacyImportError else {
        return XCTFail("应以事务失败返回，实际：\(error)")
      }
    }

    XCTAssertEqual(try makeTestCatalogStore(fileURL: catalogURL).load().catalog, originalCatalog)
    XCTAssertEqual(
      try ActivationStateFileStore(fileURL: activationURL).loadActiveTargetID(), originalID)
    XCTAssertEqual(
      originalServerFields.password, "original-password")
    XCTAssertFalse(marker.completed)
  }

  func testPreferenceOnlyLegacyDomainIsNotImportable() throws {
    let defaults = UserDefaults(suiteName: "legacy-import-preferences-only")!
    defaults.removePersistentDomain(forName: "legacy-import-preferences-only")
    defer { defaults.removePersistentDomain(forName: "legacy-import-preferences-only") }
    defaults.set("externalPAC", forKey: "ShadowsocksRunningMode")
    defaults.set(false, forKey: "LaunchAtLogin")

    let provider = UserDefaultsLegacySnapshotProvider(
      defaults: defaults, bundleIdentifier: "legacy-import-preferences-only")

    XCTAssertNil(try provider.readSnapshot())
  }
}

extension LegacyImportTests {
  func testValidProfileWithoutLegacyIDGetsNewIdentityAndCounts() throws {
    var profile = Self.validProfile()
    profile.removeValue(forKey: "Id")
    provider.snapshot = try LegacySnapshot(
      propertyList: ["ServerProfiles": [profile]])

    let outcome = try makeService().importCurrentSnapshot()

    XCTAssertEqual(outcome.report.importedServerCount, 1)
    XCTAssertEqual(outcome.report.regeneratedIdentityCount, 1)
  }

  fileprivate static let validID = "11111111-1111-4111-8111-111111111111"
  fileprivate static let duplicateID = "22222222-2222-4222-8222-222222222222"

  fileprivate static func validProfile() -> [String: Any] {
    [
      "Id": validID,
      "ServerHost": "203.0.113.7",
      "ServerPort": 8388,
      "Method": "aes-256-gcm",
      "Password": "password-1",
      "Remark": "香港 01",
      "Plugin": "unknown-plugin",
      "PluginOptions": "mode=websocket;host=example.test",
    ]
  }

  /// 精简档案；`id` 为 nil 时缺省 Id 键（模拟无稳定身份的旧记录）。
  fileprivate static func profile(
    id: String?, host: String, port: Int, method: String, password: String
  ) -> [String: Any] {
    var profile: [String: Any] = [
      "ServerHost": host,
      "ServerPort": port,
      "Method": method,
      "Password": password,
    ]
    if let id { profile["Id"] = id }
    return profile
  }

  fileprivate static func makeSnapshot() throws -> LegacySnapshot {
    try LegacySnapshot(
      propertyList: [
        "ServerProfiles": [
          validProfile(),
          profile(
            id: "not-a-uuid", host: "198.51.100.8", port: 8389,
            method: "chacha20-ietf-poly1305", password: "password-2"),
          profile(
            id: duplicateID, host: "198.51.100.9", port: 8390,
            method: "aes-128-gcm", password: "password-3"),
          profile(
            id: duplicateID, host: "198.51.100.10", port: 8391,
            method: "aes-128-gcm", password: "password-4"),
          profile(
            id: nil, host: "not a host", port: 8392,
            method: "aes-128-gcm", password: "password-5"),
          "not-a-profile",
        ],
        "ActiveServerProfileId": validID,
        "LocalSocks5.ListenPort": 2086,
        "LocalSocks5.ListenAddress": "127.0.0.1",
        "LocalHTTP.ListenPort": 2087,
        "LocalHTTPOn": true,
        "PacServer.ListenPort": 2089,
        "PacServer.BindToLocalhost": true,
        "LocalSocks5.EnableUDPRelay": true,
        "LocalSocks5.Timeout": 120,
        "LocalSocks5.EnableVerboseMode": true,
        "ProxyExceptions": "localhost, example.test",
        "ExternalPACURL": "https://pac.example.test/proxy.pac",
        "GFWListURL": "https://gfw.example.test/list.txt",
        "ShadowsocksRunningMode": "externalPAC",
        "EnableSwitchMode.PAC": true,
        "EnableSwitchMode.Global": true,
        "EnableSwitchMode.Manual": false,
        "EnableSwitchMode.ExternalPAC": true,
        "LaunchAtLogin": false,
      ])
  }

  fileprivate func makeService() -> LegacyImportService {
    LegacyImportService(
      source: provider,
      catalogStore: makeTestCatalogStore(fileURL: catalogURL),
      marker: marker)
  }
}

private final class TestLegacyImportMarker: LegacyImportMarkerStoring {
  var completed = false
  var failWhenSettingCompleted = false

  func isCompleted() throws -> Bool { completed }

  func setCompleted(_ completed: Bool) throws {
    if completed && failWhenSettingCompleted {
      throw TestMarkerError.rejected
    }
    self.completed = completed
  }
}

private enum TestMarkerError: Error {
  case rejected
}
