import Foundation

// MARK: - 契约与子进程

enum ContractLoad {
  case missing
  case invalid
  case loaded(RuntimeSupervision)
}

func loadContract() -> ContractLoad {
  guard FileManager.default.fileExists(atPath: supervisionURL.path) else { return .missing }
  guard let document = RuntimePublication.load(at: supervisionURL) else { return .invalid }
  return .loaded(document)
}

func writeRuntimeReceipt(for document: RuntimeSupervision, processID: Int32) -> Bool {
  let receipt = RuntimeDeploymentReceipt(processID: processID, deploymentID: document.deploymentID)
  do {
    try AtomicFileWriter.write(JSONEncoder().encode(receipt), to: runtimeStatusFileURL)
    return true
  } catch { return false }
}

func deploymentHasFailed(_ document: RuntimeSupervision) -> Bool {
  guard let data = try? Data(contentsOf: failureURL),
    let failure = try? JSONDecoder().decode(RuntimeDeploymentFailure.self, from: data)
  else { return false }
  return failure.deploymentID == document.deploymentID
}

func recordDeploymentFailure(_ document: RuntimeSupervision, reason: String) {
  do {
    try RuntimePublication.withLock(in: contractURL.deletingLastPathComponent()) {
      // 新发布不得被旧监管任务标成失败。
      guard RuntimePublication.metadata(at: supervisionURL)?.deploymentID == document.deploymentID
      else { return }
      try AtomicFileWriter.write(
        JSONEncoder().encode(
          RuntimeDeploymentFailure(
            deploymentID: document.deploymentID, reason: reason)), to: failureURL)
    }
  } catch {
    RuntimeLog.emit(.runtimePersistFailed(detail: "Deployment failure persistence failed"))
  }
}

func selectDeployment(_ document: RuntimeSupervision) -> Bool {
  do {
    try RuntimePublication.select(document, configurationLink: contractURL, aclLink: aclFileURL)
    return true
  } catch { return false }
}

func retireFiles(_ document: RuntimeSupervision, protecting: Set<String>) -> Bool {
  do {
    try RuntimePublication.retire(
      before: document, publishedAt: supervisionURL, protecting: protecting)
    return true
  } catch {
    RuntimeLog.emit(.runtimePersistFailed(detail: "Retired runtime file cleanup failed"))
    return false
  }
}

func clearRuntimeReceipt() {
  try? FileManager.default.removeItem(at: runtimeStatusFileURL)
}

func spawnSslocal() -> Process? {
  guard FileManager.default.isExecutableFile(atPath: sslocalURL.path) else { return nil }
  let child = Process()
  let errorPipe = Pipe()
  // sslocal 输出 intake：分帧 + 密码脱敏后送两个去向——agent.log 文件
  // （经 stderr 收敛，raw capture 保留）与统一日志（category `sslocal`）。
  let outputIntake = SslocalOutputIntake(
    destinations: [SslocalStandardErrorDestination(), SslocalUnifiedLogDestination()])
  child.standardError = errorPipe
  child.standardOutput = errorPipe
  errorPipe.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    outputIntake.write(data)
    if data.isEmpty { handle.readabilityHandler = nil }
  }
  child.executableURL = sslocalURL
  child.arguments = ["-c", contractURL.path]
  var childEnvironment = environment
  // 不配置 sslocal 日志级别；未设置时使用上游默认值，显式外部 RUST_LOG 原样透传。
  // macOS 的 resolv.conf 可能含带 zone id 的链路本地 nameserver（RA 下发的
  // RDNSS，如 fe80::…%en0），hickory 解析不了该后缀（hickory-dns#3713），
  // 每次启动都报错再回退 builtin。强制 builtin getaddrinfo 即回退后的实际
  // 路径，跳过这段噪音；显式外部设置仍可覆盖以便诊断。
  if childEnvironment["SS_SYSTEM_DNS_RESOLVER_FORCE_BUILTIN"] == nil {
    childEnvironment["SS_SYSTEM_DNS_RESOLVER_FORCE_BUILTIN"] = "1"
  }
  child.environment = childEnvironment
  do {
    try child.run()
    try? errorPipe.fileHandleForWriting.close()
  } catch {
    return nil
  }
  RuntimeLog.emit(.sslocalSpawned(pid: child.processIdentifier))
  return child
}

// MARK: - 日志收敛

func redirectStandardStreams(to logURL: URL) {
  let fileManager = FileManager.default
  let directory = logURL.deletingLastPathComponent()
  try? AtomicFileWriter.prepareDirectory(at: directory)
  if fileManager.fileExists(atPath: logURL.path) {
    let attributes = try? fileManager.attributesOfItem(atPath: logURL.path)
    if let size = attributes?[.size] as? UInt64, size > 1_048_576 {
      // agent.log 文件去向（stderr→freopen）的保留策略：启动时超限即截断，
      // 当前不滚动或导出诊断日志。策略留在这个文件去向（wrapper 事件行与
      // 脱敏后的 sslocal 行共写这一个文件），不并入 sslocal 输出 intake。
      try? fileManager.removeItem(at: logURL)
    }
  }
  if !fileManager.fileExists(atPath: logURL.path) {
    fileManager.createFile(
      atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
  }
  try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logURL.path)
  freopen(logURL.path, "a", stdout)
  freopen(logURL.path, "a", stderr)
}
