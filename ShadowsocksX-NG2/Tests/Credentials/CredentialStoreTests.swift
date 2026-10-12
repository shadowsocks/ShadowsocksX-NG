import XCTest

@testable import ShadowsocksX_NG2

/// 凭据存储缝：Keychain 写入/读出一致。
final class KeychainCredentialStoreTests: XCTestCase {
  private var store: KeychainCredentialStore!

  override func setUpWithError() throws {
    try super.setUpWithError()
    // 每个用例独立 service 命名空间：避免并行/重复运行互相污染
    let service = "test.ShadowsocksX-NG2.credentials.\(UUID().uuidString)"
    store = KeychainCredentialStore(service: service)
    addTeardownBlock { [service] in
      Self.removeKeychainItems(for: service)
    }
  }

  private static func removeKeychainItems(for service: String) {
    // 先枚举本用例 service 下的全部 account，再逐条删除。先解包为 String，
    // 避免将 `Optional<String>` 桥接进 Security query；逐条删除则不会遗漏同一
    // service 下多个凭据引用的记录。
    let lookup: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecReturnAttributes as String: kCFBooleanTrue as Any,
      kSecMatchLimit as String: kSecMatchLimitAll,
    ]
    var result: AnyObject?
    let lookupStatus = SecItemCopyMatching(lookup as CFDictionary, &result)
    guard lookupStatus == errSecSuccess || lookupStatus == errSecItemNotFound else {
      XCTFail("查找测试 Keychain 记录失败，status=\(lookupStatus)")
      return
    }

    let items = (result as? [[String: Any]]) ?? []
    for item in items {
      guard let account = item[kSecAttrAccount as String] as? String else {
        XCTFail("测试 Keychain 记录缺少 account")
        continue
      }
      let deleteQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
      ]
      let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
      XCTAssertTrue(
        deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound,
        "清理测试 Keychain 记录失败，status=\(deleteStatus)")
    }

    var remaining: AnyObject?
    let remainingStatus = SecItemCopyMatching(lookup as CFDictionary, &remaining)
    let remainingItems = (remaining as? [[String: Any]]) ?? []
    XCTAssertTrue(
      remainingStatus == errSecItemNotFound || remainingItems.isEmpty,
      "测试 Keychain 记录未完全清理，status=\(remainingStatus)")
  }

  func testSaveThenReadIsConsistent() throws {
    let reference = CredentialReference.fresh()
    let secret = "s3cret-密码-🔑"

    try store.save(secret, for: reference)

    XCTAssertEqual(try store.secret(for: reference), secret)
  }

  func testSaveOverwritesExistingSecret() throws {
    let reference = CredentialReference.fresh()

    try store.save("旧密码", for: reference)
    try store.save("新密码", for: reference)

    XCTAssertEqual(try store.secret(for: reference), "新密码")
  }

  func testAbsentReferenceReadsAsNil() throws {
    XCTAssertNil(try store.secret(for: CredentialReference.fresh()))
  }

  func testDeleteRemovesSecretAndIsIdempotent() throws {
    let reference = CredentialReference.fresh()
    try store.save("s", for: reference)

    try store.delete(reference)

    XCTAssertNil(try store.secret(for: reference))
    XCTAssertNoThrow(try store.delete(reference), "删除不存在的条目不报错")
  }

  func testDistinctReferencesDoNotCollide() throws {
    let first = CredentialReference.fresh()
    let second = CredentialReference.fresh()

    try store.save("A", for: first)
    try store.save("B", for: second)

    XCTAssertEqual(try store.secret(for: first), "A")
    XCTAssertEqual(try store.secret(for: second), "B")
  }
}

final class InMemoryCredentialStoreTests: XCTestCase {
  func testContractMatchesKeychainSemantics() throws {
    let store = InMemoryCredentialStore()
    let reference = CredentialReference.fresh()

    XCTAssertNil(try store.secret(for: reference))
    try store.save("x", for: reference)
    XCTAssertEqual(try store.secret(for: reference), "x")
    try store.save("y", for: reference)
    XCTAssertEqual(try store.secret(for: reference), "y")
    try store.delete(reference)
    XCTAssertNil(try store.secret(for: reference))
    try store.delete(reference)
  }
}
