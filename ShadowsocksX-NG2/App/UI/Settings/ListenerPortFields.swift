import SwiftUI

struct ListenerPortFields: View {
  @ObservedObject var workflow: SettingsWorkflow
  @Binding var draft: SettingsPortDraft

  var body: some View {
    Group {
      portField2(.socks, title: "SOCKS 代理端口")
      portField2(.http, title: "HTTP 代理端口")
    }
  }

  private func portField2(_ id: SettingsPortID, title: String) -> some View {
    let state = workflow.portFieldState(for: id, editorDraft: draft)
    return Group {
      TextField(title, value: portBinding(for: id), format: .number.grouping(.never))
        .textFieldStyle(.roundedBorder)
        .monospacedDigit()
        .disabled(workflow.isCommitting)
      ForEach(state.issues, id: \.self) { issue in
        Text(AppPresentation.message(for: issue))
          .font(.caption)
          .foregroundStyle(.red)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      if let occupancy = occupancyMessage(for: state) {
        Text(occupancy)
          .font(.caption)
          .foregroundStyle(occupancyColor(for: state))
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      if state.canSuggestFreePort {
        Button("建议空闲端口") {
          Task {
            let outcome = await workflow.suggestFreePort(for: id, from: draft)
            if case .suggestedPort(let port, let value) = outcome {
              draft.setPortValue(value, for: port)
            }
          }
        }
        .font(.caption)
        .disabled(workflow.isCommitting)
      }

    }
  }

  private func portBinding(for id: SettingsPortID) -> Binding<Int> {
    Binding(
      get: { draft.portValue(for: id) },
      set: { draft.setPortValue($0, for: id) })
  }

  private func occupancyMessage(for state: SettingsPortFieldState) -> String? {
    guard let occupancy = state.occupancy else { return nil }
    switch occupancy {
    case .free:
      return nil
    case .occupied(let occupier):
      if state.isRuntimePortException {
        return "当前代理正在使用此端口"
      }
      return "当前端口已占用" + (occupier.map { "（" + $0 + "）" } ?? "")
    case .unknown(let detail):
      return "端口状态无法确定：" + detail
    }
  }

  private func occupancyColor(for state: SettingsPortFieldState) -> Color {
    guard let occupancy = state.occupancy else { return .secondary }
    switch occupancy {
    case .free, .unknown:
      return .secondary
    case .occupied:
      return state.isRuntimePortException ? .secondary : .orange
    }
  }
}
