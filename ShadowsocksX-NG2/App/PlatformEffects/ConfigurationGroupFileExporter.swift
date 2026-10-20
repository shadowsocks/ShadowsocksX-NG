import AppKit
import Foundation
import UniformTypeIdentifiers

/// 配置组 JSON / URI 列表草稿的文件写入边界；内容准备由 CatalogWorkflow 拥有。
@MainActor
protocol ConfigurationGroupFileExporter {
  func export(draft: ConfigurationGroupExportDraft) -> ConfigurationGroupFileExportResult
}

enum ConfigurationGroupFileExportFailure: Equatable, Error {
  case writeFailed
  case uriListWriteFailed
}

enum ConfigurationGroupFileExportResult: Equatable {
  case cancelled
  case saved(URL)
  case failed(ConfigurationGroupFileExportFailure)
}

enum ConfigurationGroupExportOutcome: Equatable {
  case preparationFailed(ConfigurationGroupExportFailure)
  case cancelled
  case saved(URL)
  case exportFailed(ConfigurationGroupFileExportFailure)
}

/// 先准备完整文档，再调用 exporter；准备失败时不会打开面板或接触文件效果。
@MainActor
struct ConfigurationGroupExportAction {
  let workflow: CatalogWorkflow
  let exporter: any ConfigurationGroupFileExporter

  func perform(for groupID: NodeID) -> ConfigurationGroupExportOutcome {
    let draft: ConfigurationGroupExportDraft
    do {
      draft = try workflow.configurationGroupExportDraft(for: groupID)
    } catch let failure as ConfigurationGroupExportFailure {
      return .preparationFailed(failure)
    } catch {
      return .preparationFailed(.documentEncodingFailed)
    }

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

/// 生产文件边界：JSON / UTF-8 文本保存面板与原子文件写入集中在 AppKit adapter。
@MainActor
final class AppKitConfigurationGroupFileExporter: ConfigurationGroupFileExporter {
  func export(draft: ConfigurationGroupExportDraft) -> ConfigurationGroupFileExportResult {
    let panel = NSSavePanel()
    panel.allowedContentTypes = draft.format == .json ? [.json] : [.plainText]
    panel.nameFieldStringValue = draft.suggestedFileName
    guard panel.runModal() == .OK, let url = panel.url else {
      return .cancelled
    }

    do {
      try draft.data.write(to: url, options: .atomic)
      return .saved(url)
    } catch {
      return .failed(draft.format == .json ? .writeFailed : .uriListWriteFailed)
    }
  }
}
