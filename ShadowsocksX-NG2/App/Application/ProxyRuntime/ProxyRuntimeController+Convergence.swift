import Foundation

/// 一次计划执行的结果:动作是否全部按序成功,以及本次执行占用的并发流
/// 代际。占用代际供收敛票据推进 flow 分量,取代调用方对 execute 内部
/// 「恰好自增一次」时序的依赖(原 `flowGeneration + 1` 手算)。
struct RuntimeExecutionOutcome {
  /// 本次执行占用的 `flowGeneration`。
  let flow: Int
  /// 全部计划动作是否按序成功。
  let succeeded: Bool
}

/// 收敛票据:运行时收敛操作的代际快照。入口捕获三个并发代际,之后每步
/// 推进用它判定「从入口到现在,并发流 / 模式切换 / 运行时派生是否前进了,
/// 会话内 agent 意图是否仍开启」;被更新提交或新意图取代的旧收敛不得再
/// 变更运行时状态或写契约。
///
/// 四项失效事实由票据恒全查,不随调用路径增减——「什么会使一次收敛失效」
/// 是票据的固有语义(逐路径手选子集曾让 agent 关闭在 mode 切换的健康门
/// await 窗口内被误分类为失败并触发复活性的 restore)。各路径只负责捕获
/// 与推进时机:flow 分量在 execute 后以实际占用值推进,mode 切换路径在
/// 派生后推进 preparation 分量(派生自身会推进它),rules 部署在推进 mode
/// 代际之后捕获。
private struct ConvergenceTicket: Equatable {
  /// 并发流代际;每次 execute 之后由调用方以实际占用值推进。
  var flow: Int
  /// 模式切换代际;捕获后不再变化。
  let mode: Int
  /// 运行时文档派生代际;每次派生之后由调用方以当前值推进。
  var preparation: Int
}

extension ProxyRuntimeController {
  /// 以当前代际捕获收敛票据。
  private func convergenceTicket() -> ConvergenceTicket {
    ConvergenceTicket(
      flow: flowGeneration, mode: modeChangeGeneration,
      preparation: runtimePreparationGeneration)
  }

  /// 票据是否仍代表当前收敛:并发流 / 模式切换 / 派生三个代际均未前进,
  /// 且会话内 agent 意图仍开启。
  private func convergenceIsCurrent(_ ticket: ConvergenceTicket) -> Bool {
    ticket.flow == flowGeneration && ticket.mode == modeChangeGeneration
      && ticket.preparation == runtimePreparationGeneration
      && settings.agentEnabled
  }

  /// 派生文档对当前运行时是否无事可做（GLOSSARY.md「有效值未变的提交不做
  /// 运行时收敛」）：磁盘契约与派生字节逐位相同、agent 已注册且 wrapper
  /// 存活、控制器处于健康运行态——计划层动作序列为空即幂等跳过。判定在
  /// 置 `starting` 之前进行，跳过路径不闪状态、不重走健康门；磁盘漂移或
  /// wrapper 失踪时动作序列自然非空，走完整 deploy 自愈。
  private func convergencePlanIsEmpty(
    _ document: SslocalRuntimeDocument, preparedContract: PreparedRuntimeContract?
  ) -> Bool {
    switch state {
    case .running, .firewallBlocked:
      break
    case .off, .starting, .launchFailed, .requiresApproval, .serviceFailed:
      return false
    }
    let actions = ProxyRuntimePlan.actions(
      intent: .run(document),
      agentStatus: agent.status,
      wrapper: wrapperState(),
      contractOnDisk: runtimeFileStore.readData(), preparedContract: preparedContract)
    return actions.isEmpty
  }

  /// 统一的设置持久化 epilogue：保存失败不静默偏离持久化事实——记录日志、
  /// 呈现 `serviceFailed(.persistence)`，调用方放弃本次收敛。
  func persistSettings(_ proposed: ProxySettings) -> Bool {
    do {
      try settingsStore.save(proposed)
      return true
    } catch {
      RuntimeLog.emit(.runtimePersistFailed(detail: String(describing: error)))
      state = .serviceFailed(.persistence)
      return false
    }
  }

  /// reexpand 三-case 开关的收敛主体（显式收敛、设置保存、启动重同步共用）：
  /// deployed → 部署派生文档；目标失效 → 清除并按意图收敛；无目标 → 空监听。
  /// 幂等跳过由 apply 层的 plan 空判定承担；目录重校验（跳过名单、目标失效
  /// 清除）已在 `reexpand` 完成，不受其影响。
  func convergeToReexpanded(_ catalog: ConfigurationCatalog) async {
    guard catalogSnapshotReader.isCatalogAvailable else { return }
    switch reexpand(in: catalog) {
    case .deployed(let configuration):
      await deploy(configuration.document)
    case .clearedAndStopped(let failure):
      await handleCleared(failure)
    case nil:
      await deployListeningWithoutTarget()
    }
  }

  /// 一个意图入口隐藏派生、执行政策、恢复和失败呈现；调用者不组合执行选项。
  enum RuntimeConvergenceIntent {
    case deployment(SslocalRuntimeDocument)
    case modeTransition(ModeTransitionSnapshot)
    case savedRules
  }

  /// 用户改变模式前的事实，由意图命令捕获；恢复计划只在收敛实现中构造。
  struct ModeTransitionSnapshot {
    let settings: ProxySettings
    let mode: ProxyMode
    let document: SslocalRuntimeDocument?
    let state: AgentRunState
  }

  enum ConvergenceResult {
    case applied
    case unchanged
    /// 派生或部署失败；该意图要求的恢复与失败呈现已经处理。
    case failed
    /// 被新意图取代，不得恢复或发布旧结果。
    case superseded
  }

  @discardableResult
  func convergeRuntime(_ intent: RuntimeConvergenceIntent) async -> ConvergenceResult {
    guard catalogSnapshotReader.isCatalogAvailable else { return .failed }
    switch intent {
    case .deployment(let source): return await convergeDeployment(source)
    case .modeTransition(let snapshot): return await convergeModeTransition(snapshot)
    case .savedRules: return await convergeSavedRules()
    }
  }

  private func convergeDeployment(_ source: SslocalRuntimeDocument) async -> ConvergenceResult {
    if settingsUnreadable {
      RuntimeLog.emit(.activationFailed(reason: "settings unreadable"))
      _ = await execute(.stop, document: nil)
      lastDocument = nil
      skippedServers = []
      state = .launchFailed(.unreadableSettings)
      await systemProxyObserver.holdSystemProxyIntent()
      return .failed
    }
    let contract: PreparedRuntimeContract
    do {
      contract = try PreparedRuntimeContract(await runtimeDocument(source, for: proxyMode))
    } catch RulePreparationError.superseded {
      return .superseded
    } catch {
      RuntimeLog.emit(.runtimePersistFailed(detail: String(describing: error)))
      state = .serviceFailed(.runtimeFile)
      return .failed
    }
    var ticket = convergenceTicket()
    return await apply(contract.document, ticket: &ticket, policy: .deployment)
  }

  private func convergeModeTransition(_ snapshot: ModeTransitionSnapshot) async -> ConvergenceResult
  {
    var ticket = convergenceTicket()
    guard settings.agentEnabled, state != .off,
      let current = lastDocument ?? runtimeFileStore.loadDocument()
    else {
      systemProxyObserver.modeTransitionAwaitingRuntime()
      return .unchanged
    }
    let plan = RollbackPlan(
      document: snapshot.document ?? current, state: snapshot.state,
      payload: .modeTransition(
        mode: snapshot.mode, ruleDefaultAction: snapshot.settings.ruleDefaultAction),
      systemProxyIntentAtCapture: snapshot.settings.systemProxyEnabled,
      convergeProxyOnIntentChange: true)
    let next: SslocalRuntimeDocument
    do {
      next = try await runtimeDocument(current, for: proxyMode)
    } catch RulePreparationError.superseded {
      return .superseded
    } catch {
      RuntimeLog.emit(.runtimePersistFailed(detail: String(describing: error)))
      ticket.preparation = runtimePreparationGeneration
      await recoverModeTransition(plan, ticket: &ticket)
      return .failed
    }
    // 派生会推进 preparation；仅该意图在派生前捕获了收敛票据。
    ticket.preparation = runtimePreparationGeneration
    guard next.aclRuntime != current.aclRuntime else {
      // 保留原有特殊路径：无系统代理意图即结束；否则只检查健康，不部署或恢复。
      guard settings.systemProxyEnabled else { return .unchanged }
      state = .starting
      return await presentLaunchHealth(next) ? .applied : .failed
    }
    let result = await apply(next, ticket: &ticket, policy: .modeTransition)
    if case .failed = result { await recoverModeTransition(plan, ticket: &ticket) }
    return result
  }

  private func recoverModeTransition(_ plan: RollbackPlan, ticket: inout ConvergenceTicket) async {
    let report = await restore(plan, ticket: &ticket)
    if report.runtimeHealthy == true, report.payloadFailureDescription != nil {
      state = .serviceFailed(.persistence)
    }
  }

  private func convergeSavedRules() async -> ConvergenceResult {
    guard proxyMode == .rule, settings.agentEnabled, state != .off,
      let current = lastDocument ?? runtimeFileStore.loadDocument()
    else { return .unchanged }
    let revision = ruleDocuments.revision
    let plan = RollbackPlan(
      document: current, state: state, payload: .runtimeOnly,
      systemProxyIntentAtCapture: settings.systemProxyEnabled,
      convergeProxyOnIntentChange: false)
    let next: SslocalRuntimeDocument
    do {
      next = try await runtimeDocument(current, for: proxyMode)
    } catch RulePreparationError.superseded {
      return .superseded
    } catch {
      RuntimeLog.emit(.runtimePersistFailed(detail: String(describing: error)))
      ruleApplicationFailure = .service(.runtimeFile)
      return .failed
    }
    guard next.aclRuntime != current.aclRuntime || ruleApplicationFailure != nil else {
      ruleApplicationFailure = nil
      return .unchanged
    }
    modeChangeGeneration += 1
    var ticket = convergenceTicket()
    let result = await apply(next, ticket: &ticket, policy: .savedRules)
    switch result {
    case .applied, .unchanged:
      if revision == ruleDocuments.revision { ruleApplicationFailure = nil }
    case .superseded:
      break
    case .failed:
      let failure = ProxyRuntimeFacts(state: state).failure ?? .service(.runtimeFile)
      _ = await restore(plan, ticket: &ticket)
      if convergenceIsCurrent(ticket), revision == ruleDocuments.revision {
        ruleApplicationFailure = failure
      }
    }
    return result
  }

  /// 三种意图的执行差异只在 module 内选择，不能由调用者拼成任意组合。
  private enum DeploymentPolicy {
    case deployment
    case modeTransition
    case savedRules
  }

  /// 共用执行脊柱；恢复在同一 module 的意图实现中，票据不越过意图 seam。
  private func apply(
    _ document: SslocalRuntimeDocument,
    ticket: inout ConvergenceTicket,
    policy: DeploymentPolicy
  ) async -> ConvergenceResult {
    let contract = try? PreparedRuntimeContract(document)
    if convergencePlanIsEmpty(document, preparedContract: contract) {
      RuntimeLog.emit(.contractUnchanged)
      ruleApplicationFailure = nil
      return .unchanged
    }
    guard convergenceIsCurrent(ticket) else { return .superseded }
    lastDocument = document
    state = .starting
    let execution = await execute(.run(document), document: document, preparedContract: contract)
    ticket.flow = execution.flow
    guard convergenceIsCurrent(ticket) else { return .superseded }
    guard execution.succeeded else { return .failed }
    let healthy = await presentLaunchHealth(
      document,
      requiresReceipt: policy != .deployment || document.aclRuntime != nil,
      convergeProxyOnSuccess: policy == .deployment,
      preserveProxyOnFailure: policy != .deployment, preparedContract: contract)
    guard convergenceIsCurrent(ticket) else { return .superseded }
    guard healthy else { return .failed }
    lastDocument = document
    ruleApplicationFailure = nil
    switch policy {
    case .modeTransition: await systemProxyObserver.convergeSystemProxy(forceApply: true)
    case .savedRules: await systemProxyObserver.convergeSystemProxy()
    case .deployment: break
    }
    return .applied
  }

  /// 按回滚计划整体恢复:先查时效(票据含会话内 agent 意图)再动任何事实——
  /// 被取代或 agent 已被用户关闭的回滚不得把旧载荷写回持久层、也不得把
  /// 旧文档重新拉起;随后重持久化载荷 → 计划执行拉回旧文档(含按需拉起,
  /// 由计划层对注销/信号/注册的裁决保证与旧 restore 例程等价)→ 启动健康
  /// 门。载荷持久化失败不阻断文档恢复;文档恢复失败或健康不过即撤下系统
  /// 代理意图。
  private func restore(_ plan: RollbackPlan, ticket: inout ConvergenceTicket) async -> RestoreReport
  {
    guard convergenceIsCurrent(ticket) else {
      return RestoreReport(payloadFailureDescription: nil, runtimeHealthy: nil)
    }
    var payloadFailureDescription: String?
    var restoredSettingsForMemory: ProxySettings?
    var restoredMode: ProxyMode?
    switch plan.payload {
    case .modeTransition(let mode, let ruleDefaultAction):
      // 按快照还原偏好（模式与子选项回退，其余字段保留当前值）。
      var restored = settings
      restored.preferredMode = mode.kind
      restored.ruleDefaultAction = ruleDefaultAction
      do {
        try settingsStore.save(restored)
      } catch {
        payloadFailureDescription = String(describing: error)
        RuntimeLog.emit(.runtimePersistFailed(detail: String(describing: error)))
      }
      restoredSettingsForMemory = restored
      restoredMode = mode
    case .runtimeOnly:
      break
    }
    func report(_ healthy: Bool?) -> RestoreReport {
      RestoreReport(
        payloadFailureDescription: payloadFailureDescription, runtimeHealthy: healthy)
    }
    if let restoredSettingsForMemory { settings = restoredSettingsForMemory }
    if let restoredMode { proxyMode = restoredMode }
    lastDocument = plan.document
    state = .starting
    let contract = try? PreparedRuntimeContract(plan.document)
    let execution = await execute(
      .run(plan.document), document: plan.document, preparedContract: contract)
    ticket.flow = execution.flow
    guard convergenceIsCurrent(ticket) else { return report(nil) }
    guard execution.succeeded else {
      await systemProxyObserver.holdSystemProxyIntent()
      return report(false)
    }
    let healthy = await presentLaunchHealth(
      plan.document, requiresReceipt: true, convergeProxyOnSuccess: false,
      preparedContract: contract)
    guard convergenceIsCurrent(ticket) else { return report(nil) }
    if healthy {
      if plan.convergeProxyOnIntentChange,
        settings.systemProxyEnabled != plan.systemProxyIntentAtCapture
      {
        await systemProxyObserver.convergeSystemProxy(forceApply: true)
      } else {
        state = plan.state
      }
    } else {
      await systemProxyObserver.holdSystemProxyIntent()
    }
    return report(healthy)
  }
}

/// 收敛失败时的整体回滚计划：恢复到哪个运行时文档、健康通过后呈现哪个
/// 状态、以及除文档外还要重持久化的载荷。
private struct RollbackPlan {
  /// 回滚载荷：除运行时文档外还要恢复的持久化事实。
  enum Payload {
    /// mode 切换：设置快照的模式与规则子选项回退（其余字段保留当前值），
    /// 会话内 proxyMode 一并还原。
    case modeTransition(mode: ProxyMode, ruleDefaultAction: RuleDefaultAction)
    /// Rule application restores only the previous runtime, never saved intent.
    case runtimeOnly
  }

  /// 回滚目标文档（调用方已用当次加载值补齐）。
  let document: SslocalRuntimeDocument
  /// 健康通过后呈现的状态（收敛开始前捕获）。
  let state: ProxyRuntimeController.AgentRunState
  let payload: Payload
  /// 捕获时的系统代理意图：恢复健康后若当前意图已变化，强制重收敛一次。
  let systemProxyIntentAtCapture: Bool
  /// 是否在意图变化时强制重收敛（mode 切换路径；rules 路径为 false）。
  let convergeProxyOnIntentChange: Bool
}

/// 回滚报告：载荷重持久化与旧运行时恢复的结果。
private struct RestoreReport {
  /// 载荷持久化失败的点名描述；nil = 成功。
  let payloadFailureDescription: String?
  /// 旧运行时是否恢复到健康；nil = 恢复未尝试（被弃权或被取代）。
  let runtimeHealthy: Bool?
}
