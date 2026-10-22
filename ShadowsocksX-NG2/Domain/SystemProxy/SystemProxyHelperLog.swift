import Foundation
import os

/// 特权系统代理 helper 的封闭事件枚举：helper 侧的执行事实只进
/// 统一日志（Console.app 按 subsystem 查看），无文件面——不写 stderr、
/// 不进 agent.log、诊断日志视图与诊断报告（ADR-0006 不新增披露面）。
/// 事件面是生命周期最小集：拉起就绪、连接接受/拒绝与每个请求的 typed
/// 结果；不记 payload 内容（例外列表等）。GUI 侧 XPC 结果转述照旧，root
/// 侧事件与之在 Console 按同一 subsystem 相邻对照（ADR-0047）。
enum SystemProxyHelperLogEvent: Equatable, Sendable, CustomStringConvertible {
  /// helper 进程已拉起并开始监听（launchd on-demand 激活的唯一痕迹）。
  case listenerReady
  /// 已接受签名标识合规的客户端连接（对端 pid 为本机事实字段）。
  case connectionAccepted(pid: Int32)
  /// 拒绝签名标识不符的客户端连接（谁在敲门的唯一痕迹）。
  case connectionRejected(pid: Int32)
  /// apply 请求成功（written/unchanged 由 typed 结果给出）。
  case applyCompleted(SystemProxyWriteOutcome)
  /// clear 请求成功。
  case clearCompleted
  /// 请求失败（typed 错误族；自由 detail 段发射时标 private）。
  case requestFailed(SystemProxyError)

  /// 从 XPC 应答派生执行结果事件；引擎把解码失败与执行异常都归入
  /// typed 失败应答，这里不区分来源。
  init(response: SystemProxyHelperResponse) {
    switch response {
    case .applied(let outcome): self = .applyCompleted(outcome)
    case .cleared: self = .clearCompleted
    case .failure(let error): self = .requestFailed(error)
    }
  }

  /// 事件完整文本：typed 枚举文本 + 自由 detail 段。拆分规则沿
  /// ADR-0045：公开文本由本描述尾部裁切派生，不手抄前缀。
  var description: String {
    switch self {
    case .listenerReady:
      return "system proxy helper listening"
    case .connectionAccepted(let pid):
      return "system proxy helper connection accepted (pid=\(pid))"
    case .connectionRejected(let pid):
      return "system proxy helper connection rejected (pid=\(pid))"
    case .applyCompleted(let outcome):
      switch outcome {
      case .written:
        return "system proxy helper apply completed (outcome=written)"
      case .unchanged:
        return "system proxy helper apply completed (outcome=unchanged)"
      }
    case .clearCompleted:
      return "system proxy helper clear completed"
    case .requestFailed(let error):
      let parts = error.logParts
      guard let detail = parts.detail else {
        return "system proxy helper request failed: \(parts.text)"
      }
      return "system proxy helper request failed: \(parts.text): \(detail)"
    }
  }

  /// 发射时标 private 的自由 detail 段：恰为 `description` 的尾段。
  private var privateDetail: String? {
    guard case .requestFailed(let error) = self else { return nil }
    return error.logParts.detail
  }

  /// 系统日志路由：失败类 error、里程碑 default；category 沿用
  /// `system-proxy`，与 GUI 侧 `.systemProxyWriteFailed` 同类可对照。
  var logRoute: SystemLogRoute {
    switch self {
    case .listenerReady, .connectionAccepted, .applyCompleted, .clearCompleted:
      return route(level: .default)
    case .connectionRejected, .requestFailed:
      return route(level: .error)
    }
  }

  private func route(level: OSLogType) -> SystemLogRoute {
    guard let detail = privateDetail else {
      return SystemLogRoute(
        level: level, category: "system-proxy", text: description, privateDetail: nil)
    }
    return SystemLogRoute(
      level: level, category: "system-proxy",
      text: String(description.dropLast(detail.count)), privateDetail: detail)
  }
}

/// 事件发射缝：生产直通统一日志；测试注入替身断言发射。
enum SystemProxyHelperLog {
  static func emit(_ event: SystemProxyHelperLogEvent) {
    SystemLog.emit(event.logRoute)
  }
}

extension SystemProxyError {
  /// 统一日志文本拆分：公开的 typed 错误名与待标 private 的自由 detail
  /// 段（服务标识或 SC/XPC 错误文本）。
  var logParts: (text: String, detail: String?) {
    switch self {
    case .preferencesUnavailable: return ("preferences unavailable", nil)
    case .preferencesBusy: return ("preferences busy", nil)
    case .noCurrentNetworkSet: return ("no current network set", nil)
    case .noNetworkLocations: return ("no network locations", nil)
    case .noProxyServices: return ("no proxy services", nil)
    case .unreadableService(let detail): return ("unreadable service", detail)
    case .invalidStoredConfiguration(let detail): return ("invalid stored configuration", detail)
    case .cannotWriteService(let detail): return ("cannot write service", detail)
    case .commitFailed(let detail): return ("commit failed", detail)
    case .applyFailed(let detail): return ("apply failed", detail)
    case .invalidRequest(let detail): return ("invalid request", detail)
    case .helperUnavailable(let detail): return ("helper unavailable", detail)
    }
  }
}
