import Foundation

/// 用户主动触发的纯文本剪贴板 seam。读取不到文本是正常的空状态；只有写入
/// 失败才产生 typed failure。URI 解析、分享策略与敏感信息判断不属于此协议。
@MainActor
protocol TextClipboard {
  func read() -> String?
  func write(_ text: String) throws
}

enum TextClipboardFailure: Equatable, Error {
  case writeFailed
}
