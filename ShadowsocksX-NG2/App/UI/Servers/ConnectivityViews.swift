import SwiftUI

/// Observes only the network observations, with a periodic expiry projection.
struct ConnectivityCell: View {
  @ObservedObject var module: ServerConnectivity
  let node: CatalogTreeNode
  let workflow: CatalogWorkflow
  var selected = false

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let value = presentation(at: context.date)
      HStack(spacing: 5) {
        Text(value.text)
          .foregroundStyle(
            selected
              ? AnyShapeStyle(
                Color(nsColor: .alternateSelectedControlTextColor)
                  .opacity(value.expired ? 0.85 : 1))
              : AnyShapeStyle(value.expired ? .secondary : .primary))
        if value.testing {
          ProgressView().controlSize(.mini)
            .tint(selected ? Color(nsColor: .alternateSelectedControlTextColor) : nil)
        }
      }
      .help(value.help)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(ConnectivityCopy.text("响应延迟")))
      .accessibilityValue(
        Text(
          value.text + " " + value.help + (value.testing ? " " + ConnectivityCopy.text("测试中") : ""))
      )
    }
  }

  private struct Presentation {
    let text: String
    let help: String
    let expired: Bool
    let testing: Bool
  }

  private func presentation(at date: Date) -> Presentation {
    let record: ServerConnectivity.Record?
    let text: String
    var prefix = ""
    let summary = module.summary(for: node.connectivityServerIDs, at: date)
    if node.isGroup {
      record = summary.record
      text = record.map { ConnectivityCopy.outcome($0.outcome) } ?? (summary.hasResults ? "—" : "")
      if let id = summary.serverID { prefix = workflow.displayName(for: id) + " · " }
    } else {
      record = module.history(for: node.id).first
      text = record.map { ConnectivityCopy.outcome($0.outcome) } ?? ""
    }
    let expired = record?.isExpired(at: date) ?? false
    let help =
      record.map {
        prefix + $0.finishedAt.formatted(date: .numeric, time: .standard)
          + (expired ? " · " + ConnectivityCopy.text("已过期") : "")
      }
      ?? (summary.hasResults && node.isGroup
        ? ConnectivityCopy.text("无成功结果") : ConnectivityCopy.text("尚未测试"))
    return Presentation(text: text, help: help, expired: expired, testing: summary.isTesting)
  }
}

struct ConnectivityTestButton: View {
  @ObservedObject var module: ServerConnectivity
  let node: CatalogTreeNode
  var body: some View {
    let isTesting = node.connectivityServerIDs.contains { module.testing.contains($0) }
    Button(ConnectivityCopy.text(isTesting ? "测试中..." : "延迟测试")) {
      module.test(node.connectivityServerIDs)
    }
    .disabled(
      isTesting || !node.containsServerConfiguration || (!node.isGroup && module.isCooling(node.id))
    )
  }
}

/// Copy is kept at the presentation edge; failures never render raw errors or URLs.
enum ConnectivityCopy {
  static func text(_ key: String) -> String {
    NSLocalizedString(key, tableName: "Connectivity", bundle: .main, comment: "")
  }
  static func outcome(_ value: ServerConnectivity.Outcome) -> String {
    switch value {
    case .success(let milliseconds): "\(milliseconds) ms"
    case .unsupported: text("配置不支持")
    case .preparationTimeout: text("准备超时")
    case .requestTimeout: text("请求超时")
    case .configuration: text("配置错误")
    case .startup: text("启动错误")
    case .network: text("网络错误")
    case .http(let status): "HTTP \(status)"
    }
  }
}
