import Foundation

/// 写入侧窄 seam：设置工作流只依赖已提交快照、当前 runtime 的
/// typed listener facts 与提交入口。生产实现是 `ProxyRuntimeController`
/// 的薄扩展；测试注入 fake。Domain 快照类型只出现在本缝与 adapter。读取侧是
/// 运行时控制器的主 actor 状态，本缝随之主 actor 绑定。
@MainActor
protocol SettingsCommitting: AnyObject {
  var committedSettings: ProxyRuntimeSettings { get }
  var runtimeListenFacts: RuntimeListenFacts? { get }
  var runtimeListenerProcessID: Int32? { get }
  func updateListening(_ proposed: ProxyListeningConfiguration) async throws
  func updateProxyExceptions(_ value: String) async
}

extension ProxyRuntimeController: SettingsCommitting {
  var committedSettings: ProxyRuntimeSettings { settings }
  var runtimeListenFacts: RuntimeListenFacts? { effectiveRuntimeListenFacts }
  var runtimeListenerProcessID: Int32? { effectiveRuntimeListenerProcessID }

}

/// Settings field adapters keep port IDs, endpoints, and validation facts aligned.
enum SettingsPortAdapter {
  /// UI 形状端口标识 → 端点类型（module 内部复用 Domain 端口语义）。
  static func endpoint(for id: SettingsPortID, group: SettingsListeningGroup) -> ProxyEndpointKind {
    switch (group, id) {
    case (.local, .socks): .socks
    case (.local, .http): .http
    case (.lan, .socks): .lanSocks
    case (.lan, .http): .lanHTTP
    }
  }

  /// 全局端口校验保留四个端点的身份，错误只归位到当前编辑组涉及的字段。
  static func fieldIssues(
    from errors: [PortSettingError], group: SettingsListeningGroup
  ) -> [SettingsFieldIssue] {
    errors.flatMap { error -> [SettingsFieldIssue] in
      let endpoints: [ProxyEndpointKind]
      switch error {
      case .portOutOfRange(let endpoint, _):
        endpoints = [endpoint]
      case .duplicatePort(let endpoint, let otherEndpoint, _):
        endpoints = [endpoint, otherEndpoint]
      }
      return endpoints.compactMap { endpoint in
        guard
          let id = SettingsPortID.allCases.first(where: {
            Self.endpoint(for: $0, group: group) == endpoint
          })
        else { return nil }
        return .port(id, error: error)
      }
    }
  }

}

extension SettingsPortOccupancy {
  /// 探测层判定 → UI 形状事实。
  init(_ occupancy: PortOccupancy) {
    switch occupancy {
    case .free:
      self = .free
    case .occupied(let facts):
      self = .occupied(occupier: facts.occupier)
    case .unknown(let detail):
      self = .unknown(detail: detail)
    }
  }
}
