import SwiftUI

struct LocalhostListeningEditorSheet: View {
  @ObservedObject var workflow: SettingsWorkflow
  @Environment(\.dismiss) private var dismiss
  @State private var draft: SettingsPortDraft

  init(workflow: SettingsWorkflow, initialDraft: SettingsPortDraft) {
    self.workflow = workflow
    _draft = State(initialValue: initialDraft)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("本地监听")
        .font(.title2)
      Text("SOCKS 与 HTTP 代理在本地回环地址 127.0.0.1 监听")
        .font(.caption).foregroundStyle(.secondary)
      Text("端口范围为 1025–65535，SOCKS 与 HTTP 代理端口必须不同")
        .font(.caption)
        .foregroundStyle(.secondary)

      Form {
        ListenerPortFields(workflow: workflow, draft: $draft)

        if let failure = workflow.lastFailure {
          Label(failure.presentableMessage, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
        }
      }

      HStack {
        Spacer()
        Button("取消", role: .cancel) {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        .disabled(workflow.isCommitting)

        Button(workflow.isCommitting ? String(localized: "保存中…") : String(localized: "保存")) {
          Task {
            if case .persisted = await workflow.savePortSettings(draft) {
              dismiss()
            }
          }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!workflow.canSavePortSettings(draft))
      }
    }
    .padding(24)
    .frame(width: 400)
    .interactiveDismissDisabled(workflow.isCommitting)
    .task(id: draft) {
      workflow.refreshPortEditorOccupancy(for: draft)
    }
  }

}
