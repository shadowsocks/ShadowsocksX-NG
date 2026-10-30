import Foundation

// MARK: - 监听建立判定

/// 覆盖插件启动、上游初始测速（默认超时 5 秒）与调度余量；GUI 健康窗另留拉起时间。
let listenEstablishmentDeadline: TimeInterval = 15
/// 单次探测超时与轮询间隔；正常启动百毫秒级完成，超时路径总耗时不超时限太多。
let listenProbeTimeout: TimeInterval = 0.25
let listenProbeInterval: TimeInterval = 0.1

/// 返回首个未通过的检查；nil 表示所有入站已就绪。轮询只在期限到达时输出失败。
func listenerReadinessFailure(
  document: RuntimeSupervision,
  child: Process
) -> String? {
  guard child.isRunning else { return "check=process outcome=exited" }
  for local in document.locals {
    let endpoint = "endpoint=\(local.inboundProtocol) \(local.localAddress):\(local.localPort)"
    let connection = "\(endpoint) probeHost=\(local.probeHost) check=connect"
    switch EndpointHealthProbe.probe(
      host: local.probeHost, port: local.localPort, timeout: listenProbeTimeout)
    {
    case .reachable: break
    case .refused(let detail): return "\(connection) outcome=refused detail=\(detail)"
    case .timedOut: return "\(connection) outcome=timedOut"
    }

    if document.acl != nil,
      !RuntimeSocketOwnershipProbe.process(
        child.processIdentifier, ownsTCPListenerOn: local.localPort)
    {
      return "\(endpoint) check=ownership outcome=unconfirmed"
    }
  }
  return child.isRunning ? nil : "check=process outcome=exited"
}
