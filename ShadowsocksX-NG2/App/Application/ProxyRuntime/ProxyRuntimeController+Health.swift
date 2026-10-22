import Foundation

private struct LocalEndpointFailure {
  let local: SslocalLocalDocument
  let host: String
  let outcome: EndpointHealthProbe.Outcome
}

private enum LaunchHealthAttempt {
  case ready(RuntimeDeploymentReceipt?)
  case retry(LocalEndpointFailure?)
  case agentLost
}

private struct LaunchHealthTimeout {
  let expectedDigest: String?
  let endpointFailure: LocalEndpointFailure?
  let generation: Int
  let preparation: Int
  let preserveProxyOnFailure: Bool
}

extension ProxyRuntimeController {
  /// 启动健康呈现：确认本地入站；直连模式额外要求
  /// 回执持续指向当前健康子进程，防止旧监听通过共享端口冒充新实例。
  @discardableResult
  func presentLaunchHealth(
    _ document: SslocalRuntimeDocument,
    requiresReceipt: Bool = false,
    convergeProxyOnSuccess: Bool = true,
    preserveProxyOnFailure: Bool = false,
    preparedContract: PreparedRuntimeContract? = nil,
    reloadingProcessID: Int32? = nil
  ) async -> Bool {
    guard preparedContract == nil || preparedContract?.document == document else {
      return await reportRuntimeFileFailure(preserveProxyOnFailure: preserveProxyOnFailure)
    }
    let facts = RuntimeDeploymentFacts(document)
    let generation = flowGeneration
    let preparation = runtimePreparationGeneration
    let expectedDigest =
      requiresReceipt ? runtimeFileStore.receiptIdentity(for: document.intentSHA256) : nil
    guard !requiresReceipt || expectedDigest != nil else {
      return await reportRuntimeFileFailure(preserveProxyOnFailure: preserveProxyOnFailure)
    }

    let deadline = Date().addingTimeInterval(launchHealthTimeoutSeconds)
    var endpointFailure: LocalEndpointFailure?
    while Date() < deadline {
      guard generation == flowGeneration, preparation == runtimePreparationGeneration else {
        return false
      }
      let attempt = await launchHealthAttempt(
        facts, expectedDigest: expectedDigest, reloadingProcessID: reloadingProcessID)
      guard generation == flowGeneration, preparation == runtimePreparationGeneration else {
        return false
      }
      switch attempt {
      case .ready(let receipt):
        return await finishHealthyLaunch(
          facts,
          receipt: receipt,
          generation: (generation, preparation),
          convergeProxyOnSuccess: convergeProxyOnSuccess,
          preserveProxyOnFailure: preserveProxyOnFailure)
      case .retry(let endpoint):
        endpointFailure = endpoint
      case .agentLost:
        return await reportAgentLost(preserveProxyOnFailure: preserveProxyOnFailure)
      }
      try? await launchHealthRetryDelay()
    }
    return await reportLaunchHealthTimeout(
      LaunchHealthTimeout(
        expectedDigest: expectedDigest,
        endpointFailure: endpointFailure,
        generation: generation, preparation: preparation,
        preserveProxyOnFailure: preserveProxyOnFailure))
  }

  private func launchHealthAttempt(
    _ document: RuntimeDeploymentFacts,
    expectedDigest: String?, reloadingProcessID: Int32? = nil
  ) async -> LaunchHealthAttempt {
    if runtimeFileStore.blocksDeployment(document.intentSHA256) { return .agentLost }
    var receiptForHealth: RuntimeDeploymentReceipt?
    if let expectedDigest {
      guard let receipt = runtimeFileStore.readRuntimeReceipt(),
        receipt.deploymentID == expectedDigest
      else {
        return .retry(nil)
      }
      guard receipt.processID > 0, processIsAlive(receipt.processID) else {
        return .agentLost
      }
      receiptForHealth = receipt
    }

    if reloadingProcessID == nil || receiptForHealth?.processID != reloadingProcessID {
      if reloadingProcessID != nil { state = .starting }
      if let endpointFailure = await unhealthyLocalEndpoint(in: document) {
        return .retry(endpointFailure)
      }
    }

    if let receiptForHealth {
      guard runtimeFileStore.readRuntimeReceipt() == receiptForHealth else {
        return .retry(nil)
      }
      guard processIsAlive(receiptForHealth.processID) else { return .agentLost }
    }
    return .ready(receiptForHealth)
  }

  private func finishHealthyLaunch(
    _ document: RuntimeDeploymentFacts,
    receipt: RuntimeDeploymentReceipt?,
    generation: (flow: Int, preparation: Int),
    convergeProxyOnSuccess: Bool,
    preserveProxyOnFailure: Bool
  ) async -> Bool {
    guard generation.flow == flowGeneration,
      generation.preparation == runtimePreparationGeneration
    else { return false }
    await presentFirewallStatus(for: document)
    guard generation.flow == flowGeneration,
      generation.preparation == runtimePreparationGeneration
    else { return false }
    if let receipt, !receiptIsCurrentAndLive(receipt) {
      return await reportAgentLost(preserveProxyOnFailure: preserveProxyOnFailure)
    }
    if convergeProxyOnSuccess { await systemProxyObserver.convergeSystemProxy() }
    return true
  }

  private func receiptIsCurrentAndLive(_ receipt: RuntimeDeploymentReceipt) -> Bool {
    guard receipt.processID > 0,
      runtimeFileStore.readRuntimeReceipt() == receipt
    else { return false }
    return processIsAlive(receipt.processID)
  }

  private func reportAgentLost(preserveProxyOnFailure: Bool) async -> Bool {
    guard !preserveProxyOnFailure else { return false }
    state = .serviceFailed(.agent)
    await systemProxyObserver.holdSystemProxyIntent()
    return false
  }

  private func reportRuntimeFileFailure(preserveProxyOnFailure: Bool) async -> Bool {
    guard !preserveProxyOnFailure else { return false }
    state = .serviceFailed(.runtimeFile)
    await systemProxyObserver.holdSystemProxyIntent()
    return false
  }

  private func reportLaunchHealthTimeout(_ timeout: LaunchHealthTimeout) async -> Bool {
    guard timeout.generation == flowGeneration,
      timeout.preparation == runtimePreparationGeneration
    else { return false }
    guard !timeout.preserveProxyOnFailure else { return false }
    if let expectedDigest = timeout.expectedDigest,
      !hasLiveReceipt(expectedDigest: expectedDigest)
    {
      return await reportAgentLost(preserveProxyOnFailure: false)
    }
    if let endpointFailure = timeout.endpointFailure {
      presentEndpointFailure(endpointFailure)
    } else {
      state = .launchFailed(
        .localEndpoint(endpoint: "SOCKS", host: "127.0.0.1", port: 0, cause: .unknown))
    }
    await systemProxyObserver.holdSystemProxyIntent()
    return false
  }

  private func hasLiveReceipt(expectedDigest: String) -> Bool {
    guard let receipt = runtimeFileStore.readRuntimeReceipt(),
      receipt.deploymentID == expectedDigest
    else { return false }
    return receiptIsCurrentAndLive(receipt)
  }

  private func unhealthyLocalEndpoint(
    in document: RuntimeDeploymentFacts
  ) async -> LocalEndpointFailure? {
    for local in document.locals {
      let outcome = await probeAsync(
        host: local.probeHost, port: local.localPort, timeout: 1.5)
      if outcome != .reachable {
        return LocalEndpointFailure(local: local, host: local.probeHost, outcome: outcome)
      }
    }
    return nil
  }

  private func presentEndpointFailure(_ failure: LocalEndpointFailure) {
    let detail: String
    let cause: RuntimeEndpointFailure
    switch failure.outcome {
    case .reachable:
      detail = "已连通"
      cause = .unknown
    case .refused(let reason):
      detail = reason
      cause = .refused
    case .timedOut:
      detail = "连接超时"
      cause = .timedOut
    }
    RuntimeLog.emit(
      .endpointProbeFailed(
        host: failure.host, port: failure.local.localPort, detail: detail))
    let endpointName = failure.local.inboundProtocol.uppercased()
    state = .launchFailed(
      .localEndpoint(
        endpoint: endpointName, host: failure.host, port: failure.local.localPort, cause: cause))
  }
}

extension ProxyRuntimeController {
  /// Agent 独占稳定运行期间的故障判定；GUI 只读取明确失败，避免重复连接入站。
  /// 任务柄仍由系统代理观察机持有，并保留批准状态与待首次应用的刷新。
  func runSystemProxyHealthObservationLoop() async {
    while !Task.isCancelled {
      try? await Task.sleep(nanoseconds: systemProxyHealthPollIntervalNanoseconds)
      guard !Task.isCancelled,
        settings.systemProxyEnabled || systemProxyState.hasOperationFailure
      else { return }
      systemProxyObserver.refreshSystemProxyApproval()
      systemProxyObserver.updateSystemProxyActions()
      guard settings.systemProxyEnabled, state != .starting, runtimeReloadProcesses.isEmpty,
        !systemProxyObserver.systemProxyStartupInProgress, settings.agentEnabled,
        let document = runtimeObservation
      else { continue }
      if let failure = runtimeFileStore.readFailure(),
        let deploymentID = runtimeFileStore.receiptIdentity(for: document.intentSHA256),
        failure.deploymentID == deploymentID
      {
        state = .serviceFailed(.agent)
        await systemProxyObserver.suspendSystemProxy()
      } else if systemProxyObserver.systemProxyInitialApplyPending {
        await systemProxyObserver.convergeSystemProxy()
      }
    }
  }
}
