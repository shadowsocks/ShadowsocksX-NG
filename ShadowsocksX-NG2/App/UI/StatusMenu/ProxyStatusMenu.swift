import AppKit
import SwiftUI

/// 菜单栏面板：窗口入口与退出。
struct ProxyStatusMenu: View {
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

      Button("关于 ShadowsocksX-NG2") {
        windowAnchor.window?.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: AboutView.sceneID)
      }
      .padding(12)

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
