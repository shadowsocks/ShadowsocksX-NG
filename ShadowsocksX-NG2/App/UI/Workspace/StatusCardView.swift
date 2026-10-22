import SwiftUI

/// 菜单栏面板代理状态卡
struct StatusCardView: View {
  @ObservedObject var control: ProxyControlWorkflow

  var body: some View {
    let card = StatusCardModel.card(from: control.snapshot)
    row(card.runtimeRow)
    if let detail = card.runtimeDetail {
      detailLine(detail)
    }
    row(card.systemProxyRow)
    if let detail = card.systemProxyDetail {
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

  private func color(_ tone: StatusCardModel.Tone) -> Color {
    switch tone {
    case .positive: .green
    case .attention: .orange
    case .failure: .red
    case .neutral: .secondary
    }
  }
}
