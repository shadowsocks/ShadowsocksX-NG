import Foundation

@testable import ShadowsocksX_NG2

/// 测试支持：模拟 wrapper 写入部署收据。生产唯一收据写者是 Agent wrapper
/// （AgentContract.writeRuntimeReceipt），GUI 侧只有读（readRuntimeReceipt）；
/// 收据格式知识由 Domain 的 RuntimeDeploymentReceipt 类型承载，此处只复刻
/// wrapper 的「写动作」供夹具布置磁盘状态。
extension RuntimeFileStore {
  func writeRuntimeReceipt(for document: SslocalRuntimeDocument, processID: Int32) throws {
    guard receiptIdentity(for: document) != nil else {
      throw PersistenceError.ioFailure(detail: "Runtime contract digest is unavailable")
    }
    try writePublishedRuntimeReceipt(processID: processID)
  }
}

/// 测试观察真实发布文件；不把上游输出反向重建为 GUI 运行意图。
struct PublishedRuntimeConfiguration: Equatable {
  let configuration: SslocalConfigurationDocument
  let snapshot: RuntimeSupervision
  let intentSHA256: String

  var servers: [SslocalServerDocument] { configuration.servers }
  var locals: [SslocalLocalDocument] { configuration.locals }
  var socksPort: Int { locals.first { $0.inboundProtocol == "socks" }?.localPort ?? 0 }
  var httpPort: Int { locals.first { $0.inboundProtocol == "http" }?.localPort ?? 0 }
  var aclRuntime: ProxyACLDocument? {
    guard let acl = snapshot.acl,
      let summary = snapshot.aclVariants.first(where: { $0.value == acl })?.key,
      let path = configuration.aclFilePath
    else { return nil }
    return ProxyACLDocument(path: path, summary: summary, content: "", sha256: acl.sha256)
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.configuration == rhs.configuration && lhs.intentSHA256 == rhs.intentSHA256
  }
}

extension RuntimeFileStore {
  func loadDocument() -> PublishedRuntimeConfiguration? {
    guard let snapshot = RuntimePublication.load(at: supervisionFileURL),
      let data = try? Data(contentsOf: directoryURL.appendingPathComponent(snapshot.configuration)),
      let configuration = try? JSONDecoder().decode(SslocalConfigurationDocument.self, from: data),
      let intentData = try? Data(
        contentsOf: directoryURL.appendingPathComponent(snapshot.intentFile)),
      let intent = try? JSONDecoder().decode(PublishedRuntimeIntent.self, from: intentData)
    else { return nil }
    return PublishedRuntimeConfiguration(
      configuration: configuration, snapshot: snapshot, intentSHA256: intent.sha256)
  }

  func readData() -> Data? {
    guard let snapshot = RuntimePublication.load(at: supervisionFileURL) else { return nil }
    return try? Data(contentsOf: directoryURL.appendingPathComponent(snapshot.configuration))
  }

  func receiptIdentity(for document: PublishedRuntimeConfiguration) -> String? {
    guard let current = loadDocument(), current.intentSHA256 == document.intentSHA256 else {
      return nil
    }
    return current.snapshot.deploymentID
  }

  func writeRuntimeReceipt(for document: PublishedRuntimeConfiguration, processID: Int32) throws {
    guard receiptIdentity(for: document) != nil else { throw POSIXError(.EINVAL) }
    try writePublishedRuntimeReceipt(processID: processID)
  }
}

extension RuntimeFileStore {
  func writePublishedRuntimeReceipt(processID: Int32) throws {
    guard let snapshot = RuntimePublication.load(at: supervisionFileURL) else {
      throw POSIXError(.EINVAL)
    }
    try RuntimePublication.select(snapshot, configurationLink: fileURL, aclLink: aclFileURL)
    try AtomicFileWriter.write(
      JSONEncoder().encode(
        RuntimeDeploymentReceipt(processID: processID, deploymentID: snapshot.deploymentID)),
      to: runtimeStatusFileURL)
  }
}
