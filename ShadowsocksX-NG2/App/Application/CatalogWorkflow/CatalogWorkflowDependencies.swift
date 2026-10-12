import Foundation

/// 组合根专用依赖束：目录工作流全部实现 adapter 的唯一装配缝。
/// 生产 adapter 由组合根（MainApp）装配，测试注入 hermetic fake；
/// CatalogWorkflow 不自行创建钥匙串存储、网络获取器或提交协调器。
/// 本类型不是 UI-facing facade：视图不得引用——独立 target 拆分前，
/// 同 target 的访问纪律由 architecture deletion check 守护。
@MainActor
struct CatalogWorkflowDependencies {
  /// 提交管线与运行时收敛的唯一入口；与代理运行时路径共享同一
  /// committed catalog source（组合根创建并注入）。
  let coordinator: CatalogCommitCoordinator
  /// 凭据存储：只在 module 内出现，UI 不持有。
  let credentials: CredentialStoring
  /// 受管插件提供缝（编辑面集内事实与可执行文件存在性）。
  let plugins: PluginExecutableResolving
  /// 订阅获取缝。
  let subscriptionFetcher: SubscriptionFetching
  /// Legacy 导入服务（快照发现、完成标记与原子导入）。
  let legacyImportService: LegacyImportService
  /// Legacy 导入提交后的 2.0 运行时边界（组合根一次性接线；独立于普通提交管线）。
  let postLegacyImport: ((LegacyImportOutcome) async -> Void)?
  /// 激活缝：生产 adapter 为 `ProxyRuntimeController`，测试注入假 adapter。
  let activator: Activating
}
