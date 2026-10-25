import SwiftUI

/// 服务器表单通过目录事实解释名称引用；参数草稿独立于插件来源。
struct ServerPluginSection: View {
  @Binding var selection: PluginSelection
  @ObservedObject var options: PluginOptionsDraft
  let plugin: PluginSectionState?
  let isEditable: Bool
  /// 参数字段的行内校验错误（字节超限或未完成行）。
  let optionsError: ServerFormFieldError?
  let optionsFocus: FocusState<ServerFormField?>.Binding

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      picker
      detail
    }
  }

  @ViewBuilder
  private var picker: some View {
    if let plugin {
      Picker("插件", selection: $selection) {
        Text("无").tag(PluginSelection.none)
        ForEach(plugin.programs.map(\.program), id: \.self) { program in
          Text(program).tag(
            selection == .unknown(program: program)
              ? selection : PluginSelection.named(program: program))
        }
        if let program = plugin.unresolvedProgram(for: selection) {
          Text(program).tag(selection)
        }
        if plugin.selection != selection,
          let program = plugin.unresolvedProgram(for: plugin.selection)
        {
          Text(program).tag(plugin.selection)
        }
      }
      .disabled(!isEditable)
    } else {
      LabeledContent("插件") {
        Text("不可用").foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private var detail: some View {
    if let plugin {
      switch selection {
      case .none:
        EmptyView()
      case .named(let program), .unknown(let program):
        if plugin.unresolvedProgram(for: selection) != nil {
          unknownNotice(program: program, plugin: plugin)
        } else {
          namedPluginDetails(program: program, plugin: plugin)
        }
      }
    }
  }

  /// 目录中的名称引用：参数编辑区与可用性警告；订阅只读走独立只读视图。
  @ViewBuilder
  private func namedPluginDetails(program: String, plugin: PluginSectionState) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      availabilityNotice(program: program, plugin: plugin)
      Text("插件参数")
        .font(.callout.weight(.medium))
        .foregroundStyle(.secondary)
      if isEditable {
        PluginOptionsEditor(
          draft: options,
          fieldError: optionsError,
          fieldFocus: optionsFocus)
      } else {
        PluginOptionsReadOnlyEditor(draft: options)
      }
    }
  }

  /// 集外引用：原样保留并明确指出当前 app 无法提供该插件。
  @ViewBuilder
  private func unknownNotice(program: String, plugin: PluginSectionState) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if plugin.mappingsUnreadable {
        availabilityNotice(program: program, plugin: plugin)
      } else {
        warning(Text("未找到插件“\(program)”。引用和已保存参数将保留；可添加同名用户插件，或改选其他插件或“无”。"))
      }
      if plugin.optionsPresent {
        Text("插件参数已配置（存于钥匙串，原样保留）。")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private func availabilityNotice(program: String, plugin: PluginSectionState) -> some View {
    if let message = plugin.availabilityWarning(for: program) {
      warning(Text(message))
    }
  }

  private func warning(_ text: Text) -> some View {
    Label {
      text
    } icon: {
      Image(systemName: "exclamationmark.triangle.fill")
    }
    .font(.footnote)
    .foregroundStyle(.orange)
  }
}

/// 查看模式切换（参数列表 ⇄ 原始文本）；被未完成行拒绝时回弹到当前模式。
struct PluginOptionsModePicker: View {
  @ObservedObject var draft: PluginOptionsDraft
  @State private var displayedMode = PluginOptionsDraft.Mode.table

  var body: some View {
    Picker("查看模式", selection: modeBinding) {
      Text("参数列表").tag(PluginOptionsDraft.Mode.table)
      Text("原始文本").tag(PluginOptionsDraft.Mode.rawText)
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .onChange(of: draft.mode) { _, mode in
      displayedMode = mode
    }
  }

  private var modeBinding: Binding<PluginOptionsDraft.Mode> {
    Binding(
      get: { displayedMode },
      set: { requested in
        displayedMode = requested
        // macOS 分段 Picker 在 SwiftUI 更新事务内调用绑定 setter；草稿的
        // @Published 更新须离开该事务，避免向观察视图同步发布变更。
        Task { @MainActor in
          let succeeded =
            requested == .rawText ? draft.switchToRawText() : draft.switchToTable()
          displayedMode = succeeded ? requested : draft.mode
        }
      })
  }
}

/// 插件参数编辑区：Table 布局的无边框输入行——行首「值/开关」
/// 分段选择器决定行的值形态，底部空行即快速添加入口，长值经「编辑值…」
/// 独立编辑；切换查看模式不触发表单变更检测。
