import Foundation

// MARK: - 监听建立判定

/// 监听判定时限：sslocal 拉起后 3 秒内应完成本地监听绑定。
let listenEstablishmentDeadline: TimeInterval = 3
/// 单次探测超时与轮询间隔；正常启动百毫秒级完成，超时路径总耗时不超时限太多。
let listenProbeTimeout: TimeInterval = 0.25
let listenProbeInterval: TimeInterval = 0.1

/// sslocal 拉起后阻塞监管线程至多 3 秒轮询契约内的本地端点（运行期失败以
/// sslocal 信号为准）：全部端点就绪即返回；信号（停止/重载/子进程
/// 退出）到达即让位交还监管循环；超时且子进程仍在 → 记 error 日志但继续监管
/// （GUI 健康门负责呈现，wrapper 不做启停决策）。
func awaitListenEstablishment(
  document: SslocalRuntimeDocument,
  child: Process,
  flags: SignalFlags
) -> Bool {
  let deadline = DispatchTime.now() + listenEstablishmentDeadline
  while DispatchTime.now() < deadline {
    guard child.isRunning else { return false }
    let listenersReady = listenersAreEstablished(document: document, child: child)
    guard child.isRunning else { return false }
    if listenersReady {
      return true
    }
    if flags.wait(timeout: .now() + listenProbeInterval) == .success {
      flags.rearmIfPending()
      return false
    }
  }
  guard child.isRunning else { return false }  // 已退出：退出事件自带点名日志
  let endpoints = document.locals
    .map { "\($0.inboundProtocol) \($0.localAddress):\($0.localPort)" }
    .joined(separator: ", ")
  RuntimeLog.emit(.listenNotEstablished(detail: endpoints))
  return false
}

func listenersAreEstablished(
  document: SslocalRuntimeDocument,
  child: Process
) -> Bool {
  guard child.isRunning else { return false }
  for local in document.locals {
    guard
      EndpointHealthProbe.probe(
        host: local.probeHost,
        port: local.localPort,
        timeout: listenProbeTimeout) == .reachable
    else { return false }

    if document.aclRuntime != nil,
      !RuntimeSocketOwnershipProbe.process(
        child.processIdentifier, ownsTCPListenerOn: local.localPort)
    {
      return false
    }
  }
  return child.isRunning
}
