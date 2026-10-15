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
      } supplement: {
        EmptyView()
      })
    host.frame = NSRect(x: 0, y: 0, width: 480, height: 600)
    host.layoutSubtreeIfNeeded()
    #expect(containsFooter(in: host))
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
