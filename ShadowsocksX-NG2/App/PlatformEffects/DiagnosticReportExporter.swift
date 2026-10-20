import Foundation

/// 脱敏报告草稿离开 DiagnosticsWorkflow 后的用户选择与写入 seam。报告内容、
/// 脱敏策略与导出完成事件仍由诊断工作流/呈现层拥有。
@MainActor
protocol DiagnosticReportExporter {
  func export(draft: DiagnosticReportDraft) -> DiagnosticReportExportResult
}

enum DiagnosticReportExportFailure: Equatable, Error {
  case writeFailed
}

enum DiagnosticReportExportResult: Equatable {
  case cancelled
  case saved(URL)
  case failed(DiagnosticReportExportFailure)
}

/// 诊断导出动作只编排阶段，不拥有 AppKit 文件效果，也不登记完成事件。调用方
/// 必须只在 `.saved` 后调用 `DiagnosticsWorkflow.noteExportCompleted`。
enum DiagnosticReportExportOutcome: Equatable {
  case preparationFailed(DiagnosticReportFailure)
  case cancelled
  case saved(URL)
  case exportFailed(DiagnosticReportExportFailure)
}

@MainActor
struct DiagnosticReportExportAction {
  let diagnostics: DiagnosticsWorkflow
  let exporter: any DiagnosticReportExporter

  func perform() -> DiagnosticReportExportOutcome {
    switch diagnostics.prepareReport() {
    case .failed(let failure):
      return .preparationFailed(failure)
    case .ready(let draft):
      switch exporter.export(draft: draft) {
      case .cancelled:
        return .cancelled
      case .saved(let url):
        return .saved(url)
      case .failed(let failure):
        return .exportFailed(failure)
      }
    }
  }
}
