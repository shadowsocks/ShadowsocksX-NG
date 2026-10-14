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
      text = record.map { ConnectivityCopy.fastest($0.outcome) } ?? (summary.hasResults ? "—" : "")
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

struct ConnectivityBatchButton: View {
  @ObservedObject var module: ServerConnectivity
  let targets: [NodeID]
  @State private var batchID: UUID?

  var body: some View {
    HStack(spacing: 6) {
      Button {
        batchID = module.test(targets)
      } label: {
        Label(ConnectivityCopy.text("测试全部"), systemImage: "waveform.path.ecg")
      }
      .disabled(targets.isEmpty)
      if let batchID, let batch = module.batch(batchID), batch.completed < batch.targets.count {
        ProgressView().controlSize(.mini)
      }
    }
  }
}

struct ConnectivityTestButton: View {
  @ObservedObject var module: ServerConnectivity
  let node: CatalogTreeNode
  var body: some View {
    Button(ConnectivityCopy.text("测试连通性")) { module.test(node.connectivityServerIDs) }
      .disabled(!node.containsServerConfiguration || (!node.isGroup && module.isCooling(node.id)))
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
  static func fastest(_ value: ServerConnectivity.Outcome) -> String {
    String.localizedStringWithFormat(text("最快 %@"), outcome(value))
  }
}

struct ConnectivityDetailView: View {
  @ObservedObject var module: ServerConnectivity
  let node: CatalogTreeNode
  let workflow: CatalogWorkflow

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(ConnectivityCopy.text(node.isGroup ? "最快响应延迟" : "连通性测试")).font(.headline)
          ConnectivityTestButton(module: module, node: node)
        }
        if node.isGroup {
          ConnectivityCell(module: module, node: node, workflow: workflow)
          let summary = module.summary(for: node.connectivityServerIDs, at: context.date)
          if let id = summary.serverID, let record = summary.record {
            Text(workflow.displayName(for: id))
            Text(timestamp(record, at: context.date)).foregroundStyle(.secondary)
          } else if summary.hasResults {
            Text(ConnectivityCopy.text("无成功结果")).foregroundStyle(.secondary)
          }
        } else {
          ForEach(module.history(for: node.id)) { record in
            HStack {
              Text(timestamp(record, at: context.date)).foregroundStyle(.secondary)
              Spacer()
              Text(ConnectivityCopy.outcome(record.outcome))
            }
          }
        }
      }
    }
  }

  private func timestamp(_ record: ServerConnectivity.Record, at date: Date) -> String {
    record.finishedAt.formatted(date: .numeric, time: .standard)
      + (record.isExpired(at: date) ? " · " + ConnectivityCopy.text("已过期") : "")
  }
}
