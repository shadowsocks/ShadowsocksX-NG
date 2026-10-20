import Foundation
import os

/// 运行时日志基线：事件是封闭枚举，脱敏由构造保证——永不
/// 携带密码、插件参数、Keychain 值、完整订阅 URL 及其 token 或运行时 JSON
/// 内容；测试 URL 属于非敏感信息，可完整记录。服务器地址与备注默认不进
/// 普通日志（端点探测失败点名的 host:port 是本机监听端点，属于需要呈现的
/// 事实字段，不受此限）。日志查看与诊断导出均以本事件流为数据源。
enum RuntimeLogEvent: Equatable, CustomStringConvertible, Sendable {
  /// 契约文件已原子写入（只携带数量元数据，非内容）。
  case contractWritten(serverCount: Int)
  /// 契约内容与磁盘一致，跳过写入（幂等）。
  case contractUnchanged
  /// 系统代理期望值与系统当前应用值语义等价，跳过写入（零授权）。
  case systemProxyUnchanged
  /// 特权系统代理 helper 的 SMAppService 注册失败（不含内容）。
  case systemProxyHelperRegisterFailed(detail: String)
  /// 系统代理写入/清除请求失败（detail 为 XPC 或 helper 错误文本）。
  case systemProxyWriteFailed(detail: String)
  /// 运行时文件已清理。
  case runtimeFilesDeleted
  /// 激活状态等运行时元数据落盘失败（不含内容）。
  case runtimePersistFailed(detail: String)
  case agentRegistered
  case agentRegisterFailed(detail: String)
  case agentUnregistered
  case agentUnregisterFailed(detail: String)
  /// wrapper 侧 sslocal 监管事件。
  case sslocalSpawned(pid: Int32)
  case sslocalSpawnFailed
  case sslocalExitedUnexpectedly(status: Int32)
  case sslocalStopRequested
  /// sslocal 拉起后限时内未完成本地监听绑定（「3 秒未建立监听 → error
  /// 日志」；监管继续，GUI 健康门负责呈现，端点为本机监听端点不受脱敏限制）。
  case listenNotEstablished(detail: String)
  case contractMissing
  case contractInvalid
  case reloadForwarded
  case reloadDeferred
  case reloadRestarted
  /// 本机代理端点启动后未就绪（点名端点与端口）。
  case endpointProbeFailed(host: String, port: Int, detail: String)
  /// 激活失败或活动目标清除（原因枚举已点名且不含秘密）。
  case activationFailed(reason: String)
  /// 用户显式触发的脱敏诊断导出已完成（不携带导出路径）。
  case diagnosticsExported
  /// 偏好设置持久化读取失败，已回落出厂默认（不静默改端口——事件进
  /// 诊断日志由查看器呈现；完整日志查看器属于独立的诊断界面。
  case settingsUnreadable(detail: String)

  case connectivityMeasurement(id: UUID, entry: ConnectivityTrace)

  /// Detailed measurements are available only through explicit in-app log viewing.
  var standardErrorLine: String? {
    if case .connectivityMeasurement = self { return nil }
    return "ssxng: \(description)\n"
  }

  var description: String {
    switch self {
    case .connectivityMeasurement(let id, let entry):
      return "connectivity \(id.uuidString) \(entry.description)"
    case .contractWritten(let serverCount):
      return "contract written (servers=\(serverCount))"
    case .contractUnchanged:
      return "contract unchanged, write skipped"
    case .systemProxyUnchanged:
      return "system proxy values unchanged, write skipped"
    case .systemProxyHelperRegisterFailed(let detail):
      return "system proxy helper register failed: \(detail)"
    case .systemProxyWriteFailed(let detail):
      return "system proxy write failed: \(detail)"
    case .runtimeFilesDeleted:
      return "runtime files deleted"
    case .runtimePersistFailed(let detail):
      return "runtime metadata persist failed: \(detail)"
    case .agentRegistered:
      return "launch agent registered"
    case .agentRegisterFailed(let detail):
      return "launch agent register failed: \(detail)"
    case .agentUnregistered:
      return "launch agent unregistered"
    case .agentUnregisterFailed(let detail):
      return "launch agent unregister failed: \(detail)"
    case .sslocalSpawned(let pid):
      return "sslocal spawned (pid=\(pid))"
    case .sslocalSpawnFailed:
      return "sslocal spawn failed"
    case .sslocalExitedUnexpectedly(let status):
      return "sslocal exited unexpectedly (status=\(status))"
    case .sslocalStopRequested:
      return "sslocal stop requested"
    case .listenNotEstablished(let detail):
      return "listen not established within deadline: \(detail)"
    case .contractMissing:
      return "contract missing"
    case .contractInvalid:
      return "supervision invalid, preserved"
    case .reloadForwarded:
      return "reload forwarded to sslocal"
    case .reloadDeferred:
      return "reload deferred until listeners are ready"
    case .reloadRestarted:
      return "reload: listen change, restarting sslocal"
    case .endpointProbeFailed(let host, let port, let detail):
      return "endpoint \(host):\(port) not ready: \(detail)"
    case .activationFailed(let reason):
      return "activation failed: \(reason)"
    case .diagnosticsExported:
      return "diagnostics report exported (redacted)"
    case .settingsUnreadable(let detail):
      return "settings unreadable, falling back to factory defaults: \(detail)"
    }
  }
}

/// 系统日志路由（统一日志，Console.app 可按 subsystem/category 过滤）：
/// level 三分（失败类 error、里程碑 default、冗长测量 info）、category 五分
/// （runtime / supervision / system-proxy / connectivity / diagnostics；
/// sslocal 输出 intake 的自由文本行走独立的 category `sslocal`，不经本枚举）。
/// 拆分规则：`text` + `privateDetail` == `description`；自由错误 detail 与
/// 连通性测量内容（含探测目标 IP）拆出由发射缝标 private，公开文本由
/// description 尾部裁切派生，不手抄前缀。穷举 switch：新事件漏路由无法编译。
extension RuntimeLogEvent {
  var systemLogRoute: SystemLogRoute {
    switch self {
    case .contractWritten, .contractUnchanged, .runtimeFilesDeleted:
      return SystemLogRoute(
        level: .default, category: "runtime", text: description, privateDetail: nil)
    case .contractMissing, .contractInvalid, .activationFailed:
      return SystemLogRoute(
        level: .error, category: "runtime", text: description, privateDetail: nil)
    case .runtimePersistFailed(let detail):
      return SystemLogRoute(
        level: .error, category: "runtime", text: String(description.dropLast(detail.count)),
        privateDetail: detail)
    case .settingsUnreadable(let detail):
      return SystemLogRoute(
        level: .error, category: "runtime",
        text: String(description.dropLast(detail.count)), privateDetail: detail)
    case .agentRegistered, .agentUnregistered, .sslocalSpawned, .sslocalStopRequested,
      .reloadForwarded, .reloadDeferred, .reloadRestarted:
      return SystemLogRoute(
        level: .default, category: "supervision", text: description, privateDetail: nil)
    case .sslocalSpawnFailed, .sslocalExitedUnexpectedly, .listenNotEstablished:
      return SystemLogRoute(
        level: .error, category: "supervision", text: description, privateDetail: nil)
    case .agentRegisterFailed(let detail):
      return SystemLogRoute(
        level: .error, category: "supervision",
        text: String(description.dropLast(detail.count)), privateDetail: detail)
    case .agentUnregisterFailed(let detail):
      return SystemLogRoute(
        level: .error, category: "supervision",
        text: String(description.dropLast(detail.count)), privateDetail: detail)
    case .systemProxyUnchanged:
      return SystemLogRoute(
        level: .default, category: "system-proxy", text: description, privateDetail: nil)
    case .systemProxyHelperRegisterFailed(let detail):
      return SystemLogRoute(
        level: .error, category: "system-proxy",
        text: String(description.dropLast(detail.count)), privateDetail: detail)
    case .systemProxyWriteFailed(let detail):
      return SystemLogRoute(
        level: .error, category: "system-proxy",
        text: String(description.dropLast(detail.count)), privateDetail: detail)
    case .endpointProbeFailed(_, _, let detail):
      return SystemLogRoute(
        level: .error, category: "connectivity",
        text: String(description.dropLast(detail.count)), privateDetail: detail)
    case .connectivityMeasurement(_, let entry):
      // 测量内容含探测目标 IP，整段标 private（普通日志不进服务器地址）。
      return SystemLogRoute(
        level: .info, category: "connectivity",
        text: String(description.dropLast(entry.description.count)),
        privateDetail: entry.description)
    case .diagnosticsExported:
      return SystemLogRoute(
        level: .default, category: "diagnostics", text: description, privateDetail: nil)
    }
  }
}

/// 系统日志路由事实：发射缝按此构造统一日志消息。`text` 已含与
/// `privateDetail` 之间的分隔符，两者拼接等于事件的 `description`。
struct SystemLogRoute: Sendable {
  var level: OSLogType
  var category: String
  var text: String
  var privateDetail: String?
}

/// 事件接收缝：GUI 进程把事件接入 RuntimeEventStore（内存环形
/// 缓冲），供主窗口日志查看器实时呈现与诊断导出取用；wrapper 进程不注册
/// （stderr 收敛进 agent.log）。接收方拿到的是封闭枚举原值，渲染发生在
/// 呈现边缘（诊断报告的白名单清洗只可能作用于原值）。
protocol RuntimeEventSink: Sendable {
  func append(event: RuntimeLogEvent, timestamp: Date)
}

/// 敏感信息脱敏工具（「敏感信息」定义的读取面）。
enum Redactor {
  /// 敏感远程 URL 只保留 scheme+host：路径、查询与片段全部略去，完整订阅
  /// URL 与 URL token 永不入日志。解析失败一律归并为占位符。
  /// 测试 URL 无需脱敏，不使用此方法。
  static func remoteURL(_ url: String) -> String {
    guard let parsed = URL(string: url), let host = parsed.host(), !host.isEmpty else {
      return "<redacted-url>"
    }
    return "\(parsed.scheme ?? "https")://\(host)/…"
  }

}

/// 事件发射缝：wrapper 与 GUI 共用 stderr 行式输出（wrapper 侧收敛进
/// agent.log）与系统日志输出（统一 subsystem，Console.app 按 category 过滤，
/// 拆出的 detail 段标 private）；GUI 启动时另注册接收缝接入事件缓冲。
enum RuntimeLog {
  /// 系统日志 subsystem：各进程共用一个名字，Console.app 一条过滤全看。
  static let subsystem = "com.qiuyuzhou.ShadowsocksX-NG2"

  private static let sinkHolder = SinkHolder()

  /// 注册/替换事件接收缝；传 nil 移除接收缝（测试隔离用）。
  static func setSink(_ sink: (any RuntimeEventSink)?) {
    sinkHolder.set(sink)
  }

  static func emit(_ event: RuntimeLogEvent) {
    if let line = event.standardErrorLine { FileHandle.standardError.write(Data(line.utf8)) }
    let route = event.systemLogRoute
    let logger = Logger(subsystem: subsystem, category: route.category)
    if let detail = route.privateDetail {
      logger.log(level: route.level, "\(route.text, privacy: .public)\(detail, privacy: .private)")
    } else {
      logger.log(level: route.level, "\(route.text, privacy: .public)")
    }
    sinkHolder.current?.append(event: event, timestamp: Date())
  }

  /// 可变静态的锁保护持有者：emit 可能来自任意线程。
  private final class SinkHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var sink: (any RuntimeEventSink)?

    var current: (any RuntimeEventSink)? {
      lock.lock()
      defer { lock.unlock() }
      return sink
    }

    func set(_ value: (any RuntimeEventSink)?) {
      lock.lock()
      defer { lock.unlock() }
      sink = value
    }
  }
}

/// Structured latency observations for explicit local log viewing. These events
/// are excluded from shared diagnostic reports, including their target IPs.
struct ConnectivityTrace: Equatable, Sendable, CustomStringConvertible {
  enum Phase: String, Sendable {
    case startup, google, cloudflare, candidate, selected, sample, summary
  }
  enum Status: String, Sendable {
    case success, network, timeout, http, configuration, cancelled, insufficientSamples
  }
  enum FailureStage: String, Sendable {
    case none, startup, dns, selection, request, send, headers
    case localTCP = "local_tcp"
    case firstByte = "first_byte"
  }
  var phase: Phase
  var status: Status
  var index: Int = 0
  var address: String?
  var milliseconds: Double?
  var localTCPMilliseconds: Double?
  var sendMilliseconds: Double?
  var firstByteMilliseconds: Double?
  var headersMilliseconds: Double?
  var failureStage: FailureStage = .none
  var httpStatus: Int?

  var description: String {
    var fields = ["phase=\(phase.rawValue)", "result=\(status.rawValue)"]
    if index > 0 { fields.append("index=\(index)") }
    if let address { fields.append("ip=\(address)") }
    if let httpStatus { fields.append("http=\(httpStatus)") }
    if failureStage != .none { fields.append("failure_stage=\(failureStage.rawValue)") }
    let times: [(String, Double?)] = [
      ("total_ms", milliseconds), ("local_tcp_ms", localTCPMilliseconds),
      ("send_ms", sendMilliseconds), ("wait_first_byte_ms", firstByteMilliseconds),
      ("first_byte_to_headers_ms", headersMilliseconds),
    ]
    for (name, value) in times {
      if let value {
        fields.append(
          "\(name)=\(String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value))")
      }
    }
    return fields.joined(separator: " ")
  }
}
