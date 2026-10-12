import SwiftUI

/// 「复制代理环境变量设置命令」卡：按所选 shell 格式复制 HTTP 与 SOCKS 环境变量。
/// 非「仅本机」监听方式下先以单选下拉框选择命令地址，两种 shell
/// 的全部代理端点共用该选择；仅本机方式隐藏下拉框并始终使用回环地址。
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
          commandButton(for: .zshBash)
          commandButton(for: .fish)
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
    return Button {
      copy(shell)
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
    .help(shell.command(from: control.snapshot.terminalProxyEnvironmentCommands))
  }

  private func copy(_ shell: TerminalCommandShell) {
    // 复制前刷新：失效选择回退后的命令即剪贴板内容，与按钮
    // 提示保持同一选择。
    let commands = control.refreshTerminalCommands()
    do {
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

private enum TerminalCommandShell: Equatable {
  case zshBash
  case fish

  var title: String {
    switch self {
    case .zshBash: "zsh / bash"
    case .fish: "fish"
    }
  }

  func command(from commands: TerminalProxyEnvironmentCommands) -> String {
    switch self {
    case .zshBash: commands.zshBash
    case .fish: commands.fish
    }
  }
}

/// 「快速操作」卡：更新全部订阅。
struct QuickActionCard: View {
  @ObservedObject var workflow: CatalogWorkflow

  @State private var isRefreshingAll = false

  var body: some View {
    HomeCard(
      title: "快速操作",
      subtitle: nil,
      trailing: { EmptyView() },
      content: {
        VStack(spacing: 10) {
          QuickActionButton(
            icon: "arrow.triangle.2.circlepath",
            title: isRefreshingAll ? "正在更新…" : "更新全部订阅",
            help: nil,
            action: refreshAll
          )
          .disabled(workflow.subscriptions.isEmpty || isRefreshingAll)
          if isRefreshingAll {
            ProgressView()
              .controlSize(.small)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding(.top, 6)
      })
  }

  private func refreshAll() {
    isRefreshingAll = true
    Task {
      await workflow.refreshAllSubscriptions()
      isRefreshingAll = false
    }
  }

}
