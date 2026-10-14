import SwiftUI

/// 装配当前节点的详情会话；查询、参数装载与命令均留在共用视图之外。
struct CatalogNodeDetailView: View {
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
      NodeDetailView(detail: presentation(for: node)) {
        Button(
          activation.pendingTargetID == nodeID
            ? String(localized: "激活中…", table: "ServerDetails")
            : String(localized: "激活", table: "ServerDetails")
        ) {
          Task { @MainActor in
            do {
              _ = try await activation.activate(nodeID, via: workflow)
            } catch {
              errors.present(error)
            }
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!(eligibility?.canActivate ?? false) || activation.isPending)
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
    var detail = NodeDetailPresentation(
      node: node, server: server, eligibility: eligibility, isActiveTarget: isActiveTarget)
    if let server, server.plugin.selection != .none {
      if parameters.failure != nil {
        detail.appendPluginParameterFailure()
      } else {
        detail.appendPluginParameters(parameters.options.rawText)
      }
    }
    if activation.feedbackTargetID == nodeID, let feedback = activation.feedback {
      let message: String?
      switch feedback {
      case .rejected(let failure): message = AppPresentation.message(for: failure)
      case .failed(let value): message = value
      case .activated(let skipped) where skipped > 0:
        message = String(localized: "已跳过 \(skipped) 个存在已知阻塞问题的服务器。", table: "ServerDetails")
      case .activated: message = nil
      }
      if let message { detail.subtitle += " · " + message }
    }
    return detail
  }
}
