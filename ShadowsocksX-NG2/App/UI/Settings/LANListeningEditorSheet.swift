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
        Form {
          Toggle("启用局域网监听", isOn: $draft.isEnabled)

          Group {
            Picker("监听方式", selection: $draft.mode) {
              ForEach(LANListenerMode.allCases, id: \.self) { mode in
                VStack(alignment: .leading, spacing: 2) {
                  Text(mode.displayName)
                  Text(mode.bindingHint).font(.caption).foregroundStyle(.secondary)
                }.tag(mode)
              }
            }
            .pickerStyle(.radioGroup)

            Divider()

            Section {
              ListenerPortFields(workflow: workflow, draft: $draft.ports)
            } footer: {
              Text("端口范围为 1025–65535")
                .font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            Toggle("SOCKS UDP 中继", isOn: $draft.udpRelayEnabled)
            Text("当前的身份验证实现无法可靠保护 UDP 中继。")
              .font(.caption).foregroundStyle(.secondary)

            Divider()

            authenticationFields
          }
          .disabled(!draft.isEnabled)
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
        Button(workflow.isCommitting ? String(localized: "保存中…") : String(localized: "保存")) {
          Task { await save() }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!workflow.canSaveLANListening(draft))
      }
    }
    .disabled(workflow.isCommitting)
    .padding(24)
    .frame(width: 500)
    .interactiveDismissDisabled(workflow.isCommitting)
    .task(id: draft.ports) { workflow.refreshPortEditorOccupancy(for: draft.ports) }
  }

  private var authenticationFields: some View {
    Group {
      Toggle("身份验证", isOn: $draft.authenticationEnabled)
      Section {
        TextField("用户名", text: $draft.username)
          .autocorrectionDisabled()

        let showBtn = Button {
          showPassword.toggle()
        } label: {
          Image(systemName: showPassword ? "eye.slash" : "eye")
        }
        .buttonStyle(.borderless)
        .help(showPassword ? String(localized: "隐藏密码") : String(localized: "显示密码"))
        .accessibilityLabel(showPassword ? String(localized: "隐藏密码") : String(localized: "显示密码"))

        if showPassword {
          TextField(text: $draft.password) {
            showBtn
            Text("密码")
          }
          .background(PasswordAutofillOptOut())
        } else {
          SecureField(text: $draft.password) {
            showBtn
            Text("密码")
          }
          .background(PasswordAutofillOptOut())
        }

        Text("SOCKS 与 HTTP 共用一组凭据。用户名和密码为 1–255 个可打印 ASCII 字符，用户名不得包含冒号。")
          .font(.caption).foregroundStyle(.secondary)
        if !draft.hasValidCredentials {
          Text("用户名或密码无效。")
            .font(.caption).foregroundStyle(.red)
        }
      }
      .disabled(!draft.authenticationEnabled)

    }
  }

  private func save() async {
    saveError = nil
    switch await workflow.saveLANListening(draft) {
    case .persisted: dismiss()
    case .rejected(.occupied): saveError = String(localized: "端口已占用，未保存局域网监听。")
    case .rejected: saveError = String(localized: "配置发生变化或校验未完成，请重试。")
    case .persistenceFailed(let failure):
      switch failure {
      case .store(let error): saveError = AppPresentation.message(for: error)
      case .unknown: saveError = String(localized: "局域网监听保存失败。")
      }
    case .suggestedPort: break
    }
  }
}
