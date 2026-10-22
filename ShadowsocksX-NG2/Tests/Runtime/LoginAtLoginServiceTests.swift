import XCTest

@testable import ShadowsocksX_NG2

@MainActor
final class LaunchAtLoginServiceTests: XCTestCase {
  func testStartsOffUntilTheUserEnablesIt() {
    let service = FakeLoginItemService()
    let controller = LaunchAtLoginController(service: service)

    XCTAssertFalse(controller.isEnabled)
    XCTAssertEqual(controller.status, .notRegistered)
    XCTAssertEqual(service.registerCount, 0, "启动不自动注册,默认关闭")
  }

  func testEnablingRegistersAndReflectsSystemState() {
    let service = FakeLoginItemService()
    let controller = LaunchAtLoginController(service: service)

    controller.setEnabled(true)

    XCTAssertTrue(controller.isEnabled)
    XCTAssertEqual(service.registerCount, 1)
    XCTAssertEqual(controller.status, .registered)
    XCTAssertNil(controller.errorMessage)
  }

  func testDisablingUnregistersAndReflectsSystemState() {
    let service = FakeLoginItemService()
    let controller = LaunchAtLoginController(service: service)
    controller.setEnabled(true)

    controller.setEnabled(false)

    XCTAssertFalse(controller.isEnabled)
    XCTAssertEqual(service.unregisterCount, 1)
    XCTAssertEqual(controller.status, .notRegistered)
  }

  func testApprovalPendingCountsAsEnabled() {
    let service = FakeLoginItemService()
    service.status = .requiresApproval
    let controller = LaunchAtLoginController(service: service)

    XCTAssertTrue(controller.isEnabled)
    XCTAssertTrue(controller.requiresApproval)
    XCTAssertEqual(service.registerCount, 0)
  }

  func testRegistrationFailureNamesErrorAndKeepsSystemState() {
    let service = FakeLoginItemService()
    service.registerError = FakeError.system
    let controller = LaunchAtLoginController(service: service)

    controller.setEnabled(true)

    XCTAssertFalse(controller.isEnabled)
    XCTAssertEqual(controller.status, .notRegistered)
    XCTAssertEqual(service.registerCount, 1)
    XCTAssertEqual(controller.errorMessage, AppPresentation.unknownError)
  }

  private enum FakeError: Error, CustomStringConvertible {
    case system

    var description: String { "fake-system-error" }
  }

  private final class FakeLoginItemService: LaunchAtLoginControlling {
    var status: LoginItemStatus = .notRegistered
    var registerCount = 0
    var unregisterCount = 0
    var registerError: Error?

    func register() throws {
      registerCount += 1
      if let registerError { throw registerError }
      status = .registered
    }

    func unregister() throws {
      unregisterCount += 1
      status = .notRegistered
    }
  }
}
