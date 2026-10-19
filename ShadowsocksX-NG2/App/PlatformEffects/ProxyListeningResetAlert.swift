import AppKit

/// 启动门禁尚无工作区窗口；使用应用级模态提示，静默启动也能完成确认。
@MainActor
enum ProxyListeningResetAlert {
  static func present(_ error: ProxyListeningStoreError) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = String(localized: "无法读取监听配置")
    alert.informativeText =
      AppPresentation.message(for: error) + "\n\n"
      + String(
        localized: "重置会丢弃原有监听配置，包括端口和局域网认证设置，并关闭局域网监听。服务器库和其他偏好设置保持不变。重置成功后应用才能继续启动。")
    alert.addButton(withTitle: String(localized: "重置监听配置"))
    NSApplication.shared.activate()
    alert.runModal()
  }
}
