import SwiftUI

/// 只接受展示值与外部动作；不查询节点类型、工作流或凭据。
struct NodeDetailView<
  PrimaryActions: View, SecondaryActions: View, Feedback: View, PropertiesFooter: View,
  Supplement: View
>: View {
  let detail: NodeDetailPresentation
  @ViewBuilder let primaryActions: PrimaryActions
  @ViewBuilder let secondaryActions: SecondaryActions
  @ViewBuilder let feedback: Feedback
  let propertiesFooter: (NodeDetailPresentation.Properties) -> PropertiesFooter?
  @ViewBuilder let supplement: Supplement

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 8) {
          Text(detail.title)
            .font(.title2.weight(.semibold))
            .textSelection(.enabled)
          VStack(alignment: .leading, spacing: 4) {
            Text(detail.subtitle)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
            if let secondarySubtitle = detail.secondarySubtitle {
              Text(secondarySubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
          }
          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) { primaryActions }
              .buttonStyle(.borderedProminent)
            HStack(spacing: 12) { secondaryActions }
              .buttonStyle(.bordered)
          }
          .fixedSize(horizontal: true, vertical: true)
          .background {
            GeometryReader { geometry in
              Color.clear.preference(
                key: NodeDetailMinimumWidth.self, value: geometry.size.width + 32)
            }
          }
          feedback
        }
        Divider()
        ForEach(detail.properties) { group in
          let footer = propertiesFooter(group)
          if !group.items.isEmpty || footer != nil {
            VStack(alignment: .leading, spacing: 10) {
              Text(group.title).font(.headline)
              Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                ForEach(Array(group.items.enumerated()), id: \.offset) { _, property in
                  GridRow(alignment: .top) {
                    Text(property.label)
                      .foregroundStyle(.secondary)
                      .multilineTextAlignment(.trailing)
                      .gridColumnAlignment(.trailing)
                    Text(property.value)
                      .textSelection(.enabled)
                      .frame(maxWidth: .infinity, alignment: .leading)
                  }
                }
              }
              footer
            }
          }
        }
        supplement
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.vertical, 16)
    }
  }
}

/// 操作区按完整文字测量；包含详情的左右内边距，供外层分栏限制拖动宽度。
struct NodeDetailMinimumWidth: PreferenceKey {
  static let defaultValue: CGFloat = 320

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}
