import SwiftUI

/// 只接受展示值与外部动作；不查询节点类型、工作流或凭据。
struct NodeDetailView<Actions: View, Supplement: View>: View {
  let detail: NodeDetailPresentation
  @ViewBuilder let actions: Actions
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
          HStack(spacing: 16) { actions }
            .buttonStyle(.link)
        }
        Divider()
        ForEach(Array(detail.properties.enumerated()), id: \.offset) { _, group in
          if !group.items.isEmpty {
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
