import Foundation
import os

/// 脱敏后行的去向缝：intake 只产出行，行最终落在哪里由 adapter 决定。
protocol SslocalLineDestination: Sendable {
  func receive(_ line: String)
}

/// adapter：wrapper 的 stderr。`redirectStandardStreams` 以 freopen 把 stderr
/// 收敛进 agent.log，raw capture 原样保留（ADR-0006 的本地查看面）。handle
/// 可注入（生产默认标准错误），测试用管道替身断言序列化，不碰进程全局 stderr。
struct SslocalStandardErrorDestination: SslocalLineDestination {
  private let handle: FileHandle

  init(handle: FileHandle = .standardError) {
    self.handle = handle
  }

  func receive(_ line: String) {
    handle.write(Data((line + "\n").utf8))
  }
}

/// adapter：统一日志（category `sslocal`，与 RuntimeLogEvent 同 subsystem）。
/// 上游输出是自由文本，不进封闭枚举事件流；整行标 private——上游默认日志
/// 可能含服务器地址（ADR-0014），正文阅读继续走 agent.log 查看面。Console
/// 获得时间戳、category、level 与行数关联；stderr/agent.log 通路没有这些
/// 可过滤维度。
struct SslocalUnifiedLogDestination: SslocalLineDestination {
  private let logger = Logger(subsystem: RuntimeLog.subsystem, category: "sslocal")

  func receive(_ line: String) {
    logger.log(level: Self.level(for: line), "\(line, privacy: .private)")
  }

  /// level 只按空白分隔 token 探测上游级别名（tracing/env_logger 文本格式
  /// 的 ERROR/WARN/WARNING），探测不到一律 `.info`（stream 可见、不落盘）；
  /// agent.log 才是持久面，持久 store 只收探测到的警告与错误。统一日志只有
  /// 五级、没有 warning：WARN/WARNING 落 `.default`（持久、与 error 可区分，
  /// 级别名仍在行文本里）。上游改格式时优雅退化为全 `.info`，不丢行。
  static func level(for line: String) -> OSLogType {
    for token in line.split(whereSeparator: \.isWhitespace) {
      switch token {
      case "ERROR": return .error
      case "WARN", "WARNING": return .default
      default: continue
      }
    }
    return .info
  }
}

/// sslocal 输出 intake：chunk-safe 行分帧 + 密码脱敏 + 超长行丢弃，把脱敏后的
/// 行送到去向缝。FileHandle 回调通过锁串行访问缓冲区，避免分块输入绕过隐藏
/// 规则。`write(Data())` 表示输入结束，冲刷尾部半行。
///
/// 这是上游自由文本进入日志去向的唯一入口：脱敏规则只在这一处，不再随去向
/// 复制；上游认证失败日志包含客户端提交的密码，按完整行隐藏密码后再分发。
final class SslocalOutputIntake: @unchecked Sendable {
  private let lock = NSLock()
  private var buffer = Data()
  private var discardingOversizedLine = false
  private let destinations: [any SslocalLineDestination]

  init(destinations: [any SslocalLineDestination]) {
    self.destinations = destinations
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
      emitLine("sslocal: log line truncated")
    }
  }

  private func emitLine(_ text: String?) {
    guard let text else { return }
    let sanitized = text.replacingOccurrences(
      of: "password: [^\\r\\n]*",
      with: "password: [redacted]", options: .regularExpression)
    for destination in destinations {
      destination.receive(sanitized)
    }
  }
}
