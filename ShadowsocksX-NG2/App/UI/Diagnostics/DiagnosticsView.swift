import SwiftUI

/// 独立诊断窗口：可筛选的日志表格与选中行详情。
/// 日志只在查看器中呈现；诊断导出继续通过 DiagnosticsWorkflow 准备脱敏报告。
struct DiagnosticsView: View {
  @ObservedObject var diagnostics: DiagnosticsWorkflow
  @ObservedObject var windowState: DiagnosticsWindowState
  let clipboard: any TextClipboard
  let exporter: any DiagnosticReportExporter

  @State private var selection: Set<DiagnosticLogEntry.ID> = []

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      logCard
      Text(
        "诊断导出只包含状态、存在性、权限和脱敏元数据，不包含密码、插件参数、订阅 URL 或运行时 JSON。"
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.leading, 28)
    .padding(.trailing, 32)
    .padding(.top, 24)
    .padding(.bottom, 36)
    .frame(minWidth: 800, minHeight: 520)
    .background(DiagnosticsWindowAnchor(state: windowState).frame(width: 0, height: 0))
    .task(id: windowState.isOpen) {
      if windowState.isOpen { await diagnostics.readWhileActive() }
    }
    .presentingErrors(windowState.errors)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("导出诊断…", systemImage: "square.and.arrow.up") {
          exportDiagnostics()
        }
      }
    }
    .alert(
      "诊断已导出",
      isPresented: Binding(
        get: { windowState.exportedDiagnosticsPath != nil },
        set: { if !$0 { windowState.exportedDiagnosticsPath = nil } })
    ) {
      Button("好", role: .cancel) {}
    } message: {
      Text(windowState.exportedDiagnosticsPath ?? "")
    }
  }

  /// 诊断导出：沿用 DiagnosticReportExportAction 既有入口；文件写
  /// 入成功后才登记导出完成事件。
  private func exportDiagnostics() {
    switch DiagnosticReportExportAction(
      diagnostics: diagnostics, exporter: exporter
    ).perform()
    {
    case .preparationFailed(let failure):
      windowState.errors.present(failure)
    case .cancelled:
      break
    case .saved(let url):
      diagnostics.noteExportCompleted()
      windowState.exportedDiagnosticsPath = url.path
    case .exportFailed(let failure):
      windowState.errors.present(failure)
    }
  }

  // MARK: - 日志卡

  private var logCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 12) {
        Picker("日志级别", selection: $windowState.filter.level) {
          Text("全部").tag(DiagnosticLogFilter.Level.all)
          Text("警告+错误").tag(DiagnosticLogFilter.Level.warnings)
          Text("仅错误").tag(DiagnosticLogFilter.Level.errors)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        Picker("日志来源", selection: $windowState.filter.source) {
          Text("全部").tag(DiagnosticLogFilter.Source.all)
          Text("GUI").tag(DiagnosticLogFilter.Source.gui)
          Text("wrapper").tag(DiagnosticLogFilter.Source.wrapper)
          Text("sslocal").tag(DiagnosticLogFilter.Source.sslocal)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        Spacer(minLength: 12)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      Divider()
      DiagnosticsLogSplitView {
        logTable
      } details: {
        logDetails
      }
      .frame(minHeight: 300, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      .background.secondary,
      in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(.quaternary)
    )
  }

  private var visibleRows: [DiagnosticLogEntry] {
    diagnostics.logView.entries.filter { windowState.filter.admits($0.line) }
  }

  private var selectedRows: [DiagnosticLogEntry] {
    visibleRows.filter { selection.contains($0.id) }
  }

  /// 空态提示：无过滤时提示如何产生日志；过滤后只提示过滤条件。
  private var emptyMessage: String {
    if windowState.filter == DiagnosticLogFilter() {
      return String(
        localized: "暂无日志；开关代理或激活服务器后，GUI 事件、wrapper 与 sslocal 的日志行会实时出现在这里。")
    }
    return String(localized: "当前过滤条件下没有日志行。")
  }

  private var logTable: some View {
    let rows = visibleRows
    let selected = selectedRows
    return Table(rows, selection: $selection) {
      TableColumn("时间") { row in
        Text(row.tableTimestampText)
          .help(row.timestampText)
      }
      .width(min: 90, ideal: 105)
      TableColumn("日志级别") { row in
        Text(row.line.level.rawValue)
      }
      .width(min: 60, ideal: 70)
      TableColumn("分类") { row in
        Text(row.sourceText)
      }
      .width(min: 60, ideal: 70)
      TableColumn("消息") { row in
        Text(row.line.text)
      }
      .width(min: 160, ideal: 520)
    }
    .font(.system(size: 11, design: .monospaced))
    .lineLimit(1)
    .truncationMode(.tail)
    .onCopyCommand(
      perform: selected.isEmpty
        ? nil
        : {
          [
            NSItemProvider(
              object: selected.map(\.line.rendered).joined(separator: "\n") as NSString)
          ]
        }
    )
    .contextMenu(forSelectionType: DiagnosticLogEntry.ID.self) { ids in
      Button("复制") {
        copyToClipboard(
          rows.filter { ids.contains($0.id) }.map(\.line.rendered).joined(separator: "\n"))
      }
      .disabled(ids.isEmpty)
    }
    .onChange(of: rows.map(\.id)) { _, ids in
      selection.formIntersection(ids)
    }
    .overlay {
      if rows.isEmpty {
        Text(emptyMessage)
          .font(.callout)
          .foregroundStyle(.secondary)
          .padding(16)
          .allowsHitTesting(false)
      }
    }
  }

  private var logDetails: some View {
    let selected = selectedRows
    return ScrollView {
      if selected.count == 1, let row = selected.first {
        VStack(alignment: .leading, spacing: 12) {
          LabeledContent("时间", value: row.timestampText)
          LabeledContent("日志级别", value: row.line.level.rawValue)
          LabeledContent("分类", value: row.sourceText)
          Divider()
          Text("消息")
            .font(.headline)
          Text(row.line.text)
            .font(.system(size: 11, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .textSelection(.enabled)
        .padding(16)
      } else {
        Group {
          if selected.isEmpty {
            Text("选择日志查看详情")
          } else {
            Text("已选择 \(selected.count) 条日志")
          }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
      }
    }
  }

  private func copyToClipboard(_ text: String) {
    do {
      try clipboard.write(text)
    } catch {
      windowState.errors.present(error)
    }
  }
}

extension DiagnosticLogEntry {
  private static let tableTimestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
  }()

  var tableTimestampText: String {
    line.timestamp.map { Self.tableTimestampFormatter.string(from: $0) } ?? "—"
  }

  var timestampText: String {
    line.timestamp.map { LogLine.timestampFormatter.string(from: $0) } ?? "—"
  }

  var sourceText: String { line.source == .gui ? "GUI" : line.source.rawValue }
}
