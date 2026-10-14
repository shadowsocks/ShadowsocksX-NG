import SwiftUI

/// 「复制代理环境变量设置命令」卡：按所选 shell 格式复制 HTTP 与 SOCKS 环境变量。
/// 局域网开启时以单选下拉框选择命令地址，各种 shell
/// 的全部代理端点共用该选择；局域网关闭时隐藏下拉框并使用本地入口。
struct TerminalProxyEnvironmentCard: View {
  @ObservedObject var control: ProxyControlWorkflow
  let clipboard: any TextClipboard
  let errors: ErrorAlertPresenter

  @State private var copiedShell: TerminalCommandShell?
  @State private var feedbackTask: Task<Void, Never>?

  var body: some View {
    HomeCard(
      title: "复制代理环境变量设置命令",
      subtitle: nil,
      trailing: { EmptyView() },
      content: {
        VStack(spacing: 10) {
          if control.snapshot.commandAddressPicker.isVisible {
            // Menu（而非 Picker）：菜单项经 adaptive-controls 机制桥接，
            // 两个 Text 映射为 NSMenuItem 的原生 title/subtitle；Picker 的
            // 选项桥接会把多 Text 压平成独立菜单项。
            Menu {
              ForEach(
                control.snapshot.commandAddressPicker.candidates, id: \.identity
              ) { candidate in
                Button {
                  control.selectCommandAddress(candidate)
                } label: {
                  Text(candidate.address)
                  Text(menuSubtitle(for: candidate))
                }
              }
            } label: {
              Text(control.snapshot.commandAddressPicker.selected.address)
                .lineLimit(1)
            }
            .menuStyle(.borderedButton)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 收起状态详情：接口名称与地址类型以说明行展示在按钮下方。
            HStack(spacing: 4) {
              Text("接口：\(control.snapshot.commandAddressPicker.selected.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
              if let annotation = control.snapshot.commandAddressPicker.selected.annotation {
                Text("·")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                Text("地址类型：\(annotation)")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          if control.snapshot.terminalProxyEnvironmentCommands.failure != nil {
            Text("局域网身份验证密码不可读，请重试。")
              .font(.caption).foregroundStyle(.red)
          }
          ForEach(control.snapshot.terminalCommandShells, id: \.self) { shell in
            commandButton(for: shell)
          }
        }
        .padding(.top, 6)
      }
    )
    .onAppear {
      control.refreshTerminalCommands()
    }
    .onDisappear {
      feedbackTask?.cancel()
      feedbackTask = nil
      copiedShell = nil
    }
  }

  /// 菜单项副标题：接口名称 + IPv6 类型注记（ifconfig 同源），注记在前便于
  /// 先辨认地址类型；无注记时仅接口名称。
  private func menuSubtitle(for candidate: TerminalCommandAddress) -> String {
    guard let annotation = candidate.annotation else { return candidate.displayName }
    return "\(annotation) - \(candidate.displayName)"
  }

  private func commandButton(for shell: TerminalCommandShell) -> some View {
    let isCopied = copiedShell == shell
    let expectedAddress = control.snapshot.commandAddressPicker.selected.identity
    return Button {
      copy(shell, expectedAddress: expectedAddress)
    } label: {
      HStack(spacing: 10) {
        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
          .foregroundStyle(isCopied ? Color.green : Color.accentColor)
        Text(isCopied ? "已复制" : shell.title)
          .font(.callout.weight(.medium))
          .foregroundStyle(.primary)
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      .quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous)
    )
    .disabled(control.snapshot.terminalProxyEnvironmentCommands.failure != nil)
    .help(shell.command(from: control.snapshot.terminalProxyEnvironmentCommands))
  }

  private func copy(_ shell: TerminalCommandShell, expectedAddress: TerminalCommandAddressIdentity)
  {
    do {
      let commands = try control.prepareTerminalCommandsForCopy(expectedAddress: expectedAddress)
      try clipboard.write(shell.command(from: commands))
      feedbackTask?.cancel()
      copiedShell = shell
      feedbackTask = Task { @MainActor in
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        guard !Task.isCancelled, copiedShell == shell else { return }
        copiedShell = nil
        feedbackTask = nil
      }
    } catch {
      feedbackTask?.cancel()
      feedbackTask = nil
      copiedShell = nil
      errors.present(error)
    }
  }
}

extension TerminalCommandShell {
  fileprivate var title: String {
    switch self {
    case .zshBash: "zsh / bash"
    case .fish: "fish"
    case .nushell: "Nushell"
    case .windowsCMD: "Windows：CMD"
    case .windowsPowerShell: "Windows：PowerShell"
    }
  }
}
