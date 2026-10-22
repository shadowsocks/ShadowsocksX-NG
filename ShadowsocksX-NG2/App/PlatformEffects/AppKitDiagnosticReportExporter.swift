import AppKit
import UniformTypeIdentifiers

/// 生产诊断报告 exporter：只接收已由 DiagnosticsWorkflow 脱敏完成的草稿，负责
/// 保存面板与用户选定 URL 的文件写入。原始 NSError 不跨过此 adapter。
@MainActor
final class AppKitDiagnosticReportExporter: DiagnosticReportExporter {
  func export(draft: DiagnosticReportDraft) -> DiagnosticReportExportResult {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.plainText]
    panel.nameFieldStringValue = draft.suggestedFileName
    guard panel.runModal() == .OK, let url = panel.url else {
      return .cancelled
    }

    do {
      try draft.data.write(to: url)
      return .saved(url)
    } catch {
      return .failed(.writeFailed)
    }
  }
}
