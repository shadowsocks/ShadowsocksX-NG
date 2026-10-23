import Combine
import XCTest

@testable import ShadowsocksX_NG2

@MainActor
final class WorkspaceRouteTests: XCTestCase {
  func testFreshRouteStartsAtHomeWithoutPersistedState() {
    XCTAssertEqual(WorkspaceRoute().destination, .home)
  }

  /// 侧栏 List/NavigationSplitView 会在视图更新期间回写 selection Binding；
  /// 同值导航不得 publish（否则触发 view-update 期间发布警告）。
  func testNavigateToCurrentDestinationDoesNotPublish() {
    let route = WorkspaceRoute()
    var changeCount = 0
    let cancellable = route.objectWillChange.sink { _ in changeCount += 1 }
    defer { cancellable.cancel() }

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
}
