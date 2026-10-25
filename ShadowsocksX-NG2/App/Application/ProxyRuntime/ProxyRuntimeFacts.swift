import Foundation

/// Stable runtime status categories exposed to app presentation surfaces.
/// 系统代理结果不在此列：它有独立的 `SystemProxyApplicationFacts`
/// 系统代理结果使用独立的状态面。
enum ProxyRuntimeStatus: Equatable, Sendable {
  case off
  case starting
  case running
  case firewallBlocked
  case launchFailed
  case requiresApproval
  case serviceFailed
}

/// Domain-neutral runtime projection for status-menu presentation. The
/// controller's state representation stays behind the adapter below.
struct ProxyRuntimeFacts: Equatable, Sendable {
  let status: ProxyRuntimeStatus
  let isOn: Bool
  let failure: RuntimeFailureFacts?

  init(
    status: ProxyRuntimeStatus,
    isOn: Bool,
    failure: RuntimeFailureFacts? = nil
  ) {
    self.status = status
    self.isOn = isOn
    self.failure = failure
  }
}

/// 系统代理实际作用的固定类别：意图持久化为开关事实，这里
/// 呈现 NG2 对系统设置的真实作用，与 agent 运行状态互不代替。
enum SystemProxyApplicationFacts: Equatable, Sendable {
  /// 意图关闭：系统代理清理完成。
  case idle
  /// 意图开启，等待 agent 健康或可用出口；条件恢复后自动收敛。
  case pending
  /// 已应用系统代理配置。
  case applied
  /// 写入或恢复失败（typed）。
  case failed(SystemProxyFailureFacts)
  case changed
  case applying
  case repairing
  case repairFailed(SystemProxyFailureFacts)
  case clearFailed(SystemProxyFailureFacts)
  case paused
  case unreadable(SystemProxyFailureFacts)
}

struct SystemProxyDifference: Equatable, Sendable, Identifiable {
  enum Kind: Equatable, Sendable { case changed, notApplied, remaining }
  let identifier: SystemProxyServiceIdentifier
  let name: String
  let kind: Kind
  var id: SystemProxyServiceIdentifier { identifier }
}

/// Current observation and action availability, independent of the last operation result.
struct SystemProxyInspectionFacts: Equatable, Sendable {
  var differences: [SystemProxyDifference] = []
  var readFailure: SystemProxyFailureFacts?
  var canRepair = false
  var canRetryClear = false
  var isBusy = false
  var backgroundUnavailable = false
}

/// Safe endpoint health categories used by runtime state and presentation.
enum RuntimeEndpointFailure: Equatable, Sendable {
  case refused
  case timedOut
  case invalidResponse
  case unknown
}

struct FirewallBlockedFacts: Equatable, Sendable {
  let executableName: String
}

enum LaunchFailureFacts: Equatable, Sendable {
  case missingRuntimeDocument
  case localEndpoint(
    endpoint: String, host: String, port: Int, cause: RuntimeEndpointFailure)
  case unreadableSettings
}

enum ServiceFailureFacts: Equatable, Sendable {
  case runtimeFile
  case agent
  case missingDocument
  case persistence
  case unknown
}

enum SystemProxyOperationFailure: Equatable, Sendable {
  case preferencesUnavailable
  case preferencesBusy
  case noCurrentNetworkSet
  case noNetworkLocations
  case noProxyServices
  case unreadableService
  case invalidStoredConfiguration
  case cannotWriteService
  case commitFailed
  case applyFailed
  case invalidRequest
  case helperUnavailable
}

extension SystemProxyOperationFailure {
  /// `SystemProxyError` 的呈现类别投影：稳定事实只保留操作类别；Domain 错误
  /// 的关联值（排查细节）不出现在运行时事实里。
  init(_ error: SystemProxyError) {
    self = Self.preferenceFailure(error) ?? Self.serviceFailure(error)
  }

  private static func preferenceFailure(_ error: SystemProxyError) -> Self? {
    switch error {
    case .preferencesUnavailable: return .preferencesUnavailable
    case .preferencesBusy: return .preferencesBusy
    case .noCurrentNetworkSet: return .noCurrentNetworkSet
    case .noNetworkLocations: return .noNetworkLocations
    case .noProxyServices: return .noProxyServices
    default: return nil
    }
  }

  private static func serviceFailure(_ error: SystemProxyError) -> Self {
    switch error {
    case .unreadableService: return .unreadableService
    case .invalidStoredConfiguration: return .invalidStoredConfiguration
    case .cannotWriteService: return .cannotWriteService
    case .commitFailed: return .commitFailed
    case .applyFailed: return .applyFailed
    case .invalidRequest: return .invalidRequest
    case .helperUnavailable: return .helperUnavailable
    case .preferencesUnavailable, .preferencesBusy, .noCurrentNetworkSet,
      .noNetworkLocations, .noProxyServices:
      preconditionFailure("Preference failures are mapped before service failures")
    }
  }
}

enum SystemProxyFailureFacts: Equatable, Sendable {
  case operation(SystemProxyOperationFailure)
  case unknown
}

/// Structured runtime failure projection used by runtime synchronization and
/// app presentation. No arbitrary platform detail is carried into this state.
/// `.systemProxy` 只用于把系统代理失败携带进结构化 outcome（设置工作流与
/// 目录收敛结果）；呈现面走 `SystemProxyApplicationFacts.failed`。
enum RuntimeFailureFacts: Error, Equatable, Sendable {
  case firewallBlocked(FirewallBlockedFacts)
  case launch(LaunchFailureFacts)
  case service(ServiceFailureFacts)
  case activation(ActivationFailure)
  case requiresApproval
  case systemProxy(SystemProxyFailureFacts)
}

extension ProxyRuntimeFacts {
  init(state: ProxyRuntimeController.AgentRunState) {
    switch state {
    case .off:
      self.init(status: .off, isOn: false)
    case .starting:
      self.init(status: .starting, isOn: true)
    case .running:
      self.init(status: .running, isOn: true)
    case .firewallBlocked(let facts):
      self.init(
        status: .firewallBlocked, isOn: true, failure: .firewallBlocked(facts))
    case .launchFailed(let facts):
      self.init(status: .launchFailed, isOn: false, failure: .launch(facts))
    case .requiresApproval:
      self.init(status: .requiresApproval, isOn: true, failure: .requiresApproval)
    case .serviceFailed(let facts):
      self.init(status: .serviceFailed, isOn: false, failure: .service(facts))
    }
  }
}

extension SystemProxyApplicationFacts {
  var hasOperationFailure: Bool { isApplyFailure || isClearFailure }
  var isApplyFailure: Bool {
    switch self {
    case .failed, .repairFailed: true
    default: false
    }
  }
  var isClearFailure: Bool {
    if case .clearFailed = self { return true }
    return false
  }
}
