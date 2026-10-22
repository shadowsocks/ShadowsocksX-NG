import Foundation

/// 用户主动触发的图片剪贴板 seam：以 PNG 数据为规范输入写入剪贴板。生产
/// adapter 负责平台类型映射（PNG 之外附加哪些兼容类型），协议不感知；读取
/// 侧暂无消费者，协议不设 read。分享策略与二维码生成不属于此协议。
@MainActor
protocol ImageClipboard {
  func write(_ pngData: Data) throws
}

enum ImageClipboardFailure: Equatable, Error {
  case writeFailed
}
