import SwiftUI

/// 首页分区：代理模式切换、运行控制、终端代理环境变量命令。
/// 模式与两个开关（agent/系统代理）走代理控制
/// 工作流的整体 snapshot；命令复制是 UI 副作用。三种模式（规则/全局/直连）
/// 与规则子选项共用同一快照。
struct HomeView: View {
  @ObservedObject var workflow: CatalogWorkflow
  @ObservedObject var control: ProxyControlWorkflow
  let browser: HomeTargetBrowser
  let activation: ActivationFeedbackState
  let showServers: () -> Void
  let clipboard: any TextClipboard
  let errors: ErrorAlertPresenter

  var body: some View {
    ScrollView {
      HStack(alignment: .top, spacing: 20) {
        VStack(spacing: 16) {
          HomeTargetCard(
            workflow: workflow, browser: browser, activation: activation,
            activeTargetID: control.snapshot.activeTarget?.id, showServers: showServers)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        VStack(spacing: 16) {
          RuntimeControlCard(control: control)
          ModeCard(control: control)
          TerminalProxyEnvironmentCard(control: control, clipboard: clipboard, errors: errors)
        }
        .frame(width: 400)
      }
      .padding(.leading, 28)
      .padding(.trailing, 32)
      .padding(.top, 24)
      .padding(.bottom, 36)
    }
  }
}
