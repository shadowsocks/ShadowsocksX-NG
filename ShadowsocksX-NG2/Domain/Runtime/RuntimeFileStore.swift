import Foundation

/// 运行时文件存取（ACL 布局见 ADR-0011）：
/// `sslocal-active.json` 是 GUI 写、wrapper 读的跨进程交接契约。ACL 侧为
/// 每个变体一个 `acl-<summary>.ini` 实文件，外加稳定的 `acl-active.ini` 链接；
/// 契约只携带链接路径与身份摘要。写入复用 `AtomicFileWriter` 的物理安全基线
/// （目录 0700 含自愈、临时文件创建即 0600、写全校验后原子替换）；显式停止
/// 后的清理只做普通 unlink，不承诺安全擦除。
struct RuntimeFileStore {
  enum PersistenceError: Error, Equatable {
    /// 写入时的文件系统错误。
    case ioFailure(detail: String)
    /// 部署失败后无法恢复已修改的 ACL 变体或链接。
    case rollbackFailed(detail: String)
  }

  let fileURL: URL
  private let fileWriter: (Data, URL) throws -> Void

  init(
    fileURL: URL = RuntimePaths.runtimeFileURL(),
    fileWriter: @escaping (Data, URL) throws -> Void = {
      try AtomicFileWriter.write($0, to: $1)
    }
  ) {
    self.fileURL = fileURL
    self.fileWriter = fileWriter
  }

  private var directoryURL: URL { fileURL.deletingLastPathComponent() }

  /// wrapper pid 文件与契约同目录：GUI 判活与 SIGUSR1 投递依据
  /// （SMAppService 不暴露运行中 agent 的 pid）。
  var pidFileURL: URL {
    directoryURL.appendingPathComponent("agent.pid")
  }

  /// 稳定 ACL 链接（ADR-0011）：契约 `acl` 字段恒指向它，换模式只改链接。
  var aclFileURL: URL {
    directoryURL.appendingPathComponent("acl-active.ini")
  }

  /// 某个 ACL 变体的实文件。
  func aclVariantFileURL(summary: String) -> URL {
    directoryURL.appendingPathComponent("acl-\(summary).ini")
  }

  /// GUI 私有 digest 清单：未变内容免读免写。
  var aclDigestManifestURL: URL {
    directoryURL.appendingPathComponent("acl-digests.json")
  }

  var runtimeStatusFileURL: URL {
    directoryURL.appendingPathComponent("agent-runtime-status.json")
  }

  /// 变体、链接、契约按序原子替换；失败时恢复已完成的变更。
  func write(_ document: SslocalRuntimeDocument) throws {
    let contract: PreparedRuntimeContract
    do {
      contract = try PreparedRuntimeContract(document)
    } catch {
      throw PersistenceError.ioFailure(detail: String(describing: error))
    }
    try write(contract)
  }

  /// 单次部署准备好的契约字节由比较与写入共用。
  func write(_ contract: PreparedRuntimeContract) throws {
    let document = contract.document
    var mutations: [Mutation] = []
    var verifiedDigest: DigestEntry?
    do {
      if let acl = document.aclRuntime {
        guard acl.path == aclFileURL.standardizedFileURL.path, acl.isWellFormed else {
          throw PersistenceError.ioFailure(detail: "ACL sidecar path or digest is invalid")
        }
        let variant = aclVariantFileURL(summary: acl.summary)
        if acl.content.isEmpty {
          guard isRegularVariant(variant) else {
            throw PersistenceError.ioFailure(detail: "Existing ACL variant is unavailable")
          }
        } else {
          let change = try prepareVariant(acl, at: variant)
          if change.needsWrite {
            try fileWriter(Data(acl.content.utf8), variant)
            mutations.append(.variant(variant, change.previous))
          }
          verifiedDigest = DigestEntry(sha256: acl.sha256, size: acl.content.utf8.count)
        }
        let previousLink = try activeLinkState()
        if previousLink != .link(variant.lastPathComponent) {
          try repointActiveLink(to: variant)
          mutations.append(.link(previousLink))
        }
      }
      try fileWriter(contract.data, fileURL)
    } catch {
      let original = String(describing: error)
      let failures = rollback(mutations)
      if !failures.isEmpty {
        throw PersistenceError.rollbackFailed(
          detail: original + "; rollback: " + failures.joined(separator: "; "))
      }
      throw PersistenceError.ioFailure(detail: original)
    }
    // 清单只在契约成功后登记；它不参与部署事务的正确性。
    if let verifiedDigest, let acl = document.aclRuntime {
      recordDigest(summary: acl.summary, entry: verifiedDigest)
    }
  }

  private enum LinkState: Equatable {
    case absent
    case link(String)
    case file(Data)
  }

  private enum Mutation {
    case variant(URL, Data?)
    case link(LinkState)
  }

  private func rollback(_ mutations: [Mutation]) -> [String] {
    var failures: [String] = []
    for mutation in mutations.reversed() {
      do {
        switch mutation {
        case .variant(let url, let data):
          try restoreVariant(data, at: url)
        case .link(let state):
          try restoreLink(state)
        }
      } catch {
        failures.append(String(describing: error))
      }
    }
    return failures
  }

  /// 读取侧判定：结构有效 + 链接解析后仍在运行目录内。不读 ACL 内容、
  /// 不核摘要（ADR-0011 / Q12）。
  func loadDocument() -> SslocalRuntimeDocument? {
    guard let data = try? Data(contentsOf: fileURL) else { return nil }
    guard let document = SslocalRuntimeDocument.decodeValidated(data) else { return nil }
    guard let acl = document.aclRuntime else { return document }
    guard
      acl.path == aclFileURL.standardizedFileURL.path,
      activeLinkResolvesInsideDirectory()
    else { return nil }
    return document
  }

  /// 磁盘原始字节，供与派生文档比较以跳过相同内容的写入（幂等）。
  func readData() -> Data? {
    try? Data(contentsOf: fileURL)
  }

  /// 部署收据只读：唯一生产写者是 Agent wrapper（AgentContract.writeRuntimeReceipt），
  /// GUI 在健康检查中核对 pid 与契约摘要，从不写。
  func readRuntimeReceipt() -> RuntimeDeploymentReceipt? {
    guard let data = try? Data(contentsOf: runtimeStatusFileURL) else { return nil }
    return try? JSONDecoder().decode(RuntimeDeploymentReceipt.self, from: data)
  }

  /// 显式停止时的末端清理：运行时契约、wrapper pid、ACL 链接与
  /// 变体、digest 清单及原子写残留。异常崩溃路径不调用本方法（文件保留供
  /// KeepAlive 重放）。文件缺失时调用无害。
  func deleteRuntimeFiles() {
    let fileManager = FileManager.default
    try? fileManager.removeItem(at: fileURL)
    try? fileManager.removeItem(at: pidFileURL)
    try? fileManager.removeItem(at: aclFileURL)
    try? fileManager.removeItem(at: aclDigestManifestURL)
    try? fileManager.removeItem(at: runtimeStatusFileURL)
    try? fileManager.removeItem(at: directoryURL.appendingPathComponent("sslocal-active.acl"))
    if let names = try? fileManager.contentsOfDirectory(atPath: directoryURL.path) {
      for name in names {
        // 变体实文件，或 AtomicFileWriter 的暂存残留。
        if name.hasPrefix("acl-") && name.hasSuffix(".ini") {
          try? fileManager.removeItem(at: directoryURL.appendingPathComponent(name))
        } else if AtomicFileWriter.isResidueName(name) {
          try? fileManager.removeItem(at: directoryURL.appendingPathComponent(name))
        }
      }
    }
  }

}

extension RuntimeFileStore {
  // MARK: - ACL 变体与链接

  /// 命中清单不读正文；未命中只读一次，同时保留需要写入时的回滚字节。
  private func prepareVariant(_ acl: ProxyACLDocument, at url: URL) throws
    -> (needsWrite: Bool, previous: Data?)
  {
    let attributes = try attributesIfPresent(url)
    if let attributes {
      guard attributes[.type] as? FileAttributeType == .typeRegular else {
        throw PersistenceError.ioFailure(detail: "ACL variant is not a regular file")
      }
      if let recorded = loadDigestManifest()[acl.summary], recorded.sha256 == acl.sha256,
        recorded.size == acl.content.utf8.count,
        (attributes[.size] as? NSNumber)?.intValue == recorded.size
      {
        return (false, nil)
      }
      let previous = try Data(contentsOf: url)
      return (ProxyACLDocument.digest(previous) != acl.sha256, previous)
    }
    return (true, nil)
  }

  private func attributesIfPresent(_ url: URL) throws -> [FileAttributeKey: Any]? {
    do {
      return try FileManager.default.attributesOfItem(atPath: url.path)
    } catch let error as NSError
      where error.domain == NSCocoaErrorDomain
      && error.code == NSFileReadNoSuchFileError
    {
      return nil
    }
  }

  private func isRegularVariant(_ url: URL) -> Bool {
    (try? attributesIfPresent(url))?[.type] as? FileAttributeType == .typeRegular
  }

  private func activeLinkState() throws -> LinkState {
    guard let attributes = try attributesIfPresent(aclFileURL) else { return .absent }
    switch attributes[.type] as? FileAttributeType {
    case .typeSymbolicLink:
      return .link(try FileManager.default.destinationOfSymbolicLink(atPath: aclFileURL.path))
    case .typeRegular:
      return .file(try Data(contentsOf: aclFileURL))
    default:
      throw PersistenceError.ioFailure(detail: "Active ACL path is not a file or link")
    }
  }

  private struct DigestEntry: Codable, Equatable {
    let sha256: String
    let size: Int
  }

  private func loadDigestManifest() -> [String: DigestEntry] {
    guard let data = try? Data(contentsOf: aclDigestManifestURL) else { return [:] }
    return (try? JSONDecoder().decode([String: DigestEntry].self, from: data)) ?? [:]
  }

  private func recordDigest(summary: String, entry: DigestEntry) {
    var manifest = loadDigestManifest()
    guard manifest[summary] != entry else { return }
    manifest[summary] = entry
    guard let data = try? JSONEncoder().encode(manifest) else { return }
    try? fileWriter(data, aclDigestManifestURL)
  }

  private func repointActiveLink(to variantURL: URL) throws {
    let fileManager = FileManager.default
    let temporaryLink = AtomicFileWriter.temporaryURL(for: aclFileURL)
    try? fileManager.removeItem(at: temporaryLink)
    try fileManager.createSymbolicLink(
      atPath: temporaryLink.path, withDestinationPath: variantURL.lastPathComponent)
    if fileManager.fileExists(atPath: aclFileURL.path)
      || (try? fileManager
        .destinationOfSymbolicLink(atPath: aclFileURL.path)) != nil
    {
      // rename 原子替换既有链接/文件。
      guard rename(temporaryLink.path, aclFileURL.path) == 0 else {
        try? fileManager.removeItem(at: temporaryLink)
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
    } else {
      try fileManager.moveItem(at: temporaryLink, to: aclFileURL)
    }
  }

  private func restoreVariant(_ previousData: Data?, at variantURL: URL) throws {
    if let previousData {
      try fileWriter(previousData, variantURL)
    } else {
      try FileManager.default.removeItem(at: variantURL)
    }
  }

  private func restoreLink(_ state: LinkState) throws {
    switch state {
    case .link(let target):
      let temporary = AtomicFileWriter.temporaryURL(for: aclFileURL)
      defer { try? FileManager.default.removeItem(at: temporary) }
      try FileManager.default.createSymbolicLink(
        atPath: temporary.path, withDestinationPath: target)
      guard rename(temporary.path, aclFileURL.path) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
    case .file(let data):
      try fileWriter(data, aclFileURL)
    case .absent:
      try FileManager.default.removeItem(at: aclFileURL)
    }
  }

  /// 链接（或实文件）解析后必须仍在运行目录内——防链接逃逸（ADR-0011）。
  private func activeLinkResolvesInsideDirectory() -> Bool {
    ACLActiveLinkPolicy.resolvesToRegularFile(inside: directoryURL, linkURL: aclFileURL)
  }
}
