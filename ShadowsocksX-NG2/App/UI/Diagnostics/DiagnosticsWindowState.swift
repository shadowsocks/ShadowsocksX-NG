import AppKit
import SwiftUI

/// 进程内保留日志来源；轮询只跟随这一个窗口的真实开关状态。
@MainActor
final class DiagnosticsWindowState: ObservableObject {
  static let sceneID = "diagnostics"

  @Published private(set) var isOpen = false
  @Published var filter = DiagnosticLogFilter()
  @Published var exportedDiagnosticsPath: String?
  let errors = ErrorAlertPresenter()
  private weak var window: NSWindow?

  init() {
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(windowPresented(_:)),
      name: NSWindow.didBecomeKeyNotification, object: nil)
    center.addObserver(
      self, selector: #selector(windowPresented(_:)),
      name: NSWindow.didChangeOcclusionStateNotification, object: nil)
    center.addObserver(
      self, selector: #selector(windowClosed(_:)),
      name: NSWindow.willCloseNotification, object: nil)
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  func attach(to window: NSWindow) {
    self.window = window
    if window.isVisible { isOpen = true }
  }

  @objc private func windowPresented(_ notification: Notification) {
    guard let candidate = notification.object as? NSWindow,
      candidate === window, candidate.isVisible, !isOpen
    else { return }
    isOpen = true
  }

  @objc private func windowClosed(_ notification: Notification) {
    guard let candidate = notification.object as? NSWindow, candidate === window else { return }
    isOpen = false
    exportedDiagnosticsPath = nil
    errors.dismiss()
  }
}

/// 只上交宿主窗口；不拥有窗口、不改变 delegate，也不把隐藏误当关闭。
struct DiagnosticsWindowAnchor: NSViewRepresentable {
  let state: DiagnosticsWindowState

  func makeNSView(context: Context) -> AnchorView { AnchorView(state: state) }
  func updateNSView(_ nsView: AnchorView, context: Context) {}

  final class AnchorView: NSView {
    private let state: DiagnosticsWindowState

    init(state: DiagnosticsWindowState) {
      self.state = state
      super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("NSView 不走 storyboard 初始化") }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      guard let window else { return }
      // attach 发生于视图更新中；延迟发布，避免在 SwiftUI 更新中发布状态。
      Task { @MainActor [weak self, weak window] in
        guard let self, let window, self.window === window else { return }
        state.attach(to: window)
      }
    }
  }
}
