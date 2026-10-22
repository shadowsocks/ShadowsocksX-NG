import AppKit
import Combine
import SwiftUI
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct PluginOptionsModePickerTests {
  @Test
  func nativePickerDefersDraftPublicationUntilAfterItsAction() async throws {
    let draft = PluginOptionsDraft()
    draft.load("tls;host=example.com;path=/ws;")
    let host = NSHostingView(rootView: PluginOptionsModePicker(draft: draft))
    host.frame = NSRect(x: 0, y: 0, width: 320, height: 60)
    host.layoutSubtreeIfNeeded()
    let picker = try #require(Self.segmentedControl(in: host))
    var publications = 0
    let observation = draft.objectWillChange.sink { publications += 1 }
    defer { observation.cancel() }

    // 原生 macOS Picker 的 action 在 SwiftUI 更新事务内写入绑定。
    // 此时同步发布 ObservableObject 变更会触发运行时警告。
    picker.selectedSegment = 1
    picker.sendAction(picker.action, to: picker.target)
    #expect(publications == 0)
    #expect(draft.mode == .table)

    await Task { @MainActor in }.value
    #expect(draft.mode == .rawText)
    #expect(draft.rawText == "tls;host=example.com;path=/ws;")
    #expect(publications > 0)

    publications = 0
    picker.selectedSegment = 0
    picker.sendAction(picker.action, to: picker.target)
    #expect(publications == 0)
    await Task { @MainActor in }.value
    #expect(draft.mode == .table)
    #expect(draft.composedString == "tls;host=example.com;path=/ws;")
  }

  @Test
  func nativePickerKeepsTableModeWhenARowIsUnfinished() async throws {
    let draft = PluginOptionsDraft()
    draft.load("host=example.com")
    draft.updateValue("unfinished", of: draft.quickAddRowID)
    let host = NSHostingView(rootView: PluginOptionsModePicker(draft: draft))
    host.frame = NSRect(x: 0, y: 0, width: 320, height: 60)
    host.layoutSubtreeIfNeeded()
    let picker = try #require(Self.segmentedControl(in: host))

    picker.selectedSegment = 1
    picker.sendAction(picker.action, to: picker.target)
    await Task { @MainActor in }.value
    host.layoutSubtreeIfNeeded()
    #expect(draft.mode == .table)
    #expect(draft.hasUnfinishedRows)
    #expect(picker.selectedSegment == 0)
  }

  private static func segmentedControl(in view: NSView) -> NSSegmentedControl? {
    if let control = view as? NSSegmentedControl { return control }
    return view.subviews.lazy.compactMap { segmentedControl(in: $0) }.first
  }
}
