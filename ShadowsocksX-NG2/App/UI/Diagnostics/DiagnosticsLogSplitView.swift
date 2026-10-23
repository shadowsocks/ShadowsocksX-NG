import AppKit
import SwiftUI

/// 原生分栏只设置一次初始宽度，后续更新保留用户拖动的位置。
struct DiagnosticsLogSplitView<Logs: View, Details: View>: NSViewControllerRepresentable {
  @ViewBuilder let logs: Logs
  @ViewBuilder let details: Details

  func makeNSViewController(context: Context) -> Controller {
    Controller(logs: logs, details: details)
  }

  func updateNSViewController(_ controller: Controller, context: Context) {
    controller.logs.rootView = logs
    controller.details.rootView = details
    // 离开 SwiftUI 的尺寸试算与更新事务后，按实际分栏宽度定位。
    DispatchQueue.main.async { [weak controller] in
      controller?.initializeWidth()
    }
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize, nsViewController: Controller, context: Context
  ) -> CGSize? {
    proposal.replacingUnspecifiedDimensions(by: CGSize(width: 740, height: 300))
  }

  final class Controller: NSSplitViewController {
    let logs: NSHostingController<Logs>
    let details: NSHostingController<Details>
    private var initializedWidth = false

    init(logs: Logs, details: Details) {
      self.logs = NSHostingController(rootView: logs)
      self.details = NSHostingController(rootView: details)
      super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("NSViewController 不走 storyboard 初始化") }

    override func viewDidLoad() {
      super.viewDidLoad()
      splitView.isVertical = true
      splitView.dividerStyle = .thin
      let logItem = NSSplitViewItem(viewController: logs)
      logItem.minimumThickness = 520
      let detailItem = NSSplitViewItem(viewController: details)
      detailItem.minimumThickness = 180
      // 高于日志栏默认的 250、低于拖动的 490，窗口缩放优先调整日志栏。
      detailItem.holdingPriority = NSLayoutConstraint.Priority(260)
      addSplitViewItem(logItem)
      addSplitViewItem(detailItem)
    }

    func initializeWidth() {
      guard !initializedWidth, view.window != nil,
        splitView.bounds.width >= 700 + splitView.dividerThickness
      else { return }
      initializedWidth = true
      splitView.layoutSubtreeIfNeeded()
      splitView.setPosition(
        splitView.bounds.width - splitView.dividerThickness - 220, ofDividerAt: 0)
      splitView.layoutSubtreeIfNeeded()
    }
  }
}
