import Foundation

// 代理运行时 wrapper：LaunchAgent
// 常驻进程，读取跨进程契约 `sslocal-active.json`，以绝对配置路径启动官方
// sslocal、监管其生命周期。PAC HTTP endpoint 已移除。
//
// 协议要点：
// - 显式停止（GUI 注销 → launchd SIGTERM 本进程）：SIGTERM 转发 sslocal 并
//   等待其退出，随后本进程以 0 退出；KeepAlive={SuccessfulExit:false} 不会
//   重启干净退出。
// - 崩溃恢复：sslocal 意外退出 → 本进程非零退出 → KeepAlive 重启并重放最后
// 有效快照（异常路径不触碰契约文件）。
// - 变更协议：SIGUSR1 到达后重读契约；仅 `servers` 变化 → 转发 SIGUSR1 给
//   sslocal（上游热重载服务器列表）；监听地址/端口/协议/mode 结构性变化 →
//   优雅重启。
// - 契约缺失 → 干净退出（等待 GUI 重新写入并注册）；契约无效 → 普通 unlink
//   清理后干净退出，避免把上游必然拒绝的配置反复交给 sslocal。
//
// 测试缝（生产走默认值）：`SSXNG_CONTRACT_PATH`、`SSXNG_SSLOCAL_PATH`、
// `SSXNG_RUNTIME_DIR`（pid 文件与收敛日志的替代目录，测试隔离用）。

// wrapper 与 sslocal 的输出收敛到应用支持目录内的 0600 日志；launchd 统一日
// 志不承载代理细节。
redirectStandardStreams(
  to: runtimeDirectoryOverride?.appendingPathComponent("agent.log") ?? RuntimePaths.agentLogURL())

FileManager.default.createFile(
  atPath: pidFileURL.path,
  contents: Data("\(getpid())\n".utf8),
  attributes: [.posixPermissions: 0o600])
try? FileManager.default.removeItem(at: runtimeStatusFileURL)

let exitStatus = supervise()
try? FileManager.default.removeItem(at: pidFileURL)
clearRuntimeReceipt()
exit(exitStatus)

// MARK: - 监管循环

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

  while true {
    guard let document = loadValidatedContract() else { return 0 }

    // Wrapper 上次崩溃时 sslocal 可能仍活着；旧回执不得替新子进程通过健康门。
    clearRuntimeReceipt()

    guard let gated = spawnGatedChild(document) else { return 0 }
    let child = gated.child

    // 监听建立判定（「3 秒未建立监听 → error 日志」）。
    let listenersEstablished = awaitListenEstablishment(
      document: document, child: child, flags: flags)
    guard child.isRunning else {
      return reportStartupChildExit(child)
    }

    let receiptPublished =
      !gated.requiresOwnedListenerReceipt
      || (listenersEstablished
        && writeRuntimeReceipt(for: document, processID: child.processIdentifier))
    switch superviseChild(
      child, document: document, flags: flags,
      receiptPublished: receiptPublished)
    {
    case .stoppedCleanly:
      return 0
    case .childLost:
      return 1
    case .restart:
      continue
    }
  }
}

/// 读取有效契约；缺失或无效分别记日志并清理（干净退出语义由调用方返回）。
private func loadValidatedContract() -> SslocalRuntimeDocument? {
  switch loadContract() {
  case .missing:
    RuntimeLog.emit(.contractMissing)
    return nil
  case .invalid:
    try? FileManager.default.removeItem(at: contractURL)
    RuntimeLog.emit(.contractInvalidRemoved)
    return nil
  case .loaded(let loaded):
    return loaded
  }
}

/// 拉起 sslocal 并通过回执门（无 ACL 时回执即发布）；失败即清理并返回 nil。
private func spawnGatedChild(
  _ document: SslocalRuntimeDocument
) -> (child: Process, requiresOwnedListenerReceipt: Bool)? {
  guard let child = spawnSslocal(document) else {
    RuntimeLog.emit(.sslocalSpawnFailed)
    clearRuntimeReceipt()
    return nil
  }
  let requiresOwnedListenerReceipt = document.aclRuntime != nil
  guard child.isRunning,
    requiresOwnedListenerReceipt
      || writeRuntimeReceipt(for: document, processID: child.processIdentifier)
  else {
    stopUnsupervisedChild(child)
    clearRuntimeReceipt()
    return nil
  }
  return (child, requiresOwnedListenerReceipt)
}

/// 监听建立窗口内子进程已退出：收敛退出状态（非零，交 KeepAlive 重放）。
private func reportStartupChildExit(_ child: Process) -> Int32 {
  child.waitUntilExit()
  RuntimeLog.emit(.sslocalExitedUnexpectedly(status: child.terminationStatus))
  clearRuntimeReceipt()
  return 1
}

/// 启动阶段的失败收敛；此时还没有 DispatchSource 收割子进程。
private func stopUnsupervisedChild(_ child: Process) {
  RuntimeLog.emit(.sslocalStopRequested)
  child.terminate()
  let deadline = Date().addingTimeInterval(10)
  while child.isRunning && Date() < deadline {
    Thread.sleep(forTimeInterval: 0.05)
  }
  if child.isRunning { kill(child.processIdentifier, SIGKILL) }
  child.waitUntilExit()
}

private enum SupervisionOutcome {
  /// 显式停止或契约缺失/无效：干净退出，launchd 不再重启。
  case stoppedCleanly
  /// 子进程意外退出：非零退出，交 KeepAlive 重放最后有效快照。
  case childLost
  /// 契约监听结构变化：重读文件并重新拉起。
  case restart
}

/// 子进程收割句柄：退出状态的单一写入点（handler 线程）与读取点（监管线程），
/// 由信号量唤醒提供 happens-before。
private struct ChildReaper {
  let exitStatus: ExitStatusBox
  let exitSource: DispatchSourceProcess

  init(child: Process, flags: SignalFlags) {
    // 单一收割点：waitUntilExit 只在这里调用，其余路径等 box 出值。
    let box = ExitStatusBox()
    let source = DispatchSource.makeProcessSource(
      identifier: child.processIdentifier, eventMask: .exit, queue: signalsQueue)
    source.setEventHandler {
      child.waitUntilExit()
      box.store(child.terminationStatus)
      flags.wake()
    }
    self.exitStatus = box
    self.exitSource = source
    source.resume()
  }
}

/// 监管事件循环的可变状态：当前契约、回执发布位与挂起的重载转发。
private struct SupervisionState {
  var currentDocument: SslocalRuntimeDocument
  var receiptPublished: Bool
  var serverReloadPendingUntilReady = false
}

private func superviseChild(
  _ child: Process,
  document: SslocalRuntimeDocument,
  flags: SignalFlags,
  receiptPublished initialReceiptPublished: Bool
) -> SupervisionOutcome {
  var state = SupervisionState(
    currentDocument: document, receiptPublished: initialReceiptPublished)
  let reaper = ChildReaper(child: child, flags: flags)

  while true {
    if state.receiptPublished {
      flags.wait()
    } else if flags.wait(timeout: .now() + listenProbeInterval) == .timedOut {
      if let outcome = probeListeners(child: child, state: &state) { return outcome }
      continue
    }
    if flags.consumeStop() {
      RuntimeLog.emit(.sslocalStopRequested)
      return stopCleanly(child: child, reaper: reaper, flags: flags)
    }
    if let status = reaper.exitStatus.load() {
      return handleUnexpectedExit(status, reaper: reaper)
    }
    guard flags.consumeReload() else { continue }

    if let outcome = handleReload(
      child: child, reaper: reaper, flags: flags, state: &state)
    {
      return outcome
    }
  }
}

/// 回执未发布时的监听探测路径：监听就绪即转发挂起的重载并补写回执；
/// 子进程消失交由收割事件处理，这里只清回执。返回 `.childLost` 表示转发失败。
private func probeListeners(
  child: Process, state: inout SupervisionState
) -> SupervisionOutcome? {
  guard child.isRunning,
    listenersAreEstablished(document: state.currentDocument, child: child)
  else {
    if !state.receiptPublished { clearRuntimeReceipt() }
    return nil
  }
  if state.serverReloadPendingUntilReady {
    guard kill(child.processIdentifier, SIGUSR1) == 0 else { return .childLost }
    state.serverReloadPendingUntilReady = false
  }
  state.receiptPublished = writeRuntimeReceipt(
    for: state.currentDocument, processID: child.processIdentifier)
  if !state.receiptPublished { clearRuntimeReceipt() }
  return nil
}

/// 处理 SIGUSR1 重载：契约缺失/无效→干净退出；监听结构变化→优雅重启；
/// 监听未就绪→推迟转发；否则转发并补写回执。返回 nil 表示继续监管循环。
private func handleReload(
  child: Process,
  reaper: ChildReaper,
  flags: SignalFlags,
  state: inout SupervisionState
) -> SupervisionOutcome? {
  switch loadContract() {
  case .missing:
    RuntimeLog.emit(.contractMissing)
    return stopCleanly(child: child, reaper: reaper, flags: flags)
  case .invalid:
    try? FileManager.default.removeItem(at: contractURL)
    RuntimeLog.emit(.contractInvalidRemoved)
    return stopCleanly(child: child, reaper: reaper, flags: flags)
  case .loaded(let reloaded):
    if reloaded.listenFingerprint != state.currentDocument.listenFingerprint {
      RuntimeLog.emit(.reloadRestarted)
      stopRuntime(child: child, reaper: reaper, flags: flags)
      if flags.consumeStop() {
        return .stoppedCleanly
      }
      flags.rearmIfPending()
      return .restart
    }
    state.currentDocument = reloaded
    let ownsConfiguredListeners =
      reloaded.aclRuntime == nil
      || listenersAreEstablished(document: reloaded, child: child)
    guard ownsConfiguredListeners else {
      RuntimeLog.emit(.reloadDeferred)
      state.serverReloadPendingUntilReady = true
      state.receiptPublished = false
      clearRuntimeReceipt()
      return nil
    }

    RuntimeLog.emit(.reloadForwarded)
    guard kill(child.processIdentifier, SIGUSR1) == 0 else { return .childLost }
    state.serverReloadPendingUntilReady = false
    state.receiptPublished = writeRuntimeReceipt(
      for: reloaded, processID: child.processIdentifier)
    if !state.receiptPublished { clearRuntimeReceipt() }
    return nil
  }
}

private func stopCleanly(
  child: Process,
  reaper: ChildReaper,
  flags: SignalFlags
) -> SupervisionOutcome {
  stopRuntime(child: child, reaper: reaper, flags: flags)
  return .stoppedCleanly
}

private func handleUnexpectedExit(
  _ status: Int32,
  reaper: ChildReaper
) -> SupervisionOutcome {
  RuntimeLog.emit(.sslocalExitedUnexpectedly(status: status))
  clearRuntimeReceipt()
  reaper.exitSource.cancel()
  return .childLost
}

private func stopRuntime(
  child: Process,
  reaper: ChildReaper,
  flags: SignalFlags
) {
  stopChild(child, reaper: reaper, flags: flags)
  clearRuntimeReceipt()
}

private func stopChild(
  _ child: Process,
  reaper: ChildReaper,
  flags: SignalFlags
) {
  kill(child.processIdentifier, SIGTERM)
  let gracefulDeadline = DispatchTime.now() + 10
  while reaper.exitStatus.load() == nil {
    if flags.wait(timeout: gracefulDeadline) == .timedOut {
      kill(child.processIdentifier, SIGKILL)
      _ = flags.wait(timeout: DispatchTime.now() + 5)
    }
  }
  reaper.exitSource.cancel()
  flags.rearmIfPending()
}
