import SwiftUI

/// 服务器导入面板：由窗口工具栏「导入服务器配置」按钮打开，窗口壳统一持有
/// 呈现；添加订阅表单由服务器分区自持（ServersView）。
private enum WorkspaceSheet: String, Identifiable {
  case importServers

  var id: String { rawValue }
}

/// 主窗口标签页外壳：WorkspaceRoute 持有导航位置；各分区持有页级动作。
/// 仅当前 destination 挂载内容，延续切页清理草稿与取消页面任务的生命周期；
/// 激活反馈仍由窗口壳持有，跨标签切换存续。
struct MainWindowView: View {
  /// 纯转发的分区工作流与控制器：壳 body 不读它们（分区视图自行观察），
  /// 用 let 转发，壳不重复订阅它们的发布。
  let rulesWorkflow: RulesWorkflow
  @ObservedObject var route: WorkspaceRoute
  @ObservedObject var workflow: CatalogWorkflow
  @ObservedObject var control: ProxyControlWorkflow
  /// 首页运行控制卡与菜单栏状态卡共享的状态显示 debounce 模型；壳 body
  /// 不读它（分区视图自行观察），用 let 转发。
  let statusDisplay: StatusDisplayModel
  let plugins: PluginManagementModel
  let settingsWorkflow: SettingsWorkflow
  let loginController: LaunchAtLoginController
  let silentLaunch: SilentLaunchController
  /// 目录树折叠状态：组合根持有的长寿命对象，跨 destination 切换存续；服务器
  /// 侧栏使用（见 CatalogExpansionState）。
  let expansion: CatalogExpansionState
  let clipboard: any TextClipboard
  let imageClipboard: any ImageClipboard
  let configurationGroupFileExporter: any ConfigurationGroupFileExporter
  let qrImageSaver: any QrImageSaver

  /// 激活反馈由首页、侧栏右键与分组详情共用。
  @StateObject private var activationFeedback = ActivationFeedbackState()
  @StateObject private var homeBrowser = HomeTargetBrowser()
  /// 系统标签选择先落在 SwiftUI 自管状态，再同步到 route，避免在视图
  /// 更新期间发布；外部导航反向同步，route 仍是导航位置的唯一来源。
  @State private var tabSelection: WorkspaceDestination = WorkspaceRoute.initialDestination
  @State private var selection: NodeID?
  @State private var serverSection: ServerListSection = .manual
  /// 全局导入面板由窗口壳持有。
  @State private var presentedWorkspaceSheet: WorkspaceSheet?

  var body: some View {
    TabView(selection: $tabSelection) {
      ForEach(WorkspaceDestination.allCases) { destination in
        Tab(destination.label, systemImage: destination.systemImage, value: destination) {
          if route.destination == destination {
            if let failure = workflow.libraryFailure,
              destination == .home || destination == .servers
            {
              ServerLibraryRecoveryView(workflow: workflow, failure: failure)
            } else {
              destinationView(destination)
            }
          }
        }
      }
    }
    .tabViewStyle(.automatic)
    .toolbar {
      ToolbarItem(placement: .navigation) {
        importButton
      }
    }
    .onChange(of: tabSelection) { _, destination in
      route.navigate(to: destination)
    }
    .onChange(of: route.destination, initial: true) { _, destination in
      if tabSelection != destination {
        tabSelection = destination
      }
    }
    .onChange(of: workflow.tree) {
      homeBrowser.reconcile(in: workflow.tree, favorites: workflow.favorites)
    }
    .onChange(of: workflow.favoriteIDs) {
      homeBrowser.reconcile(in: workflow.tree, favorites: workflow.favorites)
    }
    .onChange(of: selection) {
      guard let selection, let node = workflow.tree.node(withID: selection) else { return }
      guard serverSection != .favorites else { return }
      serverSection = ServerListSection(source: node.source)
      expansion.reveal(selection, in: workflow.tree)
    }
    .navigationTitle(route.destination.label)
    .frame(minWidth: 920, minHeight: 580)
    .sheet(item: $presentedWorkspaceSheet) { sheet in
      switch sheet {
      case .importServers:
        ImportServersSheet(
          workflow: workflow, clipboard: clipboard,
          selection: Binding(
            get: { selection },
            set: { id in
              if id != nil { serverSection = .manual }
              selection = id
            }),
          selectNewNodes: serverSection == .favorites)
      }
    }
  }

  // MARK: - 全局导入入口

  private var importButton: some View {
    Button {
      presentWorkspaceSheet(.importServers)
    } label: {
      Label("导入", systemImage: "square.and.arrow.down")
    }
    .help("导入")
    .disabled(workflow.libraryFailure != nil)
  }

  private func presentWorkspaceSheet(_ sheet: WorkspaceSheet) {
    route.navigate(to: .servers)
    presentedWorkspaceSheet = sheet
  }

  // MARK: - 分区承载

  @ViewBuilder
  private func destinationView(_ destination: WorkspaceDestination) -> some View {
    switch destination {
    case .home:
      WorkspaceHomeView(
        workflow: workflow,
        control: control,
        statusDisplay: statusDisplay,
        browser: homeBrowser,
        activation: activationFeedback,
        showServers: { route.navigate(to: .servers) },
        clipboard: clipboard)
    case .servers:
      ServersView(
        workflow: workflow,
        activation: activationFeedback,
        activeTargetID: control.snapshot.activeTarget?.id,
        selection: $selection,
        section: $serverSection,
        expansion: expansion,
        clipboard: clipboard,
        imageClipboard: imageClipboard,
        configurationGroupFileExporter: configurationGroupFileExporter,
        qrImageSaver: qrImageSaver)
    case .rules:
      RulesView(workflow: rulesWorkflow)
    case .settings:
      SettingsView(
        plugins: plugins, workflow: settingsWorkflow, loginController: loginController,
        silentLaunch: silentLaunch
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

extension WorkspaceDestination {
  var label: String {
    switch self {
    case .home: String(localized: "首页")
    case .servers: String(localized: "服务器")
    case .rules: RulesCopy.text("代理规则")
    case .settings: String(localized: "设置")
    }
  }

  var systemImage: String {
    switch self {
    case .home: "house"
    case .servers: "server.rack"
    case .rules: "list.bullet.rectangle"
    case .settings: "gearshape"
    }
  }
}

// MARK: - 首页 destination 包装壳

/// 首页 destination 的包装视图：承载共享错误弹窗挂载，行为
/// 委托给 HomeView。旧版导入的主动弹窗已移除（docs/design/unified-server-
/// import.md），发现状态仅供统一导入面板的 Legacy 入口显隐。
private struct WorkspaceHomeView: View {
  @ObservedObject var workflow: CatalogWorkflow
  @ObservedObject var control: ProxyControlWorkflow
  let statusDisplay: StatusDisplayModel
  let browser: HomeTargetBrowser
  let activation: ActivationFeedbackState
  let showServers: () -> Void
  let clipboard: any TextClipboard
  @StateObject private var errors = ErrorAlertPresenter()

  var body: some View {
    HomeView(
      workflow: workflow,
      control: control,
      statusDisplay: statusDisplay,
      browser: browser,
      activation: activation,
      showServers: showServers,
      clipboard: clipboard,
      errors: errors
    )
    .presentingErrors(errors)
  }
}
