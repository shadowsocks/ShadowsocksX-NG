import Foundation

// MARK: - 契约与子进程

enum ContractLoad {
  case missing
  case invalid
  case loaded(SslocalRuntimeDocument)
}

func loadContract() -> ContractLoad {
  guard let data = try? Data(contentsOf: contractURL) else { return .missing }
  guard let document = SslocalRuntimeDocument.decodeValidated(data) else { return .invalid }
  if let acl = document.aclRuntime {
    // ADR-0011：契约只带身份；Agent 不读 ACL 内容、不核摘要，只保证链接
    // 解析后落在运行目录内（防逃逸）且文件存在。
    guard
      document.aclFilePath == aclFileURL.standardizedFileURL.path,
      acl.path == aclFileURL.standardizedFileURL.path,
      ACLActiveLinkPolicy.resolvesToRegularFile(
        inside: aclFileURL.deletingLastPathComponent(), linkURL: aclFileURL)
    else { return .invalid }
  }
  return .loaded(document)
}

func writeRuntimeReceipt(for document: SslocalRuntimeDocument, processID: Int32) -> Bool {
  guard let digest = document.deploymentSHA256 else { return false }
  let receipt = RuntimeDeploymentReceipt(processID: processID, contractSHA256: digest)
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  guard let data = try? encoder.encode(receipt) else { return false }
  do {
    try AtomicFileWriter.write(data, to: runtimeStatusFileURL)
    return true
  } catch {
    return false
  }
}

func clearRuntimeReceipt() {
  try? FileManager.default.removeItem(at: runtimeStatusFileURL)
}

func spawnSslocal(_ document: SslocalRuntimeDocument) -> Process? {
  guard FileManager.default.isExecutableFile(atPath: sslocalURL.path) else { return nil }
  let child = Process()
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
  try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
  try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
  if fileManager.fileExists(atPath: logURL.path) {
    let attributes = try? fileManager.attributesOfItem(atPath: logURL.path)
    if let size = attributes?[.size] as? UInt64, size > 1_048_576 {
      // 启动时超限即截断；当前不滚动或导出诊断日志。
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
