import SwiftUI

/// 设置分区：常规、后台代理客户端、系统代理与插件管理，采用
/// 分组卡，行式呈现（主文案 + 次说明 + 行尾控件）。设置项由各自编辑器独立保存；
/// 登录项与静默启动开关绑定独立控制器。
struct SettingsView: View {
  let plugins: PluginManagementModel
  @ObservedObject var workflow: SettingsWorkflow
  @ObservedObject var loginController: LaunchAtLoginController
  @ObservedObject var silentLaunch: SilentLaunchController
  @State private var presentedEditor: SettingsEditorSheet?
  @AppStorage("showStatusBarRuntimeDots") private var showStatusBarRuntimeDots = true

  var body: some View {
    Form {
      generalSection
      endpointSection
      ConnectivityURLSettings(workflow: workflow)
      systemProxySection
      PluginManagementSection(model: plugins)
    }
    .formStyle(.grouped)
    .sheet(item: $presentedEditor) { editor in
      switch editor {
      case .ports(let session):
        LocalhostListeningEditorSheet(workflow: workflow, initialDraft: session.initialDraft)
      case .lan(let session):
        LANListeningEditorSheet(workflow: workflow, initialDraft: session.initialDraft)
      case .proxyExceptions(let session):
        ProxyExceptionsEditorSheet(workflow: workflow, initialValue: session.initialValue)
      }
    }
  }

  // MARK: - 常规

  private var generalSection: some View {
    Section {
      VStack(alignment: .leading, spacing: 4) {
        Toggle(
          isOn: Binding(
            get: { loginController.isEnabled },
            set: { loginController.setEnabled($0) })
        ) {
          settingCopy(
            String(localized: "登录时启动 ShadowsocksX-NG2"), note: String(localized: "启动菜单栏应用，不会自动开启代理")
          )
        }
        .toggleStyle(.switch)
        if loginController.requiresApproval {
          Text("请在系统设置 → 登录项 → 允许在后台运行中批准 ShadowsocksX-NG2。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let loginError = loginController.errorMessage {
          Text(loginError)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }
      .padding(.vertical, 4)
      VStack(alignment: .leading, spacing: 4) {
        Toggle(
          isOn: Binding(
            get: { silentLaunch.isEnabled },
            set: { silentLaunch.setEnabled($0) })
        ) {
          settingCopy(String(localized: "静默启动"), note: String(localized: "启动时后台运行，不显示主窗口；下次启动生效"))
        }
        .toggleStyle(.switch)
      }
      .padding(.vertical, 4)
      Toggle("显示状态栏运行状态圆点", isOn: $showStatusBarRuntimeDots)
        .toggleStyle(.switch)
        .padding(.vertical, 4)
      LanguageSettingsRow()
    } header: {
      sectionHeader(String(localized: "常规"))
    }
  }

  // MARK: - 后台代理客户端

  private var endpointSection: some View {
    Section {
      if let failure = workflow.lastFailure {
        Label(failure.presentableMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.footnote)
          .foregroundStyle(.red)
      }
      portSettingsRow
      settingRow(String(localized: "局域网监听")) {
        Button {
          presentedEditor = .lan(
            LANListeningEditorSession(initialDraft: workflow.beginLANListeningEditing()))
        } label: {
          HStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 3) {
              let lan = workflow.committedLANListening
              if lan.isEnabled {
                Text("\(lan.mode.displayName) SOCKS \(lan.socksPort) / HTTP \(lan.httpPort)")
                Text(lanSummary)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              } else {
                Text("关闭")
              }
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
          }
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("局域网监听")
      }
    } header: {
      sectionHeader(String(localized: "后台代理客户端"))
    }
  }

  private var lanSummary: String {
    let lan = workflow.committedLANListening
    let udp = lan.udpRelayEnabled ? String(localized: "UDP 中继启用") : String(localized: "UDP 中继禁用")
    let auth =
      lan.authenticationEnabled ? String(localized: "身份验证已启用") : String(localized: "身份验证已禁用")
    return "\(udp) / \(auth)"
  }

  // MARK: - 系统代理

  private var systemProxySection: some View {
    Section {
      settingRow(
        String(localized: "额外系统代理例外"),
        note: String(localized: "只追加到系统代理；应用固定绕过规则仍生效")
      ) {
        Button {
          presentedEditor = .proxyExceptions(
            ProxyExceptionsEditorSession(initialValue: workflow.beginProxyExceptionsEditing()))
        } label: {
          HStack(spacing: 8) {
            Text("\(workflow.committedProxyExceptionCount) 项")
            Image(systemName: "chevron.right")
              .font(.caption.weight(.semibold))
          }
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("额外系统代理例外")
        .accessibilityValue("\(workflow.committedProxyExceptionCount) 项")
        .accessibilityHint("编辑并保存额外的系统代理例外")
      }
    } header: {
      sectionHeader(String(localized: "系统代理"))
    }
  }

  // MARK: - 呈现组件

  /// 分组卡标题行。
  private func sectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.headline)
      .padding(.vertical, 2)
  }

  /// 主文案 + 可选次说明（原型行式；后台代理客户端区不配次说明）。
  private func settingCopy(_ title: String, note: String? = nil) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.body)
      if let note {
        Text(note)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  /// 行式布局：左侧文案，右侧控件。
  private func settingRow<Control: View>(
    _ title: String, note: String? = nil, @ViewBuilder control: () -> Control
  ) -> some View {
    HStack(spacing: 16) {
      settingCopy(title, note: note)
      Spacer(minLength: 16)
      control()
    }
  }
}

// MARK: - 端口设置摘要与编辑框

extension SettingsView {
  fileprivate var portSettingsRow: some View {
    let ports = workflow.committedPortDraft
    let socksPort = ports.socksPort.formatted(.number.grouping(.never))
    let httpPort = ports.httpPort.formatted(.number.grouping(.never))
    return settingRow(String(localized: "本地监听")) {
      Button {
        presentedEditor = .ports(
          PortSettingsEditorSession(initialDraft: workflow.beginPortSettingsEditing()))
      } label: {
        HStack(spacing: 8) {
          Text("SOCKS \(socksPort) / HTTP \(httpPort)")
            .monospacedDigit()
          Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
        }
      }
      .buttonStyle(.bordered)
      .accessibilityLabel("本地监听")
      .accessibilityValue("SOCKS \(socksPort)，HTTP 代理 \(httpPort)")
    }
  }

}

private enum SettingsEditorSheet: Identifiable {
  case ports(PortSettingsEditorSession)
  case lan(LANListeningEditorSession)
  case proxyExceptions(ProxyExceptionsEditorSession)

  var id: UUID {
    switch self {
    case .ports(let session): session.id
    case .lan(let session): session.id
    case .proxyExceptions(let session): session.id
    }
  }
}

private struct PortSettingsEditorSession: Identifiable {
  let id = UUID()
  let initialDraft: SettingsPortDraft
}

private struct ProxyExceptionsEditorSession: Identifiable {
  let id = UUID()
  let initialValue: String
}

private struct ProxyExceptionsEditorSheet: View {
  @ObservedObject var workflow: SettingsWorkflow
  @Environment(\.dismiss) private var dismiss
  @State private var draft: String

  init(workflow: SettingsWorkflow, initialValue: String) {
    self.workflow = workflow
    _draft = State(initialValue: initialValue)
  }

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          Text("额外系统代理例外")
            .font(.title2)
          Text("添加希望 macOS 系统代理跳过的主机名、域名或 IP/CIDR。留空并确定会清除用户添加的条目。")
            .font(.caption)
            .foregroundStyle(.secondary)

          TextEditor(text: $draft)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(height: 112)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
              RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
            }
            .disabled(workflow.isCommitting)
            .accessibilityLabel("额外系统代理例外")

          Text(
            "格式：域名、主机名或 IP/CIDR，以逗号、顿号、空格或换行分隔。示例：127.0.0.1, 192.168.0.0/16, localhost。"
          )
          .font(.caption)
          .foregroundStyle(.secondary)

          Divider()

          VStack(alignment: .leading, spacing: 6) {
            Text("应用固定的系统代理例外")
              .font(.headline)
            Text(FixedLocalProxyRanges.systemProxyExceptions.joined(separator: "\n"))
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
            Text("应用系统代理配置时，还会固定开启“不包括简单主机名（Exclude simple hostnames）”。")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          VStack(alignment: .leading, spacing: 6) {
            Text("应用固定的 ACL 绕过规则")
              .font(.headline)
            Text(FixedLocalProxyRanges.aclBypassRules.joined(separator: "\n"))
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
            Text("这些规则用于本机 SOCKS/HTTP 入站；上方输入只追加到系统代理例外，不会修改 ACL。")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          if let failure = workflow.lastFailure {
            Label(failure.presentableMessage, systemImage: "exclamationmark.triangle.fill")
              .font(.footnote)
              .foregroundStyle(.red)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 16)
      }

      HStack {
        Spacer()
        Button("取消", role: .cancel) {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        .disabled(workflow.isCommitting)

        Button(workflow.isCommitting ? String(localized: "保存中…") : String(localized: "确定")) {
          Task {
            if case .persisted = await workflow.saveProxyExceptions(draft) {
              dismiss()
            }
          }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(workflow.isCommitting)
      }
      .padding(.top, 12)
    }
    .padding(24)
    .frame(width: 560, height: 640)
    .interactiveDismissDisabled(workflow.isCommitting)
  }
}
