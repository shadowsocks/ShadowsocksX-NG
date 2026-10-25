import Foundation
import Security
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct SubscriptionInformationWorkflowTests {
  @Test func successfulInformationSurvivesFailureAndReload() async throws {
    try await withWorkflow { workflow, store, fetcher in
      let summary = try await workflow.createSubscription(urlString: "https://p.example.com/sub")
      #expect(summary.information?.bytesUsed == 25)
      #expect(summary.information?.bytesRemaining == 75)
      #expect(summary.information?.expiresAt == Date(timeIntervalSince1970: 0))
      #expect(summary.information?.trafficResetAt == Date(timeIntervalSince1970: 86_400))
      let succeededAt = try #require(summary.lastSucceededAt)
      if case .succeeded(let attemptAt) = summary.status {
        #expect(succeededAt == attemptAt)
      } else {
        Issue.record("应成功提交")
      }
      fetcher.setBehavior(.failure(.httpStatus(code: 503)))
      await workflow.refreshSubscription(summary.id)
      let failed = try #require(workflow.subscriptions.first)
      #expect(failed.information == summary.information)
      #expect(failed.lastSucceededAt == succeededAt)
      let reloaded = makeCatalogWorkflow(
        coordinator: CatalogCommitCoordinator(fileStore: store, runtime: FakeCatalogRuntime()))
      #expect(reloaded.subscriptions.first?.information == summary.information)
      #expect(reloaded.subscriptions.first?.lastSucceededAt == succeededAt)
    }
  }

  @Test func successfulRefreshReplacesMissingAndInvalidFields() async throws {
    try await withWorkflow { workflow, _, fetcher in
      let first = try await workflow.createSubscription(urlString: "https://p.example.com/sub")
      fetcher.setBehavior(
        .success(
          Data(
            #"""
            {"version":1,
            "servers":[],
            "bytes_used":50,
            "bytes_remaining":-1,
            "expires_at":"1970-01-01T00:00:00Z",
            "x_shadowsocksx_ng":{"schema_version":1,
            "expires_at":123}}
            """#
            .utf8)))
      await workflow.refreshSubscription(first.id)
      let replaced = try #require(workflow.subscriptions.first)
      #expect(replaced.information?.bytesUsed == 50)
      #expect(replaced.information?.bytesRemaining == nil)
      #expect(first.information?.expiresAt != nil)
      #expect(first.information?.trafficResetAt != nil)
      #expect(replaced.information?.expiresAt == nil)
      #expect(replaced.information?.trafficResetAt == nil)

      fetcher.setBehavior(.success(Data(#"{"version":1,"servers":[]}"#.utf8)))
      await workflow.refreshSubscription(first.id)
      let empty = try #require(workflow.subscriptions.first)
      #expect(empty.information == nil)
      if case .succeeded(let date) = empty.status {
        #expect(empty.lastSucceededAt == date)
        #expect(date >= first.lastSucceededAt!)
      } else {
        Issue.record("无资料响应仍应成功")
      }
    }
  }

  @Test func cancelledRefreshCannotCommitEvenIfFetcherReturnsData() async throws {
    try await withWorkflow { workflow, store, _ in
      let first = try await workflow.createSubscription(urlString: "https://p.example.com/sub")
      let bytes = try Data(contentsOf: store.fileURL)
      let fetcher = InformationGateFetcher()
      let reloaded = makeCatalogWorkflow(
        coordinator: CatalogCommitCoordinator(fileStore: store, runtime: FakeCatalogRuntime()),
        subscriptionFetcher: fetcher)
      let refresh = Task { await reloaded.refreshSubscription(first.id) }
      await fetcher.entered.wait()
      refresh.cancel()
      fetcher.release.release()
      await refresh.value
      #expect(reloaded.subscriptions.first == first)
      #expect(try Data(contentsOf: store.fileURL) == bytes)
    }
  }

  @Test func persistenceFailureDoesNotPublishNewInformation() async throws {
    try await withWorkflow { workflow, store, fetcher in
      let first = try await workflow.createSubscription(urlString: "https://p.example.com/sub")
      let tree = workflow.tree
      // 只破坏本夹具的文件路径，让原子替换失败，不影响其他 runner。
      let directory = URL(fileURLWithPath: store.fileURL.deletingLastPathComponent().path)
      try FileManager.default.removeItem(at: directory)
      try Data().write(to: directory)
      fetcher.setBehavior(.success(Data(#"{"version":1,"servers":[],"bytes_used":100}"#.utf8)))
      await workflow.refreshSubscription(first.id)
      #expect(workflow.subscriptions.first?.information == first.information)
      #expect(workflow.subscriptions.first?.lastSucceededAt == first.lastSucceededAt)
      #expect(workflow.tree == tree)
    }
  }

  @Test func encryptedDocumentHidesSecretsAndRetainsOnlyAllowlistedInformation() async throws {
    try await withWorkflow { workflow, store, fetcher in
      fetcher.setBehavior(
        .success(
          Data(
            #"""
            {"version":1,
            "servers":[{"server":"203.0.113.7",
            "server_port":8388,
            "method":"aes-256-gcm",
            "password":"RAW-SERVER-PASSWORD",
            "plugin":"v2ray-plugin",
            "plugin_opts":"RAW-PLUGIN-OPTIONS"}],
            "bytes_used":18446744073709551615,
            "provider_token":"RAW-PROVIDER-TOKEN"}
            """#
            .utf8)))
      let first = try await workflow.createSubscription(
        urlString: "https://p.example.com/sub?secret=RAW-URL-TOKEN")
      #expect(first.information?.bytesUsed == UInt64.max)
      let raw = try Data(contentsOf: store.fileURL)
      for secret in [
        "RAW-SERVER-PASSWORD", "RAW-PLUGIN-OPTIONS", "RAW-PROVIDER-TOKEN", "RAW-URL-TOKEN",
      ] {
        #expect(raw.range(of: Data(secret.utf8)) == nil)
      }
      let reloaded = makeCatalogWorkflow(
        coordinator: CatalogCommitCoordinator(fileStore: store, runtime: FakeCatalogRuntime()))
      #expect(reloaded.subscriptions.first?.information?.bytesUsed == UInt64.max)
    }
  }

  @Test func oldDocumentWithoutInformationOrSuccessfulTimeLoadsWithoutGuessing() async throws {
    try await withWorkflow { workflow, store, _ in
      _ = try await workflow.createSubscription(urlString: "https://p.example.com/sub")
      var document = try store.load()
      document.subscriptions[0].information = nil
      document.subscriptions[0].lastSucceededAt = nil
      try store.save(document)
      let reloaded = makeCatalogWorkflow(
        coordinator: CatalogCommitCoordinator(fileStore: store, runtime: FakeCatalogRuntime()))
      #expect(reloaded.subscriptions.count == 1)
      #expect(reloaded.subscriptions.first?.information == nil)
      #expect(reloaded.subscriptions.first?.lastSucceededAt == nil)
    }
  }

  private func withWorkflow(
    _ body:
      @MainActor (
        CatalogWorkflow, CatalogFileStore, FakeSubscriptionFetcher
      ) async throws -> Void
  ) async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("subscription-information-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = makeTestCatalogStore(fileURL: directory.appendingPathComponent("catalog.json"))
    let fetcher = FakeSubscriptionFetcher(
      behavior: .success(
        Data(
          #"""
          {"version":1,
          "servers":[],
          "bytes_used":25,
          "bytes_remaining":75,
          "x_shadowsocksx_ng":{"schema_version":1,
          "expires_at":"1970-01-01T00:00:00Z",
          "traffic_reset_at":"1970-01-02T00:00:00Z"}}
          """#
          .utf8)))
    let workflow = makeCatalogWorkflow(
      coordinator: CatalogCommitCoordinator(fileStore: store, runtime: FakeCatalogRuntime()),
      subscriptionFetcher: fetcher)
    try await body(workflow, store, fetcher)
  }
}

private struct InformationGateFetcher: SubscriptionFetching {
  let entered = AsyncGate()
  let release = AsyncGate()

  func fetch(_ url: URL) async throws -> Data {
    entered.release()
    await release.wait()
    return Data(#"{"version":1,"servers":[],"bytes_used":100}"#.utf8)
  }
}
