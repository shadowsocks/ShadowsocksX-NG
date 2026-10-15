import SwiftUI

/// 装配当前节点的详情会话；查询、参数装载与命令均留在共用视图之外。
struct CatalogNodeDetailView: View {
  @Environment(\.locale) private var locale
  @Environment(\.timeZone) private var timeZone
  @ObservedObject var workflow: CatalogWorkflow
  @ObservedObject var activation: ActivationFeedbackState
  let nodeID: NodeID
  let isActiveTarget: Bool
  let errors: ErrorAlertPresenter
  @StateObject private var parameters = ServerDetailParameters()

  private var node: CatalogTreeNode? { workflow.tree.node(withID: nodeID) }
  private var eligibility: ActivationEligibility? { workflow.activationEligibility(for: nodeID) }

  var body: some View {
    if let node {
      let detail = presentation(for: node)
      NodeDetailView(detail: detail) {
        Button(
          activation.pendingTargetID == nodeID
            ? String(localized: "激活中…", table: "ServerDetails")
            : String(localized: "激活", table: "ServerDetails"),
          systemImage: "bolt.fill"
        ) {
          Task { @MainActor in
            do {
              _ = try await activation.activate(nodeID, via: workflow)
            } catch {
              // 激活状态记录失败，详情在 feedback 区域显示结果。
            }
          }
        }
        .disabled(!(eligibility?.canActivate ?? false) || activation.isPending)
        if let subscription = subscriptionSummary(for: node) {
          Button(
            workflow.refreshingSubscriptionIDs.contains(subscription.id)
              ? String(localized: "更新中…", table: "ServerDetails")
              : String(localized: "更新", table: "ServerDetails")
          ) {
            Task { await workflow.refreshSubscription(subscription.id) }
          }
          .disabled(workflow.refreshingSubscriptionIDs.contains(subscription.id))
        }
      } secondaryActions: {
        if let module = workflow.connectivity {
          ConnectivityTestButton(module: module, node: node)
        }
        Button(
          workflow.isFavorite(nodeID)
            ? String(localized: "取消收藏", table: "ServerDetails")
            : String(localized: "收藏", table: "ServerDetails")
        ) {
          do {
            try workflow.setFavorite(nodeID, isFavorite: !workflow.isFavorite(nodeID))
          } catch {
            errors.present(error)
          }
        }
        if !node.isGroup && parameters.failure != nil {
          Button(String(localized: "重新加载", table: "ServerDetails")) {
            parameters.reload(load: workflow.serverDetailPluginOptions)
          }
        }
      } feedback: {
        ActivationDetailFeedbackView(
          messages: detail.activationMessages,
          completion: activation.completion?.targetID == nodeID ? activation.completion : nil)
        if let subscription = subscriptionSummary(for: node) {
          SubscriptionRefreshFeedbackView(
            isRefreshing: workflow.refreshingSubscriptionIDs.contains(subscription.id),
            completion: workflow.subscriptionRefreshCompletions[subscription.id]
          )
          .id(subscription.id)
        }
      } supplement: {
        if let module = workflow.connectivity {
          ConnectivityDetailView(module: module, node: node, workflow: workflow)
        }
      }
      .onAppear {
        if !node.isGroup {
          parameters.showServer(nodeID, load: workflow.serverDetailPluginOptions)
        }
      }
      .onReceive(workflow.serverDetailChanges) { affected in
        parameters.didRefresh(affectedServers: affected, load: workflow.serverDetailPluginOptions)
      }
    }
  }

  private func presentation(for node: CatalogTreeNode) -> NodeDetailPresentation {
    let server = node.isGroup ? nil : workflow.serverDetailPresentation(for: nodeID)
    let subscription = subscriptionSummary(for: node)
    var detail = NodeDetailPresentation(
      node: node, server: server, eligibility: eligibility, isActiveTarget: isActiveTarget,
      subscription: subscription, locale: locale, timeZone: timeZone)
    if let server, server.plugin.selection != .none {
      if parameters.failure != nil {
        detail.appendPluginParameterFailure()
      } else {
        detail.appendPluginParameters(parameters.options.rawText)
      }
    }
    return detail
  }

  private func subscriptionSummary(for node: CatalogTreeNode) -> SubscriptionSummary? {
    guard node.isRootSubscriptionGroup else { return nil }
    return workflow.subscriptions.first { $0.groupID == node.id }
  }
}
