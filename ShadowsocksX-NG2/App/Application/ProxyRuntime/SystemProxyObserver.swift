import Foundation

/// 系统代理观察/修复策略机（ADR-0022）：收敛、挂起、意图保持、
/// 修复、清理重试、helper 门禁与 cleanup-until-quiet 观察循环的唯一属主。
/// 意图开关、出口可用性与期望配置由组合方以闭包注入，模块不反向依赖控制器；
/// 呈现事实经自身事实通道（didChange 语义，每主队列轮合并）由运行时
/// adapter 合入 workflow 再发布链。
/// 底层只依赖 `SystemProxyControlling`、helper 注册缝与网络变化监视。
@MainActor
final class SystemProxyObserver {
  enum SystemProxyObservationMode: Equatable {
    case stopped
    case enabled
    case cleanup
  }

  /// Current configuration or operation result, independent of persisted intent.
  internal(set) var systemProxyState: SystemProxyApplicationFacts = .idle {
    didSet { factChanges.markChanged() }
  }
  /// Approval remains actionable even after an off-intent clear failure.
  internal(set) var systemProxyApprovalRequired = false { didSet { factChanges.markChanged() } }
  internal(set) var systemProxyInspection = SystemProxyInspectionFacts() {
    didSet { factChanges.markChanged() }
  }
  /// 呈现事实变化通道（didChange 语义）：三个事实属性的 didSet 汇集于此。
  let factChanges = CoalescedFactSignal()

  // 命令实现拆分为文件级扩展；观察事实仅由本模块消费，其他实现细节保持 private。
  var lastDesiredSystemProxyConfiguration: SystemProxyConfiguration?
  private var knownSystemProxyServices: Set<SystemProxyServiceIdentifier> = []
  private var systemProxyOperationInProgress = false
  /// 读面：健康循环体在 launch 重同步抑制期跳过巡检。
  internal(set) var systemProxyStartupInProgress = false
  /// 读面：健康循环的收敛条件。
  internal(set) var systemProxyInitialApplyPending = false
  /// 读面：健康循环的收敛条件。
  internal(set) var systemProxyWasUnavailable = false
  /// Read-only task handle lets observers await cancellation completion.
  internal(set) var systemProxyHealthTask: Task<Void, Never>?
  var systemProxyReadGeneration = 0
  /// 读面：观察机测试。
  internal(set) var systemProxyObservationMode = SystemProxyObservationMode.stopped
  var systemProxyCleanupRescanRequested = false
  var systemProxyCleanupTask: Task<SystemProxyApplicationFacts, Never>?
  var systemProxyInspectionScheduled = false
  /// Last passive inspection; awaiting it observes event convergence without a timing guess.
  internal(set) var systemProxyInspectionTask: Task<Void, Never>?

  let systemProxy: SystemProxyControlling
  let systemProxyHelper: SystemProxyHelperServicing
  let systemProxyNetworkChangeMonitor: SystemProxyNetworkChangeMonitoring
  /// 宿主 app bundle 缝（生产为 Bundle.main）：LaunchDaemon 清单指纹的定位基准。
  let appBundle: Bundle
  /// 注册清单漂移重注时，注销与重注的间隔（launchd 对节流中 job 的移除异步）。
  let helperRefreshDelayNanoseconds: UInt64
  /// cleanup 每轮扫描后等待 SystemConfiguration 通知排空的静默窗。
  let cleanupSettleNanoseconds: UInt64
  let isIntentEnabled: @MainActor () -> Bool
  let isExitAvailable: @MainActor () -> Bool
  let desiredConfiguration: @MainActor () -> SystemProxyConfiguration?
  /// 健康观察循环体经此注入、留在控制器（循环体含运行时健康呈现）；任务柄
  /// 由观察机创建并持有（cleanup 与停机路径都要取消它）。
  private let systemProxyHealthObservationLoop: @MainActor () async -> Void

  init(
    systemProxy: SystemProxyControlling,
    systemProxyHelper: SystemProxyHelperServicing,
    systemProxyNetworkChangeMonitor: SystemProxyNetworkChangeMonitoring,
    appBundle: Bundle,
    helperRefreshDelayNanoseconds: UInt64,
    cleanupSettleNanoseconds: UInt64 = 100_000_000,
    isIntentEnabled: @escaping @MainActor () -> Bool,
    isExitAvailable: @escaping @MainActor () -> Bool,
    desiredConfiguration: @escaping @MainActor () -> SystemProxyConfiguration?,
    systemProxyHealthObservationLoop: @escaping @MainActor () async -> Void
  ) {
    self.systemProxy = systemProxy
    self.systemProxyHelper = systemProxyHelper
    self.systemProxyNetworkChangeMonitor = systemProxyNetworkChangeMonitor
    self.appBundle = appBundle
    self.helperRefreshDelayNanoseconds = helperRefreshDelayNanoseconds
    self.cleanupSettleNanoseconds = cleanupSettleNanoseconds
    self.isIntentEnabled = isIntentEnabled
    self.isExitAvailable = isExitAvailable
    self.desiredConfiguration = desiredConfiguration
    self.systemProxyHealthObservationLoop = systemProxyHealthObservationLoop
  }

  // MARK: - 收敛与应用

  /// Explicit initial application, saved-value changes, or real health recovery.
  /// A healthy GUI startup and passive events only inspect current settings.
  func convergeSystemProxy(forceApply: Bool = false) async {
    guard await waitForSystemProxyOperation() else { return }
    guard isIntentEnabled(), !systemProxyStartupInProgress else { return }
    guard isExitAvailable() else {
      await suspendSystemProxy()
      return
    }
    guard let configuration = desiredConfiguration() else { return }
    let needsApplication =
      forceApply || systemProxyInitialApplyPending || systemProxyWasUnavailable
      || lastDesiredSystemProxyConfiguration != configuration
    if needsApplication {
      await applySystemProxy(configuration, repairing: false)
    } else {
      if systemProxyHelper.status == .approved { _ = await ensureHelperAvailableForApply() }
      await recheckSystemProxy()
    }
  }

  private func applySystemProxy(
    _ configuration: SystemProxyConfiguration, repairing: Bool
  ) async {
    guard !systemProxyOperationInProgress else { return }
    beginSystemProxyOperation()
    defer { endSystemProxyOperation() }
    guard await ensureHelperAvailableForApply() else {
      if !systemProxyState.hasOperationFailure { systemProxyState = .pending }
      updateSystemProxyActions()
      return
    }
    guard isIntentEnabled(), isExitAvailable() else { return }
    if repairing {
      guard await prepareSystemProxyRepair(configuration) else { return }
    }
    systemProxyState = repairing ? .repairing : .applying
    updateSystemProxyActions()
    // Mark the attempt before awaiting: a failed operation is never implicitly retried.
    systemProxyInitialApplyPending = false
    systemProxyWasUnavailable = false
    systemProxyInspection.backgroundUnavailable = false
    lastDesiredSystemProxyConfiguration = configuration
    do {
      if repairing {
        try await systemProxy.repair(configuration)
      } else {
        let outcome = try await systemProxy.apply(configuration)
        if outcome == .unchanged { RuntimeLog.emit(.systemProxyUnchanged) }
      }
      await inspectSystemProxy(configuration: configuration, afterRepair: repairing)
    } catch {
      RuntimeLog.emit(.systemProxyWriteFailed(detail: String(describing: error)))
      systemProxyState =
        repairing
        ? .repairFailed(systemProxyFacts(for: error)) : .failed(systemProxyFacts(for: error))
      await inspectSystemProxy(configuration: configuration, preserveResult: true)
    }
  }

  private func prepareSystemProxyRepair(_ configuration: SystemProxyConfiguration) async -> Bool {
    guard
      await inspectSystemProxy(
        configuration: configuration,
        preserveResult: systemProxyState.hasOperationFailure)
    else { return false }
    guard isIntentEnabled(), isExitAvailable(),
      desiredConfiguration() == configuration, systemProxyHelper.status == .approved
    else { return false }
    guard !systemProxyInspection.differences.isEmpty else {
      systemProxyState = .applied
      return false
    }
    return true
  }

  func repairSystemProxy() async {
    updateSystemProxyActions()
    guard systemProxyInspection.canRepair, let configuration = desiredConfiguration()
    else { return }
    await applySystemProxy(configuration, repairing: true)
  }

  func recheckSystemProxy() async {
    refreshSystemProxyApproval()
    guard isIntentEnabled(), let configuration = desiredConfiguration() else {
      updateSystemProxyActions()
      return
    }
    guard !systemProxyOperationInProgress else { return }
    await inspectSystemProxy(
      configuration: configuration,
      preserveResult: systemProxyState.hasOperationFailure || !isExitAvailable())
    updateSystemProxyActions()
  }

  @discardableResult
  private func inspectSystemProxy(
    configuration: SystemProxyConfiguration, afterRepair: Bool = false,
    preserveResult: Bool = false
  ) async -> Bool {
    systemProxyReadGeneration += 1
    let generation = systemProxyReadGeneration
    do {
      let services = try await systemProxy.readServices()
      guard !services.isEmpty else { throw SystemProxyError.noProxyServices }
      guard generation == systemProxyReadGeneration, isIntentEnabled(),
        desiredConfiguration() == configuration
      else { return false }
      let writes = try SystemProxyPlanner.makeApplyPlan(
        services: services, configuration: configuration
      ).writes
      let differing = Set(writes.map(\.identifier))
      systemProxyInspection.differences = services.compactMap { service in
        guard differing.contains(service.identifier) else { return nil }
        return SystemProxyDifference(
          identifier: service.identifier, name: service.name,
          kind: afterRepair
            ? .remaining
            : (knownSystemProxyServices.contains(service.identifier) ? .changed : .notApplied))
      }
      // Only observed consistency establishes a known service; an unsuccessful write
      // response cannot establish that this app's configuration was ever present.
      knownSystemProxyServices.formUnion(
        services.filter {
          !differing.contains($0.identifier)
        }.map(\.identifier))
      systemProxyInspection.readFailure = nil
      if !preserveResult && !systemProxyState.isClearFailure && !systemProxyWasUnavailable {
        systemProxyState = differing.isEmpty ? .applied : .changed
      }
      return true
    } catch {
      guard generation == systemProxyReadGeneration else { return false }
      systemProxyInspection.differences = []
      systemProxyInspection.readFailure = systemProxyFacts(for: error)
      if !preserveResult && !systemProxyState.isClearFailure && !systemProxyWasUnavailable {
        systemProxyState = .unreadable(systemProxyFacts(for: error))
      }
      return false
    }
  }

  func suspendSystemProxy() async {
    guard isIntentEnabled(), !systemProxyStartupInProgress else { return }
    guard !systemProxyWasUnavailable else {
      updateSystemProxyActions()
      return
    }
    guard await waitForSystemProxyOperation() else { return }
    guard isIntentEnabled(), !systemProxyWasUnavailable else { return }
    systemProxyWasUnavailable = true
    systemProxyInspection.backgroundUnavailable = true
    systemProxyInitialApplyPending = false
    beginSystemProxyOperation()
    defer { endSystemProxyOperation() }
    let outcome = await clearSystemProxyOutcome()
    systemProxyState = outcome == .idle ? .paused : outcome
    if outcome == .idle {
      systemProxyInspection.differences = []
      systemProxyInspection.readFailure = nil
    }
  }

  func retrySystemProxyClear() async {
    updateSystemProxyActions()
    guard systemProxyInspection.canRetryClear else { return }
    beginSystemProxyOperation()
    defer { endSystemProxyOperation() }
    let outcome = await clearSystemProxyOutcome()
    systemProxyState = outcome == .idle && isIntentEnabled() ? .paused : outcome
  }

  func beginSystemProxyOperation() {
    systemProxyOperationInProgress = true
    systemProxyInspection.isBusy = true
    systemProxyReadGeneration += 1
    updateSystemProxyActions()
  }

  /// 进行中操作的等待队列：操作收尾时唤醒全部等待者，等待者再经既有二次
  /// 门禁（begin 前的 guard）竞争下一轮；被取消的等待者照旧得到 false 中止。
  private var operationWaiters: [CheckedContinuation<Void, Never>] = []

  func waitForSystemProxyOperation() async -> Bool {
    while systemProxyOperationInProgress {
      await withCheckedContinuation { operationWaiters.append($0) }
    }
    return !Task.isCancelled
  }

  func endSystemProxyOperation() {
    systemProxyOperationInProgress = false
    systemProxyInspection.isBusy = false
    let waiters = operationWaiters
    operationWaiters = []
    for waiter in waiters { waiter.resume() }
    updateSystemProxyActions()
  }
}

// MARK: - 呈现动作与批准刷新

extension SystemProxyObserver {
  func refreshSystemProxyApproval() {
    systemProxyApprovalRequired =
      systemProxyHelper.status != .approved
      && (isIntentEnabled() || systemProxyState.hasOperationFailure)
  }

  func updateSystemProxyActions() {
    refreshSystemProxyApproval()
    let available = !systemProxyOperationInProgress && !systemProxyApprovalRequired
    systemProxyInspection.canRepair =
      available && isIntentEnabled()
      && isExitAvailable() && systemProxyInspection.readFailure == nil
      && (!systemProxyInspection.differences.isEmpty || systemProxyState.isApplyFailure)
    systemProxyInspection.canRetryClear = available && systemProxyState.isClearFailure
    if systemProxyState.hasOperationFailure {
      scheduleSystemProxyHealthObservation()
    } else if !isIntentEnabled() {
      systemProxyHealthTask?.cancel()
      systemProxyHealthTask = nil
    }
  }

  /// 请求调度健康观察循环：任务柄由观察机创建并持有，已存在则幂等返回。
  func scheduleSystemProxyHealthObservation() {
    guard systemProxyHealthTask == nil else { return }
    systemProxyHealthTask = Task { @MainActor [weak self] in
      await self?.systemProxyHealthObservationLoop()
    }
  }
}

// MARK: - 意图命令（控制器写面唯一入口）
