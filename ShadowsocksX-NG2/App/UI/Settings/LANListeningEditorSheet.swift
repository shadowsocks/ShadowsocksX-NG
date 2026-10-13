import SwiftUI

struct LANListeningEditorSession: Identifiable {
  let id = UUID()
  let initialDraft: LANListeningDraft
}

struct LANListeningEditorSheet: View {
  @ObservedObject var workflow: SettingsWorkflow
  @Environment(\.dismiss) private var dismiss
  @State private var draft: LANListeningDraft
  @State private var saveError: String?
  @State private var showPassword = false

  init(workflow: SettingsWorkflow, initialDraft: LANListeningDraft) {
    self.workflow = workflow
    _draft = State(initialValue: initialDraft)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("局域网监听").font(.title2)
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Picker("监听方式", selection: $draft.mode) {
            ForEach(ListenerMode.allCases, id: \.self) { mode in
              VStack(alignment: .leading, spacing: 2) {
                Text(mode.displayName)
                if mode != .disabled {
                  Text(mode.bindingHint).font(.caption).foregroundStyle(.secondary)
                }
              }.tag(mode)
            }
          }
          .pickerStyle(.radioGroup)

          VStack(alignment: .leading, spacing: 18) {
            Divider()
            Text("端口范围为 1025–65535，四个代理端口必须不同")
              .font(.caption).foregroundStyle(.secondary)
            ListenerPortFields(workflow: workflow, draft: $draft.ports)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
              Toggle("SOCKS UDP 中继", isOn: $draft.udpRelayEnabled)
              Text("当前实现的身份验证无法可靠保护 UDP 中继。")
                .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            authenticationFields
          }
          .disabled(draft.mode == .disabled)
        }
        .padding(4)
      }
      .frame(maxHeight: 620)
      if let saveError {
        Text(saveError).font(.caption).foregroundStyle(.red)
      }
      HStack {
        Spacer()
        Button("取消", role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button(workflow.isCommitting ? "保存中…" : "保存") {
          Task { await save() }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!workflow.canSaveLANListening(draft))
      }
    }
    .disabled(workflow.isCommitting)
    .padding(24)
    .frame(width: 520)
    .interactiveDismissDisabled(workflow.isCommitting)
    .task(id: draft.ports) { workflow.refreshPortEditorOccupancy(for: draft.ports) }
  }

  private var authenticationFields: some View {
    VStack(alignment: .leading, spacing: 12) {
      Toggle("身份验证", isOn: $draft.authenticationEnabled)
      VStack(spacing: 12) {
        HStack {
          Text("用户名")
          Spacer()
          TextField("用户名", text: $draft.username)
            .frame(width: 230)
            .autocorrectionDisabled()
        }
        HStack {
          Text("密码")
          Spacer()
          HStack(spacing: 8) {
            Group {
              if showPassword {
                TextField("密码", text: $draft.password)
                  .background(PasswordAutofillOptOut())
              } else {
                SecureField("密码", text: $draft.password)
                  .background(PasswordAutofillOptOut())
              }
            }
            .textContentType(nil)
            .autocorrectionDisabled()
            Button {
              showPassword.toggle()
            } label: {
              Image(systemName: showPassword ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help(showPassword ? "隐藏密码" : "显示密码")
            .accessibilityLabel(showPassword ? "隐藏密码" : "显示密码")
          }
          .frame(width: 230)
        }
      }
      .textFieldStyle(.roundedBorder)
      .disabled(!draft.authenticationEnabled)
      Text("SOCKS 与 HTTP 共用一组凭据。用户名和密码为 1–255 个可打印 ASCII 字符，用户名不得包含冒号。")
        .font(.caption).foregroundStyle(.secondary)
      if !draft.hasValidCredentials {
        Text("用户名或密码无效。")
          .font(.caption).foregroundStyle(.red)
      }
    }
  }

  private func save() async {
    saveError = nil
    switch await workflow.saveLANListening(draft) {
    case .persisted: dismiss()
    case .rejected(.occupied): saveError = "端口已占用，未保存局域网监听。"
    case .rejected: saveError = "配置发生变化或校验未完成，请重试。"
    case .persistenceFailed(let failure):
      switch failure {
      case .store(let error): saveError = AppPresentation.message(for: error)
      case .unknown: saveError = "局域网监听保存失败。"
      }
    case .suggestedPort: break
    }
  }
}
