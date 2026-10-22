import SwiftUI

struct HomeTargetRow: View {
  static let height: CGFloat = 34
  let row: CatalogTreeRow
  let workflow: CatalogWorkflow
  let selected: Bool
  let active: Bool
  /// 子树含活动目标（严格后代）：空心闪电，与实心的"本行即活动目标"区分。
  let containsActiveTarget: Bool
  let expandable: Bool
  let expanded: Bool
  let path: String
  let select: () -> Void
  let toggle: () -> Void

  var body: some View {
    HStack(spacing: 0) {
      if expandable {
        Button(action: toggle) {
          Image(systemName: expanded ? "chevron.down" : "chevron.right")
            .font(.caption.weight(.semibold))
            .frame(width: 22, height: Self.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
          expanded
            ? String(localized: "收起 \(row.node.name)", table: "HomeTargets")
            : String(localized: "展开 \(row.node.name)", table: "HomeTargets"))
      } else {
        Color.clear.frame(width: 22)
      }
      Button(action: select) {
        HStack(spacing: 6) {
          Image(systemName: row.node.isGroup ? "folder" : "server.rack")
          Text(row.node.name).lineLimit(1).truncationMode(.tail)
          if active {
            Image(systemName: "bolt.fill")
              .foregroundStyle(
                selected ? Color(nsColor: .alternateSelectedControlTextColor) : .orange
              )
              .help(String(localized: "活动目标"))
          } else if containsActiveTarget {
            Image(systemName: "bolt")
              .foregroundStyle(
                selected ? Color(nsColor: .alternateSelectedControlTextColor) : .orange
              )
              .help(String(localized: "组内含活动目标"))
          }
          Spacer(minLength: 4)
          if let module = workflow.connectivity {
            ConnectivityCell(module: module, node: row.node, workflow: workflow, selected: selected)
              .monospacedDigit()
              .frame(width: 130, alignment: .trailing)
          }
        }
        .font(.callout)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(path)
      .accessibilityAddTraits(selected ? .isSelected : [])
    }
    .padding(.leading, CGFloat(row.depth) * 16 + 2)
    .padding(.trailing, 8)
    .foregroundStyle(selected ? Color(nsColor: .alternateSelectedControlTextColor) : .primary)
    .background(
      selected ? Color(nsColor: .selectedContentBackgroundColor) : .clear,
      in: RoundedRectangle(cornerRadius: 5)
    )
    .frame(height: Self.height)
  }
}
