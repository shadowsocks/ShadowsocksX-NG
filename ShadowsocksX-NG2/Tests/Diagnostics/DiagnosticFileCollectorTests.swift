import XCTest

@testable import ShadowsocksX_NG2

/// 文件事实收集：只读存在性/权限/大小/时间，永不读内容。
final class DiagnosticFileCollectorTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ssxng-diag-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    // 临时目录默认带 0755：对齐产品基线（运行时目录 0700）再断言。
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700], ofItemAtPath: directory.path)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    try super.tearDownWithError()
  }

  func testCollectsPermissionsSizeAndTimeForFile() throws {
    let url = directory.appendingPathComponent("catalog.json")
    try Data(repeating: 0x41, count: 123).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    let before = Date().addingTimeInterval(-60)

    let facts = DiagnosticFileCollector.collect(label: "catalog.json", url: url)

    XCTAssertTrue(facts.exists)
    XCTAssertFalse(facts.isDirectory)
    XCTAssertEqual(facts.permissionsOctal, "0600")
    XCTAssertEqual(facts.sizeBytes, 123)
    let modified = try XCTUnwrap(facts.modifiedAt)
    XCTAssertGreaterThanOrEqual(modified, before)
  }

  func testCollectsDirectoryPermissionsWithoutSize() throws {
    let facts = DiagnosticFileCollector.collect(label: "运行时目录", url: directory)

    XCTAssertTrue(facts.exists)
    XCTAssertTrue(facts.isDirectory)
    XCTAssertEqual(facts.permissionsOctal, "0700")
  }

  func testMissingFileReportsNonExistenceWithNoFacts() {
    let facts = DiagnosticFileCollector.collect(
      label: "agent.pid", url: directory.appendingPathComponent("missing"))

    XCTAssertFalse(facts.exists)
    XCTAssertNil(facts.permissionsOctal)
    XCTAssertNil(facts.sizeBytes)
    XCTAssertNil(facts.modifiedAt)
  }
}
