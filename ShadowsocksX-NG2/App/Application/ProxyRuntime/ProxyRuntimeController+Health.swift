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
    preparedContract: PreparedRuntimeContract? = nil
  ) async -> Bool {
    guard preparedContract == nil || preparedContract?.document == document else {
      return await reportRuntimeFileFailure(preserveProxyOnFailure: preserveProxyOnFailure)
    }
    let generation = flowGeneration
    let preparation = runtimePreparationGeneration
    let expectedDigest =
      requiresReceipt ? (preparedContract?.sha256 ?? document.deploymentSHA256) : nil
    guard !requiresReceipt || expectedDigest != nil else {
      return await reportRuntimeFileFailure(preserveProxyOnFailure: preserveProxyOnFailure)
    }

    let deadline = Date().addingTimeInterval(launchHealthTimeoutSeconds)
    var endpointFailure: LocalEndpointFailure?
    while Date() < deadline {
      guard generation == flowGeneration, preparation == runtimePreparationGeneration else {
        return false
      }
      let attempt = await launchHealthAttempt(document, expectedDigest: expectedDigest)
      guard generation == flowGeneration, preparation == runtimePreparationGeneration else {
        return false
      }
      switch attempt {
      case .ready(let receipt):
        return await finishHealthyLaunch(
          document,
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
    _ document: SslocalRuntimeDocument,
    expectedDigest: String?
  ) async -> LaunchHealthAttempt {
    var receiptForHealth: RuntimeDeploymentReceipt?
    if let expectedDigest {
      guard let receipt = runtimeFileStore.readRuntimeReceipt(),
        receipt.contractSHA256 == expectedDigest
      else {
        return .retry(nil)
      }
      guard receipt.processID > 0, processIsAlive(receipt.processID) else {
        return .agentLost
      }
      receiptForHealth = receipt
    }

    if let endpointFailure = await unhealthyLocalEndpoint(in: document) {
      return .retry(endpointFailure)
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
    _ document: SslocalRuntimeDocument,
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
      receipt.contractSHA256 == expectedDigest
    else { return false }
    return receiptIsCurrentAndLive(receipt)
  }

  private func unhealthyLocalEndpoint(
    in document: SslocalRuntimeDocument
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
  /// Uses the existing local endpoint/receipt health seam while the GUI is alive.
  /// Network path availability is deliberately absent from this decision.
  /// 任务柄与循环调度在观察机（scheduleSystemProxyHealthObservation）；循环体
  /// 留在本体——它同时承担运行时健康呈现，系统代理反应转发给观察机。
  func runSystemProxyHealthObservationLoop() async {
    while !Task.isCancelled {
      try? await Task.sleep(nanoseconds: systemProxyHealthPollIntervalNanoseconds)
      guard !Task.isCancelled,
        settings.systemProxyEnabled || systemProxyState.hasOperationFailure
      else { return }
      systemProxyObserver.refreshSystemProxyApproval()
      systemProxyObserver.updateSystemProxyActions()
      guard settings.systemProxyEnabled, state != .starting,
        !systemProxyObserver.systemProxyStartupInProgress, settings.agentEnabled,
        let document = lastDocument
      else { continue }
      await inspectSystemProxyRuntimeHealth(document)
    }
  }

  private func inspectSystemProxyRuntimeHealth(_ document: SslocalRuntimeDocument) async {
    let generation = flowGeneration
    let outcome = await launchHealthAttempt(
      document, expectedDigest: document.aclRuntime != nil ? document.deploymentSHA256 : nil)
    // await 恢复后重查意图与代际：agent 已被关闭或已有新 execute 时，
    // 失败呈现与系统代理挂起都归属新的意图状态，本任务不得再改写。
    guard !Task.isCancelled, generation == flowGeneration, settings.systemProxyEnabled,
      settings.agentEnabled
    else {
      return
    }
    switch outcome {
    case .ready:
      let wasUnavailable = systemProxyObserver.systemProxyWasUnavailable
      switch state {
      case .running, .firewallBlocked: break
      default: await presentFirewallStatus(for: document)
      }
      if !systemProxyExitAvailable {
        await systemProxyObserver.suspendSystemProxy()
      } else if wasUnavailable || systemProxyObserver.systemProxyInitialApplyPending {
        await systemProxyObserver.convergeSystemProxy()
      }
    case .agentLost:
      state = .serviceFailed(.agent)
      await systemProxyObserver.suspendSystemProxy()
    case .retry(let failure):
      if let failure { presentEndpointFailure(failure) } else { state = .serviceFailed(.agent) }
      await systemProxyObserver.suspendSystemProxy()
    }
  }
}
