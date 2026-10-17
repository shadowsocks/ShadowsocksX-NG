import Foundation

/// 偏好存储。非敏感字段写入受保护的 JSON。GFWList URL 与 PAC 用户规则已移除；
/// 未发布的 NG2 PAC 偏好不做迁移。
struct ProxySettingsFileStore: ProxySettingsStoring {
  let fileURL: URL

  init(
    fileURL: URL = ProxySettingsFileStore.defaultFileURL()
  ) {
    self.fileURL = fileURL
  }

  static func defaultFileURL() -> URL {
    RuntimePaths.settingsFileURL()
  }

  func load() throws -> ProxySettings {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return ProxySettings()
    }

    let data: Data
    do {
      data = try Data(contentsOf: fileURL)
    } catch {
      throw ProxySettingsStoreError.ioFailure(detail: String(describing: error))
    }
    let record: ProxySettingsRecord
    do {
      record = try JSONDecoder().decode(ProxySettingsRecord.self, from: data)
    } catch {
      throw ProxySettingsStoreError.corrupt(detail: String(describing: error))
    }
    return try settings(from: record)
  }

  func save(_ settings: ProxySettings) throws {
    _ = try validated(settings)
    do {
      let data = try Self.jsonEncoder.encode(record(from: settings))
      try AtomicFileWriter.write(data, to: fileURL)
    } catch {
      throw ProxySettingsStoreError.ioFailure(detail: String(describing: error))
    }
  }

  static func restored(store: ProxySettingsFileStore = ProxySettingsFileStore())
    -> RestoredProxySettings
  {
    do {
      return RestoredProxySettings(settings: try store.load(), unreadableError: nil)
    } catch {
      // load() 的契约只抛 ProxySettingsStoreError；Swift 的 throws 擦除迫使这里收窄一次。
      guard let storeError = error as? ProxySettingsStoreError else {
        preconditionFailure("load() 只抛 ProxySettingsStoreError")
      }
      RuntimeLog.emit(.settingsUnreadable(detail: String(describing: error)))
      return RestoredProxySettings(settings: ProxySettings(), unreadableError: storeError)
    }
  }

  private func validated(_ settings: ProxySettings) throws -> ProxySettings {
    try settings.enforcePersistenceConstraints()
    return settings
  }

  private func settings(from record: ProxySettingsRecord) throws -> ProxySettings {
    var listen = SslocalListenSettings()
    listen.local = record.localListen
    listen.lan = record.lanListen

    return try validated(
      ProxySettings(
        listen: listen,
        connectivityURLReference: record.connectivityURLReference,
        proxyExceptions: record.proxyExceptions,
        preferredMode: record.preferredMode,
        ruleDefaultAction: record.ruleDefaultAction,
        agentEnabled: record.agentEnabled,
        systemProxyEnabled: record.systemProxyEnabled))
  }

  private func record(from settings: ProxySettings) -> ProxySettingsRecord {
    var record = ProxySettingsRecord()
    record.connectivityURLReference = settings.connectivityURLReference
    record.localListen = settings.listen.local
    record.lanListen = settings.listen.lan
    record.proxyExceptions = settings.proxyExceptions
    record.preferredMode = settings.preferredMode
    record.ruleDefaultAction = settings.ruleDefaultAction
    record.agentEnabled = settings.agentEnabled
    record.systemProxyEnabled = settings.systemProxyEnabled
    return record
  }

  private static let jsonEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }()
}

private struct ProxySettingsRecord: Codable, Equatable, Sendable {
  var connectivityURLReference: CredentialReference?
  var localListen = LocalListeningSettings()
  var lanListen = LANListeningSettings()
  var proxyExceptions: String = ProxySettings.defaultProxyExceptions
  var preferredMode: ProxyModeKind = .rule
  var ruleDefaultAction: RuleDefaultAction = .proxyWhenUnmatched
  var agentEnabled: Bool = false
  var systemProxyEnabled: Bool = false

  init() {}

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    connectivityURLReference = try container.decodeIfPresent(
      CredentialReference.self, forKey: .connectivityURLReference)
    // 未正式发版：忽略旧的单组监听字段，不迁移独立旧监听文件。
    localListen =
      try container.decodeIfPresent(LocalListeningSettings.self, forKey: .localListen)
      ?? LocalListeningSettings()
    lanListen =
      try container.decodeIfPresent(LANListeningSettings.self, forKey: .lanListen)
      ?? LANListeningSettings()
    proxyExceptions =
      try container.decodeIfPresent(String.self, forKey: .proxyExceptions)
      ?? ProxySettings.defaultProxyExceptions
    // 旧 NG2 偏好里的 "pac" 等已删除值容错回落到规则模式。未发布的 PAC 偏好
    // 不做迁移，但解码失败会把全部保留字段连坐丢掉。
    if let rawMode = try container.decodeIfPresent(String.self, forKey: .preferredMode),
      let mode = ProxyModeKind(rawValue: rawMode)
    {
      preferredMode = mode
    } else {
      preferredMode = .rule
    }
    // 规则模式子选项：出厂「未匹配时代理」。
    ruleDefaultAction =
      try container.decodeIfPresent(RuleDefaultAction.self, forKey: .ruleDefaultAction)
      ?? .proxyWhenUnmatched
    // 未发版无迁移：缺省 agent off、系统代理 off（ADR-0011）。
    agentEnabled = try container.decodeIfPresent(Bool.self, forKey: .agentEnabled) ?? false
    systemProxyEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .systemProxyEnabled) ?? false
  }
}

extension ProxySettingsRecord {
  fileprivate enum CodingKeys: String, CodingKey {
    case connectivityURLReference
    case localListen, lanListen
    case proxyExceptions
    case preferredMode
    case ruleDefaultAction
    case agentEnabled, systemProxyEnabled
  }
}
