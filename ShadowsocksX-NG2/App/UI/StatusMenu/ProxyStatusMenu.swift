import AppKit
import SwiftUI

/// 菜单栏窗口式面板：重开主窗口、只读状态卡、无效服务器提示与退出。
/// 控制与目标选择留在工作区；状态卡的状态行走 statusDisplay 的瞬态门控
/// 呈现（与首页运行控制卡同一 debounce 口径）。
struct ProxyStatusMenu: View {
  @ObservedObject var control: ProxyControlWorkflow
  let statusDisplay: StatusDisplayModel
  @Environment(\.openWindow) private var openWindow
  /// 只捕获本面板的宿主窗口，打开主窗口时不会误关其他窗口。
  @State private var windowAnchor = NSView(frame: .zero)

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("打开主窗口…") {
        windowAnchor.window?.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: WorkspaceRoute.workspaceSceneID)
      }
      .padding(12)

      Button("诊断…") {
        windowAnchor.window?.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: DiagnosticsWindowState.sceneID)
      }
      .padding(12)

      Divider()
      StatusCardView(control: control, statusDisplay: statusDisplay)
      Divider()
      Button("退出 ShadowsocksX-NG2（代理仍在后台运行）") {
        NSApp.terminate(nil)
      }
      .padding(12)
    }
    .frame(width: 320, alignment: .leading)
    .background(StatusPanelWindowAnchor(view: windowAnchor).frame(width: 0, height: 0))
  }
}

/// MenuBarExtra 没有关闭弹出面板的绑定；零尺寸视图定位当前面板的窗口。
private struct StatusPanelWindowAnchor: NSViewRepresentable {
  let view: NSView

  func makeNSView(context: Context) -> NSView { view }
  func updateNSView(_ nsView: NSView, context: Context) {}
}
