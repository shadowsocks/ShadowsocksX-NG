import Foundation
import Security

/// 独立设置凭据访问缝；服务器库中的秘密值不经过此存储。
protocol CredentialStoring {
  /// 写入即覆盖既有值（同一引用始终对应最新秘密）。
  func save(_ secret: String, for reference: CredentialReference) throws
  /// 无对应条目返回 `nil`，不视为错误。
  func secret(for reference: CredentialReference) throws -> String?
  /// 删除不存在的条目不视为错误（幂等）。
  func delete(_ reference: CredentialReference) throws
}

enum CredentialStoreError: Error, Equatable {
  /// Keychain 返回预期之外的状态码。
  case keychainStatus(OSStatus)
  /// 存储的秘密值不是合法 UTF-8 文本。
  case secretNotUTF8
}

/// 生产实现：登录钥匙串 Generic Password。`service` 隔离本应用命名空间，
/// `account` 即凭据引用；可访问性取「首次解锁后」，兼顾代理运行时读取。
struct KeychainCredentialStore: CredentialStoring {
  let service: String

  init(service: String = "com.qiuyuzhou.ShadowsocksX-NG2.credentials") {
    self.service = service
  }

  func save(_ secret: String, for reference: CredentialReference) throws {
    let data = Data(secret.utf8)
    let query = baseQuery(for: reference)
    let update: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
    if status == errSecItemNotFound {
      var addItem = query
      addItem[kSecValueData as String] = data
      addItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      status = SecItemAdd(addItem as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw CredentialStoreError.keychainStatus(status) }
  }

  func secret(for reference: CredentialReference) throws -> String? {
    var query = baseQuery(for: reference)
    query[kSecReturnData as String] = kCFBooleanTrue as Any
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw CredentialStoreError.keychainStatus(status)
    }
    guard let secret = String(data: data, encoding: .utf8) else {
      throw CredentialStoreError.secretNotUTF8
    }
    return secret
  }

  func delete(_ reference: CredentialReference) throws {
    let status = SecItemDelete(baseQuery(for: reference) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw CredentialStoreError.keychainStatus(status)
    }
  }

  private func baseQuery(for reference: CredentialReference) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: reference.rawValue,
    ]
  }
}
