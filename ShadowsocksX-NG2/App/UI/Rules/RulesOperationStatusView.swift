import SwiftUI

/// A reserved toolbar row keeps feedback from resizing or replacing the rule table.
struct RulesOperationStatusView: View {
  @ObservedObject var workflow: RulesWorkflow
  @State private var showsDetails = false

  var body: some View {
    HStack(spacing: 8) {
      Spacer(minLength: 0)
      switch workflow.snapshot.operationStatus {
      case .idle, .initialLoading:
        EmptyView()
      case .updating:
        progress("正在更新规则…")
      case .refreshing:
        progress("正在加载规则…")
      case .collectionIncomplete:
        Label(RulesCopy.text("集合不完整"), systemImage: "exclamationmark.triangle")
          .foregroundStyle(.orange)
        detailsButton
        refreshButton
      case .feedback(let feedback):
        Label {
          Text(verbatim: feedback.summary).lineLimit(1).truncationMode(.middle)
        } icon: {
          Image(
            systemName: feedback.outcome.isSuccess ? "checkmark.circle" : "exclamationmark.triangle"
          )
          .foregroundStyle(feedback.outcome.isSuccess ? Color.secondary : Color.orange)
        }
        .help(feedback.summary)
        if !feedback.outcome.isSuccess {
          detailsButton
          Button(RulesCopy.text("关闭"), systemImage: "xmark") {
            workflow.dismissFeedback()
          }.labelStyle(.iconOnly)
        }
      }
    }
    .font(.caption)
    .controlSize(.small)
    .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22)
    .onChange(of: workflow.snapshot.operationStatus) { _, _ in showsDetails = false }
  }

  private func progress(_ key: String) -> some View {
    HStack(spacing: 6) {
      ProgressView().controlSize(.mini)
      Text(RulesCopy.text(key))
    }.accessibilityElement(children: .combine)
  }

  private var detailsButton: some View {
    Button(RulesCopy.text("查看详情")) { showsDetails = true }
      .popover(isPresented: $showsDetails) { details }
  }

  private var refreshButton: some View {
    Button(RulesCopy.text("刷新规则")) {
      showsDetails = false
      Task { await workflow.refresh(retryFailedSources: true) }
    }
  }

  private var details: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        if let feedback = workflow.snapshot.commitFeedback {
          Text(verbatim: feedback.summary).font(.headline)
          if let detail = feedback.outcome.failureDetail {
            Text(verbatim: detail).textSelection(.enabled)
          }
          if let nextStep = feedback.outcome.nextStep {
            Text(RulesCopy.text(nextStep))
          }
        }
        if !workflow.snapshot.issues.isEmpty {
          Text(RulesCopy.text("规则列表未更新，请刷新规则。"))
          RulesCollectionIssuesView(issues: workflow.snapshot.issues)
        }
      }.frame(maxWidth: .infinity, alignment: .leading).padding()
    }.frame(width: 380).frame(maxHeight: 300)
  }
}

struct RulesCollectionIssuesView: View {
  let issues: [RulesPageSnapshot.Issue]

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(RulesCopy.text("集合不完整时，覆盖解释仅基于已加载来源。"))
      ForEach(issues, id: \.self) { issue in
        Text(verbatim: description(issue)).textSelection(.enabled)
      }
    }.font(.caption)
  }

  private func description(_ issue: RulesPageSnapshot.Issue) -> String {
    switch issue {
    case .userDocument(let detail): "\(RulesCopy.text("自定义规则")): \(detail)"
    case .builtin(let source, let detail): "\(source.label): \(detail)"
    }
  }
}
