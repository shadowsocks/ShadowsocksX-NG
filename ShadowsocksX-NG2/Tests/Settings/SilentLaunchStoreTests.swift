import XCTest

@testable import ShadowsocksX_NG2

/// 静默启动偏好持久化（ADR 0017，UserDefaults 形态）：往返无损；键缺失与
/// 外部错误类型按安全侧恢复「不静默」。
/// 套件实例 + teardown 移除持久域，不触碰生产 defaults（测试封闭性公约）。
final class SilentLaunchStoreTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!
  private var store: SilentLaunchStore!

  override func setUpWithError() throws {
    try super.setUpWithError()
    suiteName = "silent-launch-store-tests-\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    store = SilentLaunchStore(defaults: defaults)
  }

  override func tearDownWithError() throws {
    defaults.removePersistentDomain(forName: suiteName)
    try super.tearDownWithError()
  }

  // MARK: 缺失与错误类型

  func testMissingKeyLoadsAsNotSilent() {
    XCTAssertFalse(store.loadSilentLaunchEnabled(), "键缺失按出厂默认：不静默")
  }

  func testForeignTypeLoadsAsNotSilentOnTheSafeSide() {
    // cfprefs 无「损坏」可观测性：外部写入的错误类型按安全侧回落默认。
    defaults.set("yes", forKey: "silentLaunch")

    XCTAssertFalse(store.loadSilentLaunchEnabled())
  }

  // MARK: 往返无损

  func testSaveAndLoadRoundTripBothValues() {
    store.save(silentLaunchEnabled: true)
    XCTAssertTrue(store.loadSilentLaunchEnabled())

    store.save(silentLaunchEnabled: false)
    XCTAssertFalse(store.loadSilentLaunchEnabled())
  }

}
