import Foundation

@testable import ShadowsocksX_NG2

/// 测试支持：模拟 wrapper 写入部署收据。生产唯一收据写者是 Agent wrapper
/// （AgentContract.writeRuntimeReceipt），GUI 侧只有读（readRuntimeReceipt）；
/// 收据格式知识由 Domain 的 RuntimeDeploymentReceipt 类型承载，此处只复刻
/// wrapper 的「写动作」供夹具布置磁盘状态。
extension RuntimeFileStore {
  func writeRuntimeReceipt(for document: SslocalRuntimeDocument, processID: Int32) throws {
    guard let digest = receiptIdentity(for: document) else {
      throw PersistenceError.ioFailure(detail: "Runtime contract digest is unavailable")
    }
    if let snapshot = RuntimePublication.load(at: supervisionFileURL) {
      try RuntimePublication.select(snapshot, configurationLink: fileURL, aclLink: aclFileURL)
    }
    let receipt = RuntimeDeploymentReceipt(processID: processID, deploymentID: digest)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    do {
      try AtomicFileWriter.write(try encoder.encode(receipt), to: runtimeStatusFileURL)
    } catch {
      throw PersistenceError.ioFailure(detail: String(describing: error))
    }
  }
}
