import Darwin
import Foundation

/// 日志视图 intake（诊断日志查看器的唯一行来源）：把两个原始面——GUI 事件
/// 环形缓冲与 wrapper `agent.log` 尾部——归一成同一种行（`LogLine`）按时间
/// 归并。tail 窗口逻辑也收在这一处。raw 行只经显式查看/复制呈现，永不进入
/// 诊断报告（报告走 `RuntimeLogEvent` 白名单投影，ADR-0006）。
enum DiagnosticLogIntake {
  /// agent.log 尾部读取（够诊断即可）：只取文件末尾有限字节并按行
  /// 对齐。文件缺失或不可读返回 nil；内容按 UTF-8 宽容解码，起始半行丢弃。
  static func readTail(of url: URL, maxBytes: Int = 64 * 1024) -> String? {
    readTailSnapshot(of: url, maxBytes: maxBytes)?.text
  }

  /// 文件身份与每行的绝对字节位置随 tail 一起采样，窗口裁剪不改变保留行的身份。
  static func readTailSnapshot(of url: URL, maxBytes: Int = 64 * 1024) -> DiagnosticLogTail? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    var attributes = stat()
    guard fstat(handle.fileDescriptor, &attributes) == 0 else { return nil }
    let size = (try? handle.seekToEnd()) ?? 0
    let window = min(UInt64(max(1, maxBytes)), size)
    var offset = size - window
    try? handle.seek(toOffset: offset)
    var data = (try? handle.read(upToCount: Int(window))) ?? Data()
    guard !data.isEmpty else { return nil }
    if window < size, let firstNewline = data.firstIndex(of: 10) {
      offset += UInt64(firstNewline + 1)
      data.removeSubrange(...firstNewline)
    }
    return DiagnosticLogTail(
      data: data, fileID: UInt64(attributes.st_ino), offset: offset)
  }

  /// 归并行（旧→新）：GUI 事件行与 agent.log 尾部行统一按时间戳排序。
  /// 旧格式行（无法解析时间戳）排在最前并保持文件内顺序——它们来自升级前
  /// 落盘，时间未知。
  static func rows(events: [RuntimeEventStore.Entry], tail: String?) -> [LogLine] {
    entries(
      events: events,
      tail: tail.map { DiagnosticLogTail(text: $0, fileID: 0, offset: 0) }
    ).map(\.line)
  }

  static func entries(
    events: [RuntimeEventStore.Entry], tail: DiagnosticLogTail?
  ) -> [DiagnosticLogEntry] {
    var merged = events.map { entry in
      DiagnosticLogEntry(
        id: .gui(entry.id),
        line: LogLine(event: entry.event, timestamp: entry.timestamp, source: .gui))
    }
    merged.append(contentsOf: tailEntries(tail))
    return merged.enumerated()
      .sorted { lhs, rhs in
        let left = lhs.element.line.timestamp ?? .distantPast
        let right = rhs.element.line.timestamp ?? .distantPast
        return left == right ? lhs.offset < rhs.offset : left < right
      }
      .map(\.element)
  }

  /// 按原始字节拆 LF，保留 CR 和空行；无效 UTF-8 不影响后续行的文件位置。
  private static func tailEntries(_ tail: DiagnosticLogTail?) -> [DiagnosticLogEntry] {
    guard let tail, !tail.data.isEmpty else { return [] }
    var lines = tail.data.split(separator: 10, omittingEmptySubsequences: false)
    if tail.data.last == 10 { lines.removeLast() }
    var offset = tail.offset
    return lines.map { bytes in
      // 坏字节替换而非丢弃整行；位置仍按原始字节计数。
      // swiftlint:disable:next optional_data_string_conversion
      let raw = String(decoding: bytes, as: UTF8.self)
      defer { offset += UInt64(bytes.count + 1) }
      return DiagnosticLogEntry(
        id: .agent(file: tail.fileID, offset: offset, text: raw),
        line: LogLine.parse(raw) ?? LogLine.legacy(raw))
    }
  }
}

/// 一次文件尾部采样，offset 是 data 首字节在文件中的绝对位置。
struct DiagnosticLogTail: Sendable {
  let data: Data
  let fileID: UInt64
  let offset: UInt64

  // swiftlint:disable:next optional_data_string_conversion
  var text: String { String(decoding: data, as: UTF8.self) }
}

extension DiagnosticLogTail {
  init(text: String, fileID: UInt64, offset: UInt64) {
    self.init(data: Data(text.utf8), fileID: fileID, offset: offset)
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
    rows.filter(admits)
  }

  func admits(_ line: LogLine) -> Bool {
    level.admits(line.level) && source.admits(line.source)
  }
}
