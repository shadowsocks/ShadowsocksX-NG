import XCTest

@testable import ShadowsocksX_NG2

/// 静默启动控制器（ADR 0017）：初始值来自持久化；翻转先落盘后翻内存。
/// UserDefaults 无失败信号，文件版的「失败保原值并点名」路径不再存在。
@MainActor
final class SilentLaunchControllerTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!
  private var store: SilentLaunchStore!

  override func setUp() async throws {
    try await super.setUp()
    suiteName = "silent-launch-controller-tests-\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    store = SilentLaunchStore(defaults: defaults)
  }

  override func tearDown() async throws {
    defaults.removePersistentDomain(forName: suiteName)
    try await super.tearDown()
  }

  func testInitialValueComesFromStore() {
    XCTAssertFalse(
      SilentLaunchController(store: store).isEnabled, "无持久化记录按出厂默认：不静默")

    store.save(silentLaunchEnabled: true)
    XCTAssertTrue(SilentLaunchController(store: store).isEnabled)
  }

  func testEnablePersistsBeforeFlippingPublishedState() {
    let controller = SilentLaunchController(store: store)

    controller.setEnabled(true)

    XCTAssertTrue(controller.isEnabled)
    XCTAssertTrue(store.loadSilentLaunchEnabled())
  }

  func testDisablePersists() {
    store.save(silentLaunchEnabled: true)
    let controller = SilentLaunchController(store: store)

    controller.setEnabled(false)

    XCTAssertFalse(controller.isEnabled)
    XCTAssertFalse(store.loadSilentLaunchEnabled())
  }
}
