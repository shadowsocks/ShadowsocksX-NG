import Foundation

// MARK: - Setting editor models

/// Stable UI identifier for the SOCKS5 and HTTP port fields. The view does not
/// need to import the probe layer's endpoint type.
enum SettingsPortID: CaseIterable, Hashable, Sendable {
  case socks
  case http
}

/// The SOCKS5 and HTTP ports edited and saved together as one settings item.
enum SettingsListeningGroup: Sendable { case local, lan }

struct SettingsPortDraft: Equatable, Sendable {
  var socksPort: Int
  var httpPort: Int
  var group: SettingsListeningGroup = .local
  var listenerMode: LANListenerMode = .allIPv4Interfaces
  var isEnabled = false

  func portValue(for id: SettingsPortID) -> Int {
    switch id {
    case .socks: socksPort
    case .http: httpPort
    }
  }

  mutating func setPortValue(_ value: Int, for id: SettingsPortID) {
    switch id {
    case .socks: socksPort = value
    case .http: httpPort = value
    }
  }
}

// MARK: - 按字段归位的校验问题

/// 字段标识（按字段归位查询）；端口问题用端口标识变体。
enum SettingsFieldID: Hashable, Sendable {
  case port(SettingsPortID)
}

/// 按字段归位的校验问题：每条保留 Domain 的 typed fact；文案由 App
/// presentation edge 派生。
enum SettingsFieldIssue: Hashable, Sendable {
  case port(SettingsPortID, error: ProxySettingsValidationError)

  var field: SettingsFieldID {
    switch self {
    case .port(let id, _): .port(id)
    }
  }

  var error: ProxySettingsValidationError {
    switch self {
    case .port(_, let error):
      error
    }
  }
}

// MARK: - 端口 field state

/// 端口占用的类型化事实（UI 形状）：文案与颜色由视图决定。
enum SettingsPortOccupancy: Equatable, Sendable {
  case free
  /// 端口不可绑定；占用进程名尽力解析（未知为 nil）。
  case occupied(occupier: String?)
  case unknown(detail: String)
}

/// 每个端口字段的 field state：两个端口行复用同一套呈现逻辑。
struct SettingsPortFieldState: Equatable, Sendable {
  let id: SettingsPortID
  /// 该端口当前草稿值。
  let draftValue: Int
  /// 类型化占用事实；`nil` = 尚未探测。
  let occupancy: SettingsPortOccupancy?
  /// 该端口的字段问题事实；文案由 presentation edge 派生。
  let issues: [SettingsFieldIssue]
  /// Whether the running listener matches the complete edited listen identity.
  let isRuntimePortException: Bool
  /// 是否可建议空闲端口（被占用且不是运行中端口例外）。
  let canSuggestFreePort: Bool
}

// MARK: - 命令结果与拒绝原因

/// Typed reasons why a command cannot proceed. The workflow exposes facts,
/// not localized strings or a Boolean that makes validation and occupancy
/// failures indistinguishable.
enum SettingsCommandRejection: Equatable, Sendable {
  case inProgress
  case superseded
  case validation([SettingsFieldIssue])
  case occupied([SettingsPortID])
  case noFreePort(SettingsPortID)
}

enum SettingsPersistenceFailure: Error, Equatable, Sendable {
  case store(ProxySettingsStoreError)
  case unknown
}

/// Results for port suggestion and item-save commands. Proxy runtime status is
/// presented by its owning status UI, not this settings interface.
enum SettingsCommandOutcome: Equatable, Sendable {
  case rejected(SettingsCommandRejection)
  case suggestedPort(port: SettingsPortID, value: Int)
  case persisted
  case persistenceFailed(SettingsPersistenceFailure)
}

/// Settings workflow 的最后失败仍是 typed；workflow 不提前渲染句子。
enum SettingsWorkflowFailure: Error, Equatable, Sendable {
  case store(ProxySettingsStoreError)
  case unknown
}

/// 局域网 sheet 的完整草稿；密码只属于编辑会话。
struct LANListeningDraft: Equatable, Sendable {
  var ports: SettingsPortDraft
  var udpRelayEnabled: Bool
  var authenticationEnabled: Bool
  var username: String
  var password: String

  var hasValidCredentials: Bool {
    RuntimeListenerAuthentication.validUsername(username)
      && RuntimeListenerAuthentication.validPassword(password)
  }

  var isEnabled: Bool {
    get { ports.isEnabled }
    set { ports.isEnabled = newValue }
  }

  var mode: LANListenerMode {
    get { ports.listenerMode }
    set { ports.listenerMode = newValue }
  }
}
