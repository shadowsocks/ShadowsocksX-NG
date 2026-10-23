import SwiftUI

/// 应用名称菜单中的诊断窗口入口：与状态菜单入口同开唯一诊断窗口，
/// 仅随 regular 形态的应用菜单栏出现（accessory 形态无此菜单栏）。
struct DiagnosticsCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(after: .appInfo) {
      Button("诊断…") {
        openWindow(id: DiagnosticsWindowState.sceneID)
      }
    }
  }
}
