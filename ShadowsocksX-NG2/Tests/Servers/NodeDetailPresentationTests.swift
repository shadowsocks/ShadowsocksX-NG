import AppKit
import Foundation
import SwiftUI
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct NodeDetailPresentationTests {
  @Test
  func groupCountsServerDescendantsAndShowsUnknownTimes() {
    let detail = NodeDetailPresentation(
      node: node(isGroup: true), server: nil,
      eligibility: ActivationEligibility(
        canActivate: true, candidateCount: 2, skippedInvalidCount: 1, ineligibility: nil),
      isActiveTarget: true)
    #expect(detail.title == "测试节点")
    #expect(detail.subtitle.contains(String(localized: "活动目标")))
    #expect(!detail.subtitle.contains("激活时将跳过"))
    #expect(detail.activationMessages.count == 1)
    #expect(detail.activationMessages[0].contains("1"))
    #expect(detail.properties.count == 1)
    #expect(detail.properties[0].items.map(\.value) == ["detail-id", "2", "1", "—", "—"])
  }

  @Test
  func groupContainingActiveTargetMarksItInSubtitle() {
    let marked = NodeDetailPresentation(
      node: node(isGroup: true), server: nil, eligibility: nil,
      isActiveTarget: false, containsActiveTarget: true)
    #expect(marked.subtitle == "本地 · 含活动目标")
    let unmarked = NodeDetailPresentation(
      node: node(isGroup: true), server: nil, eligibility: nil,
      isActiveTarget: false, containsActiveTarget: false)
    #expect(unmarked.subtitle == "本地")
  }

  @Test
  func parameterPropertiesPreserveFlagsEmptyValuesOrderAndDuplicates() {
    var detail = NodeDetailPresentation(
      node: node(isGroup: false), server: nil, eligibility: nil, isActiveTarget: false)
    detail.appendPluginParameters("tls;host=one;host=two;empty=")
    let items = detail.properties.last!.items
    #expect(items.map(\.label) == ["tls", "host", "host", "empty"])
    #expect(items.map(\.value) == [String(localized: "开关"), "one", "two", String(localized: "空值")])
  }

  @Test
  func opaqueParametersRemainVerbatimAndEmptyParametersAddNoGroup() {
    var detail = NodeDetailPresentation(
      node: node(isGroup: false), server: nil, eligibility: nil, isActiveTarget: false)
    detail.appendPluginParameters("")
    #expect(detail.properties.count == 1)
    detail.appendPluginParameters("opaque\\")
    #expect(detail.properties.last?.items.map(\.value) == ["opaque\\"])
  }

  @Test
  func parameterFailureLeavesConnectionInformationVisible() {
    let server = ServerDetailPresentation(
      name: "测试节点", address: "example.com", port: 8388, encryptionMethod: "aes-256-gcm",
      plugin: PluginSectionState(
        selection: .unknown(program: "unknown-plugin"), programs: [],
        mappingsUnreadable: false, optionsPresent: true, options: ""))
    var detail = NodeDetailPresentation(
      node: node(isGroup: false), server: server, eligibility: nil, isActiveTarget: false)
    detail.appendPluginParameterFailure()
    #expect(
      detail.properties[1].items.map(\.value) == [
        "example.com", "8388", "aes-256-gcm", "unknown-plugin",
      ])
    #expect(detail.properties[2].items.map(\.value) == [String(localized: "无法读取插件参数")])
    #expect(detail.properties[0].items.map(\.value) == ["detail-id", "—", "—"])
  }

  @Test
  func pluginAvailabilityFailureKeepsItsSpecificExplanation() {
    let plugin = PluginSectionState(
      selection: .named(program: "v2ray-plugin"),
      programs: [.init(program: "v2ray-plugin", source: .user, availability: .notExecutable)],
      mappingsUnreadable: false, optionsPresent: false, options: "")
    let server = ServerDetailPresentation(
      name: "测试节点", address: "example.com", port: 8388,
      encryptionMethod: "aes-256-gcm", plugin: plugin)
    let detail = NodeDetailPresentation(
      node: node(isGroup: false, invalidReasons: [.pluginNotProvided(program: "v2ray-plugin")]),
      server: server, eligibility: nil, isActiveTarget: false)
    #expect(!detail.subtitle.contains("插件文件不可执行"))
    #expect(detail.activationMessages == ["插件文件不可执行，请检查文件类型和执行权限。"])
  }

  @Test(arguments: [false, true])
  func propertiesFooterRendersWithAndWithoutRows(hasRows: Bool) throws {
    var detail = NodeDetailPresentation(
      node: node(isGroup: true), server: nil, eligibility: nil, isActiveTarget: false)
    detail.properties = [
      .init(
        id: .information, title: "Properties", items: hasRows ? [.init(label: "A", value: "B")] : []
      )
    ]
    let host = NSHostingView(
      rootView: NodeDetailView(detail: detail) {
        EmptyView()
      } secondaryActions: {
        EmptyView()
      } feedback: {
        EmptyView()
      } propertiesFooter: { group in
        group.id == .information ? FooterMarker() : nil
      })
    host.frame = NSRect(x: 0, y: 0, width: 480, height: 600)
    host.layoutSubtreeIfNeeded()
    #expect(containsFooter(in: host))
  }

  @Test
  func connectivityHistoryUsesTimeOnlyAndPreservesRepeatedLabelsAndFailures() {
    let date = Date(timeIntervalSince1970: 37_421)
    let records = [
      ServerConnectivity.Record(
        finishedAt: date, outcome: .success(milliseconds: 42), networkExpired: true),
      ServerConnectivity.Record(finishedAt: date, outcome: .requestTimeout),
      ServerConnectivity.Record(finishedAt: date.addingTimeInterval(-60), outcome: .http(302)),
    ]
    let properties = NodeDetailPresentation.connectivityHistory(
      records, locale: Locale(identifier: "en_GB"), timeZone: TimeZone(secondsFromGMT: 3600)!)
    #expect(properties.id == .connectivity)
    #expect(properties.items.map(\.label) == ["11:23:41", "11:23:41", "11:22:41"])
    #expect(properties.items.map(\.value) == ["42 ms", ConnectivityCopy.text("请求超时"), "HTTP 302"])
  }

  @Test
  func connectivityEmptyStatesAreExplicitProperties() {
    let locale = Locale(identifier: "en_GB")
    let zone = TimeZone(secondsFromGMT: 0)!
    let history = NodeDetailPresentation.connectivityHistory([], locale: locale, timeZone: zone)
    #expect(
      history.items == [
        .init(label: ConnectivityCopy.text("状态"), value: ConnectivityCopy.text("尚未测试"))
      ])
    for hasResults in [false, true] {
      let summary = ServerConnectivity.Summary(
        serverID: nil, record: nil, hasResults: hasResults, isTesting: true)
      let properties = NodeDetailPresentation.connectivitySummary(
        summary,
        serverName: { _ in
          Issue.record("No server should be resolved")
          return ""
        },
        locale: locale, timeZone: zone)
      #expect(
        properties.items == [
          .init(
            label: ConnectivityCopy.text("状态"),
            value: ConnectivityCopy.text(hasResults ? "无成功结果" : "尚未测试"))
        ])
    }
  }

  @Test
  func connectivityGroupPropertiesFollowFreshnessNetworkChangesAndNames() async {
    let ids = [NodeID.fresh(), NodeID.fresh()]
    var now = Date(timeIntervalSince1970: 37_421)
    var latency = 10
    var name = "First"
    let module = ServerConnectivity(
      configuration: { _ in
        SslocalServerDocument(
          id: "test", server: "example.com", serverPort: 443, password: "secret",
          method: "aes-256-gcm", plugin: nil, pluginOpts: nil)
      }, now: { now },
      measure: { _, _, _ in .success(milliseconds: latency) })
    func properties(at date: Date) -> NodeDetailPresentation.Properties {
      NodeDetailPresentation.connectivitySummary(
        module.summary(for: ids, at: date), serverName: { $0 == ids[0] ? name : "Second" },
        locale: Locale(identifier: "en_GB"), timeZone: TimeZone(secondsFromGMT: 0)!)
    }
    await module.wait(for: module.test([ids[0]]))
    #expect(properties(at: now).items.map(\.value) == ["10 ms", "First", "10:23:41"])
    name = "Renamed"
    #expect(properties(at: now).items[1].value == "Renamed")
    now.addTimeInterval(60)
    latency = 20
    await module.wait(for: module.test([ids[1]]))
    #expect(properties(at: now).items[1].value == "Renamed")
    // First expires while Second is still fresh, without another measurement.
    #expect(
      properties(at: now.addingTimeInterval(240)).items.map(\.value) == [
        "20 ms", "Second", "10:24:41",
      ])
    module.networkChanged()
    #expect(properties(at: now.addingTimeInterval(240)).items[1].value == "Renamed")
    module.setURL(URL(string: "http://example.com/check")!)
    #expect(properties(at: now).items.map(\.value) == [ConnectivityCopy.text("尚未测试")])
  }

  private func containsFooter(in view: NSView) -> Bool {
    view.identifier?.rawValue == "properties-footer"
      || view.subviews.contains { containsFooter(in: $0) }
  }

  private struct FooterMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSTextField {
      let field = NSTextField(labelWithString: "Custom footer")
      field.identifier = NSUserInterfaceItemIdentifier("properties-footer")
      return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {}
  }

  private func node(isGroup: Bool, invalidReasons: [LeafInvalidationReason] = []) -> CatalogTreeNode
  {
    CatalogTreeNode(
      id: NodeID(rawValue: "detail-id"), name: "测试节点", isGroup: isGroup,
      source: .manual, parentID: nil, createdAt: nil, updatedAt: nil,
      invalidReasons: invalidReasons, childCount: 1, subtreeNodeCount: 4,
      invalidDescendantCount: 1, children: isGroup ? [] : nil)
  }
}
