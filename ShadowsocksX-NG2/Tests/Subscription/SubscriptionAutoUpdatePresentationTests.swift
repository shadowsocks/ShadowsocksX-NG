import Foundation
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct SubscriptionAutoUpdatePresentationTests {
  @Test(
    arguments: SubscriptionUpdateMode.allCases,
    [(false, false), (false, true), (true, false), (true, true)])
  func detailsShowEffectiveModeRestrictionsAndPlanInOrder(
    mode: SubscriptionUpdateMode, flags: (Bool, Bool)
  ) async throws {
    let (allowsOverride, hasSucceeded) = flags
    try await withAutoUpdateFixture { fixture in
      fixture.respond(mode: mode, allowsOverride: allowsOverride)
      var summary = try await fixture.create()
      if !hasSucceeded { summary.lastSucceededAt = nil }
      summary.information = SubscriptionInformation(bytesUsed: 100)
      let node = try #require(fixture.workflow.tree.node(withID: summary.groupID))
      let detail = NodeDetailPresentation(
        node: node, server: nil, eligibility: nil, isActiveTarget: false, subscription: summary)
      let rows = try #require(detail.properties.first { $0.id == .subscription }).items
      var labels: [String] = []
      if hasSucceeded { labels.append("最后更新时间") }
      labels.append("自动更新")
      if !allowsOverride { labels.append("配置限制") }
      if mode != .off { labels.append("下次更新时间") }
      labels.append("已用流量")
      #expect(rows.map(\.label) == labels)
      #expect(rows.first { $0.label == "自动更新" }?.value == mode.displayName)
      #expect(rows.first { $0.label == "配置限制" }?.value == (allowsOverride ? nil : "供应商禁止覆盖自动更新设置"))
    }
  }

  @Test func fileImportAndGroupShareDoNotPropagateAutomaticUpdates() async throws {
    try await withAutoUpdateFixture { fixture in
      let data = Data(
        #"""
        {"version":1,
        "servers":[{"server":"example.com",
        "server_port":8388,
        "method":"aes-256-gcm",
        "password":"p"}],
        "x_shadowsocksx_ng":{"schema_version":1,
        "auto_update":{"mode":"daily",
        "allow_user_override":false}}}
        """#
        .utf8)
      fixture.fetcher.setBehavior(.success(data))
      let summary = try await fixture.create()
      let draft = try fixture.workflow.configurationGroupExportDraft(for: summary.groupID)
      let json = try #require(String(data: draft.data, encoding: .utf8))
      #expect(!json.contains("auto_update"))
      #expect(!json.contains("nextUpdateAt"))
      let imported = await fixture.workflow.importServers(
        from: [.file(name: "provider.json", data: data)], into: nil)
      let groupID = try #require(imported.sources.first?.result.importedGroupID)
      #expect(fixture.workflow.tree.node(withID: groupID)?.isManual == true)
      #expect(fixture.workflow.subscriptions.count == 1)
    }
  }
}
