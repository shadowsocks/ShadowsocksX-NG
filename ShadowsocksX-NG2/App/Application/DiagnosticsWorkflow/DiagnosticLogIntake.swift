import Foundation

/// 日志视图 intake（诊断日志查看器的唯一行来源）：把两个原始面——GUI 事件
/// 环形缓冲与 wrapper `agent.log` 尾部——归一成同一种行（`LogLine`）按时间
/// 归并。tail 窗口逻辑也收在这一处。raw 行只经显式查看/复制呈现，永不进入
/// 诊断报告（报告走 `RuntimeLogEvent` 白名单投影，ADR-0006）。
enum DiagnosticLogIntake {
  /// agent.log 尾部读取（够诊断即可）：只取文件末尾有限字节并按行
  /// 对齐。文件缺失或不可读返回 nil；内容按 UTF-8 宽容解码，起始半行丢弃。
  static func readTail(of url: URL, maxBytes: Int = 64 * 1024) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    let size = (try? handle.seekToEnd()) ?? 0
    let window = min(UInt64(max(1, maxBytes)), size)
    try? handle.seek(toOffset: size - window)
    var data = (try? handle.read(upToCount: Int(window))) ?? Data()
    guard !data.isEmpty else { return nil }
    if window < size, let firstNewline = data.firstIndex(of: 10) {
      data.removeSubrange(...firstNewline)
    }
    // 窗口边界可能切断多字节字符：有意宽容解码，坏字节替换而非丢弃整段。
    // swiftlint:disable:next optional_data_string_conversion
    return String(decoding: data, as: UTF8.self)
  }

  /// 归并行（旧→新）：GUI 事件行与 agent.log 尾部行统一按时间戳排序。
  /// 旧格式行（无法解析时间戳）排在最前并保持文件内顺序——它们来自升级前
  /// 落盘，时间未知。
  static func rows(events: [RuntimeEventStore.Entry], tail: String?) -> [LogLine] {
    var merged: [LogLine] = events.map { entry in
      LogLine(event: entry.event, timestamp: entry.timestamp, source: .gui)
    }
    merged.append(contentsOf: tailLines(tail))
    return merged.enumerated()
      .sorted { lhs, rhs in
        let left = lhs.element.timestamp ?? .distantPast
        let right = rhs.element.timestamp ?? .distantPast
        return left == right ? lhs.offset < rhs.offset : left < right
      }
      .map(\.element)
  }

  /// 尾部文本按行归一：统一行格式严格解析，旧格式行降级保留原文。空行是
  /// 行内容（raw 保真），只把结尾行分隔符排除在外。
  private static func tailLines(_ tail: String?) -> [LogLine] {
    guard let tail, !tail.isEmpty else { return [] }
    // 按 scalar 拆 LF：Swift Character 把 CRLF 合为一个字符，不能按单个 LF 匹配。
    var lines = tail.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false)
      .map(String.init)
    if tail.unicodeScalars.last == "\n" { lines.removeLast() }
    return lines.map { LogLine.parse($0) ?? LogLine.legacy($0) }
  }
}

/// 查看器行过滤（纯函数；UI 只做 chip 绑定）：级别三档与来源四档组合。
/// 复制跟随可见行，导出面不受过滤影响。
struct DiagnosticLogFilter: Equatable, Sendable {
  /// 级别档：全部 / 警告+错误 / 仅错误。
  enum Level: String, CaseIterable, Identifiable, Sendable {
    case all, warnings, errors

    var id: Self { self }

    func admits(_ level: LogLineLevel) -> Bool {
      switch self {
      case .all: return true
      case .warnings: return level != .info
      case .errors: return level == .error
      }
    }
  }

  /// 来源档：全部 / GUI 事件 / wrapper 事件 / sslocal 上游输出。
  enum Source: String, CaseIterable, Identifiable, Sendable {
    case all, gui, wrapper, sslocal

    var id: Self { self }

    func admits(_ source: LogLineSource) -> Bool {
      switch self {
      case .all: return true
      case .gui: return source == .gui
      case .wrapper: return source == .wrapper
      case .sslocal: return source == .sslocal
      }
    }
  }

  var level: Level = .all
  var source: Source = .all

  func apply(_ rows: [LogLine]) -> [LogLine] {
    rows.filter { level.admits($0.level) && source.admits($0.source) }
  }
}
