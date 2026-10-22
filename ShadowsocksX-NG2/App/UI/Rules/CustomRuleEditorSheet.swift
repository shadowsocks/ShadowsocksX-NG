import SwiftUI

/// The draft belongs to this presentation; only an explicit save enters the Workflow.
struct CustomRuleEditorSheet: View {
  @ObservedObject var workflow: RulesWorkflow
  @Environment(\.dismiss) private var dismiss
  @State private var draft: CustomRuleDraft
  @State private var preview: CustomRulePreview?
  @State private var isSaving = false
  @State private var saveFailure: CustomRuleUpdateOutcome?

  init(workflow: RulesWorkflow, draft: CustomRuleDraft) {
    self.workflow = workflow
    _draft = State(initialValue: draft)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(RulesCopy.text(draft.editingID == nil ? "新增规则" : "编辑规则"))
        .font(.title2)
      Form {
        VStack(alignment: .leading, spacing: 10) {
          Picker(RulesCopy.text("类型"), selection: $draft.kind) {
            ForEach(CustomRuleDraft.Kind.allCases, id: \.self) { kind in
              Text(verbatim: kind.label).tag(kind)
            }
          }
          .pickerStyle(.segmented)
          TextField(RulesCopy.text("匹配内容"), text: $draft.content)
            .autocorrectionDisabled()
          Picker(RulesCopy.text("行动"), selection: $draft.action) {
            Text(RulesCopy.text("代理")).tag(RuleAction.proxy)
            Text(RulesCopy.text("直连")).tag(RuleAction.direct)
          }
          .pickerStyle(.segmented)
        }
      }.disabled(isSaving || workflow.snapshot.isCommitting)
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          if let preview {
            if let content = preview.displayContent {
              LabeledContent(RulesCopy.text("规范化预览")) {
                Text(verbatim: content).textSelection(.enabled)
              }
            }
            if let failure = preview.failure {
              Text(verbatim: failure.message).foregroundStyle(.orange)
            } else if let row = preview.row {
              if !row.sources.subtracting([.custom]).isEmpty {
                Text(RulesCopy.text("将与已有来源合并显示。"))
                Text(verbatim: row.sourceLabels).foregroundStyle(.secondary)
              }
              if preview.inheritsDisablement {
                Text(RulesCopy.text("新身份将继承禁用状态；旧禁用记录保留。"))
              } else if !row.isEnabled {
                Text(RulesCopy.text("此身份已禁用；保存不会重新启用。"))
              }
              RulesRelationshipsContent(row: row)
              Text(RulesCopy.text("覆盖关系仅解释已启用规则之间的关系，不代表当前流量行为。"))
                .font(.caption).foregroundStyle(.secondary)
            }
          } else {
            ProgressView().controlSize(.small)
          }
          if let saveFailure {
            Label(saveFailure.rulesMessage, systemImage: "exclamationmark.triangle")
              .foregroundStyle(.orange)
            if let detail = saveFailure.failureDetail {
              Text(verbatim: detail).textSelection(.enabled)
            }
            if let nextStep = saveFailure.nextStep { Text(RulesCopy.text(nextStep)) }
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
      // 预览区随内容伸缩，上限封顶，避免初始 ProgressView 阶段撑出大片空白、
      // 长预览把 sheet 无限拉高。
      .frame(maxHeight: 210)
      HStack {
        if isSaving || workflow.snapshot.isCommitting {
          ProgressView().controlSize(.small)
          Text(RulesCopy.text("正在更新规则…")).font(.caption)
        }
        Spacer()
        Button("取消", role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
          .disabled(isSaving || workflow.snapshot.isCommitting)
        Button("保存") { save() }
          .keyboardShortcut(.defaultAction)
          .disabled(preview?.document == nil || isSaving || !workflow.snapshot.isComplete)
      }
    }
    .onChange(of: draft) { _, _ in saveFailure = nil }
    // 预览内容高度天然波动（失败提示一两行，合法预览可达上限），尺寸变化
    // 只发生在合法↔失败、关系行增减这类语义边界；平缓过渡避免 sheet 跳动。
    .animation(.snappy(duration: 0.2), value: preview)
    .animation(.snappy(duration: 0.2), value: saveFailure)
    .padding(20)
    .frame(width: 530)
    .interactiveDismissDisabled(isSaving || workflow.snapshot.isCommitting)
    .task(
      id: PreviewRequest(
        draft: draft, version: workflow.snapshot.version, isComplete: workflow.snapshot.isComplete)
    ) {
      // 重算期间保留上一次预览：清空会让预览区塌缩成进度条，sheet 随
      // 每个按键先缩后胀；新结果就绪后原位替换（旧任务由 task(id:) 取消）。
      let result = await workflow.previewCustomRule(draft)
      guard !Task.isCancelled else { return }
      preview = result
    }
  }

  private func save() {
    guard !isSaving, workflow.snapshot.isComplete else { return }
    isSaving = true
    saveFailure = nil
    Task {
      let result = await workflow.saveCustomRule(draft)
      isSaving = false
      switch result {
      case .unavailable(let failure): preview = CustomRulePreview(failure: failure)
      case .committed(let outcome):
        if outcome.isSuccess { dismiss() } else { saveFailure = outcome }
      }
    }
  }

  private struct PreviewRequest: Equatable {
    let draft: CustomRuleDraft
    let version: String
    let isComplete: Bool
  }
}

extension CustomRuleDraft.Kind {
  var label: String {
    switch self {
    case .ipAddress: RulesCopy.text("IP 地址")
    case .cidr: RulesCopy.text("CIDR 范围")
    case .domainSuffix: RulesCopy.text("域名后缀")
    case .domainExact: RulesCopy.text("精确域名")
    }
  }
}

extension CustomRulePreview.Failure {
  var message: String {
    switch self {
    case .incompleteCollection: RulesCopy.text("集合不完整")
    case .busy: RulesCopy.text("正在更新规则…")
    case .staleDraft: RulesCopy.text("规则集合已变化，请重新打开编辑器。")
    case .duplicate: RulesCopy.text("相同匹配条件和行动的自定义规则已存在。")
    case .fixedPolicyDisablement:
      RulesCopy.text("无法更新规则") + " · " + RulesCopy.text("固定策略优先，以下范围始终直连。")
    case .fixedLocalConflict: RulesCopy.text("代理规则与固定本地策略冲突，无法保存。")
    case .invalidInput(let kind):
      switch kind {
      case .ipAddress: RulesCopy.text("请输入有效的 IPv4 或 IPv6 地址。")
      case .cidr: RulesCopy.text("请输入有效的 IPv4 或 IPv6 CIDR 范围。")
      case .domainExact, .domainSuffix:
        RulesCopy.text("请输入有效的 ASCII 域名；不支持通配符、URL 或路径。")
      }
    }
  }
}
