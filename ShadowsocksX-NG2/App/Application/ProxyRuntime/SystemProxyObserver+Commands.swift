import Foundation

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
  func ensureHelperAvailableForApply() async -> Bool {
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
  func clearSystemProxyOutcome() async -> SystemProxyApplicationFacts {
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
  func systemProxyFacts(for error: Error) -> SystemProxyFailureFacts {
    if let error = error as? SystemProxyError {
      return .operation(SystemProxyOperationFailure(error))
    }
    return .unknown
  }
}
