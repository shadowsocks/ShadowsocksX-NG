import AppKit
import Foundation
import UniformTypeIdentifiers

/// 二维码图片保存的用户选择与文件写入边界；PNG 数据与建议文件名由 UI 准备。
/// 命名用「保存/ saver」而不用导出（导出术语保留给配置组与诊断报告文件快照，
/// GLOSSARY.md）。
@MainActor
protocol QrImageSaver {
  func save(_ draft: QrImageSaveDraft) -> QrImageSaveResult
}

struct QrImageSaveDraft: Equatable {
  /// 二维码 PNG 数据；字段名与 ConfigurationGroupExportDraft.data 同法，
  /// 使文件写入调用命中架构守卫的 `.data.write(to:` 聚焦 token。
  let data: Data
  let suggestedFileName: String

  /// 保存面板默认文件名：显示名中的路径非法字符（/ 与 :）替换为空格并去首尾
  /// 空白，清洗后为空回退固定名，保证面板总有可编辑的初始名。
  static func suggestedFileName(from displayName: String) -> String {
    let cleaned =
      displayName
      .replacingOccurrences(of: "/", with: " ")
      .replacingOccurrences(of: ":", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let base = cleaned.isEmpty ? "ss-qrcode" : cleaned
    return "\(base).png"
  }
}

enum QrImageSaveFailure: Equatable, Error {
  case writeFailed
}

enum QrImageSaveResult: Equatable {
  case cancelled
  case saved(URL)
  case failed(QrImageSaveFailure)
}

/// 生产文件边界：PNG 保存面板与原子文件写入集中在此 AppKit adapter。
@MainActor
final class AppKitQrImageSaver: QrImageSaver {
  func save(_ draft: QrImageSaveDraft) -> QrImageSaveResult {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.nameFieldStringValue = draft.suggestedFileName
    guard panel.runModal() == .OK, let url = panel.url else {
      return .cancelled
    }

    do {
      try draft.data.write(to: url, options: .atomic)
      return .saved(url)
    } catch {
      return .failed(.writeFailed)
    }
  }
}
