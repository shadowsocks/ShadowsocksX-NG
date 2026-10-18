import Foundation

// MARK: - 进程级路径与环境（测试缝经 SSXNG_* 环境变量覆盖）

let environment = ProcessInfo.processInfo.environment

let contractURL: URL =
  environment["SSXNG_CONTRACT_PATH"].map { URL(fileURLWithPath: $0) }
  ?? RuntimePaths.runtimeFileURL()

let sslocalURL: URL =
  environment["SSXNG_SSLOCAL_PATH"].map { URL(fileURLWithPath: $0) }
  ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/sslocal")

let runtimeDirectoryOverride: URL? = environment["SSXNG_RUNTIME_DIR"].map {
  URL(fileURLWithPath: $0, isDirectory: true)
}

let aclFileURL: URL =
  runtimeDirectoryOverride?.appendingPathComponent("acl-active.ini")
  ?? RuntimePaths.aclFileURL()

let pidFileURL: URL =
  runtimeDirectoryOverride?.appendingPathComponent("agent.pid") ?? RuntimePaths.agentPIDFileURL()

let runtimeStatusFileURL: URL =
  runtimeDirectoryOverride?.appendingPathComponent("agent-runtime-status.json")
  ?? RuntimePaths.agentRuntimeStatusURL()

let supervisionURL = contractURL.deletingLastPathComponent().appendingPathComponent(
  "agent-supervision.json")
let failureURL = contractURL.deletingLastPathComponent().appendingPathComponent(
  "agent-deployment-failure.json")

let childPIDURL = contractURL.deletingLastPathComponent().appendingPathComponent("sslocal.pid")
