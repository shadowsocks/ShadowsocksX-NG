import Foundation
import Security

enum MasterKeyStoreError: Error, Equatable {
  case keychainStatus(OSStatus)
}

/// 主密钥的二进制存储；交互只由显式解锁或重置命令开启。
protocol MasterKeyStoring {
  func read(_ id: UUID, allowingInteraction: Bool) throws -> Data?
  func create(_ data: Data, id: UUID, allowingInteraction: Bool) throws
}

struct KeychainMasterKeyStore: MasterKeyStoring {
  let service: String

  init(namespace: String) {
    self.service = "com.qiuyuzhou.ShadowsocksX-NG2.\(namespace)"
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
        throw MasterKeyStoreError.keychainStatus(status)
      }
      return data
    }
  }

  func create(_ data: Data, id: UUID, allowingInteraction: Bool) throws {
    try withClassicKeychainInteraction(allowingInteraction) {
      var application: SecTrustedApplication?
      try check(SecTrustedApplicationCreateFromPath(nil, &application))
      guard let application else { throw MasterKeyStoreError.keychainStatus(errSecParam) }
      var access: SecAccess?
      try check(
        SecAccessCreate(
          "ShadowsocksX-NG2 encrypted configuration" as CFString,
          [application] as CFArray, &access))
      guard let access else { throw MasterKeyStoreError.keychainStatus(errSecParam) }
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
    guard status == errSecSuccess else { throw MasterKeyStoreError.keychainStatus(status) }
  }
}

/// 经典钥匙串使用进程级交互开关。同步调用结束后恢复原值，不把交互许可留给后台操作。
private func withClassicKeychainInteraction<T>(_ allowed: Bool, _ operation: () throws -> T) throws
  -> T
{
  var previous: DarwinBoolean = false
  let getStatus = SecKeychainGetUserInteractionAllowed(&previous)
  guard getStatus == errSecSuccess else { throw MasterKeyStoreError.keychainStatus(getStatus) }
  let setStatus = SecKeychainSetUserInteractionAllowed(allowed)
  guard setStatus == errSecSuccess else { throw MasterKeyStoreError.keychainStatus(setStatus) }
  defer { SecKeychainSetUserInteractionAllowed(previous.boolValue) }
  return try operation()
}
