import Foundation

/// 统一导入的逐来源结果 → 呈现行（本地化在呈现边缘
/// 完成）。失败明细不回显原始行内容（ss:// 行内嵌 base64 密码），
/// 文本来源以行号定位；原始文本就在剪贴板/文件里，行号足以定位。
enum ImportOutcomePresentation {
  static func row(for outcome: ImportSourceOutcome, targetName: String) -> ImportResultRow {
    let sourceName = sourceDisplayName(outcome.source)
    switch outcome.result {
    case .imported(let count, _):
      return ImportResultRow(
        sourceName: sourceName,
        title: String(localized: "已导入 \(count) 台服务器到「\(targetName)」"),
        details: [],
        style: .success)
    case .partial(let addedCount, let failures):
      return ImportResultRow(
        sourceName: sourceName,
        title: String(localized: "已添加 \(addedCount) 台服务器；以下条目无法解析"),
        details: failures.map {
          String(localized: "第 \($0.lineIndex + 1) 行：\($0.reason.presentableMessage)")
        },
        style: .partial)
    case .failed(let failure):
      return ImportResultRow(
        sourceName: sourceName,
        title: failure.presentableMessage,
        details: [],
        style: .failure)
    }
  }

  /// Legacy 导入报告 → 结果行（与 Legacy 专属表单时代的报告同口径）。
  static func row(for report: LegacyImportReport) -> ImportResultRow {
    let imported = report.importedServerCount
    let skipped = report.skippedRecords.count
    let regenerated = report.regeneratedIdentityCount
    var details = [
      String(
        localized:
          "统计：导入 \(imported) 台，跳过 \(skipped) 条，身份重生成 \(regenerated) 个。"
      )
    ]
    if report.regeneratedIdentityCount > 0 {
      let count = report.regeneratedIdentityCount
      details.append(
        String(localized: "有 \(count) 台服务器因 UUID 缺失、无效、重复或冲突而生成了新身份。"))
    }
    details.append(
      contentsOf: report.skippedRecords.map { record in
        String(
          localized:
            "第 \(record.index + 1) 条（\(record.description)）：\(record.reason.presentableMessage)")
      })
    return ImportResultRow(
      sourceName: legacySourceName,
      title: String(localized: "已导入 \(report.importedServerCount) 台服务器到「\(report.groupName)」"),
      details: details,
      style: report.skippedRecords.isEmpty ? .success : .partial)
  }

  /// Legacy 导入抛错（无快照、提交失败等）→ 失败结果行。
  static func failureRow(_ error: Error, sourceName: String? = nil) -> ImportResultRow {
    ImportResultRow(
      sourceName: sourceName ?? legacySourceName,
      title: error.presentableMessage,
      details: [],
      style: .failure)
  }

  /// 文件内容读取失败（面板读盘早于管线）→ 失败结果行。
  static func unreadableFileRow(fileName: String) -> ImportResultRow {
    ImportResultRow(
      sourceName: fileName,
      title: String(localized: "文件无法读取"),
      details: [],
      style: .failure)
  }

  static var legacySourceName: String { String(localized: "旧版本 ShadowsocksX-NG") }

  static func sourceDisplayName(_ source: ImportSource) -> String {
    switch source {
    case .clipboardText: return String(localized: "剪贴板")
    case .file(let name, _): return name
    }
  }
}

/// 统一导入面板的逐来源结果行（非敏感；明细为行号/统计与 typed 文案）。
struct ImportResultRow: Identifiable, Equatable {
  enum Style: Equatable {
    case success
    case partial
    case failure
  }

  let id = UUID()
  let sourceName: String
  let title: String
  let details: [String]
  let style: Style
}
