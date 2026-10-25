import Foundation

// Agent 只读取非秘密监管资料，独占稳定链接切换。配置和认证由 GUI 准备。
redirectStandardStreams(to: agentLogURL)
// stderr 行式输出的来源标记：本进程是 wrapper，行内据此与 GUI 事件区分。
RuntimeLog.setLineSource(.wrapper)

// 日志与运行目录独立创建；不能依赖日志初始化建立生命周期锁的父目录。
do {
  try AtomicFileWriter.prepareDirectory(at: runtimePaths.directoryURL)
} catch { exit(1) }
// 生命周期锁防止两个 Agent 同时启动监听进程。锁随进程退出自动释放。
let agentLock = open(
  runtimePaths.agentLockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
guard agentLock >= 0, flock(agentLock, LOCK_EX | LOCK_NB) == 0 else { exit(0) }

try? AtomicFileWriter.write(Data("\(getpid())\n".utf8), to: pidFileURL)
let exitStatus = supervise()
try? FileManager.default.removeItem(at: pidFileURL)
clearRuntimeReceipt()
close(agentLock)
exit(exitStatus)

private func supervise() -> Int32 {
  let flags = SignalFlags()
  let stopSource = observeSignal(SIGTERM, flags: flags) { flags.requestStop() }
  let interruptSource = observeSignal(SIGINT, flags: flags) { flags.requestStop() }
  let reloadSource = observeSignal(SIGUSR1, flags: flags) { flags.requestReload() }
  defer {
    stopSource.cancel()
    interruptSource.cancel()
    reloadSource.cancel()
  }

  while !flags.consumeStop() {
    guard let document = loadValidatedContract(), !deploymentHasFailed(document) else { return 0 }
    // wrapper 崩溃遗留的子进程未确认退出时，宁可报错，也不能启动第二个监听实例。
    guard !hasUnconfirmedChild() else {
      recordDeploymentFailure(document, reason: "Previous child exit unconfirmed")
      return 0
    }
    clearRuntimeReceipt()
    guard selectDeployment(document), let child = spawnSslocal() else {
      recordDeploymentFailure(document, reason: "Child launch failed")
      return 0
    }
    do {
      try AtomicFileWriter.write(Data(String(child.processIdentifier).utf8), to: childPIDURL)
    } catch {
      _ = stopChild(child)
      recordDeploymentFailure(document, reason: "Child identity persistence failed")
      return 0
    }
    let outcome = superviseChild(child, document: document, flags: flags)
    guard !child.isRunning else { return 0 }
    try? FileManager.default.removeItem(at: childPIDURL)
    switch outcome {
    case .stopped: return 0
    case .restart: continue
    }
  }
  return 0
}

private func hasUnconfirmedChild() -> Bool {
  guard FileManager.default.fileExists(atPath: childPIDURL.path) else { return false }
  guard let data = try? String(contentsOf: childPIDURL, encoding: .utf8),
    let pid = Int32(data), pid > 0
  else { return true }
  return kill(pid, 0) == 0 || errno == EPERM
}

private func loadValidatedContract() -> RuntimeSupervision? {
  switch loadContract() {
  case .missing:
    RuntimeLog.emit(.contractMissing)
    return nil
  case .invalid:
    RuntimeLog.emit(.contractInvalid)
    return nil
  case .loaded(let document): return document
  }
}

private enum SupervisionOutcome { case stopped, restart }

private struct SupervisionState {
  var current: RuntimeSupervision
  var processFiles: Set<String>
  var reloadPending = RuntimeReloadState()
  var healthy = false
  var receiptPublished = false
  var readinessDeadline: Date
}

private func superviseChild(
  _ child: Process, document: RuntimeSupervision,
  flags: SignalFlags
) -> SupervisionOutcome {
  var state = SupervisionState(
    current: document, processFiles: document.retainedFiles,
    readinessDeadline: Date().addingTimeInterval(listenEstablishmentDeadline))
  while true {
    if flags.consumeStop() {
      if !stopChild(child) {
        recordDeploymentFailure(state.current, reason: "Child stop unconfirmed")
      }
      return .stopped
    }
    if let outcome = handleChildExit(child, state: &state) { return outcome }
    if let outcome = establishChildReadiness(child, state: &state) { return outcome }
    if let outcome = publishChildReceipt(child, state: &state) { return outcome }
    if let outcome = applyReloadIfRequested(child, flags: flags, state: &state) { return outcome }
    _ = flags.wait(timeout: .now() + listenProbeInterval)
  }
}

private func handleChildExit(
  _ child: Process, state: inout SupervisionState
) -> SupervisionOutcome? {
  guard !child.isRunning else { return nil }
  child.waitUntilExit()
  RuntimeLog.emit(.sslocalExitedUnexpectedly(status: child.terminationStatus))
  clearRuntimeReceipt()
  guard state.healthy else {
    recordDeploymentFailure(state.current, reason: "Child exited before deployment became healthy")
    return .stopped
  }
  // 已健康的当前部署发生意外退出；下一轮重放当前发布，不选择历史配置。
  return .restart
}

private func establishChildReadiness(
  _ child: Process, state: inout SupervisionState
) -> SupervisionOutcome? {
  guard !state.healthy else { return nil }
  if listenersAreEstablished(document: state.current, child: child) {
    guard sendReloadSignals(&state.reloadPending, to: child.processIdentifier) else {
      recordDeploymentFailure(state.current, reason: "Deferred reload failed")
      _ = stopChild(child)
      return .stopped
    }
    state.healthy = true
    return nil
  }
  guard Date() >= state.readinessDeadline else { return nil }
  RuntimeLog.emit(
    .listenNotEstablished(
      detail: state.current.locals.map {
        "\($0.inboundProtocol) \($0.localAddress):\($0.localPort)"
      }.joined(separator: ", ")))
  recordDeploymentFailure(state.current, reason: "Listener establishment failed")
  _ = stopChild(child)
  return .stopped
}

private func publishChildReceipt(
  _ child: Process, state: inout SupervisionState
) -> SupervisionOutcome? {
  guard !state.receiptPublished, state.healthy || state.current.acl == nil else { return nil }
  state.receiptPublished = writeRuntimeReceipt(
    for: state.current, processID: child.processIdentifier)
  guard state.receiptPublished else {
    recordDeploymentFailure(state.current, reason: "Receipt publication failed")
    _ = stopChild(child)
    return .stopped
  }
  guard retireFiles(state.current, protecting: state.processFiles) else {
    recordDeploymentFailure(state.current, reason: "Retired runtime file cleanup failed")
    _ = stopChild(child)
    return .stopped
  }
  return nil
}

private func applyReloadIfRequested(
  _ child: Process, flags: SignalFlags, state: inout SupervisionState
) -> SupervisionOutcome? {
  guard flags.consumeReload() else { return nil }
  guard let next = loadValidatedContract(), !deploymentHasFailed(next) else {
    _ = stopChild(child)
    return .stopped
  }
  guard next.generation >= state.current.generation else {
    recordDeploymentFailure(state.current, reason: "Stale publication rejected")
    _ = stopChild(child)
    return .stopped
  }
  if next.requiresRestart(from: state.current) {
    RuntimeLog.emit(.reloadRestarted)
    guard stopChild(child) else {
      recordDeploymentFailure(next, reason: "Child stop unconfirmed")
      return .stopped
    }
    return .restart
  }
  return applyInPlaceReload(next, child: child, state: &state)
}

private func applyInPlaceReload(
  _ next: RuntimeSupervision, child: Process, state: inout SupervisionState
) -> SupervisionOutcome? {
  let needsDeferral = next.acl != nil && !state.healthy
  state.reloadPending.enqueue(next, from: state.current)
  guard selectDeployment(next),
    needsDeferral || sendReloadSignals(&state.reloadPending, to: child.processIdentifier)
  else {
    recordDeploymentFailure(next, reason: "Reload failed")
    _ = stopChild(child)
    return .stopped
  }
  RuntimeLog.emit(needsDeferral ? .reloadDeferred : .reloadForwarded)
  state.processFiles.formUnion(next.retainedFiles)
  state.current = next
  state.receiptPublished = false
  state.readinessDeadline = Date().addingTimeInterval(listenEstablishmentDeadline)
  return nil
}

private func sendReloadSignals(_ signals: inout RuntimeReloadState, to processID: Int32) -> Bool {
  signals.flush { kill(processID, $0) == 0 }
}

/// 停止超时不得进入启动分支。保留 pid 文件供下次 Agent 拒绝重叠启动。
private func stopChild(_ child: Process) -> Bool {
  RuntimeLog.emit(.sslocalStopRequested)
  if child.isRunning { kill(child.processIdentifier, SIGTERM) }
  var deadline = Date().addingTimeInterval(10)
  while child.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
  if child.isRunning {
    kill(child.processIdentifier, SIGKILL)
    deadline = Date().addingTimeInterval(5)
    while child.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
  }
  guard !child.isRunning else { return false }
  child.waitUntilExit()
  clearRuntimeReceipt()
  return true
}
