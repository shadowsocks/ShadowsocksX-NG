import Foundation
import Testing

@testable import ShadowsocksX_NG2

/// 偏好持久化读侧失败分类：损坏、I/O 失败与无效端口不得静默回落出厂端口，
/// `restored()` 必须携带点名错误（「任何路径不静默改端口」）。
struct ProxyRuntimeSettingsStoreRecoveryTests {
  private func withStore(
    _ body: (_ store: ProxyListeningFileStore, _ directory: URL) throws -> Void
  ) throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ssxng-settings-recovery-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ProxyListeningFileStore(
      fileURL: directory.appendingPathComponent("proxy-listening.json"))
    try body(store, directory)
  }

  @Test
  func loadReportsCorruptFileInsteadOfSilentlyRewritingPorts() throws {
    try withStore { store, directory in
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try Data("not json".utf8).write(to: store.fileURL)

      do {
        _ = try store.load()
        Issue.record("损坏文件应抛出 corrupt")
      } catch {
        guard case .corrupt = error as? ProxyListeningStoreError else {
          Issue.record("应为 corrupt，实际 \(error)")
          return
        }
      }
    }
  }

  @Test
  func loadDistinguishesReadFailureFromCorruption() throws {
    try withStore { store, directory in
      // proxy-listening.json 本身是一个目录：存在性检查通过，读取失败 → ioFailure。
      try FileManager.default.createDirectory(
        at: store.fileURL, withIntermediateDirectories: true)

      do {
        _ = try store.load()
        Issue.record("读取失败应抛出 ioFailure")
      } catch {
        guard case .ioFailure = error as? ProxyListeningStoreError else {
          Issue.record("应为 ioFailure，实际 \(error)")
          return
        }
      }
    }
  }

  @Test
  func loadRejectsPersistedDuplicatePorts() throws {
    try withStore { store, directory in
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try Data(
        """
        {"localListen":{"socksPort":1086,"httpPort":1086}}
        """.utf8
      ).write(to: store.fileURL)

      do {
        _ = try store.load()
        Issue.record("重复端口应抛出 invalid")
      } catch {
        #expect(
          error as? ProxyListeningStoreError
            == .invalid([.duplicatePort(endpoint: .socks, otherEndpoint: .http, port: 1086)]))
      }
    }
  }

  @Test
  func restoredCarriesNamedErrorAndFactoryDefaults() throws {
    try withStore { store, directory in
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try Data("not json".utf8).write(to: store.fileURL)

      let restored = ProxyListeningFileStore.restored(store: store)

      #expect(restored.configuration == ProxyListeningConfiguration())
      guard case .corrupt = restored.unreadableError else {
        Issue.record("restored 必须携带 corrupt 错误，实际 \(String(describing: restored.unreadableError))")
        return
      }
    }
  }

  @Test
  func restoredOnMissingFileIsFactoryDefaultsWithoutError() throws {
    try withStore { store, _ in
      let restored = ProxyListeningFileStore.restored(store: store)

      #expect(restored.configuration == ProxyListeningConfiguration())
      #expect(restored.unreadableError == nil)
    }
  }
}
