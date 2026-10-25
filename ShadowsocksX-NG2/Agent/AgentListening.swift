import Foundation

// MARK: - 监听建立判定

/// 监听判定时限：sslocal 拉起后 5 秒内应完成本地监听绑定。
let listenEstablishmentDeadline: TimeInterval = 5
/// 单次探测超时与轮询间隔；正常启动百毫秒级完成，超时路径总耗时不超时限太多。
let listenProbeTimeout: TimeInterval = 0.25
let listenProbeInterval: TimeInterval = 0.1

func listenersAreEstablished(
  document: RuntimeSupervision,
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

    if document.acl != nil,
      !RuntimeSocketOwnershipProbe.process(
        child.processIdentifier, ownsTCPListenerOn: local.localPort)
    {
      return false
    }
  }
  return child.isRunning
}
