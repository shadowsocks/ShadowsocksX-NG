import SwiftUI

struct RulesAddressTestView: View {
  @ObservedObject var workflow: RulesWorkflow

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        TextField(
          RulesCopy.text("地址（域名、IP 或 URL）"),
          text: Binding(
            get: { workflow.snapshot.addressTest.target },
            set: { workflow.setTestTarget($0) })
        )
        .textFieldStyle(.roundedBorder)
        .autocorrectionDisabled()
        .onSubmit { submit() }
        Button(RulesCopy.text("测试")) { submit() }
          .disabled(
            workflow.snapshot.isLoading || workflow.snapshot.isCommitting
              || workflow.snapshot.addressTest.isTesting)
      }
      if workflow.snapshot.addressTest.isTesting {
        ProgressView(RulesCopy.text("测试中…")).controlSize(.small)
      }
      if let failure = workflow.snapshot.addressTest.failure {
        Label(
          RulesCopy.text(
            failure == .invalidTarget
              ? "请输入有效的域名、IP 或带主机的 URL。" : "集合不完整，无法测试地址。"),
          systemImage: "exclamationmark.triangle")
      }
      if let result = workflow.snapshot.addressTest.result {
        resultSummary(result)
        ScrollView {
          VStack(alignment: .leading, spacing: 6) {
            evidence(result.deciding, title: "决定结果的规则", explanation: nil)
            evidence(
              result.otherMatches, title: "其他命中规则",
              explanation: result.explanation == .fixedLocal
                ? "固定本地策略优先。" : result.explanation.label)
          }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxHeight: 140)
      }
    }.padding()
  }

  private func submit() {
    guard !workflow.snapshot.isLoading, !workflow.snapshot.isCommitting,
      !workflow.snapshot.addressTest.isTesting
    else { return }
    Task { await workflow.testAddress() }
  }

  private func resultSummary(_ result: OfflineRuleMatcher.Result) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(result.outcome.label).font(.headline)
        Text(verbatim: result.target).textSelection(.enabled)
      }
      if result.domainWithoutDNS {
        Text(RulesCopy.text("未经 DNS 解析，未测试 IP 规则")).font(.caption)
      }
      if let explanation = result.explanation.label {
        Text(RulesCopy.text(explanation)).font(.caption)
      }
      Text(RulesCopy.text("显示顺序不代表路由优先级。"))
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private func evidence(_ rows: [RulesRow], title: String, explanation: String?) -> some View {
    if !rows.isEmpty {
      Text(RulesCopy.text(title)).font(.subheadline.bold())
      ForEach(rows) { row in
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: "\(row.displayContent) · \(row.matchType) · \(row.actionLabel)")
          Text(verbatim: row.sourceLabels).foregroundStyle(.secondary)
          if let explanation { Text(RulesCopy.text(explanation)) }
        }.font(.caption).textSelection(.enabled)
      }
    }
  }
}

extension OfflineRuleMatcher.Outcome {
  var label: String {
    switch self {
    case .proxy: RulesCopy.text("代理")
    case .direct: RulesCopy.text("直连")
    case .unmatched: RulesCopy.text("未匹配规则")
    }
  }
}

extension OfflineRuleMatcher.Explanation {
  var label: String? {
    switch self {
    case .fixedLocal: "固定本地策略优先。"
    case .domainProxy: "域名同时命中两种行动时，代理优先。"
    case .ipDirect: "IP 同时命中两种行动时，直连优先。"
    case .singleAction, .noMatch: nil
    }
  }
}
