import Foundation

/// GUI 侧运行事件环形缓冲：收集 `RuntimeLog.emit`
/// 的事件供主窗口日志查看器实时呈现与诊断导出取用。事件文本来自封闭枚举的
/// 渲染，构造上不含敏感值；容量封顶只留最近事件（够诊断即可，不做复杂轮转）。
/// wrapper 进程不使用本存储（其 stderr 已收敛进 agent.log）。
final class RuntimeEventStore: RuntimeEventSink, @unchecked Sendable {
  struct Entry: Equatable, Identifiable {
    let id: Int
    let timestamp: Date
    /// 事件原值（封闭枚举）：原始呈现与报告白名单投影共用同一事实。
    let event: RuntimeLogEvent

    /// 事件文本（查看器与原始行共用）。
    var text: String { event.description }

    /// 查看器共用的行格式；固定 POSIX locale 保证报障对照不随用户
    /// 区域漂移。
    var renderedLine: String {
      renderedLine(eventText: text)
    }

    /// 指定事件文本的行格式；报告侧先经白名单清洗，再复用相同时间戳与间隔。
    /// 时间戳格式与统一日志行（`LogLine`）共用同一 POSIX 格式器。
    func renderedLine(eventText: String) -> String {
      "\(LogLine.timestampFormatter.string(from: timestamp))  \(eventText)"
    }
  }

  /// 进程级共享实例：GUI 启动时注册为 RuntimeLog 的接收缝。
  static let shared = RuntimeEventStore()

  private let lock = NSLock()
  private var entries: [Entry] = []
  private var nextID = 0
  private let capacity: Int

  init(capacity: Int = 500) {
    self.capacity = max(1, capacity)
  }

  /// 当前缓冲快照（旧→新）。
  var snapshot: [Entry] {
    lock.lock()
    defer { lock.unlock() }
    return entries
  }

  func append(event: RuntimeLogEvent, timestamp: Date = Date()) {
    lock.lock()
    defer { lock.unlock() }
    entries.append(Entry(id: nextID, timestamp: timestamp, event: event))
    nextID += 1
    if entries.count > capacity {
      entries.removeFirst(entries.count - capacity)
    }
  }
}
