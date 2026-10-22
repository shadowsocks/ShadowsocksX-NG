import Foundation

@testable import ShadowsocksX_NG2

/// 导出缝的测试替身：记录收到的 draft，但不打开保存面板、不写文件。
@MainActor
final class InMemoryDiagnosticReportExporter: DiagnosticReportExporter {
  var result: DiagnosticReportExportResult
  private(set) var drafts: [DiagnosticReportDraft] = []

  init(result: DiagnosticReportExportResult = .cancelled) {
    self.result = result
  }

  func export(draft: DiagnosticReportDraft) -> DiagnosticReportExportResult {
    drafts.append(draft)
    return result
  }
}

/// 配置组文件导出缝的测试替身：同上，只记录 draft 并返回预设结果。
@MainActor
final class InMemoryConfigurationGroupFileExporter: ConfigurationGroupFileExporter {
  var result: ConfigurationGroupFileExportResult
  private(set) var drafts: [ConfigurationGroupExportDraft] = []

  init(result: ConfigurationGroupFileExportResult = .cancelled) {
    self.result = result
  }

  func export(draft: ConfigurationGroupExportDraft) -> ConfigurationGroupFileExportResult {
    drafts.append(draft)
    return result
  }
}
