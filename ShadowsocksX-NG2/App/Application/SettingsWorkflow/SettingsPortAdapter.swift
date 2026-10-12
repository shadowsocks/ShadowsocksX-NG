import Foundation

/// 写入侧窄 seam：设置工作流只依赖已提交快照、当前 runtime 的
/// typed listener facts 与提交入口。生产实现是 `ProxyRuntimeController`
/// 的薄扩展；测试注入 fake。Domain 快照类型只出现在本缝与 adapter。读取侧是
/// 运行时控制器的主 actor 状态，本缝随之主 actor 绑定。
@MainActor
protocol SettingsCommitting: AnyObject {
  var committedSettings: ProxySettings { get }
  var runtimeListenFacts: RuntimeListenFacts? { get }
  var runtimeListenerProcessID: Int32? { get }
  func updateSettings(_ proposed: ProxySettings) async throws
}

extension ProxyRuntimeController: SettingsCommitting {
  var committedSettings: ProxySettings { settings }
  var runtimeListenFacts: RuntimeListenFacts? { effectiveRuntimeListenFacts }
  var runtimeListenerProcessID: Int32? { effectiveRuntimeListenerProcessID }

}

/// Settings field adapters keep port IDs, endpoints, and validation facts aligned.
enum SettingsPortAdapter {
  /// UI 形状端口标识 → 端点类型（module 内部复用 Domain 端口语义）。
  static func endpoint(for id: SettingsPortID) -> ProxyEndpointKind {
    switch id {
    case .socks: .socks
    case .http: .http
    }
  }

  /// Domain 点名校验错误 → 按字段归位的问题；点名文案沿用既有错误属性。
  /// 端口互异涉及两个端点，两侧端口各归位一条，用户只改有错的那个输入。
  static func fieldIssues(from errors: [ProxySettingsValidationError]) -> [SettingsFieldIssue] {
    errors.flatMap { error -> [SettingsFieldIssue] in
      switch error {
      case .portOutOfRange(let endpoint, _):
        return [.port(portID(for: endpoint), error: error)]
      case .duplicatePort(let endpoint, let otherEndpoint, _):
        return [
          .port(portID(for: endpoint), error: error),
          .port(portID(for: otherEndpoint), error: error),
        ]
      }
    }
  }

  private static func portID(for endpoint: ProxyEndpointKind) -> SettingsPortID {
    switch endpoint {
    case .socks, .lanSocks: .socks
    case .http, .lanHTTP: .http
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
