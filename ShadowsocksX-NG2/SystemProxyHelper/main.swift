import Foundation

// 特权系统代理 helper 入口：随 app 打包、经 SMAppService.daemon
// 注册的 on-demand LaunchDaemon。launchd 以 MachServices 键按需拉起本进程，
// GUI 侧每次连接到固定 MachService 名即触发激活。
let delegate = SystemProxyHelperListenerDelegate(
  engine: SystemProxyHelperEngine(perform: SystemProxyWriter.perform))
let listener = NSXPCListener(machServiceName: SystemProxyHelperIdentity.machServiceName)
listener.delegate = delegate
listener.resume()
// 拉起就绪事件只进统一日志（ADR-0047）：launchd 丢弃本进程 stdout/stderr，
// 这是「helper 是否被拉起」的唯一痕迹。
SystemProxyHelperLog.emit(.listenerReady)
dispatchMain()
