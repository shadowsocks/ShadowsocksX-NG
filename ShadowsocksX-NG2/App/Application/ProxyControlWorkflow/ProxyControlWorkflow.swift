import Combine
import Foundation

// MARK: - Snapshot 投影

/// 可安全复制的 HTTP 导出能力：shell 可直接 source 的 http/https
/// 双导出行。原始监听设置与内部端口语义不进 snapshot。复制是 UI 的副作用，
/// workflow 不触剪贴板。
struct HTTPExportCapability: Equatable, Sendable {
  /// 已就绪的导出行（UI 原样复制，不自行拼装）。
  let copyableLine: String
}

/// 首页可复制的 shell 环境变量设置命令。不同 shell 的语法由 workflow 一次投影，
/// 呈现层只选择格式并执行剪贴板副作用。
enum TerminalCommandFailure: Error, Equatable, Sendable {
  case credentialUnreadable
  case addressUnavailable
}

struct TerminalProxyEnvironmentCommands: Equatable, Sendable {
  let zshBash: String
  let fish: String
  let nushell: String
  let windowsCMD: String
  let windowsPowerShell: String
  var failure: TerminalCommandFailure?
}

enum TerminalCommandShell: CaseIterable, Hashable, Sendable {
  case zshBash, fish, nushell, windowsCMD, windowsPowerShell

  func command(from commands: TerminalProxyEnvironmentCommands) -> String {
    switch self {
    case .zshBash: commands.zshBash
    case .fish: commands.fish
    case .nushell: commands.nushell
    case .windowsCMD: commands.windowsCMD
    case .windowsPowerShell: commands.windowsPowerShell
    }
  }
}

/// 活动目标安全事实：存在性 + 可展示路径摘要。身份是不透明
/// `NodeID`（级联勾选用）；不含凭据、原始配置 URL 或目录树结构。路径摘要
/// 是目录 projection 的显示名（导入缺名的服务器叶子以地址端口为名称，与目录树
/// 呈现一致），不额外携带配置细节。
struct ProxyActiveTargetFacts: Equatable, Sendable {
  let id: NodeID
  /// 根 → 叶显示名路径（" / " 连接）；目标已不在当前目录树中为 nil。
  let pathSummary: String?
}

/// 代理控制的统一 UI-facing snapshot：一次 workflow
/// observation 产出的整体安全投影，所有字段来自同一时间点。agent 意图/运行
/// 状态与系统代理意图/实际应用是四个独立事实，两个开关互不代替；不含控制
/// 器内部状态枚举、`ProxyRuntimeSettings`、完整目录树、凭据、原始 URL、原始日志或
/// 本地化文案；失败保持 typed facts，成句呈现由 App presentation edge 负责。
struct ProxyControlSnapshot: Equatable, Sendable {
  /// Agent 运行事实：状态类别、「在跑」投影与 typed 失败。
  let runtime: ProxyRuntimeFacts
  /// Agent 开关意图（持久化；默认开启）。
  let agentIntentEnabled: Bool
  /// 最近一次激活拒绝或目标清除的点名原因（独立于运行状态；agent 可能仍在
  /// 监听）。
  let activationFailure: ActivationFailure?
  /// 系统代理开关意图（持久化；默认关闭）。
  let systemProxyIntentEnabled: Bool
  /// 系统代理实际应用状态（与 agent 运行状态分开呈现）。
  let systemProxyApplication: SystemProxyApplicationFacts
  /// Helper approval blockage, including failed cleanup after intent is off.
  let systemProxyApprovalRequired: Bool
  var systemProxyInspection = SystemProxyInspectionFacts()
  /// 当前已应用的代理模式（持久化成功的模式）。
  let proxyMode: ProxyMode
  /// 规则模式子选项：未匹配默认动作；仅规则模式呈现。
  let ruleDefaultAction: RuleDefaultAction
  /// 可用模式由 Domain 单点策略投影；UI 不自行判断可用性。
  let availableModes: [ProxyMode]
  /// 活动目标事实；无活动目标为 nil。
  let activeTarget: ProxyActiveTargetFacts?
  /// 最近一次激活预检或目录收敛跳过的无效服务器数量。
  let skippedInvalidServerCount: Int
  /// HTTP 导出能力。
  let httpExport: HTTPExportCapability
  /// 首页命令地址选择器：可见性、候选与生效选择。
  let commandAddressPicker: TerminalCommandAddressPicker
  /// 首页终端代理环境变量命令；端点地址为生效
  /// 命令地址选择，端口取已保存监听事实。
  let terminalProxyEnvironmentCommands: TerminalProxyEnvironmentCommands

  /// Windows 格式供其他设备使用，只在局域网入口与网络地址都有效时提供。
  var terminalCommandShells: [TerminalCommandShell] {
    commandAddressPicker.isVisible && commandAddressPicker.selected.address != "127.0.0.1"
      ? TerminalCommandShell.allCases : [.zshBash, .fish, .nushell]
  }
}

// MARK: - 适配缝

/// 生产运行时适配缝：包装现有 `ProxyRuntimeController` 的
/// 能力与观察。不复制状态机、generation 与健康门禁；意图持久化先行、失败
/// 清理与系统代理生命周期语义全部留在控制器；测试注入确定性 fake。
@MainActor
protocol ProxyRuntimeAdapting: AnyObject {
  /// Agent 运行事实（状态类别 + 「在跑」投影 + typed 失败）。
  var runtimeFacts: ProxyRuntimeFacts { get }
  /// Agent 开关意图。
  var agentIntentEnabled: Bool { get }
  /// 最近一次激活拒绝/目标清除的点名原因。
  var activationFailure: ActivationFailure? { get }
  /// 系统代理开关意图。
  var systemProxyIntentEnabled: Bool { get }
  /// 系统代理实际应用状态。
  var systemProxyApplication: SystemProxyApplicationFacts { get }
  /// 特权 helper 是否等待登录项批准。
  var systemProxyApprovalRequired: Bool { get }
  var systemProxyInspection: SystemProxyInspectionFacts { get }
  /// 当前已应用的代理模式。
  var proxyMode: ProxyMode { get }
  /// 规则模式子选项。
  var ruleDefaultAction: RuleDefaultAction { get }
  /// 最近一次激活预检或目录收敛跳过的无效服务器数量。
  var skippedInvalidServerCount: Int { get }
  /// 当前活动目标身份；无目标为 nil（目录侧目标事实的唯一输入）。
  var activeTargetID: NodeID? { get }
  /// 可安全复制的 HTTP 导出能力。
  var httpExportCapability: HTTPExportCapability { get }
  /// 已保存监听事实：命令地址候选过滤与命令生成的数据来源。
  var listenFacts: RuntimeListenFacts { get }
  func terminalLANPassword() throws -> String
  /// 运行时事实变化通知：目录驱动、设置变更或运行时收敛导致事实变化后
  /// 发值。生产实现合并控制器与观察机的 didChange 事实通道（同一主队列轮
  /// 多次写合并为一次）；fake 同步发值。workflow 以此触发整体重观察。
  var changes: AnyPublisher<Void, Never> { get }

  /// 启动重同步（GUI 重启后的注册态重校验）。
  func resyncOnLaunch() async
  /// Agent 开关命令。
  func setAgentEnabled(_ enabled: Bool) async
  /// 系统代理开关命令。
  func setSystemProxyEnabled(_ enabled: Bool) async
  /// 打开 helper 的登录项批准路径。
  func openSystemProxyHelperApproval() async
  func repairSystemProxy() async
  func retrySystemProxyClear() async
  func recheckSystemProxy() async
  func setProxyMode(_ mode: ProxyMode) async
  /// 规则模式子选项命令。
  func setRuleDefaultAction(_ action: RuleDefaultAction) async
}

/// 窄的目录目标事实缝：目录侧只向代理控制提供活动
/// 目标的存在性与安全路径摘要；完整目录树、订阅对象与凭据不出此接口。
@MainActor
protocol ProxyTargetFactsReading: AnyObject {
  /// 活动目标安全事实：无活动目标为 nil；目标不在当前目录树中时摘要为 nil。
  func activeTargetFacts(for targetID: NodeID?) -> ProxyActiveTargetFacts?
}

// MARK: - Workflow

/// 代理控制工作流 module：状态菜单与主窗口共用的唯一
/// UI-facing 代理控制 seam。围绕现有 `ProxyRuntimeController` 建立稳定
/// typed interface：整体发布的 `ProxyControlSnapshot` 与 typed async
/// commands；命令完成后重新发布完整 snapshot，预期运行时失败以
/// `RuntimeFailureFacts` 进入 snapshot。不拆分控制器，也不持有第二套运行时
/// 状态机；活动目标树、目标激活与订阅刷新仍由 CatalogWorkflow 负责，安全
/// 诊断与导出仍由 DiagnosticsWorkflow 负责。
@MainActor
final class ProxyControlWorkflow: ObservableObject {
  /// 最新整体 snapshot（唯一读取面；每次观察整体替换）。
  @Published private(set) var snapshot: ProxyControlSnapshot

  private let runtime: any ProxyRuntimeAdapting
  private let targetFacts: any ProxyTargetFactsReading
  private let interfaceFacts: any LocalInterfaceFactsReading
  /// 会话内命令地址选择：生命周期长于首页视图，不持久化；
  /// 每次观察与最新候选对账，失效即回退默认回环。
  private var commandAddressSelection: TerminalCommandAddressIdentity?
  private var cancellables: Set<AnyCancellable> = []

  init(
    runtime: any ProxyRuntimeAdapting,
    targetFacts: any ProxyTargetFactsReading,
    interfaceFacts: any LocalInterfaceFactsReading
  ) {
    self.runtime = runtime
    self.targetFacts = targetFacts
    self.interfaceFacts = interfaceFacts
    let observation = Self.makeSnapshot(
      runtime: runtime, targetFacts: targetFacts, interfaceFacts: interfaceFacts,
      selection: nil)
    commandAddressSelection = observation.selection
    snapshot = observation.snapshot
    runtime.changes
      .sink { [weak self] _ in self?.republish() }
      .store(in: &cancellables)
    interfaceFacts.changes
      .sink { [weak self] _ in self?.republish() }
      .store(in: &cancellables)
  }

  // MARK: - 观察与命令

  /// 启动观察：GUI 重启后的注册态重校验 + 整体重发布（组合根在启动时调用）。
  func resyncOnLaunch() async {
    await runtime.resyncOnLaunch()
    republish()
  }

  /// Agent 开关：命令完成后返回并发布完整新 snapshot。
  @discardableResult
  func setAgentEnabled(_ enabled: Bool) async -> ProxyControlSnapshot {
    await runtime.setAgentEnabled(enabled)
    return republish()
  }

  /// 系统代理开关：命令完成后返回并发布完整新 snapshot。
  @discardableResult
  func setSystemProxyEnabled(_ enabled: Bool) async -> ProxyControlSnapshot {
    await runtime.setSystemProxyEnabled(enabled)
    return republish()
  }

  /// 打开 helper 批准路径并重试收敛；完成后整体重发布。
  @discardableResult
  func openSystemProxyHelperApproval() async -> ProxyControlSnapshot {
    await runtime.openSystemProxyHelperApproval()
    return republish()
  }

  @discardableResult
  func repairSystemProxy() async -> ProxyControlSnapshot {
    await runtime.repairSystemProxy()
    return republish()
  }

  @discardableResult
  func retrySystemProxyClear() async -> ProxyControlSnapshot {
    await runtime.retrySystemProxyClear()
    return republish()
  }

  @discardableResult
  func recheckSystemProxy() async -> ProxyControlSnapshot {
    await runtime.recheckSystemProxy()
    return republish()
  }

  /// 切换代理模式：no-op 语义由控制器既有入口裁定；
  /// 完成后整体重发布。持久化失败保留旧模式，失败以 typed fact 呈现。
  @discardableResult
  func setProxyMode(_ mode: ProxyMode) async -> ProxyControlSnapshot {
    await runtime.setProxyMode(mode)
    return republish()
  }

  /// 切换规则模式子选项：完成后整体重发布。
  @discardableResult
  func setRuleDefaultAction(_ action: RuleDefaultAction) async -> ProxyControlSnapshot {
    await runtime.setRuleDefaultAction(action)
    return republish()
  }

  // MARK: - 首页命令地址

  /// 下拉框选址：仅记录会话内选择并整体重发布；不触碰代理运行状态、监听
  /// 设置与系统代理。
  @discardableResult
  func selectCommandAddress(_ address: TerminalCommandAddress) -> ProxyControlSnapshot {
    commandAddressSelection = address.identity
    return republish()
  }

  /// 刷新命令地址候选并整体重发布（进入首页与复制前调用；网络变化经接口
  /// 事实变化通知自动刷新）。失效选择回退到本地地址。
  @discardableResult
  func refreshTerminalCommands() -> TerminalProxyEnvironmentCommands {
    republish().terminalProxyEnvironmentCommands
  }

  /// 复制前核实按钮呈现时的 IP 仍有效；回退只更新界面，不改写剪贴板。
  /// 显式传入原地址身份，防止网络通知先回退 snapshot 后复制旧按钮。
  func prepareTerminalCommandsForCopy(expectedAddress: TerminalCommandAddressIdentity) throws
    -> TerminalProxyEnvironmentCommands
  {
    let commands = refreshTerminalCommands()
    guard snapshot.commandAddressPicker.selected.identity == expectedAddress else {
      throw TerminalCommandFailure.addressUnavailable
    }
    if let failure = commands.failure { throw failure }
    return commands
  }

  // MARK: - 整体观察（implementation，UI 不可见）

  /// 一次 observation 内整体拼装 snapshot；任何单一事实变化后整体替换，
  /// 不暴露「新模式配旧状态」的混合结果。命令地址选择在观察内与最新候选
  /// 对账，回退结果同步回会话状态（失效选择不随网络恢复复活）。
  @discardableResult
  private func republish() -> ProxyControlSnapshot {
    let observation = Self.makeSnapshot(
      runtime: runtime, targetFacts: targetFacts, interfaceFacts: interfaceFacts,
      selection: commandAddressSelection)
    commandAddressSelection = observation.selection
    snapshot = observation.snapshot
    return snapshot
  }

  /// 一次 observation：整体拼装 snapshot 并对账命令地址选择，返回生效选择
  /// （失效选择已回退到当前监听方式的默认回环地址）。
  private static func makeSnapshot(
    runtime: any ProxyRuntimeAdapting,
    targetFacts: any ProxyTargetFactsReading,
    interfaceFacts: any LocalInterfaceFactsReading,
    selection: TerminalCommandAddressIdentity?
  ) -> (snapshot: ProxyControlSnapshot, selection: TerminalCommandAddressIdentity) {
    let listenFacts = runtime.listenFacts
    let picker = TerminalCommandAddressPolicy.picker(
      mode: listenFacts.lan.effectiveMode,
      interfaces: interfaceFacts.interfaces,
      selection: selection)
    return (
      ProxyControlSnapshot(
        runtime: runtime.runtimeFacts,
        agentIntentEnabled: runtime.agentIntentEnabled,
        activationFailure: runtime.activationFailure,
        systemProxyIntentEnabled: runtime.systemProxyIntentEnabled,
        systemProxyApplication: runtime.systemProxyApplication,
        systemProxyApprovalRequired: runtime.systemProxyApprovalRequired,
        systemProxyInspection: runtime.systemProxyInspection,
        proxyMode: runtime.proxyMode,
        ruleDefaultAction: runtime.ruleDefaultAction,
        availableModes: ProxyMode.availableModes,
        activeTarget: targetFacts.activeTargetFacts(for: runtime.activeTargetID),
        skippedInvalidServerCount: runtime.skippedInvalidServerCount,
        httpExport: runtime.httpExportCapability,
        commandAddressPicker: picker,
        terminalProxyEnvironmentCommands: TerminalProxyEnvironmentCommands(
          listen: listenFacts, commandAddress: picker.selected,
          password: { try runtime.terminalLANPassword() })),
      picker.selected.identity
    )
  }
}

// 未提供凭据读取能力的 adapter 必须拒绝认证命令，不能复制无密码的替代值。
extension ProxyRuntimeAdapting {
  func terminalLANPassword() throws -> String { throw TerminalCommandFailure.credentialUnreadable }
}
