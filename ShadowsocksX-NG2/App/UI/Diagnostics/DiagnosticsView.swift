import SwiftUI

/// 独立窗口诊断区：状态摘要卡、日志卡与脱敏说明行。
/// 为状态摘要卡（代理状态、活动目标）+ 日志卡（GUI 事件、wrapper 与
/// sslocal 行经日志视图 intake 归一为一个按时间排序的列表，级别与来源
/// 过滤、可复制）+ 底部脱敏说明行。导出诊断由
/// 本页自挂工具栏（呈现于窗口工具栏右端），沿用 DiagnosticReportExportAction
/// 既有入口，成功 alert 与错误弹窗均在本视图挂载。事实采样、轮询代际与报告
/// 准备全部经 DiagnosticsWorkflow 这一 UI-facing seam；本视图
/// 只负责生命周期触发、呈现与复制动作。
struct DiagnosticsView: View {
  @ObservedObject var diagnostics: DiagnosticsWorkflow
  @ObservedObject var windowState: DiagnosticsWindowState
  let clipboard: any TextClipboard
  let exporter: any DiagnosticReportExporter

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        summaryRow
        logCard
        Text(
          "诊断导出只包含状态、存在性、权限和脱敏元数据，不包含密码、插件参数、订阅 URL 或运行时 JSON。"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }
      .frame(maxWidth: 960, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.leading, 28)
      .padding(.trailing, 32)
      .padding(.top, 24)
      .padding(.bottom, 36)
    }
    .frame(minWidth: 640, minHeight: 520)
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

  // MARK: - 状态摘要

  private var summaryRow: some View {
    HStack(alignment: .top, spacing: 14) {
      statCard(
        String(localized: "代理状态"),
        value: AppPresentation.diagnosticStatus(diagnostics.summary.proxyState))
      statCard(
        String(localized: "活动目标"),
        value: diagnostics.summary.hasActiveTarget
          ? String(localized: "已设置") : String(localized: "未设置"))
    }
  }

  private func statCard(_ label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.callout.weight(.semibold))
        .lineLimit(2)
        .help(value)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
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
        .frame(width: 220)
        Picker("日志来源", selection: $windowState.filter.source) {
          Text("全部").tag(DiagnosticLogFilter.Source.all)
          Text("GUI").tag(DiagnosticLogFilter.Source.gui)
          Text("wrapper").tag(DiagnosticLogFilter.Source.wrapper)
          Text("sslocal").tag(DiagnosticLogFilter.Source.sslocal)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 240)
        Spacer(minLength: 12)
        Button {
          copyToClipboard(visibleText)
        } label: {
          Label("复制", systemImage: "doc.on.doc")
        }
        .disabled(visibleText.isEmpty)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      Divider()
      logBox
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

  /// 当前过滤条件下的可见行文本（呈现与复制共用同一可见集）。
  private var visibleText: String {
    windowState.filter.apply(diagnostics.logView.rows).map(\.rendered).joined(separator: "\n")
  }

  /// 空态提示：无过滤时提示如何产生日志；过滤后只提示过滤条件。
  private var emptyMessage: String {
    if windowState.filter == DiagnosticLogFilter() {
      return String(
        localized: "暂无日志；开关代理或激活服务器后，GUI 事件、wrapper 与 sslocal 的日志行会实时出现在这里。")
    }
    return String(localized: "当前过滤条件下没有日志行。")
  }

  private var logBox: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 2) {
        if visibleText.isEmpty {
          Text(emptyMessage)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(16)
        } else {
          Text(visibleText)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(minHeight: 300, maxHeight: 390)
  }

  private func copyToClipboard(_ text: String) {
    do {
      try clipboard.write(text)
    } catch {
      windowState.errors.present(error)
    }
  }
}
