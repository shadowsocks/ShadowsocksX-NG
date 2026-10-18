import Foundation

/// GUI 独占配置准备与监管发布；Agent 独占稳定链接切换和退休文件回收。
struct RuntimeFileStore {
  enum PersistenceError: Error, Equatable {
    case ioFailure(detail: String)
    case rollbackFailed(detail: String)
  }

  let fileURL: URL
  private let fileWriter: (Data, URL) throws -> Void

  init(
    fileURL: URL = RuntimePaths.runtimeFileURL(),
    fileWriter: @escaping (Data, URL) throws -> Void = { try AtomicFileWriter.write($0, to: $1) }
  ) {
    self.fileURL = fileURL
    self.fileWriter = fileWriter
  }

  var directoryURL: URL { fileURL.deletingLastPathComponent() }
  var supervisionFileURL: URL { directoryURL.appendingPathComponent("agent-supervision.json") }
  var failureFileURL: URL { directoryURL.appendingPathComponent("agent-deployment-failure.json") }
  var pidFileURL: URL { directoryURL.appendingPathComponent("agent.pid") }
  var aclFileURL: URL { directoryURL.appendingPathComponent("acl-active.ini") }
  var runtimeStatusFileURL: URL { directoryURL.appendingPathComponent("agent-runtime-status.json") }

  func write(_ document: SslocalRuntimeDocument) throws {
    try write(PreparedRuntimeContract(document))
  }

  func write(_ contract: PreparedRuntimeContract) throws {
    try RuntimePublication.withLock(in: directoryURL) {
      var created: [URL] = []
      var publicationID: String?
      do {
        guard contract.document.isWellFormed else { throw POSIXError(.EINVAL) }
        let old = RuntimePublication.load(at: supervisionFileURL)
        let previous = loadDocumentUnlocked(old)
        let generation = try reserveGeneration()
        let prefix = String(format: "%020llu", generation)
        func create(_ data: Data, kind: String, suffix: String) throws -> String {
          let name = "\(kind)-\(prefix)-\(suffix)"
          let url = directoryURL.appendingPathComponent(name)
          guard !FileManager.default.fileExists(atPath: url.path) else { throw POSIXError(.EEXIST) }
          // 先登记：注入的写入器即使在写后抛错，也由 GUI 清理本次未发布文件。
          created.append(url)
          try fileWriter(data, url)
          guard RuntimePublication.isRegularFile(url), try Data(contentsOf: url) == data else {
            throw POSIXError(.EIO)
          }
          return name
        }
        var variants = old?.aclVariants ?? [:]
        var selectedACL: RuntimeSupervision.ACL?
        if let acl = contract.document.aclRuntime {
          guard acl.path == aclFileURL.standardizedFileURL.path, acl.isWellFormed else {
            throw POSIXError(.EINVAL)
          }
          if let cached = variants[acl.summary], cached.sha256 == acl.sha256 {
            selectedACL = cached
          } else {
            guard !acl.content.isEmpty else { throw POSIXError(.ENOENT) }
            let data = Data(acl.content.utf8)
            let name = try create(data, kind: "acl", suffix: "\(acl.summary).ini")
            selectedACL = .init(file: name, sha256: acl.sha256, size: data.count)
            variants[acl.summary] = selectedACL
          }
        }
        let authentication = try prepareAuthentication(
          contract.document, previous: previous,
          old: old, create: { try create($0, kind: $1, suffix: $2) })
        let encoded = authentication.document
        let configuration = try create(encoded.jsonData(), kind: "config", suffix: "sslocal.json")
        _ = try create(Data(contract.sha256.utf8), kind: "config", suffix: "intent.json")
        let snapshot = RuntimeSupervision(
          version: 1, generation: generation, deploymentID: UUID().uuidString,
          configuration: configuration,
          locals: encoded.locals.map {
            .init(
              inboundProtocol: $0.inboundProtocol, localAddress: $0.localAddress,
              localPort: $0.localPort, mode: $0.mode)
          }, ipv6Only: encoded.ipv6Only, authenticationID: authentication.id,
          authenticationFiles: authentication.files, acl: selectedACL, aclVariants: variants)
        guard snapshot.validated(in: directoryURL) else { throw POSIXError(.EINVAL) }
        // 唯一发布点。所有可引用资源已落盘且校验完成；不提前触碰任何活动链接。
        publicationID = snapshot.deploymentID
        try fileWriter(JSONEncoder().encode(snapshot), supervisionFileURL)
      } catch {
        // 写入器在原子替换后报错时，发布已经发生；不得删除读者可见资源。
        if let publicationID,
          RuntimePublication.load(at: supervisionFileURL)?.deploymentID == publicationID
        {
          throw PersistenceError.ioFailure(
            detail: "Publication completed but writer reported failure")
        }
        var failures: [String] = []
        for url in created {
          do { try FileManager.default.removeItem(at: url) } catch {
            if FileManager.default.fileExists(atPath: url.path) {
              failures.append(url.lastPathComponent)
            }
          }
        }
        if !failures.isEmpty {
          throw PersistenceError.rollbackFailed(
            detail: "Unpublished cleanup: " + failures.joined(separator: ","))
        }
        throw PersistenceError.ioFailure(detail: String(describing: error))
      }
    }
  }

  private func prepareAuthentication(
    _ document: SslocalRuntimeDocument,
    previous: SslocalRuntimeDocument?, old: RuntimeSupervision?,
    create: (Data, String, String) throws -> String
  ) throws -> (document: SslocalRuntimeDocument, id: String?, files: [String]) {
    var authenticationID: String?
    var authenticationFiles: [String] = []
    var encoded = document
    if let auth = encoded.listen.authentication {
      guard auth.directory == directoryURL.standardizedFileURL.path else {
        throw POSIXError(.EINVAL)
      }
      if previous?.listen.authentication == auth, let oldID = old?.authenticationID {
        authenticationID = oldID
        authenticationFiles = old?.authenticationFiles ?? []
      } else {
        authenticationID = UUID().uuidString
        for (kind, data) in try auth.fileContents() {
          authenticationFiles.append(try create(data, "auth", "\(kind).json"))
        }
      }
      for index in encoded.locals.indices
      where encoded.locals[index].localAddress != "127.0.0.1" {
        if encoded.locals[index].inboundProtocol == "socks" {
          encoded.locals[index].socks5AuthConfigPath =
            directoryURL
            .appendingPathComponent(authenticationFiles[0]).path
        } else {
          encoded.locals[index].httpAuthConfigPath =
            directoryURL
            .appendingPathComponent(authenticationFiles[1]).path
        }
      }
    }
    return (encoded, authenticationID, authenticationFiles)
  }

  /// 代次高水位独立于部署文件持久保存。预留失败可留空号，溢出拒绝部署。
  private func reserveGeneration() throws -> UInt64 {
    let url = directoryURL.appendingPathComponent("runtime-generation")
    let current: UInt64
    if FileManager.default.fileExists(atPath: url.path) {
      guard let value = UInt64(try String(contentsOf: url, encoding: .utf8)) else {
        throw POSIXError(.EINVAL)
      }
      current = value
    } else {
      current = 0
    }
    guard current < UInt64.max else { throw POSIXError(.EOVERFLOW) }
    try AtomicFileWriter.write(Data(String(current + 1).utf8), to: url)
    return current + 1
  }

  /// 仅 GUI 读取配置；归一化生成的认证路径以保持意图比较不依赖部署代次。
  private func loadDocumentUnlocked(_ snapshot: RuntimeSupervision?) -> SslocalRuntimeDocument? {
    guard let snapshot,
      let data = try? Data(contentsOf: directoryURL.appendingPathComponent(snapshot.configuration)),
      let document = try? JSONDecoder().decode(SslocalRuntimeDocument.self, from: data)
    else { return nil }
    let normalized = document.authenticatingLAN(document.listen.authentication)
    return normalized.isWellFormed ? normalized : nil
  }

  func loadDocument() -> SslocalRuntimeDocument? {
    try? RuntimePublication.withLock(in: directoryURL) {
      loadDocumentUnlocked(RuntimePublication.load(at: supervisionFileURL))
    }
  }

  func readData() -> Data? { try? loadDocument()?.jsonData() }

  func receiptIdentity(for document: SslocalRuntimeDocument) -> String? {
    try? RuntimePublication.withLock(in: directoryURL) {
      let snapshot = RuntimePublication.metadata(at: supervisionFileURL)
      guard let snapshot,
        let identity = try? String(
          contentsOf: directoryURL.appendingPathComponent(snapshot.intentFile), encoding: .utf8),
        identity == document.intentSHA256
      else { return nil }
      return snapshot.deploymentID
    }
  }

  func blocksDeployment(_ document: SslocalRuntimeDocument) -> Bool {
    guard let failure = readFailure() else { return false }
    guard let snapshot = RuntimePublication.metadata(at: supervisionFileURL) else { return true }
    guard failure.deploymentID == snapshot.deploymentID else { return false }
    // GUI 私有身份本身丢失时也不自动重试，用户可显式重试修复派生资源。
    guard
      let identity = try? String(
        contentsOf: directoryURL.appendingPathComponent(snapshot.intentFile), encoding: .utf8),
      identity.count == 64
    else { return true }
    return identity == document.intentSHA256
  }

  func readRuntimeReceipt() -> RuntimeDeploymentReceipt? {
    guard let data = try? Data(contentsOf: runtimeStatusFileURL) else { return nil }
    return try? JSONDecoder().decode(RuntimeDeploymentReceipt.self, from: data)
  }

  func readFailure() -> RuntimeDeploymentFailure? {
    guard let data = try? Data(contentsOf: failureFileURL) else { return nil }
    return try? JSONDecoder().decode(RuntimeDeploymentFailure.self, from: data)
  }

  func recordFailure(reason: String) throws {
    try RuntimePublication.withLock(in: directoryURL) {
      guard let snapshot = RuntimePublication.metadata(at: supervisionFileURL) else {
        throw POSIXError(.EINVAL)
      }
      try AtomicFileWriter.write(
        JSONEncoder().encode(
          RuntimeDeploymentFailure(
            deploymentID: snapshot.deploymentID, reason: reason)), to: failureFileURL)
    }
  }

  /// 只清除旧部署失败。Agent 对本代新确认的失败不得被 GUI 健康任务擦除。
  func settleSuccessfulDeployment() throws {
    try RuntimePublication.withLock(in: directoryURL) {
      guard let snapshot = RuntimePublication.metadata(at: supervisionFileURL) else {
        throw POSIXError(.EINVAL)
      }
      if let failure = readFailure(), failure.deploymentID == snapshot.deploymentID {
        throw POSIXError(.EIO)
      }
      try clearFailure()
    }
  }

  func clearFailure() throws {
    if FileManager.default.fileExists(atPath: failureFileURL.path) {
      try FileManager.default.removeItem(at: failureFileURL)
    }
  }

  var hasUnconfirmedChild: Bool {
    let url = directoryURL.appendingPathComponent("sslocal.pid")
    guard FileManager.default.fileExists(atPath: url.path) else { return false }
    guard let data = try? String(contentsOf: url, encoding: .utf8), let pid = Int32(data), pid > 0
    else { return true }
    return kill(pid, 0) == 0 || errno == EPERM
  }

  /// 仅在确认 wrapper 及其子进程退出后调用；高水位与锁跨停止保留。
  func deleteRuntimeFiles() throws {
    try RuntimePublication.withLock(in: directoryURL) {
      guard !hasUnconfirmedChild else { throw POSIXError(.EBUSY) }
      let manager = FileManager.default
      for name in try manager.contentsOfDirectory(atPath: directoryURL.path) {
        if RuntimePublication.generation(of: name) != nil
          || [
            fileURL.lastPathComponent, "agent-supervision.json", "acl-active.ini", "agent.pid",
            "agent-runtime-status.json", "agent-deployment-failure.json", "sslocal.pid",
          ].contains(name)
          || name.hasPrefix("lan-auth-") || name == "acl-digests.json"
          || (name.hasPrefix("acl-") && name.hasSuffix(".ini"))
          || AtomicFileWriter.isResidueName(name)
        {
          try manager.removeItem(at: directoryURL.appendingPathComponent(name))
        }
      }
    }
  }
}
