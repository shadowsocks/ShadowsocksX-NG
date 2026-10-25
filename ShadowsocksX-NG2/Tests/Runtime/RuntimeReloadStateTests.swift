import Darwin
import Foundation
import Testing

@testable import ShadowsocksX_NG2

struct RuntimeReloadStateTests {
  @Test func serverPublicationPreservesDeferredACLReloadAndFlushClearsSignals() throws {
    let runtime = ProxyRuntimeFixture.makeTemporaryRuntime()
    defer { try? FileManager.default.removeItem(at: runtime.directory) }
    let store = RuntimeFileStore(fileURL: runtime.contract)
    let initial = ProxyRuntimeFixture.makeDocument(localPort: 1086).replacingACL(
      .global(at: store.aclFileURL))
    try store.write(initial)
    let previous = try #require(RuntimePublication.load(at: store.supervisionFileURL))
    let direct = initial.replacingACL(.direct(at: store.aclFileURL))
    try store.write(direct)
    let aclOnly = try #require(RuntimePublication.load(at: store.supervisionFileURL))
    try store.write(
      ProxyRuntimeFixture.makeDocument(serverAddress: "198.51.100.9", localPort: 1086)
        .replacingACL(direct.aclRuntime))
    let serverOnly = try #require(RuntimePublication.load(at: store.supervisionFileURL))

    var state = RuntimeReloadState()
    state.enqueue(aclOnly, from: previous)
    state.enqueue(serverOnly, from: aclOnly)
    state.enqueue(serverOnly, from: serverOnly)
    var delivered: [Int32] = []
    #expect(
      state.flush {
        delivered.append($0)
        return true
      })
    #expect(delivered == [SIGUSR1, SIGUSR2].sorted())
    delivered.removeAll()
    #expect(
      state.flush {
        delivered.append($0)
        return true
      })
    #expect(delivered.isEmpty)

    state.enqueue(aclOnly, from: serverOnly)
    #expect(!state.flush { _ in false })
    #expect(
      state.flush {
        delivered.append($0)
        return true
      })
    #expect(delivered == [SIGUSR1])
  }
}
