import Foundation

/// agent.log 尾部读取（够诊断即可）：只取文件末尾有限字节并按行
/// 对齐，供主窗口日志查看器呈现。内容只进查看器，永不进入诊断导出；导出类目
/// 不含日志正文，wrapper/sslocal 的原始输出也不经本产品脱敏管线。
enum AgentLogTail {
  /// 文件缺失或不可读返回 nil；内容按 UTF-8 宽容解码，起始半行丢弃。
  static func readLastLines(of url: URL, maxBytes: Int = 64 * 1024) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    let size = (try? handle.seekToEnd()) ?? 0
    let window = min(UInt64(max(1, maxBytes)), size)
    try? handle.seek(toOffset: size - window)
    let data = (try? handle.read(upToCount: Int(window))) ?? Data()
    guard !data.isEmpty else { return nil }
    // 窗口边界可能切断多字节字符：有意宽容解码，坏字节替换而非丢弃整段。
    // swiftlint:disable:next optional_data_string_conversion
    var text = String(decoding: data, as: UTF8.self)
    if window < size, let firstNewline = text.firstIndex(of: "\n") {
      text.removeSubrange(text.startIndex...firstNewline)
    }
    return text
  }
}
