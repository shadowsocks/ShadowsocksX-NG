import Foundation

// MARK: - 导入模型（docs/design/unified-server-import.md，ADR-0027）
//
// 导入域的 seam 类型：统一导入管线实现在 CatalogWorkflow+Import.swift，
// Legacy 编排在 CatalogWorkflow+Legacy.swift；typed 文案归 presentation edge。

/// 导入来源：剪贴板文本或单个文件。文件类型按内容嗅探分派（图片→二维码、
/// JSON 对象→SIP-008、其余→ss:// 文本行）；来源是独立解码、独立提交与
/// 结果报告的粒度单位。
enum ImportSource: Equatable, Sendable {
  case clipboardText(String)
  case file(name: String, data: Data)
}

/// 一次导入的逐来源结果聚合；来源之间互不影响。不标 Sendable：携带的
/// 提交失败携带 `any Error`（管线与 UI 同在
/// 主 actor，无跨域传递）。
struct ImportRunOutcome {
  let sources: [ImportSourceOutcome]
  /// 最后一个成功来源创建的节点；供收藏页导入后进入本地列表。
  var newNodeSelectionCandidate: NodeID?

  /// 成功来源中的落点/新建分组（最后一个），供导入后选中；nil 表示无可
  /// 选中目标（全部失败，或只导入了目录根层的文本来源）。
  var selectionCandidate: NodeID? {
    sources.compactMap { outcome -> NodeID? in
      if case .imported(_, let groupID) = outcome.result { return groupID }
      return nil
    }.last
  }
}

struct ImportSourceOutcome {
  let source: ImportSource
  let result: ImportSourceResult
}

/// 单来源结果；整体失败时不产生任何目录变更。非 Equatable：提交失败携带
/// 底层 `any Error`，测试
/// 逐 case 模式匹配。
enum ImportSourceResult {
  /// 全部导入成功。`groupID` 为新建根分组（SIP-008 来源）或落点分组
  /// （文本来源），nil 表示目录根。
  case imported(count: Int, groupID: NodeID?)
  /// 文本行部分成功：可解析行已全部添加，失败行逐条点名。
  case partial(addedCount: Int, failures: [ImportLineFailure])
  case failed(ImportSourceFailure)
}

/// 来源级失败（typed，无成句文案；呈现归 presentation edge）。
enum ImportSourceFailure: Error {
  /// SIP-008 文档解析失败（整份拒绝）。
  case parse(SubscriptionParseError)
  /// 图片不是可解码位图。
  case undecodableImage
  /// 二维码图片中没有 ss:// 负载。
  case qrPayloadNotFound
  /// 文本来源没有可解析的行（空文本）。
  case noImportableLines
  /// 服务器库提交失败；已提交值保持不变。
  case commit(any Error)
}

/// 文本行导入的逐行失败（ss:// 文本与剪贴板来源共用）。
struct ImportLineFailure: Equatable {
  /// 失败行在输入文本按换行切分后的下标（0 起）。
  let lineIndex: Int
  let reason: ImportLineFailureReason
}

enum ImportLineFailureReason: Equatable, Error {
  case decode(SsUriError)
}

/// Legacy 快照发现与完成标记：跳过不写标记，显式再导入仍
/// 创建新的独立手动分组。首启主动弹窗已移除，发现状态仅供导入面板的
/// Legacy 入口显隐。
struct LegacyImportAvailability: Equatable {
  let snapshotFound: Bool
  let completed: Bool
}
