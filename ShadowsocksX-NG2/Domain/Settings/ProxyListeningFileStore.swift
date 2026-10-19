import Foundation

extension ProxyListeningConfiguration {
  /// 保存时联合校验四端口，身份验证开启时要求用户名与密码有效。
  func enforcePersistenceConstraints() throws {
    if lan.authenticationEnabled
      && (!RuntimeListenerAuthentication.validUsername(lan.username)
        || !RuntimeListenerAuthentication.validPassword(lan.password ?? ""))
    {
      throw ProxyListeningStoreError.credentialFailure(detail: String(localized: "局域网身份验证凭据无效"))
    }
    let errors = portValidationErrors()
    guard errors.isEmpty else { throw ProxyListeningStoreError.invalid(errors) }
  }
}

protocol ProxyListeningStoring {
  func load() throws -> ProxyListeningConfiguration
  func save(_ configuration: ProxyListeningConfiguration) throws
}

enum ProxyListeningStoreError: Error, Equatable {
  case corrupt(detail: String)
  case invalid([PortSettingError])
  case ioFailure(detail: String)
  case credentialFailure(detail: String)
  case encryptedFile(EncryptedFileError)
}

/// 整体加密保存监听配置，不承载控制偏好或其他场景设置。
struct ProxyListeningFileStore: ProxyListeningStoring {
  let fileURL: URL
  private let encrypted: EncryptedFileStorage<ProxyListeningConfiguration>

  init(
    fileURL: URL = ProxyListeningFileStore.defaultFileURL(),
    keys: MasterKeyStoring = KeychainMasterKeyStore(namespace: "proxy-listening")
  ) {
    self.fileURL = fileURL
    encrypted = EncryptedFileStorage(
      keys: keys, magic: "SSXNG2LP", version: 1, maximumSize: 1024 * 1024,
      legacyFileName: "proxy-listening.json", makeDefault: { ProxyListeningConfiguration() },
      encode: { configuration in
        try configuration.enforcePersistenceConstraints()
        return try JSONEncoder().encode(configuration)
      },
      decode: { data in
        let configuration: ProxyListeningConfiguration
        do {
          configuration = try JSONDecoder().decode(ProxyListeningConfiguration.self, from: data)
        } catch { throw ProxyListeningStoreError.corrupt(detail: "invalid listening payload") }
        try configuration.enforcePersistenceConstraints()
        return configuration
      })
  }

  static func defaultFileURL() -> URL { RuntimePaths.proxyListeningFileURL() }

  func load() throws -> ProxyListeningConfiguration {
    try translatingErrors { try encrypted.load(at: fileURL, allowingInteraction: false) }
  }

  func save(_ configuration: ProxyListeningConfiguration) throws {
    try configuration.enforcePersistenceConstraints()
    try translatingErrors {
      if !encrypted.isLoaded { _ = try load() }
      try encrypted.save(configuration, at: fileURL)
    }
  }

  func reset() throws -> ProxyListeningConfiguration {
    try translatingErrors { try encrypted.reset(at: fileURL) }
  }

  private func translatingErrors<T>(_ operation: () throws -> T) throws -> T {
    do { return try operation() } catch let error as ProxyListeningStoreError {
      throw error
    } catch let error as EncryptedFileError {
      throw ProxyListeningStoreError.encryptedFile(error)
    } catch is MasterKeyStoreError {
      throw ProxyListeningStoreError.credentialFailure(detail: String(localized: "无法访问监听配置主密钥"))
    } catch { throw ProxyListeningStoreError.ioFailure(detail: String(describing: error)) }
  }

}
