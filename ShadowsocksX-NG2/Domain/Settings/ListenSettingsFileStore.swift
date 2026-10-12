import Foundation

enum ListenSettingsStoreError: Error, Equatable {
  /// 文件存在但不是可接受的记录：JSON 损坏或字段缺失。
  case corrupt(detail: String)
  /// 记录可解码但端口配置无效（范围或互异校验失败）；点名全部原因。
  case invalidPorts([PortSettingError])
  /// 读取或写入时的文件系统错误。
  case ioFailure(detail: String)
}

protocol ListenSettingsStoring {
  /// 文件缺失 → 出厂默认（出厂状态，不是改写用户配置）；损坏或无效 → 抛错。
  func load() throws -> SslocalListenSettings
  /// 保存前先做端口校验，被拒绝的保存不触碰已落盘文件。
  func save(_ settings: SslocalListenSettings) throws
}

/// 应用启动的监听设置恢复结果。`unreadableError` 非 nil 表示用户配置存在但
/// 不可读（损坏、无效或 I/O 失败），此时 `settings` 只是占位出厂默认——
/// 消费方不得静默以占位端口运行（「任何路径不静默改端口」），必须点名
/// 呈现并停止代理，等待用户修复。
struct RestoredListenSettings: Equatable {
  let settings: SslocalListenSettings
  let unreadableError: ListenSettingsStoreError?
}

/// 用户监听设置（端口、监听方式）的磁盘持久化，落盘
/// `~/Library/Application Support/ShadowsocksX-NG2/listen-settings.json`。
/// 只承载用户显式确认过的配置；与运行时契约文件分离。监听方式只按
/// 原样保留，有效性由派生文档的读取侧校验兜底。
struct ListenSettingsFileStore: ListenSettingsStoring {
  private static let jsonEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }()

  let fileURL: URL

  static func defaultFileURL() -> URL {
    RuntimePaths.listenSettingsFileURL()
  }

  init(fileURL: URL = ListenSettingsFileStore.defaultFileURL()) {
    self.fileURL = fileURL
  }

  func load() throws -> SslocalListenSettings {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return SslocalListenSettings()
    }
    let data: Data
    do {
      data = try Data(contentsOf: fileURL)
    } catch {
      throw ListenSettingsStoreError.ioFailure(detail: String(describing: error))
    }
    let record: ListenSettingsRecord
    do {
      record = try JSONDecoder().decode(ListenSettingsRecord.self, from: data)
    } catch {
      throw ListenSettingsStoreError.corrupt(detail: String(describing: error))
    }
    let settings = Self.settings(from: record)
    let validationErrors = settings.portValidationErrors()
    guard validationErrors.isEmpty else {
      throw ListenSettingsStoreError.invalidPorts(validationErrors)
    }
    return settings
  }

  func save(_ settings: SslocalListenSettings) throws {
    let validationErrors = settings.portValidationErrors()
    guard validationErrors.isEmpty else {
      throw ListenSettingsStoreError.invalidPorts(validationErrors)
    }
    let data: Data
    do {
      data = try Self.jsonEncoder.encode(Self.record(from: settings))
    } catch {
      throw ListenSettingsStoreError.ioFailure(detail: String(describing: error))
    }
    do {
      try AtomicFileWriter.write(data, to: fileURL)
    } catch {
      throw ListenSettingsStoreError.ioFailure(detail: String(describing: error))
    }
  }

  /// 应用启动的恢复入口：文件缺失是出厂状态；用户配置不可读时记录事件并
  /// 携带点名错误返回占位出厂默认（消费方据此停止代理并呈现，不静默运行
  /// 在占位端口上。
  static func restored() -> RestoredListenSettings {
    do {
      return RestoredListenSettings(settings: try Self().load(), unreadableError: nil)
    } catch let error as ListenSettingsStoreError {
      RuntimeLog.emit(.listenSettingsUnreadable(detail: String(describing: error)))
      return RestoredListenSettings(
        settings: SslocalListenSettings(), unreadableError: error)
    } catch {
      RuntimeLog.emit(.listenSettingsUnreadable(detail: String(describing: error)))
      return RestoredListenSettings(
        settings: SslocalListenSettings(),
        unreadableError: .ioFailure(detail: String(describing: error)))
    }
  }
}

/// 持久化记录只由本存储读写；测试以原始 JSON 夹具覆盖解码契约。
private struct ListenSettingsRecord: Codable, Equatable, Sendable {
  var listenerMode: ListenerMode = .localhost
  var socksPort: Int = SslocalListenSettings.defaultSocksPort
  var httpPort: Int = SslocalListenSettings.defaultHTTPPort

  init() {}

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    listenerMode =
      try container.decodeIfPresent(ListenerMode.self, forKey: .listenerMode) ?? .localhost
    socksPort =
      try container.decodeIfPresent(Int.self, forKey: .socksPort)
      ?? SslocalListenSettings.defaultSocksPort
    httpPort =
      try container.decodeIfPresent(Int.self, forKey: .httpPort)
      ?? SslocalListenSettings.defaultHTTPPort
  }

  private enum CodingKeys: String, CodingKey {
    case listenerMode, socksPort, httpPort
  }
}

extension ListenSettingsFileStore {
  private static func record(from settings: SslocalListenSettings) -> ListenSettingsRecord {
    var record = ListenSettingsRecord()
    record.listenerMode = settings.listenerMode
    record.socksPort = settings.socksPort
    record.httpPort = settings.httpPort
    return record
  }

  private static func settings(from record: ListenSettingsRecord) -> SslocalListenSettings {
    var settings = SslocalListenSettings()
    settings.listenerMode = record.listenerMode
    settings.socksPort = record.socksPort
    settings.httpPort = record.httpPort
    return settings
  }
}
