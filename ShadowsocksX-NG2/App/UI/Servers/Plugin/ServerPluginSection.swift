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
private struct PluginOptionsEditor: View {
  @ObservedObject var draft: PluginOptionsDraft
  let fieldError: ServerFormFieldError?
  let fieldFocus: FocusState<ServerFormField?>.Binding

  struct EditingValue: Identifiable {
    let id: UUID
    let text: String
  }

  @State private var editingValue: EditingValue?
  @FocusState private var focusedRowID: UUID?
  @FocusState private var focusedValueRowID: UUID?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      PluginOptionsModePicker(draft: draft)
      switch draft.mode {
      case .table:
        tableView
      case .rawText:
        rawTextView
      }
      fieldErrorLabel
    }
    .onChange(of: fieldError) { _, error in
      // 首错定位：未完成行时聚焦第一行的参数名。
      if case .unfinishedPluginOptionRow = error,
        let first = draft.rows.first(where: \.isUnfinished)
      {
        focusedRowID = first.id
      }
    }
    .sheet(item: $editingValue) { value in
      PluginOptionValueEditorSheet(initialText: value.text) { newValue in
        draft.updateValue(newValue, of: value.id)
      }
    }
  }

  // MARK: - 参数列表（Table 布局）

  private var tableView: some View {
    // 无排序 Table 的列泛型固定为 Never，TableColumn 初值的 width:/value:
    // 参数接不上（实测 macOS 15 SDK）；列宽经实例方法 width(min:ideal:max:)
    // 表达：类型/操作列定宽、参数名列限宽、值列无约束弹性吸收剩余宽度。
    Table(draft.rows) {
      TableColumn("类型") { row in
        Picker(
          "参数类型",
          selection: Binding(
            get: { row.kind },
            set: { draft.setKind($0, of: row.id) })
        ) {
          Text("值").tag(PluginOptionsDraft.Kind.keyValue)
          Text("开关").tag(PluginOptionsDraft.Kind.flag)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
      }
      .width(min: 96, ideal: 96, max: 96)
      TableColumn("参数名") { row in
        HStack(spacing: 4) {
          TextField(
            "参数名",
            text: Binding(
              get: { row.keyText },
              set: { draft.updateKey($0, of: row.id) })
          )
          .textFieldStyle(.plain)
          .focused($focusedRowID, equals: row.id)
          if row.isUnfinished {
            Image(systemName: "exclamationmark.circle.fill")
              .font(.caption)
              .foregroundStyle(.red)
              .help("缺少参数名")
          }
        }
      }
      .width(min: 72, ideal: 96, max: 140)
      TableColumn("值") { row in
        TextField(
          "值",
          text: Binding(
            get: { row.valueText },
            set: { draft.updateValue($0, of: row.id) })
        )
        .textFieldStyle(.plain)
        .lineLimit(1)
        .truncationMode(.tail)
        .disabled(row.kind == .flag)
        .focused($focusedValueRowID, equals: row.id)
      }
      TableColumn("操作") { row in
        HStack(spacing: 8) {
          Button {
            draft.moveRow(row.id, by: -1)
          } label: {
            Image(systemName: "chevron.up")
          }
          .buttonStyle(.borderless)
          .help("上移")
          .disabled(!draft.canMoveRow(row.id, by: -1))

          Button {
            draft.moveRow(row.id, by: 1)
          } label: {
            Image(systemName: "chevron.down")
          }
          .buttonStyle(.borderless)
          .help("下移")
          .disabled(!draft.canMoveRow(row.id, by: 1))

          Button {
            editingValue = EditingValue(id: row.id, text: row.valueText)
          } label: {
            Label("编辑值…", systemImage: "square.and.pencil")
          }
          .buttonStyle(.borderless)
          .disabled(row.kind == .flag)

          Button {
            draft.deleteRow(row.id)
          } label: {
            Label("删除", systemImage: "trash")
          }
          .buttonStyle(.borderless)
        }
      }
      .width(min: 196, ideal: 208, max: 224)
    }
    .tableStyle(.inset)
    .frame(height: editTableHeight)
  }

  /// 行数驱动的表格高度：单行约 30pt，夹在上下限之间。
  private var editTableHeight: CGFloat {
    max(min(52 + CGFloat(draft.rows.count) * 30, 440), 112)
  }

  // MARK: - 原始文本

  private var rawTextView: some View {
    TextEditor(text: $draft.rawText)
      .font(.system(.body, design: .monospaced))
      .frame(minHeight: 76, maxHeight: 152)
      .autocorrectionDisabled()
      .focused(fieldFocus, equals: .pluginOptions)
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(Color(nsColor: .separatorColor))
      )
  }

  // MARK: - 字段错误

  @ViewBuilder
  private var fieldErrorLabel: some View {
    switch fieldError {
    case .tooManyBytes(let limit):
      Text("插件参数最多 \(limit) 个字节")
        .font(.footnote)
        .foregroundStyle(.red)
    case .unfinishedPluginOptionRow:
      Text("存在未完成的参数行：请补全参数名、清空该行或删除它")
        .font(.footnote)
        .foregroundStyle(.red)
    case .missingName, .tooManyCharacters, .invalidPort, nil:
      EmptyView()
    }
  }
}

/// 订阅节点的参数只读呈现：Table 控件的表格展现与原始文本
/// 只读，可切换查看模式，无任何编辑入口。
struct PluginOptionsReadOnlyEditor: View {
  @ObservedObject var draft: PluginOptionsDraft

  private var visibleRows: [PluginOptionsDraft.Row] {
    draft.rows.filter { !$0.isBlank }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      PluginOptionsModePicker(draft: draft)
      switch draft.mode {
      case .table:
        Table(visibleRows) {
          TableColumn("参数名") { row in
            Text(row.keyText)
              .lineLimit(1)
              .truncationMode(.tail)
              .textSelection(.enabled)
          }
          .width(min: 72, ideal: 120, max: 220)
          TableColumn("值") { row in
            // 值单元格单行展示、尾部省略；完整内容保留在草稿与无障碍读取中。
            Text(row.valueText)
              .lineLimit(1)
              .truncationMode(.tail)
              .textSelection(.enabled)
          }
          TableColumn("类型") { row in
            Text(row.kind == .flag ? "开关" : "值")
              .foregroundStyle(.secondary)
          }
          .width(min: 48, ideal: 56, max: 64)
        }
        .tableStyle(.inset)
        .frame(height: readOnlyTableHeight)
      case .rawText:
        ScrollView {
          Text(draft.rawText)
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(minHeight: 76, maxHeight: 152)
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .stroke(Color(nsColor: .separatorColor))
        )
      }
    }
  }

  private var readOnlyTableHeight: CGFloat {
    max(min(48 + CGFloat(visibleRows.count) * 28, 400), 96)
  }
}

/// 长值独立编辑：等宽多行、初始约四行最多约八行后内部纵向
/// 滚动；只有「确认」写回父表单草稿，取消保留之前的值。
private struct PluginOptionValueEditorSheet: View {
  let initialText: String
  let onConfirm: (String) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var text: String

  init(initialText: String, onConfirm: @escaping (String) -> Void) {
    self.initialText = initialText
    self.onConfirm = onConfirm
    _text = State(initialValue: initialText)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("值")
        .font(.headline)
      TextEditor(text: $text)
        .font(.system(.body, design: .monospaced))
        .frame(minHeight: 76, maxHeight: 152)
        .autocorrectionDisabled()
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .stroke(Color(nsColor: .separatorColor))
        )
      HStack {
        Spacer()
        Button("取消", role: .cancel) { dismiss() }
        Button("确认") {
          onConfirm(text)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(16)
    .frame(minWidth: 380, minHeight: 220)
  }
}
