import AppKit
import SwiftUI

/// 菜单栏面板代理状态卡。状态行经 StatusDisplayModel 的瞬态门控呈现
/// （与首页运行控制卡同一 debounce 口径）；活动目标与模式行仍从 control
/// 的整体 snapshot 直接派生。
struct StatusCardView: View {
  @ObservedObject var control: ProxyControlWorkflow
  let statusDisplay: StatusDisplayModel

  var body: some View {
    let card = StatusCardModel.card(from: control.snapshot)
    row(statusDisplay.agent.row)
    if let detail = statusDisplay.agent.detail {
      detailLine(detail)
    }
    row(statusDisplay.systemProxy.row)
    if let detail = statusDisplay.systemProxy.detail {
      detailLine(detail)
    }

    Text(card.target.text)
      .truncationMode(.middle)
      .help(card.target.help)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("活动目标：\(card.target.text)")

    Text("模式：\(card.modeText)").accessibilityElement(children: .combine)
  }

  private func row(_ row: StatusCardModel.Row) -> some View {
    Text("\(row.label)：\(row.text)").accessibilityElement(children: .combine)
  }

  private func detailLine(_ detail: StatusCardModel.DetailLine) -> some View {
    Text(detail.text)
      .lineLimit(2)
      .help(detail.text)
  }
}

/// 首页与状态栏共用圆点及色调映射，尺寸由显示位置决定。
struct RuntimeStatusDot: View {
  let tone: StatusCardModel.Tone
  let diameter: CGFloat

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: diameter, height: diameter)
      .accessibilityHidden(true)
  }

  private var color: Color {
    switch tone {
    case .positive: .green
    case .attention: .orange
    case .failure: .red
    case .neutral: .secondary
    }
  }
}

/// 标签在启动时即挂载；启动 resync 必须留在此处，不能移入首次点开才创建的菜单内容。
struct StatusMenuLabel: View {
  let control: ProxyControlWorkflow
  let statusDisplay: StatusDisplayModel
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.displayScale) private var displayScale

  var body: some View {
    Image(nsImage: statusImage)
      .renderingMode(.original)
      .accessibilityLabel("ShadowsocksX-NG2")
      .task {
        await control.resyncOnLaunch()
      }
  }

  /// MenuBarExtra 使用单张图像承载主图标和圆点，保留圆点的原始颜色。
  private var statusImage: NSImage {
    let renderer = ImageRenderer(
      content: HStack(spacing: 2) {
        Image(systemName: "paperplane.fill")
          .font(.system(size: 16))
          .foregroundStyle(.primary)
          .frame(width: 18, height: 18)
        VStack(spacing: 5) {
          RuntimeStatusDot(tone: statusDisplay.agent.row.tone, diameter: 4)
          RuntimeStatusDot(tone: statusDisplay.systemProxy.row.tone, diameter: 4)
        }
      }
      .environment(\.colorScheme, colorScheme))
    renderer.scale = displayScale
    return renderer.nsImage ?? NSImage(
      systemSymbolName: "paperplane.fill", accessibilityDescription: nil) ?? NSImage(size: .zero)
  }
}
