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
  /// 运行时收敛」）：发布意图相同、输出字节未漂移、agent 已注册且 wrapper
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
      configurationIsCurrent: preparedContract.map { runtimeFileStore.contains($0) } ?? false)
    return actions.isEmpty
  }

  /// reexpand 三-case 开关的收敛主体（显式收敛、设置保存、启动重同步共用）：
  /// deployed → 部署派生文档；目标失效 → 清除并按意图收敛；无目标 → 空监听。
  /// 幂等跳过由 apply 层的 plan 空判定承担；目录重校验（跳过名单、目标失效
  /// 清除）已在 `reexpand` 完成，不受其影响。
  func convergeToReexpanded(_ catalog: ConfigurationCatalog) async {
    guard !settingsUnreadable else {
      state = .launchFailed(.unreadableSettings)
      return
    }
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

  /// 一个意图入口隐藏派生、执行政策和失败呈现；调用者不组合执行选项。
  enum RuntimeConvergenceIntent {
    case deployment(SslocalRuntimeDocument)
    case modeTransition
    case savedRules
  }

  enum ConvergenceResult {
    case applied
    case unchanged
    /// 派生或部署失败；失败呈现已经处理。
    case failed
    /// 被新意图取代，不得发布旧结果。
    case superseded
  }

  @discardableResult
  func convergeRuntime(_ intent: RuntimeConvergenceIntent) async -> ConvergenceResult {
    guard !settingsUnreadable else {
      state = .launchFailed(.unreadableSettings)
      return .failed
    }
    guard catalogSnapshotReader.isCatalogAvailable else { return .failed }
    switch intent {
    case .deployment(let source): return await convergeDeployment(source)
    case .modeTransition: return await convergeModeTransition()
    case .savedRules: return await convergeSavedRules()
    }
  }

  private func convergeDeployment(_ source: SslocalRuntimeDocument) async -> ConvergenceResult {
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

  private func convergeModeTransition() async -> ConvergenceResult {
    await convergeChangedIntent(policy: .modeTransition)
  }

  private func convergeSavedRules() async -> ConvergenceResult {
    guard proxyMode == .rule else { return .unchanged }
    let revision = ruleDocuments.revision
    let result = await convergeChangedIntent(policy: .savedRules)
    switch result {
    case .applied, .unchanged:
      if revision == ruleDocuments.revision { ruleApplicationFailure = nil }
    case .superseded:
      break
    case .failed:
      if revision == ruleDocuments.revision {
        ruleApplicationFailure = ProxyRuntimeFacts(state: state).failure ?? .service(.runtimeFile)
      }
    }
    return result
  }

  /// 模式与规则变更从同一份已保存资料重新展开，不以输出配置作为派生输入。
  private func convergeChangedIntent(policy: DeploymentPolicy) async -> ConvergenceResult {
    guard settings.agentEnabled, state != .off else {
      if policy == .modeTransition { systemProxyObserver.modeTransitionAwaitingRuntime() }
      return .unchanged
    }
    let source: SslocalRuntimeDocument
    switch reexpand(in: catalogSnapshotReader.catalogSnapshot) {
    case .deployed(let configuration): source = configuration.document
    case .clearedAndStopped(let failure):
      return await handleCleared(failure)
    case nil: source = SslocalRuntimeDocument(servers: [], listen: settings.listen)
    }
    var ticket = convergenceTicket()
    let next: SslocalRuntimeDocument
    let contract: PreparedRuntimeContract
    do {
      next = try await runtimeDocument(source, for: proxyMode)
      contract = try PreparedRuntimeContract(next)
    } catch RulePreparationError.superseded {
      return .superseded
    } catch {
      RuntimeLog.emit(.runtimePersistFailed(detail: String(describing: error)))
      if policy == .savedRules {
        ruleApplicationFailure = .service(.runtimeFile)
      } else {
        state = .serviceFailed(.runtimeFile)
      }
      return .failed
    }
    ticket.preparation = runtimePreparationGeneration
    let alreadyRunning: Bool
    switch state {
    case .running, .firewallBlocked: alreadyRunning = true
    default: alreadyRunning = false
    }
    let unchanged = runtimeFileStore.contains(contract)
    if policy == .savedRules, unchanged, ruleApplicationFailure == nil,
      runtimeFileStore.readFailure() == nil
    {
      return .unchanged
    }
    if policy == .modeTransition, unchanged,
      runtimeFileStore.readFailure() == nil, alreadyRunning
    {
      guard settings.systemProxyEnabled else { return .unchanged }
      state = .starting
      return await presentLaunchHealth(next) ? .applied : .failed
    }
    if policy == .savedRules {
      modeChangeGeneration += 1
      ticket = convergenceTicket()
    }
    return await apply(next, ticket: &ticket, policy: policy)
  }

  /// 三种意图的执行差异只在 module 内选择，不能由调用者拼成任意组合。
  private enum DeploymentPolicy {
    case deployment
    case modeTransition
    case savedRules
  }

  /// 共用执行脊柱；票据不越过意图 seam。
  private func apply(
    _ document: SslocalRuntimeDocument,
    ticket: inout ConvergenceTicket,
    policy: DeploymentPolicy
  ) async -> ConvergenceResult {
    let contract = try? PreparedRuntimeContract(document)
    if runtimeFileStore.blocksDeployment(document) {
      state = .serviceFailed(.agent)
      await systemProxyObserver.holdSystemProxyIntent()
      return .failed
    }
    if convergencePlanIsEmpty(document, preparedContract: contract) {
      RuntimeLog.emit(.contractUnchanged)
      ruleApplicationFailure = nil
      return .unchanged
    }
    guard convergenceIsCurrent(ticket) else { return .superseded }
    runtimeObservation = RuntimeDeploymentFacts(document)
    state = .starting
    let execution = await execute(.run(document), document: document, preparedContract: contract)
    ticket.flow = execution.flow
    guard convergenceIsCurrent(ticket) else { return .superseded }
    guard execution.succeeded else {
      if state != .requiresApproval, runtimeFileStore.receiptIdentity(for: document) != nil {
        await failDeployment(ticket: &ticket)
      }
      return .failed
    }
    let healthy = await presentLaunchHealth(
      document,
      requiresReceipt: policy != .deployment || document.aclRuntime != nil,
      convergeProxyOnSuccess: policy == .deployment,
      preserveProxyOnFailure: false, preparedContract: contract)
    guard convergenceIsCurrent(ticket) else { return .superseded }
    guard healthy else {
      await failDeployment(ticket: &ticket)
      return .failed
    }
    do { try runtimeFileStore.settleSuccessfulDeployment() } catch {
      state = .serviceFailed(.runtimeFile)
      await failDeployment(ticket: &ticket)
      return .failed
    }
    runtimeObservation = RuntimeDeploymentFacts(document)
    ruleApplicationFailure = nil
    switch policy {
    case .modeTransition: await systemProxyObserver.convergeSystemProxy(forceApply: true)
    case .savedRules: await systemProxyObserver.convergeSystemProxy()
    case .deployment: break
    }
    return .applied
  }

  /// 发布后失败保留配置及失败身份，停止服务但不改写两个开关意图。
  private func failDeployment(ticket: inout ConvergenceTicket) async {
    guard convergenceIsCurrent(ticket) else { return }
    var failureState = state
    do { try runtimeFileStore.recordFailure(reason: "GUI deployment verification failed") } catch {
      failureState = .serviceFailed(.runtimeFile)
    }
    let stopped = await unregisterFailedDeployment()
    guard convergenceIsCurrent(ticket) else { return }
    if stopped { state = failureState } else { state = .serviceFailed(.agent) }
    await systemProxyObserver.holdSystemProxyIntent()
  }

  private func unregisterFailedDeployment() async -> Bool {
    do { try agent.unregister() } catch { return false }
    await waitForWrapperExit()
    return wrapperState() == .notRunning && !runtimeFileStore.hasUnconfirmedChild
  }
}
