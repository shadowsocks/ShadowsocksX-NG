import Foundation
import XCTest

@testable import ShadowsocksX_NG2

/// 测试用内存凭据存储；契约与 Keychain 实现一致。
final class InMemoryCredentialStore: CredentialStoring {
  private var storage: [String: String] = [:]

  var storageCount: Int { storage.count }

  /// 全量键值快照（凭据生命周期观察：删除/回滚后应有值消失或恢复）。
  var storageSnapshot: [String: String] { storage }

  func save(_ secret: String, for reference: CredentialReference) throws {
    storage[reference.rawValue] = secret
  }

  func secret(for reference: CredentialReference) throws -> String? {
    storage[reference.rawValue]
  }

  func delete(_ reference: CredentialReference) throws {
    storage.removeValue(forKey: reference.rawValue)
  }
}

/// 订阅子树夹具：固定分组 + 嵌套分组 + 两个服务器叶子。
struct SubscriptionFixture {
  let catalog: ConfigurationCatalog
  let groupID: NodeID
  let nestedGroupID: NodeID
  let serverIDs: [NodeID]
}

/// 目录树测试夹具。订阅子树在这里仅用于测试刷新语义。
enum CatalogFixtures {
  /// 订阅节点身份采用「订阅前缀:供应商稳定 ID」作用域限定形式。
  static func makeSubscriptionFixture(prefix: String = "sub1") throws -> SubscriptionFixture {
    var catalog = ConfigurationCatalog()
    let groupID = NodeID(rawValue: "\(prefix):group")
    try catalog.addGroup("订阅分组", source: .subscription, id: groupID)
    let nestedGroupID = NodeID(rawValue: "\(prefix):nested-group")
    try catalog.addGroup("嵌套分组", source: .subscription, id: nestedGroupID, to: groupID)
    let serverA = NodeID(rawValue: "\(prefix):server-a")
    try catalog.addServer(
      serverFields(remark: "香港 01"), source: .subscription, id: serverA, to: groupID)
    let serverB = NodeID(rawValue: "\(prefix):server-b")
    try catalog.addServer(
      serverFields(remark: "日本 02"), source: .subscription, id: serverB, to: nestedGroupID)
    return SubscriptionFixture(
      catalog: catalog,
      groupID: groupID,
      nestedGroupID: nestedGroupID,
      serverIDs: [serverA, serverB]
    )
  }

  /// 服务器叶子夹具。地址用文档保留段（RFC 5737），不指向真实主机。
  static func serverFields(remark: String) -> ServerFields {
    ServerFields(
      address: "203.0.113.7",
      port: 8388,
      encryptionMethod: "aes-256-gcm",
      passwordRef: .fresh(),
      remark: remark,
      pluginProgram: "v2ray-plugin",
      pluginOptionsRef: .fresh()
    )
  }
}

/// 测试便捷扩展：省去每次填字段。
extension ConfigurationCatalog {
  @discardableResult
  mutating func addTestServer(
    _ remark: String,
    source: NodeSource = .manual,
    id: NodeID? = nil,
    to parent: NodeID? = nil,
    index: Int? = nil,
    now: Date = Date()
  ) throws -> NodeID {
    try addServer(
      CatalogFixtures.serverFields(remark: remark), source: source, id: id, to: parent,
      index: index, now: now
    )
  }
}

/// `XCTAssertThrowsError` 的 async 版本（表达式在 await 之后才能检查）。
@MainActor
func expectThrowsAsync(
  _ expression: @MainActor () async throws -> Void,
  onThrow errorHandler: @MainActor (Error) -> Void = { _ in },
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    _ = try await expression()
    XCTFail("预期抛错，但成功返回", file: file, line: line)
  } catch {
    errorHandler(error)
  }
}

// MARK: - 目录工作流测试夹具

/// 中性激活替身：不关心激活语义的测试场景，激活命令原子拒绝（原因任意）。
final class RejectingActivator: Activating {
  func activate(_ target: NodeID) async throws -> ActivationCommandOutcome {
    .rejectedActivation(.noActiveTarget)
  }
}

/// 永不提供快照的 Legacy 来源替身（测试不读用户 Legacy 偏好）。
struct EmptyLegacySnapshotProvider: LegacySnapshotProviding {
  func readSnapshot() throws -> LegacySnapshot? { nil }
}

/// 固定快照提供缝替身（可中途改写快照，供重读场景断言）。
final class FixedLegacySnapshotProvider: LegacySnapshotProviding {
  var snapshot: LegacySnapshot?

  init(snapshot: LegacySnapshot?) {
    self.snapshot = snapshot
  }

  func readSnapshot() throws -> LegacySnapshot? { snapshot }
}

/// 内存完成标记替身（测试不写 UserDefaults）。
final class InMemoryLegacyImportMarker: LegacyImportMarkerStoring {
  private(set) var completed = false

  func isCompleted() throws -> Bool { completed }

  func setCompleted(_ completed: Bool) throws {
    self.completed = completed
  }
}

/// 目录工作流测试组装缝：经依赖束显式装配全部 hermetic fake，
/// 不触碰生产 Keychain、UserDefaults、网络或激活边界。各测试按需覆盖任一
/// adapter；未指定 Legacy 服务时用「空快照 + 内存标记」的组合（工作流 init
/// 的发现状态读取仍被观察，但只触替身）。
@MainActor
func makeCatalogWorkflow(
  coordinator: CatalogCommitCoordinator,
  credentials: CredentialStoring,
  plugins: PluginExecutableResolving = NoManagedPluginProvider(),
  subscriptionFetcher: SubscriptionFetching = FakeSubscriptionFetcher(
    behavior: .success(Data())),
  legacyImportService: LegacyImportService? = nil,
  postLegacyImport: ((LegacyImportOutcome) async -> Void)? = nil,
  activator: Activating = RejectingActivator()
) -> CatalogWorkflow {
  CatalogWorkflow(
    dependencies: CatalogWorkflowDependencies(
      coordinator: coordinator,
      credentials: credentials,
      plugins: plugins,
      subscriptionFetcher: subscriptionFetcher,
      legacyImportService: legacyImportService
        ?? LegacyImportService(
          source: EmptyLegacySnapshotProvider(),
          catalogStore: coordinator.fileStore,
          credentials: credentials,
          marker: InMemoryLegacyImportMarker()),
      postLegacyImport: postLegacyImport,
      activator: activator))
}

// MARK: - 统一导入结果取用助手

extension ImportSourceResult {
  /// `.imported` 的添加数（非该 case 为 nil）。
  var importedCount: Int? {
    if case .imported(let count, _) = self { return count }
    return nil
  }

  /// `.imported` 的落点/新建分组（非该 case 或目录根为 nil）。
  var importedGroupID: NodeID? {
    if case .imported(_, let groupID) = self { return groupID }
    return nil
  }

  /// `.partial` 的添加数与失败行（非该 case 为 nil）。
  var partialFacts: (addedCount: Int, failures: [ImportLineFailure])? {
    if case .partial(let addedCount, let failures) = self { return (addedCount, failures) }
    return nil
  }

  /// `.failed` 的原因（非该 case 为 nil）。
  var sourceFailure: ImportSourceFailure? {
    if case .failed(let failure) = self { return failure }
    return nil
  }
}
