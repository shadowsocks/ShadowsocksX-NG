import Foundation

/// 代理运行时的只读诊断事实缝：runtime 只以固定状态
/// 类别、活动目标存在性、监听事实与已脱敏契约摘要进入诊断 workflow；生产
/// 实现是 `ProxyRuntimeController` 的诊断只读面，测试注入替身。诊断 module
/// 不直接操作 runtime controller。
@MainActor
protocol ProxyRuntimeDiagnosticFacts: AnyObject {
  /// 固定代理状态类别（不透传任意错误 detail）。
  var proxyState: DiagnosticProxyState { get }
  var hasActiveTarget: Bool { get }
  /// 当前监听设置；监听地址在报告中只以回环/非回环两态呈现。
  var listen: SslocalListenSettings { get }
  /// 运行时契约的脱敏摘要（数量与模式）；契约缺失或无效为 nil。
  var contractSummary: String? { get }
  /// 自定义规则安全摘要：数量 + 内容版本，无原始域名。
  var customRuleSummary: CustomRuleSummary? { get }
}

/// 报告事件白名单（ADR-0006）：封闭的 RuntimeLogEvent
/// 不自动获得导出资格——诊断 module 以只读派生属性显式决定每个事件的报告
/// 呈现，自由错误 detail 与对外公布的主机地址一律清洗掉；数量、端口与领域
/// 点名原因可以进入。新增事件必须先在此补充决策（漏 case 无法编译），
/// 隐私承诺不因新增字段自动扩大。
extension RuntimeLogEvent {
  /// 事件在安全报告中的呈现文本；nil = 不进报告。
  var diagnosticReportLine: String? {
    switch self {
    case .connectivityMeasurement:
      return nil
    case .contractWritten(let serverCount):
      return "contract written (servers=\(serverCount))"
    case .contractUnchanged:
      return "contract unchanged, write skipped"
    case .systemProxyUnchanged:
      return "system proxy values unchanged, write skipped"
    case .systemProxyHelperRegisterFailed:
      return "system proxy helper register failed"
    case .systemProxyWriteFailed:
      return "system proxy write failed"
    case .runtimeFilesDeleted:
      return "runtime files deleted"
    case .runtimePersistFailed:
      return "runtime metadata persist failed"
    case .agentRegistered:
      return "launch agent registered"
    case .agentRegisterFailed:
      return "launch agent register failed"
    case .agentUnregistered:
      return "launch agent unregistered"
    case .agentUnregisterFailed:
      return "launch agent unregister failed"
    case .sslocalSpawned(let pid):
      return "sslocal spawned (pid=\(pid))"
    case .sslocalSpawnFailed:
      return "sslocal spawn failed"
    case .sslocalExitedUnexpectedly(let status):
      return "sslocal exited unexpectedly (status=\(status))"
    case .sslocalStopRequested:
      return "sslocal stop requested"
    case .listenNotEstablished:
      return "listen not established within deadline"
    case .contractMissing:
      return "contract missing"
    case .contractInvalidRemoved:
      return "contract invalid, removed"
    case .reloadForwarded:
      return "reload forwarded to sslocal"
    case .reloadDeferred:
      return "reload deferred until listeners are ready"
    case .reloadRestarted:
      return "reload: listen change, restarting sslocal"
    // 本机监听端点事实只保留端口：主机地址态的对外公布地址不进报告。
    case .endpointProbeFailed(_, let port, _):
      return "local endpoint not ready (port=\(port))"
    // 激活原因是领域的点名文案（短节点片段 + 固定文本，无秘密），与代理
    // 状态类别同源；任意运行时错误 detail 不在此列。
    case .activationFailed(let reason):
      return "activation failed: \(reason)"
    case .diagnosticsExported:
      return "diagnostics report exported (redacted)"
    case .listenSettingsUnreadable:
      return "listen settings unreadable, falling back to factory defaults"
    }
  }
}

/// 诊断侧栏与详情共用的安全摘要：同一份最新 projection。
struct DiagnosticSummary: Equatable, Sendable {
  var proxyState: DiagnosticProxyState
  var hasActiveTarget: Bool
}

/// 日志视图 projection（ADR-0006）：raw GUI 事件行与
/// raw wrapper `agent.log` 尾部只经显式查看/复制呈现，永不进入诊断报告。
struct DiagnosticLogView: Equatable, Sendable {
  var guiEventLines: [String] = []
  var agentLogTail: String?
}

/// 报告准备的结构化产物：UI 只负责把 data 写入用户选择的文件。
struct DiagnosticReportDraft: Equatable {
  let data: Data
  let suggestedFileName: String
}

enum DiagnosticReportFailure: Equatable, Error {
  /// 报告文本无法编码为 UTF-8（module 不产生本地化 UI 字符串）。
  case encodingFailed
}

/// 报告准备的 typed 结果：ready 携带可写入的草稿；safe projection 无法构造
/// 时返回 typed failure，不产生报告。
enum DiagnosticReportOutcome: Equatable {
  case ready(DiagnosticReportDraft)
  case failed(DiagnosticReportFailure)
}

/// 诊断工作流 module（Candidate 03）：诊断区的唯一 UI-facing
/// seam。内部组合 runtime 事实、目录聚合事实、GUI 事件源、agent.log 尾部、
/// 文件元数据、受管插件事实、时钟与纯报告 builder；内部事实源不暴露给 UI。
/// 向 UI 提供：侧栏/详情共用的安全摘要、raw 日志视图 projection、读取生命
/// 周期（代际守卫 + 取消）、报告准备（typed 结果）与导出完成登记。
///
/// 诊断收集是只读的：不启停代理、不写系统代理设置、不改目录与凭据。文件
/// 写入、保存面板、剪贴板与 alert 属于 UI；只有用户选择的报告文件实际写入
/// 成功后，UI 才调用 `noteExportCompleted` 登记既有的导出完成事件。
@MainActor
final class DiagnosticsWorkflow: ObservableObject {
  /// 侧栏摘要与详情共用的最新安全 projection。
  @Published private(set) var summary: DiagnosticSummary
  /// 日志视图 projection：读取期间持续更新。
  @Published private(set) var logView = DiagnosticLogView()

  private let runtimeFacts: any ProxyRuntimeDiagnosticFacts
  private let events: RuntimeEventStore
  private let catalogFacts: @MainActor () -> DiagnosticCatalogFacts?
  private let agentLogTail: () -> String?
  private let fileFacts: @MainActor () -> [DiagnosticFileFacts]
  private let managedPlugins: @MainActor () -> [DiagnosticPluginFacts]
  private let homePath: () -> String?
  private let clock: () -> Date
  private let reportRendering: (DiagnosticSnapshot) -> String?
  /// 轮询间隔（生产 1 秒；测试注入更细粒度）。
  private let pollInterval: Duration
  /// 读取代际：新一轮读取使旧一轮的在途结果作废。
  private var readGeneration = 0

  init(
    runtimeFacts: any ProxyRuntimeDiagnosticFacts,
    events: RuntimeEventStore = .shared,
    catalogFacts: @escaping @MainActor () -> DiagnosticCatalogFacts?,
    agentLogTail: @escaping () -> String? = {
      AgentLogTail.readLastLines(of: RuntimePaths.agentLogURL())
    },
    fileFacts: @escaping @MainActor () -> [DiagnosticFileFacts] =
      DiagnosticsWorkflow.productionFileFacts,
    managedPlugins: @escaping @MainActor () -> [DiagnosticPluginFacts] =
      DiagnosticsWorkflow.productionManagedPlugins,
    homePath: @escaping () -> String? = { NSHomeDirectory() },
    clock: @escaping () -> Date = { Date() },
    reportRendering: @escaping (DiagnosticSnapshot) -> String? = {
      DiagnosticReportBuilder.markdown(from: $0)
    },
    pollInterval: Duration = .seconds(1)
  ) {
    self.runtimeFacts = runtimeFacts
    self.events = events
    self.catalogFacts = catalogFacts
    self.agentLogTail = agentLogTail
    self.fileFacts = fileFacts
    self.managedPlugins = managedPlugins
    self.homePath = homePath
    self.clock = clock
    self.reportRendering = reportRendering
    self.pollInterval = pollInterval
    summary = DiagnosticSummary(
      proxyState: runtimeFacts.proxyState,
      hasActiveTarget: runtimeFacts.hasActiveTarget)
  }

  /// 诊断读取生命周期（UI 在诊断区出现时驱动）：循环轮询直到任务被取消；
  /// 每次进入递增代际，旧一轮的在途结果不再发布；
  /// 共享实例保证侧栏与详情不重复轮询。
  func readWhileActive() async {
    readGeneration += 1
    let generation = readGeneration
    while !Task.isCancelled, generation == readGeneration {
      refresh(generation: generation)
      try? await Task.sleep(for: pollInterval)
    }
  }

  /// 保存面板的建议文件名（UI 在打开面板前取用；时间戳来自注入时钟）。
  func suggestedReportFileName() -> String {
    "ShadowsocksX-NG2-诊断-\(fileStamp()).txt"
  }

  /// 准备脱敏诊断报告：只读采样各事实源（best-effort，单一来源缺失不阻止
  /// 其他事实），经纯 builder 渲染并编码为 UTF-8。safe projection 无法构造
  /// 时返回 typed failure，不生成报告。
  func prepareReport() -> DiagnosticReportOutcome {
    let text = reportRendering(makeSnapshot())
    guard let data = text?.data(using: .utf8) else {
      return .failed(.encodingFailed)
    }
    return .ready(DiagnosticReportDraft(data: data, suggestedFileName: suggestedReportFileName()))
  }

  /// 导出完成登记：只有用户选择的报告文件实际写入成功后由
  /// UI 调用；打开导出面板或准备报告文本不算导出。
  func noteExportCompleted() {
    RuntimeLog.emit(.diagnosticsExported)
  }

  // MARK: - 事实采样与渲染（implementation，UI 不可见）

  private func refresh(generation: Int) {
    summary = DiagnosticSummary(
      proxyState: runtimeFacts.proxyState,
      hasActiveTarget: runtimeFacts.hasActiveTarget)
    let lines = events.snapshot.map(\.renderedLine)
    let tail = agentLogTail()
    guard generation == readGeneration, !Task.isCancelled else { return }
    logView = DiagnosticLogView(guiEventLines: lines, agentLogTail: tail)
  }

  private func makeSnapshot() -> DiagnosticSnapshot {
    var snapshot = DiagnosticSnapshot()
    snapshot.generatedAt = clock()
    snapshot.appVersion = Self.appVersion()
    snapshot.systemSummary = Self.systemSummary()
    snapshot.proxyState = runtimeFacts.proxyState
    snapshot.hasActiveTarget = runtimeFacts.hasActiveTarget
    snapshot.listen = runtimeFacts.listen
    snapshot.runtimeDocumentSummary = runtimeFacts.contractSummary
    snapshot.customRuleSummary = runtimeFacts.customRuleSummary
    snapshot.catalogFacts = catalogFacts()
    snapshot.fileFacts = fileFacts()
    snapshot.managedPlugins = managedPlugins()
    snapshot.eventLines = Self.reportEventLines(from: events.snapshot)
    snapshot.homePathForRedaction = homePath()
    return snapshot
  }

  /// 报告侧事件行：白名单清洗后的文本复用原始行的时间戳格式（原始 detail
  /// 只留在日志视图 projection，ADR-0006）。
  static func reportEventLines(from entries: [RuntimeEventStore.Entry]) -> [String] {
    entries.suffix(reportEventLimit).compactMap { entry in
      entry.event.diagnosticReportLine.map { entry.renderedLine(eventText: $0) }
    }
  }

  private static let reportEventLimit = 200

  /// 受管插件清单：静态事实表 + 可执行文件存在性（生成配置时的同一检查；
  /// 参数与路径不入导出）。
  private static func productionManagedPlugins() -> [DiagnosticPluginFacts] {
    let provider = BundleManagedPluginProvider()
    return ManagedPluginCatalog.plugins.map { info in
      DiagnosticPluginFacts(
        program: info.program,
        version: info.release,
        present: provider.executablePath(forProgram: info.program) != nil)
    }
  }

  private static func productionFileFacts() -> [DiagnosticFileFacts] {
    [
      DiagnosticFileCollector.collect(label: "运行时目录", url: RuntimePaths.runtimeDirectory()),
      DiagnosticFileCollector.collect(
        label: "catalog.json", url: CatalogFileStore.defaultFileURL()),
      DiagnosticFileCollector.collect(
        label: "activation.json", url: ActivationStateFileStore.defaultFileURL()),
      DiagnosticFileCollector.collect(
        label: "sslocal-active.json", url: RuntimePaths.runtimeFileURL()),
      DiagnosticFileCollector.collect(label: "agent.pid", url: RuntimePaths.agentPIDFileURL()),
      DiagnosticFileCollector.collect(label: "agent.log", url: RuntimePaths.agentLogURL()),
    ]
  }

  private static func appVersion() -> String? {
    guard let info = Bundle.main.infoDictionary else { return nil }
    let parts = [
      (info["CFBundleShortVersionString"] as? String).map { "版本 \($0)" },
      (info["CFBundleVersion"] as? String).map { "构建 \($0)" },
    ].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: "，")
  }

  private static func systemSummary() -> String {
    let arch: String
    #if arch(arm64)
      arch = "arm64"
    #elseif arch(x86_64)
      arch = "x86_64"
    #else
      arch = "未知架构"
    #endif
    return "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)，\(arch)"
  }

  private func fileStamp() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: clock())
  }
}

// MARK: - 生产 runtime 事实适配

extension ProxyRuntimeController: ProxyRuntimeDiagnosticFacts {
  /// 控制器状态 → 诊断安全呈现：不透传任意错误 detail；监听地址只以
  /// 回环/非回环两态进入导出，原始错误文本一律丢弃）。系统代理写入失败与
  /// 激活拒绝优先于运行状态呈现（两个状态面分开后仍归入同一组
  /// 固定诊断类别）。
  var proxyState: DiagnosticProxyState {
    if systemProxyState.hasOperationFailure {
      return .systemProxyFailed
    }
    if let failure = lastActivationFailure {
      return .activationFailed(reason: AppPresentation.message(for: failure))
    }
    switch state {
    case .off:
      return .off
    case .starting:
      return .starting
    case .running:
      return .running
    case .firewallBlocked:
      return .firewallBlocked
    case .launchFailed:
      return .launchFailed
    case .requiresApproval:
      return .requiresApproval
    case .serviceFailed:
      return .serviceFailed
    }
  }

  var hasActiveTarget: Bool { isActiveTargetPresent }

  var listen: SslocalListenSettings { listenSettings }

  var contractSummary: String? { runtimeDocumentSummary() }

  var customRuleSummary: CustomRuleSummary? { readCustomRuleSummary() }
}
