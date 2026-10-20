import Foundation
import os

/// 脱敏后行的去向缝：intake 只产出行（`LogLine`），行最终落在哪里由
/// adapter 决定。
protocol SslocalLineDestination: Sendable {
  func receive(_ row: LogLine)
}

/// adapter：wrapper 的 stderr。`redirectStandardStreams` 以 freopen 把 stderr
/// 收敛进 agent.log，行按统一行格式渲染（时间戳/级别/来源与诊断查看器同一
/// 口径）。handle 可注入（生产默认标准错误），测试用管道替身断言序列化，
/// 不碰进程全局 stderr。
struct SslocalStandardErrorDestination: SslocalLineDestination {
  private let handle: FileHandle

  init(handle: FileHandle = .standardError) {
    self.handle = handle
  }

  func receive(_ row: LogLine) {
    handle.write(Data((row.rendered + "\n").utf8))
  }
}

/// adapter：统一日志（category `sslocal`，与 RuntimeLogEvent 同 subsystem）。
/// 上游输出是自由文本，不进封闭枚举事件流；整行标 private——上游默认日志
/// 可能含服务器地址（ADR-0014），正文阅读继续走 agent.log 查看面。Console
/// 获得时间戳、category、level 与行数关联；stderr/agent.log 通路没有这些
/// 可过滤维度。级别由 intake 探测，这里只投影到统一日志五级。
struct SslocalUnifiedLogDestination: SslocalLineDestination {
  private let logger = Logger(subsystem: RuntimeLog.subsystem, category: "sslocal")

  func receive(_ row: LogLine) {
    // 统一日志写入受测试缝控制（SSXNG_SYSTEM_LOG=0 关闭），agent.log 去向不受影响。
    guard RuntimeLog.systemLogEnabled else { return }
    logger.log(level: OSLogType(row.level), "\(row.text, privacy: .private)")
  }
}

/// sslocal 输出 intake：chunk-safe 行分帧 + 密码脱敏 + 超长行丢弃，把脱敏后的
/// 行送到去向缝。FileHandle 回调通过锁串行访问缓冲区，避免分块输入绕过隐藏
/// 规则。`write(Data())` 表示输入结束，冲刷尾部半行。
///
/// 这是上游自由文本进入日志去向的唯一入口：脱敏规则只在这一处，不再随去向
/// 复制；上游认证失败日志包含客户端提交的密码，按完整行隐藏密码后再分发。
/// 行模型（时间戳、级别探测、来源 `sslocal`）也在此构造，各 adapter 只做投影。
final class SslocalOutputIntake: @unchecked Sendable {
  private let lock = NSLock()
  private var buffer = Data()
  private var discardingOversizedLine = false
  private let destinations: [any SslocalLineDestination]
  private let now: () -> Date

  init(destinations: [any SslocalLineDestination], now: @escaping () -> Date = { Date() }) {
    self.destinations = destinations
    self.now = now
  }

  func write(_ data: Data) {
    lock.lock()
    defer { lock.unlock() }
    if discardingOversizedLine {
      guard let newline = data.firstIndex(of: 10) else { return }
      discardingOversizedLine = false
      buffer.append(data.suffix(from: data.index(after: newline)))
    } else {
      buffer.append(data)
    }
    while let newline = buffer.firstIndex(of: 10) {
      emitLine(String(data: buffer.prefix(upTo: newline), encoding: .utf8))
      buffer.removeSubrange(...newline)
    }
    if data.isEmpty && !buffer.isEmpty {
      emitLine(String(data: buffer, encoding: .utf8))
      buffer.removeAll()
    } else if buffer.count > 65_536 {
      buffer.removeAll()
      discardingOversizedLine = true
      emitLine("log line truncated")
    }
  }

  private func emitLine(_ text: String?) {
    guard let text else { return }
    let sanitized = text.replacingOccurrences(
      of: "password: [^\\r\\n]*",
      with: "password: [redacted]", options: .regularExpression)
    let row = LogLine(
      timestamp: now(),
      level: .detect(in: sanitized),
      source: .sslocal,
      text: sanitized)
    for destination in destinations {
      destination.receive(row)
    }
  }
}
