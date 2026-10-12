import Security
import XCTest

@testable import ShadowsocksX_NG2

/// `CredentialWriteJournal` 自身 seam 的语义：首触快照、幂等
/// 删除、尽力回滚的三种结果。回滚经 typed outcome 断言，不戳存储内部状态。
final class CredentialWriteJournalTests: XCTestCase {
  private let passwordRef = CredentialReference(rawValue: "ref-pw")
  private let optionsRef = CredentialReference(rawValue: "ref-opts")

  // MARK: - 快照语义

  func testSaveSnapshotsOriginalOnFirstTouchOnly() throws {
    let store = InMemoryCredentialStore()
    try store.save("旧密码", for: passwordRef)
    var journal = CredentialWriteJournal(credentials: store)

    try journal.save("新密码", for: passwordRef)
    try journal.save("更新密码", for: passwordRef)

    XCTAssertEqual(journal.rollback(), .restored([passwordRef]))
    XCTAssertEqual(try store.secret(for: passwordRef), "旧密码", "回滚恢复首触快照而非中间值")
  }

  func testRollbackWithoutTouchReportsNothingToRestore() {
    let store = InMemoryCredentialStore()
    let journal = CredentialWriteJournal(credentials: store)

    XCTAssertEqual(journal.rollback(), .nothingToRestore)
  }

  func testRollbackDeletesReferenceThatWasOriginallyAbsent() throws {
    let store = InMemoryCredentialStore()
    var journal = CredentialWriteJournal(credentials: store)

    try journal.save("新秘密", for: passwordRef)

    XCTAssertEqual(journal.rollback(), .restored([passwordRef]))
    XCTAssertNil(try store.secret(for: passwordRef), "原本不存在的引用回滚后归于不存在")
  }

  // MARK: - delete 的回滚 = 复活旧秘密

  func testRollbackRevivesSecretDeletedByJournal() throws {
    let store = InMemoryCredentialStore()
    try store.save("mode=websocket", for: optionsRef)
    var journal = CredentialWriteJournal(credentials: store)

    journal.delete(optionsRef)
    XCTAssertNil(try store.secret(for: optionsRef))

    XCTAssertEqual(journal.rollback(), .restored([optionsRef]))
    XCTAssertEqual(try store.secret(for: optionsRef), "mode=websocket")
  }

  func testDeleteIsIdempotentAndKeepsFirstSnapshot() throws {
    let store = InMemoryCredentialStore()
    try store.save("mode=websocket", for: optionsRef)
    var journal = CredentialWriteJournal(credentials: store)

    journal.delete(optionsRef)
    try journal.save("obfs=http", for: optionsRef)
    journal.delete(optionsRef)

    XCTAssertEqual(journal.rollback(), .restored([optionsRef]))
    XCTAssertEqual(try store.secret(for: optionsRef), "mode=websocket", "二次触碰不覆盖首触快照")
  }

  // MARK: - 残局可观测（旧值继续生效的不变量被存储失败违例时点名）

  func testPartialRollbackNamesReferencesThatCouldNotBeRestored() throws {
    let store = SelectivelyFailingCredentialStore()
    try store.save("旧密码", for: passwordRef)
    try store.save("mode=websocket", for: optionsRef)
    store.failSave[passwordRef] = "旧密码"
    var journal = CredentialWriteJournal(credentials: store)

    try journal.save("新密码", for: passwordRef)
    journal.delete(optionsRef)

    XCTAssertEqual(
      journal.rollback(),
      .partial(restored: [optionsRef], failed: [passwordRef]),
      "单个恢复失败不中断其余引用的恢复")
  }

  func testPartialRollbackReportsFailedDeletionOfOriginallyAbsentReference() throws {
    let store = SelectivelyFailingCredentialStore()
    store.failDelete = [passwordRef]
    var journal = CredentialWriteJournal(credentials: store)

    try journal.save("新秘密", for: passwordRef)

    XCTAssertEqual(journal.rollback(), .partial(restored: [], failed: [passwordRef]))
    XCTAssertEqual(try store.secret(for: passwordRef), "新秘密", "删除失败即原值未生效，点名在 failed")
  }
}

/// 可注入「写回原值失败」的凭据存储：按 (引用, 秘密值) 对与引用命中抛错，
/// 用于制造 journal 回滚的 `.partial` 残局。命中之外的读写与 InMemory 契约
/// 一致。
private final class SelectivelyFailingCredentialStore: CredentialStoring {
  private var storage: [String: String] = [:]
  /// 命中 (引用, 秘密值) 的 save 抛错（回滚写回原值即此形态）。
  var failSave: [CredentialReference: String] = [:]
  /// 命中引用的 delete 抛错。
  var failDelete: Set<CredentialReference> = []

  func save(_ secret: String, for reference: CredentialReference) throws {
    if failSave[reference] == secret {
      throw CredentialStoreError.keychainStatus(errSecInternalError)
    }
    storage[reference.rawValue] = secret
  }

  func secret(for reference: CredentialReference) throws -> String? {
    storage[reference.rawValue]
  }

  func delete(_ reference: CredentialReference) throws {
    if failDelete.contains(reference) {
      throw CredentialStoreError.keychainStatus(errSecInternalError)
    }
    storage.removeValue(forKey: reference.rawValue)
  }
}
