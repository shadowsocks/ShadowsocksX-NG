import Foundation

/// GUI-owned runtime and system-proxy manager. Agent and system-proxy switches
/// persist independent intentions. System proxy writes use the privileged helper;
/// current configuration is observed read-only and differs from write outcomes.
/// Health/exit loss suspends system proxy settings, real recovery reapplies, and
/// passive network events only inspect (ADR-0022)——该观察/修复策略机
/// 独立在 `SystemProxyObserver`：控制器注入意图/出口/期望配置三个事实闭包并
/// 转发命令，健康循环保留在本体（循环体含运行时健康呈现）。GUI exit ends these
/// observations without stopping the LaunchAgent or adding helper responsibilities.
@MainActor
final class ProxyRuntimeController {
  /// Agent（后台代理运行时）运行状态。系统代理结果不在此面呈现——它有
  /// 独立的 `SystemProxyControlState`。
  enum AgentRunState: Equatable {
    case off
    case starting
    case running
    /// 代理在本机运行，但主机地址态的入站被 macOS 防火墙拒绝。
    case firewallBlocked(FirewallBlockedFacts)
    /// 启动失败：携带点名端点与端口的事实。
    case launchFailed(LaunchFailureFacts)
    /// 需要用户在系统设置-登录项中允许后台项。
    case requiresApproval
    /// 服务管理或运行时文件本身失败。
    case serviceFailed(ServiceFailureFacts)
  }

  /// Current configuration or operation result, independent of persisted intent.
  typealias SystemProxyControlState = SystemProxyApplicationFacts

  var state: AgentRunState = .off { didSet { factChanges.markChanged() } }
  var settings: ProxySettings { didSet { factChanges.markChanged() } }
  /// 当前活动目标（菜单栏状态摘要与级联只读呈现用）。machine 是
  /// 非通道值的普通结构体，代理关闭路径的激活动作不会触碰 state，菜单的
  /// 「目标」行依赖此属性独立触发事实通道保持实时。
  var activeTargetID: NodeID? { didSet { factChanges.markChanged() } }
  /// 最近一次激活预检在分组中跳过的服务器；仅记录 app 已知的本地阻塞原因。
  var skippedServers: [SkippedServer] = [] { didSet { factChanges.markChanged() } }
  /// 最近一次激活拒绝或目标清除的点名原因。独立于运行状态呈现：agent 可
  /// 能仍在监听，激活失败不代表运行时停止。
  var lastActivationFailure: ActivationFailure? { didSet { factChanges.markChanged() } }
  var machine: ActivationStateMachine
  /// 运行时事实变化通道（didChange 语义）：全部事实属性的 didSet 汇集于此，
  /// 同一主队列轮内多次写合并为一次，冲洗晚于同步轮——重观察方读到的必是
  /// 完整事实，不依赖 `objectWillChange` + 主队列跳的 willChange 时序。
  let factChanges = CoalescedFactSignal()

  let catalogSnapshotReader: RuntimeCatalogSnapshotReading
  let activationFileStore: ActivationStateFileStore
  let runtimeFileStore: RuntimeFileStore
  let credentials: CredentialStoring
  let plugins: PluginExecutableResolving
  let refreshPluginSecurityFacts: @MainActor () -> Void
  let settingsStore: ProxySettingsStoring
  /// 自定义规则持久化：规则模式 ACL 合并的用户入口。
  var isUpdatingRules = false
  var ruleApplicationTask: Task<Void, Never>?
  var ruleApplicationGeneration = 0
  var ruleApplicationFailure: RuntimeFailureFacts? { didSet { factChanges.markChanged() } }
  let customRuleStore: CustomRuleStore
  let ruleDocuments: RuleDocumentSession
  let ruleSnapshots: BuiltinRuleSnapshots
  var runtimePreparationGeneration = 0
  /// 监听设置不可读时的点名原因（「任何路径不静默改端口」）；非 nil 时
  /// 设置只是占位出厂默认，禁止部署（见 `deploy`）。
  var listenSettingsUnreadable: Bool
  /// 新版偏好不可读时同样禁止部署，不以出厂端口静默替代用户配置。
  var settingsUnreadable: Bool
  let agent: LaunchAgentControlling
  let probe: EndpointProbing
  let systemProxy: SystemProxyControlling
  let systemProxyHelper: SystemProxyHelperServicing
  let systemProxyNetworkChangeMonitor: SystemProxyNetworkChangeMonitoring
  /// 系统代理观察/修复策略机（ADR-0022）：呈现事实的存储与发布点，详情见
  /// 模块文档。惰性构造：事实闭包需捕获控制器，而闭包成形必须晚于自身
  /// 全部存储属性的初始化（首次访问发生在 init 之后）。
  lazy var systemProxyObserver: SystemProxyObserver = SystemProxyObserver(
    systemProxy: systemProxy,
    systemProxyHelper: systemProxyHelper,
    systemProxyNetworkChangeMonitor: systemProxyNetworkChangeMonitor,
    appBundle: appBundle,
    helperRefreshDelayNanoseconds: helperRefreshDelayNanoseconds,
    isIntentEnabled: { [weak self] in self?.settings.systemProxyEnabled ?? false },
    isExitAvailable: { [weak self] in self?.systemProxyExitAvailable ?? false },
    desiredConfiguration: { [weak self] in
      guard let self else { return nil }
      return self.desiredSystemProxyConfiguration
    },
    systemProxyHealthObservationLoop: { [weak self] in
      guard let self else { return }
      await self.runSystemProxyHealthObservationLoop()
    })
  let firewallChecker: FirewallStatusChecking
  let firewallExecutableURLs: [URL]
  /// 宿主 app bundle 缝（生产为 Bundle.main）：内置规则快照与 LaunchDaemon
  /// 清单等打包资源的定位基准。去宿主化（ADR 0021）后单测运行于 xctest
  /// runner，`Bundle.main` 不再是 app，经此缝注入构建产物 bundle。
  let appBundle: Bundle
  let firewallPollIntervalNanoseconds: UInt64
  let launchHealthTimeoutSeconds: TimeInterval
  let launchHealthRetryDelay: () async throws -> Void
  let ruleApplicationDelay: () async throws -> Void
  /// 注册清单漂移重注时，注销与重注的间隔（launchd 对节流中 job 的移除异步）。
  let systemProxyHealthPollIntervalNanoseconds: UInt64
  let helperRefreshDelayNanoseconds: UInt64
  /// 信号发送缝（默认 kill），单测观测 SIGUSR1 投递。
  let sendSignal: @Sendable (Int32, Int32) -> Int32
  let processIsAlive: @Sendable (Int32) -> Bool
  /// 并发流代际：停止请求可使进行中的启动探测立即失效。
  var flowGeneration = 0
  var modeChangeGeneration = 0
  var lastDocument: SslocalRuntimeDocument?
  var firewallObservationTask: Task<Void, Never>?

  var proxyMode: ProxyMode { didSet { factChanges.markChanged() } }

  /// 规则模式子选项：从设置快照投影。
  var ruleDefaultAction: RuleDefaultAction { settings.ruleDefaultAction }

  init(
    catalogSnapshotReader: RuntimeCatalogSnapshotReading,
    activationFileStore: ActivationStateFileStore = ActivationStateFileStore(
      fileURL: ActivationStateFileStore.defaultFileURL()),
    runtimeFileStore: RuntimeFileStore = RuntimeFileStore(),
    credentials: CredentialStoring = KeychainCredentialStore(),
    plugins: PluginExecutableResolving = BundleManagedPluginProvider(),
    refreshPluginSecurityFacts: @escaping @MainActor () -> Void = {},
    listenRestore: RestoredListenSettings = ListenSettingsFileStore.restored(),
    settingsStore: ProxySettingsStoring = ProxySettingsFileStore(),
    customRuleStore: CustomRuleStore = CustomRuleStore(),
    appBundle: Bundle = .main,
    ruleSnapshots: BuiltinRuleSnapshots? = nil,
    settingsRestore: RestoredProxySettings? = nil,
    agent: LaunchAgentControlling = SMAppLaunchAgentService(),
    probe: EndpointProbing = SystemEndpointProbe(),
    systemProxy: SystemProxyControlling = XPCSystemProxyController(),
    systemProxyHelper: SystemProxyHelperServicing = SMAppServiceSystemProxyHelper(),
    systemProxyNetworkChangeMonitor: SystemProxyNetworkChangeMonitoring =
      NoopSystemProxyNetworkChangeMonitor(),
    proxyMode: ProxyMode? = nil,
    firewallChecker: FirewallStatusChecking = SocketFilterFirewallChecker(),
    firewallExecutableURLs: [URL]? = nil,
    firewallPollIntervalNanoseconds: UInt64 = 2_000_000_000,
    launchHealthTimeoutSeconds: TimeInterval = 15,
    launchHealthRetryDelay: @escaping () async throws -> Void = {
      try await Task.sleep(for: .milliseconds(200))
    },
    ruleApplicationDelay: @escaping () async throws -> Void = {
      try await Task.sleep(for: .milliseconds(150))
    },
    systemProxyHealthPollIntervalNanoseconds: UInt64 = 2_000_000_000,
    helperRefreshDelayNanoseconds: UInt64 = 15_000_000_000,
    sendSignal: @escaping @Sendable (Int32, Int32) -> Int32 = { kill($0, $1) },
    processIsAlive: @escaping @Sendable (Int32) -> Bool = { $0 > 0 && kill($0, 0) == 0 }
  ) {
    self.catalogSnapshotReader = catalogSnapshotReader
    self.activationFileStore = activationFileStore
    self.runtimeFileStore = runtimeFileStore
    self.credentials = credentials
    self.plugins = plugins
    self.refreshPluginSecurityFacts = refreshPluginSecurityFacts
    self.settingsStore = settingsStore
    self.customRuleStore = customRuleStore
    self.ruleDocuments = RuleDocumentSession(store: customRuleStore)
    self.ruleSnapshots = ruleSnapshots ?? BuiltinRuleSnapshots(bundle: appBundle)
    self.appBundle = appBundle
    let restoredSettings =
      settingsRestore
      ?? RestoredProxySettings(
        settings: ProxySettings(listen: listenRestore.settings),
        unreadableError: listenRestore.unreadableError.map {
          .legacyListenSettings($0)
        })
    settings = restoredSettings.settings
    listenSettingsUnreadable =
      settingsRestore == nil && listenRestore.unreadableError != nil
    settingsUnreadable = restoredSettings.unreadableError != nil
    self.agent = agent
    self.probe = probe
    self.systemProxy = systemProxy
    self.systemProxyHelper = systemProxyHelper
    self.systemProxyNetworkChangeMonitor = systemProxyNetworkChangeMonitor
    self.firewallChecker = firewallChecker
    self.firewallExecutableURLs = firewallExecutableURLs ?? Self.defaultFirewallExecutableURLs
    self.firewallPollIntervalNanoseconds = firewallPollIntervalNanoseconds
    self.launchHealthTimeoutSeconds = launchHealthTimeoutSeconds
    self.launchHealthRetryDelay = launchHealthRetryDelay
    self.ruleApplicationDelay = ruleApplicationDelay
    self.systemProxyHealthPollIntervalNanoseconds = systemProxyHealthPollIntervalNanoseconds
    self.helperRefreshDelayNanoseconds = helperRefreshDelayNanoseconds
    self.sendSignal = sendSignal
    self.processIsAlive = processIsAlive
    let persistedTarget = try? activationFileStore.loadActiveTargetID()
    machine = ActivationStateMachine(activeTargetID: persistedTarget)
    activeTargetID = machine.activeTargetID
    self.proxyMode = proxyMode ?? Self.makeProxyMode(from: restoredSettings.settings)
  }
}
