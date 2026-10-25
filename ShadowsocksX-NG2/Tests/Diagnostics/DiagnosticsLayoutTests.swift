import AppKit
import SwiftUI
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct DiagnosticsLayoutTests {
  @Test func splitKeepsInitialAndUserAdjustedWidths() async throws {
    let fixture = makeWindow()
    defer { fixture.close() }
    await settle(fixture.host)
    let split = try #require(descendants(of: NSSplitView.self, in: fixture.host).first)
    #expect(split.arrangedSubviews[0].frame.width > split.arrangedSubviews[1].frame.width * 2)
    #expect(split.bounds.width == fixture.host.bounds.width - 60)
    #expect(split.arrangedSubviews[1].frame.width == 220)
    split.setPosition(split.bounds.width - split.dividerThickness - 300, ofDividerAt: 0)
    fixture.events.append(event: .diagnosticsExported)
    await settle(fixture.host)
    selectFirstRow(in: fixture.host)
    await settle(fixture.host)
    #expect(split.arrangedSubviews[1].frame.width == 300)
    fixture.window.setContentSize(NSSize(width: 1400, height: 600))
    await settle(fixture.host)
    #expect(split.arrangedSubviews[1].frame.width == 300)
    fixture.reading.cancel()
    await fixture.reading.value
  }

  @Test func filtersKeepTheirFramesDuringSelectionAndRefresh() async throws {
    let fixture = makeWindow()
    defer { fixture.close() }
    let host = fixture.host
    await settle(host)
    let pickers = descendants(of: NSSegmentedControl.self, in: host)
    try #require(pickers.count == 2)
    let initialFrames = pickers.map { $0.convert($0.bounds, to: host) }
    var observedFrames: [(Int, NSRect)] = []
    let observers = pickers.enumerated().map { index, picker in
      picker.postsFrameChangedNotifications = true
      return NotificationCenter.default.addObserver(
        forName: NSView.frameDidChangeNotification, object: picker, queue: .main
      ) { _ in
        MainActor.assumeIsolated {
          observedFrames.append((index, picker.convert(picker.bounds, to: host)))
        }
      }
    }
    defer { observers.forEach(NotificationCenter.default.removeObserver) }
    for iteration in 0..<6 {
      let picker = pickers[iteration % pickers.count]
      picker.selectedSegment = iteration % picker.segmentCount
      picker.sendAction(picker.action, to: picker.target)
      await settle(host)
      selectFirstRow(in: host)
      fixture.events.append(event: .diagnosticsExported)
      await settle(host)
      let frames = descendants(of: NSSegmentedControl.self, in: host)
        .map { $0.convert($0.bounds, to: host) }
      #expect(frames == initialFrames)
    }
    for (index, frame) in observedFrames {
      #expect(frame == initialFrames[index])
    }
    fixture.reading.cancel()
    await fixture.reading.value
  }

  @MainActor
  private struct HostedDiagnostics {
    let events: RuntimeEventStore
    let host: NSHostingView<DiagnosticsView>
    let window: NSWindow
    let reading: Task<Void, Never>

    func close() {
      reading.cancel()
      window.orderOut(nil)
      window.contentView = nil
    }
  }

  private func makeWindow() -> HostedDiagnostics {
    let events = RuntimeEventStore()
    events.append(event: .agentRegistered)
    let workflow = DiagnosticsWorkflow(
      runtimeFacts: FakeRuntimeFacts(), events: events, catalogFacts: { nil },
      agentLogTail: { DiagnosticLogTail(text: "ERROR example\n", fileID: 1, offset: 0) },
      pollInterval: .milliseconds(10))
    let state = DiagnosticsWindowState()
    let host = NSHostingView(
      rootView: DiagnosticsView(
        diagnostics: workflow, windowState: state,
        clipboard: AppKitTextClipboard(pasteboard: .withUniqueName()),
        exporter: InMemoryDiagnosticReportExporter()))
    let window = NSWindow(
      contentRect: NSRect(x: -10000, y: -10000, width: 1200, height: 600),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFront(nil)
    let reading = Task { await workflow.readWhileActive() }
    return HostedDiagnostics(events: events, host: host, window: window, reading: reading)
  }

  private func selectFirstRow(in host: NSView) {
    for table in descendants(of: NSTableView.self, in: host) where table.numberOfRows > 0 {
      table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }
  }

  private func settle(_ view: NSView) async {
    for _ in 0..<3 {
      await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
          view.layoutSubtreeIfNeeded()
          continuation.resume()
        }
      }
    }
  }

  private func descendants<T: NSView>(of type: T.Type, in view: NSView) -> [T] {
    (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(of: type, in: $0) }
  }
}
