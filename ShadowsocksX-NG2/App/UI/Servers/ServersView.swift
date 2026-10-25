import SwiftUI

/// 服务器目录、只读详情与分组命令；本视图持有新建／编辑 sheet 和确认弹窗。
/// selection 由主窗口绑定，订阅删除可清除失效选择。
struct ServersView: View {

  @ObservedObject var workflow: CatalogWorkflow
  /// 激活反馈共享状态（三激活入口共用，单飞互斥）：侧栏右键与分组详情的
  /// 激活命令都经它发出。
  let activation: ActivationFeedbackState
  /// 活动目标标记：父视图传入的运行时事实，不进目录 projection（与
  /// ServerTableNameCell/ServerDetailView 的传参先例同法）。
  let activeTargetID: NodeID?
  @Binding var selection: NodeID?
  @Binding var section: ServerListSection
  /// 服务器管理的展开状态跨工作区页面切换保留，不落盘。
  @ObservedObject var expansion: CatalogExpansionState
  let clipboard: any TextClipboard
  let imageClipboard: any ImageClipboard
  let configurationGroupFileExporter: any ConfigurationGroupFileExporter
  let qrImageSaver: any QrImageSaver

  /// 共享错误弹窗呈现（UI 持有；typed error → 本地化文案的呈现边缘）。
  /// 非 private：ServersView+Share.swift 扩展经它呈现分享失败。
  @StateObject var errors = ErrorAlertPresenter()

  /// 子树含活动目标的分组集合（空心闪电候选）；表格与详情共用一次推导。
  var activeAncestorIDs: Set<NodeID> {
    workflow.tree.ancestors(of: activeTargetID)
  }

  // 纯窗口状态：selection/sheet/alert 不进目录 module。
  @State var renameTarget: NodeID?
  @State var newGroupParent: NodeID?
  @State var isPresentingNewGroup = false
  @State var isPresentingAddSubscription = false
  @State var serverFormOperation: ServerFormSheet.Operation?
  @State var subscriptionEditTarget: SubscriptionSummary?
  @State var deleteTarget: DeleteTarget?
  @State var dropState = ServerTableDropState()
  @State private var detailMinimumWidth: CGFloat = NodeDetailMinimumWidth.defaultValue
  @FocusState var isServerTableFocused: Bool
  // 分享 popover 打开时冻结载荷、顶部资料与建议文件名。
  @State var shareContext: ShareContext?

  var body: some View {
    HSplitView {
      sourceSidebar
        .frame(minWidth: 120, idealWidth: 150, maxWidth: 200)
      // 保持分栏容器身份稳定，切换来源时只替换内部表格。
      ZStack(alignment: .topLeading) {
        if section == .favorites {
          FavoriteServersTable(
            workflow: workflow, activeTargetID: activeTargetID,
            selection: $selection, errors: errors, contextMenu: nodeContextMenu)
        } else {
          serverTable
        }
      }
      .toolbar { toolbarContent }
      .frame(minWidth: 380, idealWidth: 520, maxWidth: .infinity)
      // 分栏身份必须稳定；节点身份只重建内部详情会话，保留用户拖动后的宽度。
      ZStack(alignment: .topLeading) {
        serverDetailPane
      }
      .frame(minWidth: detailMinimumWidth, maxWidth: .infinity, maxHeight: .infinity)
      .onPreferenceChange(NodeDetailMinimumWidth.self) {
        detailMinimumWidth = max(NodeDetailMinimumWidth.defaultValue, $0)
      }
    }
    .frame(minHeight: 420)
    .sheet(
      item: Binding(
        get: { renameTarget.map(NodeContext.init) },
        set: { renameTarget = $0?.nodeID })
    ) { context in
      RenameGroupSheet(workflow: workflow, errors: errors, nodeID: context.nodeID)
    }
    .sheet(isPresented: $isPresentingNewGroup) {
      NewGroupSheet(
        workflow: workflow, errors: errors, parent: newGroupParent,
        onCreated: selectCreatedNode)
    }
    .sheet(item: $subscriptionEditTarget) { summary in
      EditSubscriptionSheet(workflow: workflow, errors: errors, summary: summary)
    }
    .sheet(isPresented: $isPresentingAddSubscription) {
      AddSubscriptionSheet(workflow: workflow, errors: errors)
    }
    .presentingErrors(errors)
    .confirmationDialog(
      deleteTitle,
      isPresented: Binding(
        get: { deleteTarget != nil },
        set: { if !$0 { deleteTarget = nil } }),
      titleVisibility: .visible
    ) {
      Button(deleteConfirmationActionTitle, role: .destructive) { commitDelete() }
      Button("取消", role: .cancel) { deleteTarget = nil }
    } message: {
      Text(deleteMessage)
    }
    .sheet(item: $serverFormOperation) { operation in
      ServerFormSheet(
        workflow: workflow, operation: operation,
        onCreated: selectCreatedNode)
    }
    // 切换选中项时立即收起分享，避免显示旧服务器。
    .onChange(of: selection) {
      shareContext = nil
    }
    .onChange(of: workflow.favoriteIDs) {
      if section == .favorites, let selection, !workflow.isFavorite(selection) {
        self.selection = nil
      }
    }
    .onChange(of: workflow.tree) {
      if let selection, !workflow.tree.containsNode(selection) {
        self.selection = nil
      }
    }
  }

}

struct NodeContext: Identifiable {
  let nodeID: NodeID
  var id: NodeID { nodeID }
}

enum DeleteTarget {
  case node(NodeID)
  case subscription(SubscriptionSummary)
}
