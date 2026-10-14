import SwiftUI

struct HomeTargetRow: View {
  static let height: CGFloat = 34
  let row: CatalogTreeRow
  let workflow: CatalogWorkflow
  let selected: Bool
  let active: Bool
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
              .foregroundStyle(selected ? Color(nsColor: .selectedTextColor) : .orange)
              .help(String(localized: "活动目标"))
          }
          Spacer(minLength: 4)
          if let module = workflow.connectivity {
            ConnectivityCell(module: module, node: row.node, workflow: workflow)
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
    .foregroundStyle(selected ? Color(nsColor: .selectedTextColor) : .primary)
    .background(
      selected ? Color(nsColor: .selectedContentBackgroundColor) : .clear,
      in: RoundedRectangle(cornerRadius: 5)
    )
    .frame(height: Self.height)
  }
}
