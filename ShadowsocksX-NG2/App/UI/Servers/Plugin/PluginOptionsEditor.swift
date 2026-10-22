import SwiftUI

struct PluginOptionsEditor: View {
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
            Text(row.kind == .flag ? String(localized: "开关") : String(localized: "值"))
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
