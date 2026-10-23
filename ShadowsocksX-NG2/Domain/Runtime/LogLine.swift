import Foundation
import os

/// 查看器口径的日志级别（经典三级）：error / warning / info。里程碑事件归
/// info，上游 WARN/WARNING 归 warning。它与统一日志的五级投影是两个口径：
/// 投影规则见 `OSLogType(_: LogLineLevel)`（warning 落持久 .default）。
enum LogLineLevel: String, Sendable {
  case error, warning, info

  /// 上游自由文本的级别探测：按空白分隔 token 匹配级别名
  /// （tracing/env_logger 文本格式的 ERROR/WARN/WARNING），忽略大小写，并支持
  /// token 外的一对方括号。探测不到一律 `.info`；上游改格式时优雅退化，不丢行。
  static func detect(in line: String) -> LogLineLevel {
    for token in line.split(whereSeparator: \.isWhitespace) {
      let levelToken =
        token.hasPrefix("[") && token.hasSuffix("]")
        ? token.dropFirst().dropLast()
        : token[...]
      switch levelToken.uppercased() {
      case "ERROR": return .error
      case "WARN", "WARNING": return .warning
      default: continue
      }
    }
    return .info
  }
}

/// 日志行来源：GUI 事件、wrapper 事件与 sslocal 上游输出。查看器的来源
/// 过滤按它区分；行格式里作为显式标记，报障粘贴自描述。
enum LogLineSource: String, Sendable {
  case gui, wrapper, sslocal
}

/// 统一日志行模型：「一行日志是什么」在本类型收口——写侧（agent.log 的
/// stderr 通路）与读侧（诊断日志查看器）共用同一渲染与解析。行格式：
/// `yyyy-MM-dd HH:mm:ss.SSS Z [error|warning|info] [gui|wrapper|sslocal] 正文`，
/// 时间戳固定 POSIX locale，报障对照不随用户区域漂移。
struct LogLine: Equatable, Sendable {
  /// 写侧行必有时间戳；旧格式行（升级前落盘）无法解析时为 nil。
  var timestamp: Date?
  var level: LogLineLevel
  var source: LogLineSource
  /// 行正文：事件描述或上游原样文本（已脱敏）。
  var text: String

  init(timestamp: Date?, level: LogLineLevel, source: LogLineSource, text: String) {
    self.timestamp = timestamp
    self.level = level
    self.source = source
    self.text = text
  }

  /// 呈现行文本。无时间戳的旧格式行保留原文（raw capture 不改写）。
  var rendered: String {
    guard let timestamp else { return text }
    return "\(Self.timestampFormatter.string(from: timestamp))"
      + " [\(level.rawValue)] [\(source.rawValue)] \(text)"
  }

  /// 严格解析统一行格式；无法解析返回 nil，由调用方走 `legacy` 降级。
  static func parse(_ raw: String) -> LogLine? {
    guard let stampEnd = raw.range(of: " [")?.lowerBound else { return nil }
    let stamp = String(raw[..<stampEnd])
    guard
      let timestamp = timestampFormatter.date(from: stamp)
        ?? legacyTimestampFormatter.date(from: stamp)
    else { return nil }
    var rest = raw[stampEnd...]
    guard let level = takeToken(&rest, as: LogLineLevel.self),
      let source = takeToken(&rest, as: LogLineSource.self),
      rest.hasPrefix(" ")
    else { return nil }
    rest = rest.dropFirst()
    return LogLine(timestamp: timestamp, level: level, source: source, text: String(rest))
  }

  /// 旧格式行降级：原文保留显示，级别尽力探测，来源按旧 `ssxng:` 事件标记
  /// 区分 wrapper 事件与上游输出；时间未知。
  static func legacy(_ raw: String) -> LogLine {
    LogLine(
      timestamp: nil,
      level: .detect(in: raw),
      source: raw.hasPrefix("ssxng: ") ? .wrapper : .sslocal,
      text: raw)
  }

  /// 从行首消费一个 ` [token]` 标记（含前导空格，不含尾随分隔空格）。
  private static func takeToken<Value: RawRepresentable>(
    _ line: inout Substring, as type: Value.Type
  ) -> Value? where Value.RawValue == String {
    guard line.hasPrefix(" [") else { return nil }
    line = line.dropFirst(2)
    guard let end = line.firstIndex(of: "]") else { return nil }
    let value = Value(rawValue: String(line[line.startIndex..<end]))
    line = line[line.index(after: end)...]
    return value
  }

  /// DateFormatter 在现代 Foundation 中线程安全；本格式器只被读取。
  static let timestampFormatter = makeTimestampFormatter("yyyy-MM-dd HH:mm:ss.SSS Z")

  // 升级前的行没有时区，只能按本地时间读取；新行必须保留回拨前后的偏移量。
  private static let legacyTimestampFormatter = makeTimestampFormatter("yyyy-MM-dd HH:mm:ss.SSS")

  private static func makeTimestampFormatter(_ format: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = format
    return formatter
  }
}

extension LogLine {
  /// 事件行：级别取自事件的统一日志路由级别（失败类 error，其余归 info），
  /// 正文为事件描述。stderr 行式输出与 GUI 查看面共用这一构造。
  init(event: RuntimeLogEvent, timestamp: Date?, source: LogLineSource) {
    self.init(
      timestamp: timestamp,
      level: LogLineLevel(os: event.systemLogRoute.level),
      source: source,
      text: event.description)
  }
}

extension OSLogType {
  /// 查看器三级级别 → 统一日志五级投影：warning 落持久的 `.default`
  /// （统一日志没有 warning 级，与 error 可区分）；info 落 `.info`
  /// （stream 可见、不落盘）。
  init(_ level: LogLineLevel) {
    switch level {
    case .error: self = .error
    case .warning: self = .default
    case .info: self = .info
    }
  }
}

extension LogLineLevel {
  /// 统一日志级别 → 查看器三级：失败类归 error，里程碑（default）与冗长
  /// 测量（info/debug）归 info。
  init(os level: OSLogType) {
    self = (level == .error || level == .fault) ? .error : .info
  }
}
