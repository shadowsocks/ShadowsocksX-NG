import AppKit
import SwiftUI

@main
struct ShadowsocksXNG2App: App {
  /// 进程期强持有（组合根装配一次）。body 不读它：事实发布经各 workflow 的
  /// didChange 通道，不借 @StateObject 订阅控制器变化。
  @NSApplicationDelegateAdaptor(ConnectivityApplicationDelegate.self) private var appDelegate
  private let connectivityLifecycle: ConnectivityLifecycle
  private let proxyController: ProxyRuntimeController
  /// 状态显示 debounce 模型：进程期强持有（与首页/菜单栏两个表面共享同一
  /// 门控状态机），body 不读它。
  private let statusDisplay: StatusDisplayModel
  @StateObject private var catalogWorkflow: CatalogWorkflow
  @StateObject private var proxyControl: ProxyControlWorkflow
  @StateObject private var loginController: LaunchAtLoginController
  @StateObject private var settingsWorkflow: SettingsWorkflow
  @StateObject private var diagnosticsWorkflow: DiagnosticsWorkflow
  @StateObject private var workspaceRoute: WorkspaceRoute
  @StateObject private var silentLaunch: SilentLaunchController
  @StateObject private var rulesWorkflow: RulesWorkspaces
  @StateObject private var windowActivation: WindowActivationPolicyCoordinator
  private let textClipboard: any TextClipboard
  private let diagnosticReportExporter: any DiagnosticReportExporter
  @StateObject private var diagnosticsWindow = DiagnosticsWindowState()
  private let workspaceContent: MainWindowView
  /// 窗口工具栏标签风格默认「图标和文本」。绑定版修饰符让用户仍可经工具栏
  /// 右键改选，选择回写本 AppStorage 键持久化，下次启动延续。
  @AppStorage("toolbarLabelStyle") private var toolbarLabelStyle: ToolbarLabelStyle = .titleAndIcon
  /// 启动呈现行为在进程内一次性定格（ADR 0017）：静默启动偏好关闭（默认）
  /// 时 presented，开启时 suppressed。切换偏好当次会话无影响，下次启动生效。
  private let launchPresentation: SceneLaunchBehavior

  init() {
    let composition = AppComposition.make()
    connectivityLifecycle = composition.connectivityLifecycle
    proxyController = composition.controller
    statusDisplay = composition.statusDisplay
    _catalogWorkflow = StateObject(wrappedValue: composition.catalogWorkflow)
    _proxyControl = StateObject(wrappedValue: composition.proxyControl)
    _loginController = StateObject(wrappedValue: composition.loginController)
    _settingsWorkflow = StateObject(wrappedValue: composition.settingsWorkflow)
    _diagnosticsWorkflow = StateObject(wrappedValue: composition.diagnosticsWorkflow)
    _workspaceRoute = StateObject(wrappedValue: composition.workspaceRoute)
    _silentLaunch = StateObject(wrappedValue: composition.silentLaunch)
    _rulesWorkflow = StateObject(wrappedValue: composition.rulesWorkflow)
    _windowActivation = StateObject(
      wrappedValue: WindowActivationPolicyCoordinator(applying: NSAppWindowActivationApplier()))
    textClipboard = composition.textClipboard
    diagnosticReportExporter = composition.diagnosticReportExporter
    workspaceContent = composition.workspaceContent
    launchPresentation = composition.silentLaunch.isEnabled ? .suppressed : .presented
    // GUI 事件接入内存环形缓冲：独立诊断窗口日志查看器与
    // 诊断导出的来源；wrapper 侧不注册，仍走 stderr → agent.log 收敛。
    RuntimeLog.setSink(RuntimeEventStore.shared)
    appDelegate.lifecycle = connectivityLifecycle
    appDelegate.catalogWorkflow = composition.catalogWorkflow
  }

  var body: some Scene {
    MenuBarExtra {
      ProxyStatusMenu(
        control: proxyControl, statusDisplay: statusDisplay)
    } label: {
      StatusMenuLabel(control: proxyControl, statusDisplay: statusDisplay)
    }
    //    .menuBarExtraStyle(.window)

    // 主 workspace 窗口（ADR 0016/0017）：SwiftUI `Window` scene。启动呈现由
    // defaultLaunchBehavior 决定：静默启动关闭（默认）时 presented 启动即呈现
    // （scene 方式启动开窗，LSUIElement 下实测生效），开启时 suppressed 直接
    // 进菜单栏形态。窗口开着期间 app 为 regular（Dock 图标/Cmd-Tab/默认菜单
    // 栏），最后一个窗口关闭回 accessory 菜单栏形态——随窗激活策略由窗口 NSWindow 生命
    // 周期通知驱动（WindowActivationPolicy，scenePhase 在 macOS 跟随应用而非
    // 窗口、关窗无事件，实测不可用）；关窗后由状态菜单首项（打开主窗口）经
    // openWindow 重开。
    // 关窗不退进程（MenuBarExtra 持进程）。
    Window("ShadowsocksX-NG2", id: WorkspaceRoute.workspaceSceneID) {
      workspaceContent
        .modifier(WindowActivationPolicy(coordinator: windowActivation))
    }
    .commands {
      AboutCommands()
      DiagnosticsCommands()
    }
    .defaultLaunchBehavior(launchPresentation)
    .defaultSize(width: 960, height: 640)
    .windowToolbarLabelStyle($toolbarLabelStyle)

    rulesReportScene
    diagnosticsScene
    AboutScenes(windowActivation: windowActivation)
  }

  private var diagnosticsScene: some Scene {
    Window("诊断", id: DiagnosticsWindowState.sceneID) {
      DiagnosticsView(
        diagnostics: diagnosticsWorkflow,
        windowState: diagnosticsWindow,
        clipboard: textClipboard,
        exporter: diagnosticReportExporter
      )
      .modifier(WindowActivationPolicy(coordinator: windowActivation))
    }
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)
    .commandsRemoved()
    .defaultSize(width: 1200, height: 600)
    .windowToolbarLabelStyle($toolbarLabelStyle)
  }

  private var rulesReportScene: some Scene {
    Window(RulesCopy.text("快照制作时的转换报告"), id: RulesReportView.sceneID) {
      RulesReportView(workflow: rulesWorkflow)
        .modifier(WindowActivationPolicy(coordinator: windowActivation))
    }
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)
    .commandsRemoved()
    .defaultSize(width: 680, height: 480)
    .windowToolbarLabelStyle($toolbarLabelStyle)
  }
}

/// 随窗激活策略与激活重试的真实 NSApp 落点。
@MainActor
private final class NSAppWindowActivationApplier: WindowActivationPolicyApplying {
  func apply(_ policy: NSApplication.ActivationPolicy) {
    guard NSApp.activationPolicy() != policy else { return }
    NSApp.setActivationPolicy(policy)
    if policy == .regular {
      // Window scene 会呈现窗口，但 LSUIElement 进程仍需显式激活才能置前。
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  var isAppActive: Bool { NSApp.isActive }

  var ownsMenuBar: Bool {
    NSWorkspace.shared.menuBarOwningApplication?.bundleIdentifier
      == Bundle.main.bundleIdentifier
  }

  var isPolicyRegular: Bool { NSApp.activationPolicy() == .regular }

  func activateApp() {
    NSApp.activate(ignoringOtherApps: true)
  }
}

/// 组合根装配：目录提交协调器与全部生产运行时适配器只在此接线一次，各 scene
/// 不再重复设置提交回调；目录工作流的实现依赖经 CatalogWorkflowDependencies
/// 显式装配（workflow 不自行创建生产默认实现）；Legacy 导入后的 2.0 运行时
/// 边界同为一次性注入。主窗口是 SwiftUI `Window` scene（MainApp body 声明），
/// 内容视图在组合根构造一次；MainWindowView 值廉价且只捕获工作流对象，其
/// StateObject 状态与 onAppear 副作用在窗口首次打开时才发生。
@MainActor
private struct AppComposition {
  let connectivityLifecycle: ConnectivityLifecycle
  let controller: ProxyRuntimeController
  let catalogWorkflow: CatalogWorkflow
  let proxyControl: ProxyControlWorkflow
  let statusDisplay: StatusDisplayModel
  let loginController: LaunchAtLoginController
  let settingsWorkflow: SettingsWorkflow
  let diagnosticsWorkflow: DiagnosticsWorkflow
  let workspaceRoute: WorkspaceRoute
  let silentLaunch: SilentLaunchController
  let expansion: CatalogExpansionState
  let textClipboard: any TextClipboard
  let diagnosticReportExporter: any DiagnosticReportExporter
  let imageClipboard: any ImageClipboard
  let rulesWorkflow: RulesWorkspaces
  let workspaceContent: MainWindowView

  static func make() -> AppComposition {
    let dependencies = ApplicationDependencies.make()
    let textClipboard = dependencies.textClipboard
    // The catalog document is read exactly once at startup. The coordinator
    // publishes later committed snapshots; the controller receives read-only
    // access to this same in-process source.
    let catalogBootstrap = CatalogCommitCoordinator.bootstrap(
      fileStore: dependencies.catalogFileStore)
    let plugins = PluginCatalog()
    let controller = makeRuntimeController(
      dependencies: dependencies, bootstrap: catalogBootstrap, plugins: plugins)
    let loginController = LaunchAtLoginController(service: dependencies.loginService)
    let catalogWorkflow = makeCatalogWorkflow(
      dependencies: dependencies,
      controller: controller,
      bootstrap: catalogBootstrap, plugins: plugins)
    connectPluginCatalog(plugins, controller: controller, workflow: catalogWorkflow)
    // 代理控制工作流 module：状态菜单等 UI 表面的唯一代理控制
    // seam，组合根接线一次。生产 runtime adapter 包装既有控制器（不复制运行
    // 时语义）；目录目标事实经窄缝从目录工作流读取；本机接口事实经独立缝
    // 提供命令地址候选。
    let proxyControl = ProxyControlWorkflow(
      runtime: ControllerProxyRuntimeAdapter(controller: controller),
      targetFacts: catalogWorkflow,
      interfaceFacts: SystemInterfaceFactsProvider())
    // 状态显示 debounce 模型：订阅代理控制工作流 snapshot，组合根接线一次，
    // 首页运行控制卡与菜单栏状态卡共享同一门控状态机。
    let statusDisplay = StatusDisplayModel(control: proxyControl)
    // 设置工作流 module（Candidate 02）：设置窗口的唯一 seam，组合根接线一次；
    // 写入侧经窄缝 SettingsCommitting，运行时控制器薄扩展即生产实现。
    let settingsWorkflow = SettingsWorkflow(
      committing: controller)
    let (connectivity, connectivityLifecycle) = makeConnectivity(
      workflow: catalogWorkflow, settings: settingsWorkflow)
    catalogWorkflow.connectivity = connectivity
    let diagnosticsWorkflow = makeDiagnosticsWorkflow(
      controller: controller, workflow: catalogWorkflow, plugins: plugins)
    let workspace = makeWorkspace(
      WorkspaceCompositionContext(
        dependencies: dependencies, controller: controller, workflow: catalogWorkflow,
        control: proxyControl, statusDisplay: statusDisplay, plugins: plugins,
        settings: settingsWorkflow,
        login: loginController, clipboard: textClipboard))
    return AppComposition(
      connectivityLifecycle: connectivityLifecycle,
      controller: controller,
      catalogWorkflow: catalogWorkflow,
      proxyControl: proxyControl,
      statusDisplay: statusDisplay,
      loginController: loginController,
      settingsWorkflow: settingsWorkflow,
      diagnosticsWorkflow: diagnosticsWorkflow,
      workspaceRoute: workspace.route,
      silentLaunch: workspace.silentLaunch,
      expansion: workspace.expansion,
      textClipboard: textClipboard,
      diagnosticReportExporter: dependencies.diagnosticReportExporter,
      imageClipboard: dependencies.imageClipboard,
      rulesWorkflow: workspace.rulesWorkflow,
      workspaceContent: workspace.content)
  }

  private static func connectPluginCatalog(
    _ plugins: PluginCatalog, controller: ProxyRuntimeController, workflow: CatalogWorkflow
  ) {
    plugins.connect(
      invalidateRuntime: { [weak controller] in controller?.pluginMappingsDidPublish() },
      revalidate: { [weak workflow] in workflow?.republishCommittedState() },
      converge: { [weak controller] in
        guard let controller else { return }
        _ = await controller.catalogDidCommit(
          snapshot: controller.catalogSnapshotReader.catalogSnapshot)
      })
  }

  private static func makeConnectivity(
    workflow: CatalogWorkflow, settings: SettingsWorkflow
  ) -> (module: ServerConnectivity, lifecycle: ConnectivityLifecycle) {
    let testRuntime = ConnectivityRuntime(
      executable: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/sslocal"))
    let connectivity = ServerConnectivity(
      configuration: { [weak workflow] id in
        guard let workflow else { throw ServerFormLoadError.notFound }
        return try workflow.connectivityConfiguration(for: id)
      },
      revision: { [weak workflow] in workflow?.connectivityRevision(for: $0) ?? "missing" },
      measure: testRuntime.measure)
    connectivity.setURL(ServerConnectivity.validURL(settings.beginConnectivityURLEditing()))
    settings.connectivityURLDidChange = { [weak connectivity] in connectivity?.setURL($0) }
    return (connectivity, ConnectivityLifecycle(module: connectivity))
  }

  private static func makeDiagnosticsWorkflow(
    controller: ProxyRuntimeController, workflow: CatalogWorkflow, plugins: PluginCatalog
  ) -> DiagnosticsWorkflow {
    DiagnosticsWorkflow(
      runtimeFacts: controller,
      catalogFacts: { workflow.diagnosticCatalogFacts },
      managedPlugins: {
        plugins.catalogSnapshot().entries.map { entry in
          DiagnosticPluginFacts(
            program: entry.program, version: entry.managedInfo?.dependency?.version ?? "",
            present: entry.availability == .available, source: entry.source)
        }
      })
  }

  private static func makeWorkspace(_ context: WorkspaceCompositionContext) -> WorkspaceComposition
  {
    let route = WorkspaceRoute()
    let silentLaunch = SilentLaunchController(store: context.dependencies.silentLaunchStore)
    let expansion = CatalogExpansionState()
    let rulesWorkflow = RulesWorkspaces { preset in
      RulesWorkflow(
        preset: preset,
        loadDocument: { try context.controller.documents(for: preset).load() },
        commitDocument: { await context.controller.commitRuleDocument($0, preset: preset) },
        builtinSnapshots: context.controller.ruleSnapshots)
    }
    let content = MainWindowView(
      rulesWorkflow: rulesWorkflow,
      route: route,
      workflow: context.workflow,
      control: context.control,
      statusDisplay: context.statusDisplay,
      plugins: PluginManagementModel(catalog: context.plugins),
      settingsWorkflow: context.settings,
      loginController: context.login,
      silentLaunch: silentLaunch,
      expansion: expansion,
      clipboard: context.clipboard,
      imageClipboard: context.dependencies.imageClipboard,
      configurationGroupFileExporter: context.dependencies.configurationGroupFileExporter,
      qrImageSaver: context.dependencies.qrImageSaver)
    return WorkspaceComposition(
      route: route, silentLaunch: silentLaunch, expansion: expansion,
      rulesWorkflow: rulesWorkflow, content: content)
  }

  /// 运行时控制器接线：读侧接目录提交协调器快照，写侧接各持久化 seam 与
  /// 系统服务适配器。
  private static func makeRuntimeController(
    dependencies: ApplicationDependencies,
    bootstrap: CatalogCommitBootstrap,
    plugins: PluginCatalog
  ) -> ProxyRuntimeController {
    ProxyRuntimeController(
      catalogSnapshotReader: bootstrap.catalogSnapshotReader,
      activationFileStore: dependencies.activationFileStore,
      runtimeFileStore: dependencies.runtimeFileStore,
      plugins: plugins,
      refreshPluginSecurityFacts: { [weak plugins] in _ = plugins?.refreshSecurityFacts() },
      listeningStore: dependencies.listeningStore,
      settingsRestore: dependencies.settingsRestore,
      agent: dependencies.launchAgent,
      systemProxyNetworkChangeMonitor: SystemProxyNetworkChangeMonitor())
  }

  /// 目录工作流接线：提交协调器与生产运行时适配器在此
  /// 一次性装配；Legacy 导入后的 2.0 运行时边界同为一次性注入。
  private static func makeCatalogWorkflow(
    dependencies: ApplicationDependencies,
    controller: ProxyRuntimeController,
    bootstrap: CatalogCommitBootstrap,
    plugins: PluginCatalog
  ) -> CatalogWorkflow {
    let coordinator = CatalogCommitCoordinator(
      fileStore: dependencies.catalogFileStore,
      runtime: ProxyRuntimeSyncAdapter(controller: controller),
      bootstrap: bootstrap)
    return CatalogWorkflow(
      dependencies: CatalogWorkflowDependencies(
        coordinator: coordinator,
        plugins: plugins,
        subscriptionFetcher: HTTPSSubscriptionFetcher(),
        legacyImportService: dependencies.legacyImportService,
        postLegacyImport: { _ in
          await controller.legacyImportDidCommit()
        },
        activator: controller))
  }
}

private struct WorkspaceCompositionContext {
  let dependencies: ApplicationDependencies
  let controller: ProxyRuntimeController
  let workflow: CatalogWorkflow
  let control: ProxyControlWorkflow
  let statusDisplay: StatusDisplayModel
  let plugins: PluginCatalog
  let settings: SettingsWorkflow
  let login: LaunchAtLoginController
  let clipboard: any TextClipboard
}

private struct WorkspaceComposition {
  let route: WorkspaceRoute
  let silentLaunch: SilentLaunchController
  let expansion: CatalogExpansionState
  let rulesWorkflow: RulesWorkspaces
  let content: MainWindowView
}
