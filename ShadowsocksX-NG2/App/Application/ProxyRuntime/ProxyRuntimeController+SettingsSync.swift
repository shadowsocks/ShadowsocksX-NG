import Foundation

// MARK: - 设置变更与目录提交同步

extension ProxyRuntimeController {
  /// A published mapping invalidates prepared documents before asynchronous convergence.
  func pluginMappingsDidPublish() {
    runtimePreparationGeneration += 1
  }

  /// 目录提交协调器的生产适配入口：以刚提交的内存快照重展开，
  /// 不回读磁盘（磁盘仍是重启与跨进程恢复的权威来源）。agent 意图开启时
  /// 原子更新运行时；目标失效 → 清除目标但 agent 继续监听。返回结构化收敛
  /// 结果，健康检查耗时属于本调用的异步收敛阶段，不改变「目录已提交」的事实。
  /// 「有效值未变的提交不做运行时收敛」由收敛脊柱 apply 层的 plan 空判定
  /// 承担（`convergencePlanIsEmpty`）；派生被更新的收敛取代时按重校验呈现。
  func catalogDidCommit(snapshot catalog: ConfigurationCatalog) async -> RuntimeSyncOutcome {
    guard catalogSnapshotReader.isCatalogAvailable else { return .failed(failure: nil) }
    switch reexpand(in: catalog) {
    case .deployed(let configuration):
      guard settings.agentEnabled else {
        return .revalidated
      }
      let result = await deploy(configuration.document)
      if case .superseded = result {
        return .revalidated
      }
      return Self.syncOutcome(
        agentState: state, systemProxyState: systemProxyState,
        skippedServers: configuration.skippedServers)
    case .clearedAndStopped(let failure):
      await handleCleared(failure)
      return .clearedAndStopped(failure)
    case nil:
      guard settings.agentEnabled else {
        return .revalidated
      }
      // 无活动目标：已在以空列表监听则不重走健康门（目录提交不该让状态闪回
      // starting）；否则补齐空监听。
      if state != .off, lastDocument?.servers.isEmpty == true {
        return Self.syncOutcome(
          agentState: state, systemProxyState: systemProxyState, skippedServers: [])
      }
      await deployListeningWithoutTarget()
      return Self.syncOutcome(
        agentState: state, systemProxyState: systemProxyState, skippedServers: [])
    }
  }

  /// 部署后的控制器状态 → 结构化收敛结果：健康通过（含防火墙受阻的运行态）
  /// 视为已收敛；系统代理写入失败携带点名细节，待应用不算目录收敛失败。
  private static func syncOutcome(
    agentState: AgentRunState, systemProxyState: SystemProxyControlState,
    skippedServers: [SkippedServer]
  ) -> RuntimeSyncOutcome {
    if case .failed(let facts) = systemProxyState {
      return .failed(failure: .systemProxy(facts))
    }
    switch agentState {
    case .running, .firewallBlocked:
      return .converged(skippedServers: skippedServers)
    case .launchFailed(let facts):
      return .failed(failure: .launch(facts))
    case .serviceFailed(let facts):
      return .failed(failure: .service(facts))
    case .requiresApproval, .off, .starting:
      return .failed(failure: nil)
    }
  }

  /// 保存监听配置后更新内存并收敛；文件失败不发布新值。
  func updateListening(_ proposed: ProxyListeningConfiguration) async throws {
    try listeningStore.save(proposed)
    settings.listen = proposed
    settingsUnreadable = false
    guard state != .off else { return }
    await convergeToReexpanded(catalogSnapshotReader.catalogSnapshot)
  }

  /// 系统代理例外是独立偏好；更新后沿用当前运行配置派生与系统代理应用路径。
  func updateProxyExceptions(_ value: String) async {
    controlPreferences.proxyExceptions = value
    settings.proxyExceptions = value
    guard state != .off else { return }
    await convergeToReexpanded(catalogSnapshotReader.catalogSnapshot)
  }

  /// Applies the post-import 2.0 runtime boundary without touching
  /// SystemConfiguration. Importing data leaves the user's system proxy
  /// dictionary untouched; any currently running 2.0 runtime is stopped and
  /// the existing 2.0 target/settings are reloaded.
  func legacyImportDidCommit() async {
    cancelFirewallObservation()
    flowGeneration += 1
    _ = await execute(.stop, document: nil)
    state = .off
    lastDocument = nil
    skippedServers = []
    lastActivationFailure = nil
    // 导入边界不触碰 SystemConfiguration（既有不变量），系统代理状态面同
    // 样不动：它呈现的是系统设置的真实作用，不由导入改写。

    if let restored = try? listeningStore.load() {
      settings.listen = restored
      settingsUnreadable = false
    }
    let persistedTarget = try? activationFileStore.loadActiveTargetID()
    machine = ActivationStateMachine(activeTargetID: persistedTarget ?? nil)
    activeTargetID = machine.activeTargetID
  }
}
