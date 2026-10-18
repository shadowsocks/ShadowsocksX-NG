import Foundation
import Testing

@testable import ShadowsocksX_NG2

struct RuntimeFileStoreTransactionTests {
  @Test(arguments: ["config-", "acl-", "agent-supervision.json"])
  func failedPreparationPreservesPublishedDeployment(failingName: String) throws {
    let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    defer { try? FileManager.default.removeItem(at: runtime.directory) }
    let store = RuntimeFileStore(fileURL: runtime.contract)
    let old = ProxyRuntimeFixture.makeDocument().replacingACL(.direct(at: store.aclFileURL))
    try store.write(old)
    let before = try Data(contentsOf: store.supervisionFileURL)
    let files = try FileManager.default.contentsOfDirectory(atPath: runtime.directory.path).sorted()
    let failing = RuntimeFileStore(fileURL: runtime.contract) { data, url in
      if url.lastPathComponent.hasPrefix(failingName) { throw POSIXError(.ENOSPC) }
      try AtomicFileWriter.write(data, to: url)
    }
    #expect(throws: (any Error).self) {
      try failing.write(old.replacingACL(.global(at: store.aclFileURL)))
    }
    #expect(try Data(contentsOf: store.supervisionFileURL) == before)
    #expect(store.loadDocument() == old)
    #expect(
      try FileManager.default.contentsOfDirectory(atPath: runtime.directory.path).sorted() == files)
  }

  @Test func reuseAndRetirementProtectPublishedCachesAndFuturePreparations() throws {
    let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    defer { try? FileManager.default.removeItem(at: runtime.directory) }
    let store = RuntimeFileStore(fileURL: runtime.contract)
    let direct = ProxyRuntimeFixture.makeDocument().replacingACL(.direct(at: store.aclFileURL))
    try store.write(direct)
    let first = try #require(RuntimePublication.load(at: store.supervisionFileURL))
    try RuntimePublication.select(
      first, configurationLink: runtime.contract, aclLink: store.aclFileURL)
    try store.write(direct.replacingACL(.global(at: store.aclFileURL)))
    let second = try #require(RuntimePublication.load(at: store.supervisionFileURL))
    let futureName = "config-00000000000000000099-sslocal.json"
    let future = runtime.directory.appendingPathComponent(futureName)
    try AtomicFileWriter.write(Data("preparing".utf8), to: future)
    // Agent 持有旧快照，GUI 已发布新代；旧进程和新发布引用必须同时存活。
    try RuntimePublication.retire(
      before: second, publishedAt: store.supervisionFileURL,
      protecting: first.retainedFiles)
    #expect(
      first.retainedFiles.union(second.retainedFiles).allSatisfy {
        FileManager.default.fileExists(atPath: runtime.directory.appendingPathComponent($0).path)
      })
    try store.write(direct)
    let third = try #require(RuntimePublication.load(at: store.supervisionFileURL))
    #expect(third.acl == first.acl)
    try RuntimePublication.retire(
      before: second, publishedAt: store.supervisionFileURL,
      protecting: first.retainedFiles)
    #expect(
      FileManager.default.fileExists(
        atPath: runtime.directory.appendingPathComponent(third.configuration).path))
    try RuntimePublication.select(
      third, configurationLink: runtime.contract, aclLink: store.aclFileURL)
    try RuntimePublication.retire(
      before: third, publishedAt: store.supervisionFileURL, protecting: [])
    #expect(
      !FileManager.default.fileExists(
        atPath: runtime.directory.appendingPathComponent(first.configuration).path))
    #expect(FileManager.default.fileExists(atPath: future.path))
    #expect(try String(contentsOf: store.aclFileURL, encoding: .utf8) == direct.aclRuntime?.content)
  }
}

extension RuntimeFileStoreTransactionTests {
  @Test func writerErrorAfterPublicationDoesNotDeletePublishedResources() throws {
    let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    defer { try? FileManager.default.removeItem(at: runtime.directory) }
    let store = RuntimeFileStore(fileURL: runtime.contract)
    let failing = RuntimeFileStore(fileURL: runtime.contract) { data, url in
      try AtomicFileWriter.write(data, to: url)
      if url == store.supervisionFileURL { throw POSIXError(.EIO) }
    }
    #expect(throws: (any Error).self) { try failing.write(ProxyRuntimeFixture.makeDocument()) }
    #expect(store.loadDocument() == ProxyRuntimeFixture.makeDocument())
    #expect(RuntimePublication.load(at: store.supervisionFileURL) != nil)
  }

  @Test func cleanupWaitsForPublicationAndKeepsReusedOlderACL() async throws {
    let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    defer { try? FileManager.default.removeItem(at: runtime.directory) }
    let store = RuntimeFileStore(fileURL: runtime.contract)
    let direct = ProxyRuntimeFixture.makeDocument().replacingACL(.direct(at: store.aclFileURL))
    try store.write(direct)
    try store.write(direct.replacingACL(.global(at: store.aclFileURL)))
    let stale = try #require(RuntimePublication.load(at: store.supervisionFileURL))
    let preparing = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let retired = DispatchSemaphore(value: 0)
    let contractURL = runtime.contract
    let publishedURL = store.supervisionFileURL
    let writer = Task.detached {
      let preparingStore = RuntimeFileStore(fileURL: contractURL) { data, url in
        if url.lastPathComponent.hasSuffix("-sslocal.json") {
          preparing.signal()
          guard release.wait(timeout: .now() + 5) == .success else { throw POSIXError(.ETIMEDOUT) }
        }
        try AtomicFileWriter.write(data, to: url)
      }
      try preparingStore.write(direct)
    }
    let awaitPreparation = { preparing.wait(timeout: .now() + 5) }
    #expect(awaitPreparation() == .success)
    let cleanup = Task.detached {
      defer { retired.signal() }
      try RuntimePublication.retire(before: stale, publishedAt: publishedURL, protecting: [])
    }
    let awaitRetirement = { retired.wait(timeout: .now() + 0.05) }
    #expect(awaitRetirement() == .timedOut)
    release.signal()
    try await writer.value
    try await cleanup.value
    let current = try #require(RuntimePublication.load(at: publishedURL))
    #expect(current.generation > stale.generation)
    #expect(current.acl == stale.aclVariants["direct"])
    #expect(store.loadDocument() == direct)
  }
}

extension RuntimeFileStoreTransactionTests {
  @Test func successfulGUIObservationCannotEraseAgentsCurrentFailure() throws {
    let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    defer { try? FileManager.default.removeItem(at: runtime.directory) }
    let store = RuntimeFileStore(fileURL: runtime.contract)
    try store.write(ProxyRuntimeFixture.makeDocument())
    try store.recordFailure(reason: "Agent observed failure after GUI probe")
    let failure = try #require(store.readFailure())
    #expect(throws: (any Error).self) { try store.settleSuccessfulDeployment() }
    #expect(store.readFailure() == failure)
  }
}
