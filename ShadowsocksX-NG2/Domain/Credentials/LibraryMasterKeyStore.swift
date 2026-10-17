import Foundation
import Security

/// 服务器库主密钥的二进制存储；交互只由显式解锁命令开启。
protocol LibraryMasterKeyStoring {
  func read(_ id: UUID, allowingInteraction: Bool) throws -> Data?
  func create(_ data: Data, id: UUID, allowingInteraction: Bool) throws
}

struct KeychainLibraryMasterKeyStore: LibraryMasterKeyStoring {
  let service: String

  init(service: String = "com.qiuyuzhou.ShadowsocksX-NG2.server-library") {
    self.service = service
  }

  func read(_ id: UUID, allowingInteraction: Bool) throws -> Data? {
    try withClassicKeychainInteraction(allowingInteraction) {
      var query = query(id)
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      var result: AnyObject?
      let status = SecItemCopyMatching(query as CFDictionary, &result)
      if status == errSecItemNotFound { return nil }
      guard status == errSecSuccess, let data = result as? Data else {
        throw CredentialStoreError.keychainStatus(status)
      }
      return data
    }
  }

  func create(_ data: Data, id: UUID, allowingInteraction: Bool) throws {
    try withClassicKeychainInteraction(allowingInteraction) {
      var application: SecTrustedApplication?
      try check(SecTrustedApplicationCreateFromPath(nil, &application))
      guard let application else { throw CredentialStoreError.keychainStatus(errSecParam) }
      var access: SecAccess?
      try check(
        SecAccessCreate(
          "ShadowsocksX-NG2 server library" as CFString,
          [application] as CFArray, &access))
      guard let access else { throw CredentialStoreError.keychainStatus(errSecParam) }
      var item = query(id)
      item[kSecValueData as String] = data
      item[kSecAttrAccess as String] = access
      try check(SecItemAdd(item as CFDictionary, nil))
    }
  }

  private func query(_ id: UUID) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: id.uuidString,
      kSecAttrSynchronizable as String: false,
      kSecUseDataProtectionKeychain as String: false,
    ]
  }

  private func check(_ status: OSStatus) throws {
    guard status == errSecSuccess else { throw CredentialStoreError.keychainStatus(status) }
  }
}

/// 旧逐项凭据迁移同样遵守前台授权入口。
extension KeychainCredentialStore {
  func librarySecret(for reference: CredentialReference, allowingInteraction: Bool) throws
    -> String?
  {
    try withClassicKeychainInteraction(allowingInteraction) { try secret(for: reference) }
  }

  func deleteLibrarySecret(_ reference: CredentialReference, allowingInteraction: Bool) throws {
    try withClassicKeychainInteraction(allowingInteraction) { try delete(reference) }
  }
}

/// 经典钥匙串使用进程级交互开关。同步调用结束后恢复原值，不把交互许可留给后台操作。
private func withClassicKeychainInteraction<T>(_ allowed: Bool, _ operation: () throws -> T) throws
  -> T
{
  var previous: DarwinBoolean = false
  let getStatus = SecKeychainGetUserInteractionAllowed(&previous)
  guard getStatus == errSecSuccess else { throw CredentialStoreError.keychainStatus(getStatus) }
  let setStatus = SecKeychainSetUserInteractionAllowed(allowed)
  guard setStatus == errSecSuccess else { throw CredentialStoreError.keychainStatus(setStatus) }
  defer { SecKeychainSetUserInteractionAllowed(previous.boolValue) }
  return try operation()
}
