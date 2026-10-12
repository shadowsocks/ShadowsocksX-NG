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
  private(set) var systemProxyState: SystemProxyApplicationFacts = .idle {
    didSet { factChanges.markChanged() }
  }
  /// Approval remains actionable even after an off-intent clear failure.
  private(set) var systemProxyApprovalRequired = false { didSet { factChanges.markChanged() } }
  private(set) var systemProxyInspection = SystemProxyInspectionFacts() {
    didSet { factChanges.markChanged() }
  }
  /// 呈现事实变化通道（didChange 语义）：三个事实属性的 didSet 汇集于此。
  let factChanges = CoalescedFactSignal()

  // 写面唯一入口是下方「意图命令」；private(set) 的读面仅开给健康循环体
  // 与观察机测试，其余实现细节一律 private。
  private var lastDesiredSystemProxyConfiguration: SystemProxyConfiguration?
  private var knownSystemProxyServices: Set<SystemProxyServiceIdentifier> = []
  private var systemProxyOperationInProgress = false
  /// 读面：健康循环体在 launch 重同步抑制期跳过巡检。
  private(set) var systemProxyStartupInProgress = false
  /// 读面：健康循环的收敛条件。
  private(set) var systemProxyInitialApplyPending = false
  /// 读面：健康循环的收敛条件。
  private(set) var systemProxyWasUnavailable = false
  /// Read-only task handle lets observers await cancellation completion.
  private(set) var systemProxyHealthTask: Task<Void, Never>?
  private var systemProxyReadGeneration = 0
  /// 读面：观察机测试。
  private(set) var systemProxyObservationMode = SystemProxyObservationMode.stopped
  private var systemProxyCleanupRescanRequested = false
  private var systemProxyCleanupTask: Task<SystemProxyApplicationFacts, Never>?
  private var systemProxyInspectionScheduled = false
  /// Last passive inspection; awaiting it observes event convergence without a timing guess.
  private(set) var systemProxyInspectionTask: Task<Void, Never>?

  let systemProxy: SystemProxyControlling
  let systemProxyHelper: SystemProxyHelperServicing
  let systemProxyNetworkChangeMonitor: SystemProxyNetworkChangeMonitoring
  /// 宿主 app bundle 缝（生产为 Bundle.main）：LaunchDaemon 清单指纹的定位基准。
  let appBundle: Bundle
  /// 注册清单漂移重注时，注销与重注的间隔（launchd 对节流中 job 的移除异步）。
  let helperRefreshDelayNanoseconds: UInt64
  /// cleanup 每轮扫描后等待 SystemConfiguration 通知排空的静默窗。
  let cleanupSettleNanoseconds: UInt64
  private let isIntentEnabled: @MainActor () -> Bool
  private let isExitAvailable: @MainActor () -> Bool
  private let desiredConfiguration: @MainActor () -> SystemProxyConfiguration?
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

  private func beginSystemProxyOperation() {
    systemProxyOperationInProgress = true
    systemProxyInspection.isBusy = true
    systemProxyReadGeneration += 1
    updateSystemProxyActions()
  }

  /// 进行中操作的等待队列：操作收尾时唤醒全部等待者，等待者再经既有二次
  /// 门禁（begin 前的 guard）竞争下一轮；被取消的等待者照旧得到 false 中止。
  private var operationWaiters: [CheckedContinuation<Void, Never>] = []

  private func waitForSystemProxyOperation() async -> Bool {
    while systemProxyOperationInProgress {
      await withCheckedContinuation { operationWaiters.append($0) }
    }
    return !Task.isCancelled
  }

  private func endSystemProxyOperation() {
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
  private func scheduleSystemProxyHealthObservation() {
    guard systemProxyHealthTask == nil else { return }
    systemProxyHealthTask = Task { @MainActor [weak self] in
      await self?.systemProxyHealthObservationLoop()
    }
  }
}

// MARK: - 意图命令（控制器写面唯一入口）

extension SystemProxyObserver {
  /// 系统代理意图开启（setSystemProxyEnabled on）：本轮必须真实应用一次——
  /// 清理期可能已把系统设置清空，不能凭 lastDesired 相等跳过；收敛后转入
  /// enabled 观察与网络变化巡检。
  func enableSystemProxyIntent() async {
    systemProxyInitialApplyPending = true
    systemProxyWasUnavailable = false
    await convergeSystemProxy()
    startEnabledSystemProxyObservation()
  }

  /// 系统代理意图关闭（setSystemProxyEnabled off）：撤销待批准/待应用标记，
  /// 读取代际推进作废在途读，无条件清理并停观察，结果原样呈现。
  func disableSystemProxyIntent() async {
    systemProxyApprovalRequired = false
    systemProxyInitialApplyPending = false
    systemProxyReadGeneration += 1
    systemProxyState = await clearAndStopSystemProxyObservation()
    updateSystemProxyActions()
  }

  /// agent 停机的观察收尾（stopAgent）：停网络监视与健康循环，观察模式归
  /// 零。呈现按代理意图分流——意图仍在则保持待应用（等 agent 恢复后收敛，
  /// 意图已关则呈现空闲状态。
  func agentDidStop() {
    systemProxyNetworkChangeMonitor.stop()
    systemProxyHealthTask?.cancel()
    systemProxyHealthTask = nil
    systemProxyObservationMode = .stopped
    if isIntentEnabled() {
      systemProxyState = .pending
    } else {
      if !systemProxyState.hasOperationFailure {
        systemProxyState = .idle
      }
      updateSystemProxyActions()
    }
  }

  /// agent 关闭级联的清理结果呈现（setAgentEnabled off）：typed 失败原样
  /// 上屏（清理不重试），成功不覆盖既有呈现。
  func presentCleanupOutcome(_ outcome: SystemProxyApplicationFacts) {
    if outcome.hasOperationFailure {
      systemProxyState = outcome
    }
    updateSystemProxyActions()
  }

  /// mode 切换发现无可收敛运行时（agent 关或无活动文档）：代理意图仍开时
  /// 保持待应用，等运行时恢复后由健康循环收敛（+Mode 提前出口）。
  func modeTransitionAwaitingRuntime() {
    if isIntentEnabled() {
      systemProxyState = .pending
    }
  }

  /// launch 重同步开始（resyncOnLaunch 入口）：抑制期 converge/suspend 拒绝
  /// 执行、健康循环跳过巡检；须由 settle 命令解除。
  func beginStartupResync() {
    systemProxyStartupInProgress = true
  }

  /// launch 重同步收尾（agent 意图关闭分支）：解除抑制（抑制期 suspend 的
  /// 守卫会拒绝执行）；代理意图仍开则挂起残留配置并转入观察。
  func settleLaunchWithAgentOff() async {
    systemProxyStartupInProgress = false
    if isIntentEnabled() {
      await suspendSystemProxy()
      startEnabledSystemProxyObservation()
    }
  }

  /// launch 重同步收尾（agent 已收敛分支）：解除抑制；代理意图开则播种期望
  /// 配置（健康 GUI 启动只巡检不强推应用），按出口可用性巡检或挂起，转入
  /// 观察；意图关呈现空闲。
  func settleLaunchAfterAgentConverged() async {
    systemProxyStartupInProgress = false
    if isIntentEnabled() {
      lastDesiredSystemProxyConfiguration = desiredConfiguration()
      if isExitAvailable() {
        await recheckSystemProxy()
      } else {
        await suspendSystemProxy()
      }
      startEnabledSystemProxyObservation()
    } else {
      systemProxyState = .idle
    }
  }
}

// MARK: - helper 门禁

extension SystemProxyObserver {
  /// helper 可用性门禁：已批准即通过——仅当 LaunchDaemon 清单
  /// 与上次注册时的指纹漂移（app 更新改过清单）才注销重注刷新 launchd 的
  /// job 定义；未注册则尝试注册（注册本身不弹授权框，成功即记指纹）；待批准
  /// 或注册失败时置位批准路径并保持待应用。
  private func ensureHelperAvailableForApply() async -> Bool {
    switch systemProxyHelper.status {
    case .approved:
      if helperRegistrationDrifted() {
        do {
          try systemProxyHelper.unregister()
          // launchd 对节流中（spawn scheduled）job 的移除是异步的：立即重注
          // 会命中尚未移除的旧定义（实测注销重注后定义不变）。等过 minimum
          // runtime（10s）节流窗再重注；间隔内收敛以旧定义失败呈超时。
          try? await Task.sleep(nanoseconds: helperRefreshDelayNanoseconds)
          try systemProxyHelper.register()
          storeHelperRegistrationStamp()
        } catch {
          // 刷新失败不记指纹，下次启动重试；状态退回后由下方分支接手。
          RuntimeLog.emit(.systemProxyHelperRegisterFailed(detail: String(describing: error)))
        }
      }
      if systemProxyHelper.status == .approved {
        systemProxyApprovalRequired = false
        return true
      }
    case .notRegistered:
      do {
        try systemProxyHelper.register()
        storeHelperRegistrationStamp()
      } catch {
        RuntimeLog.emit(.systemProxyHelperRegisterFailed(detail: String(describing: error)))
      }
      if systemProxyHelper.status == .approved {
        systemProxyApprovalRequired = false
        return true
      }
    case .requiresApproval:
      break
    }
    systemProxyApprovalRequired = true
    return false
  }

  private func helperRegistrationDrifted(defaults: UserDefaults = .standard) -> Bool {
    SystemProxyHelperRegistrationStamp.drifted(
      plistData: SystemProxyHelperIdentity.launchDaemonPlistData(in: appBundle),
      storedStamp: defaults.string(forKey: SystemProxyHelperRegistrationStamp.defaultsKey))
  }

  private func storeHelperRegistrationStamp(defaults: UserDefaults = .standard) {
    guard let plistData = SystemProxyHelperIdentity.launchDaemonPlistData(in: appBundle) else {
      return
    }
    defaults.set(
      SystemProxyHelperRegistrationStamp.stamp(plistData),
      forKey: SystemProxyHelperRegistrationStamp.defaultsKey)
  }

  /// Approval continues only an unattempted initial request; failed writes need a user retry.
  func openSystemProxyHelperApproval() async {
    systemProxyHelper.openApprovalPath()
    refreshSystemProxyApproval()
    if systemProxyInitialApplyPending && !systemProxyState.hasOperationFailure {
      await convergeSystemProxy()
    }
    updateSystemProxyActions()
  }

}

// MARK: - 意图保持与清理

extension SystemProxyObserver {
  /// Health/exit loss clears unavailable settings while preserving enabled intent.
  func holdSystemProxyIntent() async {
    if isIntentEnabled() {
      await suspendSystemProxy()
    } else if !systemProxyState.hasOperationFailure {
      systemProxyState = .idle
    }
  }

  /// 无条件清除全部系统代理配置：typed 失败原样呈现，不重试。
  private func clearSystemProxyOutcome() async -> SystemProxyApplicationFacts {
    do {
      try await systemProxy.clear()
      return .idle
    } catch {
      refreshSystemProxyApproval()
      return .clearFailed(systemProxyFacts(for: error))
    }
  }

  func startEnabledSystemProxyObservation() {
    guard systemProxyObservationMode != .enabled else { return }
    systemProxyObservationMode = .enabled
    scheduleSystemProxyHealthObservation()
    systemProxyNetworkChangeMonitor.start { [weak self] change in
      self?.handleSystemProxyNetworkChange(change)
    }
  }

  func clearAndStopSystemProxyObservation() async -> SystemProxyApplicationFacts {
    if let systemProxyCleanupTask { return await systemProxyCleanupTask.value }
    let task = Task { @MainActor [weak self] in
      guard let self else { return SystemProxyApplicationFacts.idle }
      return await self.performSystemProxyCleanupUntilQuiet()
    }
    systemProxyCleanupTask = task
    let result = await task.value
    systemProxyCleanupTask = nil
    return result
  }

  private func performSystemProxyCleanupUntilQuiet() async -> SystemProxyApplicationFacts {
    if systemProxyObservationMode != .enabled {
      systemProxyObservationMode = .cleanup
      systemProxyNetworkChangeMonitor.start { [weak self] change in
        self?.handleSystemProxyNetworkChange(change)
      }
    } else {
      systemProxyObservationMode = .cleanup
    }

    guard await waitForSystemProxyOperation() else { return systemProxyState }
    beginSystemProxyOperation()
    var outcome: SystemProxyApplicationFacts = .idle
    repeat {
      systemProxyCleanupRescanRequested = false
      outcome = await clearSystemProxyOutcome()
      // Let queued SystemConfiguration notifications reach the main actor. Any
      // location/service/proxy change during this cleanup starts another full scan.
      try? await Task.sleep(nanoseconds: cleanupSettleNanoseconds)
      await Task.yield()
    } while systemProxyCleanupRescanRequested && !outcome.hasOperationFailure

    systemProxyNetworkChangeMonitor.stop()
    systemProxyHealthTask?.cancel()
    systemProxyHealthTask = nil
    systemProxyObservationMode = .stopped
    systemProxyInspection = SystemProxyInspectionFacts()
    endSystemProxyOperation()
    return outcome
  }

  private func handleSystemProxyNetworkChange(_ change: SystemProxyNetworkChange) {
    switch systemProxyObservationMode {
    case .stopped:
      return
    case .cleanup:
      if !change.isDisjoint(with: [.networkConfiguration, .proxyConfiguration]) {
        systemProxyCleanupRescanRequested = true
      }
    case .enabled:
      guard isIntentEnabled() else { return }
      guard !systemProxyInspectionScheduled else { return }
      systemProxyInspectionScheduled = true
      systemProxyInspectionTask = Task { @MainActor [weak self] in
        await Task.yield()
        guard let self else { return }
        self.systemProxyInspectionScheduled = false
        await self.recheckSystemProxy()
      }
    }
  }

}

// MARK: - 失败事实映射

extension SystemProxyObserver {
  private func systemProxyFacts(for error: Error) -> SystemProxyFailureFacts {
    if let error = error as? SystemProxyError {
      return .operation(SystemProxyOperationFailure(error))
    }
    if let error = error as? ProxyModeError {
      return .mode(error)
    }
    return .unknown
  }
}
