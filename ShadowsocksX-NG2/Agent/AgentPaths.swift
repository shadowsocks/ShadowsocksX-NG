import Foundation

// MARK: - 进程级路径与环境（测试缝经 SSXNG_* 环境变量覆盖）

let environment = ProcessInfo.processInfo.environment

// 契约路径优先；运行目录覆盖仅在没有契约覆盖时使用，避免同一部署的路径分叉。
let runtimePaths: RuntimePaths = {
  if let path = environment["SSXNG_CONTRACT_PATH"] {
    return RuntimePaths(fileURL: URL(fileURLWithPath: path))
  }
  if let path = environment["SSXNG_RUNTIME_DIR"] {
    return RuntimePaths(directoryURL: URL(fileURLWithPath: path, isDirectory: true))
  }
  return ApplicationSupportPaths.current.runtime
}()

let contractURL = runtimePaths.fileURL
let aclFileURL = runtimePaths.aclFileURL
let pidFileURL = runtimePaths.pidFileURL
let runtimeStatusFileURL = runtimePaths.runtimeStatusFileURL
let supervisionURL = runtimePaths.supervisionFileURL
let failureURL = runtimePaths.failureFileURL
let childPIDURL = runtimePaths.childPIDFileURL

let agentLogURL: URL = {
  if let path = environment["SSXNG_LOG_PATH"] { return URL(fileURLWithPath: path) }
  if environment["SSXNG_CONTRACT_PATH"] != nil || environment["SSXNG_RUNTIME_DIR"] != nil {
    return runtimePaths.directoryURL.appendingPathComponent("agent.log")
  }
  return ApplicationSupportPaths.current.agentLogURL
}()

let sslocalURL: URL =
  environment["SSXNG_SSLOCAL_PATH"].map { URL(fileURLWithPath: $0) }
  ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/sslocal")
