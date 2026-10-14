import Combine
import Foundation
import XCTest

@testable import ShadowsocksX_NG2

@MainActor
final class WorkspaceRouteTests: XCTestCase {
  func testFreshRouteStartsAtHomeWithoutPersistedState() {
    XCTAssertEqual(WorkspaceRoute().destination, .home)
  }

  /// 侧栏 @State 选中项的初值锚定在 initialDestination 上（见 MainWindowView）；
  /// 两者脱钩会导致首帧侧栏无高亮行。
  func testInitialDestinationConstantMatchesFreshRoute() {
    XCTAssertEqual(WorkspaceRoute.initialDestination, WorkspaceRoute().destination)
  }

  /// 侧栏 List/NavigationSplitView 会在视图更新期间回写 selection Binding；
  /// 同值导航不得 publish（否则触发 view-update 期间发布警告）。
  func testNavigateToCurrentDestinationDoesNotPublish() {
    let route = WorkspaceRoute()
    var changeCount = 0
    let cancellable = route.objectWillChange.sink { _ in changeCount += 1 }

    route.navigate(to: .home)
    XCTAssertEqual(changeCount, 0)
    XCTAssertEqual(route.destination, .home)

    route.navigate(to: .servers)
    XCTAssertEqual(changeCount, 1)
    XCTAssertEqual(route.destination, .servers)

    route.navigate(to: .servers)
    XCTAssertEqual(changeCount, 1)
  }

  func testDestinationVocabularyIsFiniteAndStable() {
    XCTAssertEqual(
      WorkspaceDestination.allCases,
      [.home, .servers, .rules, .settings])
  }

  func testNavigateChangesDestinationOnly() {
    let route = WorkspaceRoute()

    route.navigate(to: .servers)

    XCTAssertEqual(route.destination, .servers)
  }

  /// 开窗落点纪律（ADR 0016，scene 方式）：主窗口是 SwiftUI `Window` scene，
  /// 主窗口重开只由状态菜单发起，规则页只可打开转换报告；启动呈现由
  /// 场景 defaultLaunchBehavior 负责。workspace id 保持在 route 中定义。
  func testWindowOpeningStaysInSanctionedSurfaces() throws {
    let appDirectory = TestSourceTree.ng2Root().appendingPathComponent(
      "App", isDirectory: true)
    let openWindowAllowed = Set(["ProxyStatusMenu.swift", "RulesView.swift"])
    let sceneIDLiteralAllowed = Set(["WorkspaceRoute.swift"])
    let fileManager = FileManager.default
    let urls = try XCTUnwrap(
      fileManager.enumerator(
        at: appDirectory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )?.compactMap { $0 as? URL }
        .filter { $0.pathExtension == "swift" })

    var openWindowViolations: [String] = []
    var sceneIDViolations: [String] = []
    for url in urls {
      guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
      let name = url.lastPathComponent
      if name == "RulesView.swift" {
        let calls = source.components(separatedBy: .newlines).filter { $0.contains("openWindow(") }
        XCTAssertTrue(
          calls.allSatisfy { $0.contains("openWindow(id: RulesReportView.sceneID)") },
          "规则页只能打开转换报告窗口")
      }
      if !openWindowAllowed.contains(name), source.contains("openWindow(") {
        openWindowViolations.append(name)
      }
      if !sceneIDLiteralAllowed.contains(name), source.contains(#""workspace""#) {
        sceneIDViolations.append(name)
      }
    }

    XCTAssertTrue(
      openWindowViolations.isEmpty,
      "openWindow 调用只允许在状态菜单和规则报告入口：\(openWindowViolations)")
    XCTAssertTrue(
      sceneIDViolations.isEmpty,
      "scene id 字面量只允许定义在 WorkspaceRoute：\(sceneIDViolations)")
  }
}
