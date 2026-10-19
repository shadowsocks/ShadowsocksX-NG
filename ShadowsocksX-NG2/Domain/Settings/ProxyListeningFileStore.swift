import Foundation

extension ProxyListeningConfiguration {
  /// 保存时联合校验四端口，身份验证开启时要求用户名与密码引用有效。
  func enforcePersistenceConstraints() throws {
    if lan.authenticationEnabled
      && (!RuntimeListenerAuthentication.validUsername(lan.username)
        || lan.passwordReference == nil)
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

struct RestoredProxyListeningConfiguration {
  let configuration: ProxyListeningConfiguration
  let unreadableError: ProxyListeningStoreError?
}

enum ProxyListeningStoreError: Error, Equatable {
  case corrupt(detail: String)
  case invalid([PortSettingError])
  case ioFailure(detail: String)
  case credentialFailure(detail: String)
}

/// 只保存本地与局域网监听配置，不承载控制偏好或其他场景设置。
struct ProxyListeningFileStore: ProxyListeningStoring {
  let fileURL: URL

  init(fileURL: URL = ProxyListeningFileStore.defaultFileURL()) {
    self.fileURL = fileURL
  }

  static func defaultFileURL() -> URL { RuntimePaths.proxyListeningFileURL() }

  func load() throws -> ProxyListeningConfiguration {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return ProxyListeningConfiguration()
    }
    let data: Data
    do { data = try Data(contentsOf: fileURL) } catch {
      throw ProxyListeningStoreError.ioFailure(detail: String(describing: error))
    }
    let record: ProxyListeningRecord
    do { record = try JSONDecoder().decode(ProxyListeningRecord.self, from: data) } catch {
      throw ProxyListeningStoreError.corrupt(detail: String(describing: error))
    }
    var configuration = ProxyListeningConfiguration()
    configuration.local = record.localListen
    configuration.lan = record.lanListen
    try configuration.enforcePersistenceConstraints()
    return configuration
  }

  func save(_ configuration: ProxyListeningConfiguration) throws {
    try configuration.enforcePersistenceConstraints()
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let record = ProxyListeningRecord(
        localListen: configuration.local, lanListen: configuration.lan)
      try AtomicFileWriter.write(encoder.encode(record), to: fileURL)
    } catch {
      throw ProxyListeningStoreError.ioFailure(detail: String(describing: error))
    }
  }

  static func restored(store: ProxyListeningFileStore = ProxyListeningFileStore())
    -> RestoredProxyListeningConfiguration
  {
    do {
      return RestoredProxyListeningConfiguration(
        configuration: try store.load(), unreadableError: nil)
    } catch {
      guard let failure = error as? ProxyListeningStoreError else {
        preconditionFailure("load() 只抛 ProxyListeningStoreError")
      }
      RuntimeLog.emit(.settingsUnreadable(detail: String(describing: failure)))
      return RestoredProxyListeningConfiguration(
        configuration: ProxyListeningConfiguration(), unreadableError: failure)
    }
  }
}

private struct ProxyListeningRecord: Codable {
  var localListen: LocalListeningSettings
  var lanListen: LANListeningSettings

  init(localListen: LocalListeningSettings, lanListen: LANListeningSettings) {
    self.localListen = localListen
    self.lanListen = lanListen
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    localListen =
      try values.decodeIfPresent(LocalListeningSettings.self, forKey: .localListen)
      ?? LocalListeningSettings()
    lanListen =
      try values.decodeIfPresent(LANListeningSettings.self, forKey: .lanListen)
      ?? LANListeningSettings()
  }
}
