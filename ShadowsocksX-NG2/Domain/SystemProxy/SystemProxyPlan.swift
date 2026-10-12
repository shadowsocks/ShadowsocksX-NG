import Foundation

/// 系统代理写入失败：helper 内 SC 操作失败与 GUI 侧 XPC 失败共用
/// 同一族，可直接作为 XPC 应答 payload 编解码（Codable）。
enum SystemProxyError: Error, Equatable, Sendable, Codable {
  case preferencesUnavailable
  case preferencesBusy
  case noCurrentNetworkSet
  case noNetworkLocations
  case noProxyServices
  case unreadableService(String)
  case invalidStoredConfiguration(String)
  case cannotWriteService(String)
  case commitFailed(String)
  case applyFailed(String)
  case invalidRequest(String)
  case helperUnavailable(String)
}

/// A service identity includes its network location because service IDs can appear in
/// different locations during cleanup-all-locations scans.
struct SystemProxyServiceIdentifier: Equatable, Hashable, Sendable {
  let locationID: String
  let serviceID: String
}

/// One service's complete Proxies dictionary as a pure value.
struct SystemProxyServiceState: Equatable, Sendable {
  let identifier: SystemProxyServiceIdentifier
  /// `nil` means that the service has no Proxies entity configuration.
  let configuration: Data?
  var name: String = ""
}

/// One planned Proxies-entity write. `nil` clears the complete entity.
struct SystemProxyPlannedWrite: Equatable, Sendable {
  let identifier: SystemProxyServiceIdentifier
  let configuration: Data?
}

/// Result of an apply plan. `unchanged` avoids an unnecessary SCPreferences commit.
enum SystemProxyWriteOutcome: Equatable, Sendable, Codable {
  case written
  case unchanged
}

/// Pure configuration planning. Apply rewrites every differing service in the active
/// location, preserving unmodeled Proxies keys. Cleanup is unconditional: the complete
/// Proxies dictionary goes for every service in every scanned location, regardless of
/// which application or account wrote it.
enum SystemProxyPlanner {
  struct ApplyPlan: Equatable, Sendable {
    let writes: [SystemProxyPlannedWrite]

    var outcome: SystemProxyWriteOutcome {
      writes.isEmpty ? .unchanged : .written
    }
  }

  struct ClearPlan: Equatable, Sendable {
    let writes: [SystemProxyPlannedWrite]
  }

  static func makeApplyPlan(
    services: [SystemProxyServiceState], configuration: SystemProxyConfiguration
  ) throws -> ApplyPlan {
    var writes: [SystemProxyPlannedWrite] = []
    for service in services {
      let original = try dictionary(
        from: service.configuration, serviceID: service.identifier.serviceID)
      let projected = SystemProxyPropertyList.applying(configuration, to: original)
      let normalizedOriginal =
        SystemProxyPropertyList.semanticallyNormalized(original) as NSDictionary
      let normalizedDesired =
        SystemProxyPropertyList.semanticallyNormalized(projected) as NSDictionary
      guard !normalizedOriginal.isEqual(normalizedDesired) else { continue }
      let desired = try propertyListData(
        from: projected,
        serviceID: service.identifier.serviceID)
      writes.append(SystemProxyPlannedWrite(identifier: service.identifier, configuration: desired))
    }
    return ApplyPlan(writes: writes)
  }

  /// 无条件清理计划：凡持有 Proxies 实体的服务都整字典移除，不校验来源，
  /// 也不保存或查询端点签名、所有权标记或历史快照。
  static func makeClearPlan(services: [SystemProxyServiceState]) -> ClearPlan {
    let writes =
      services
      .filter { $0.configuration != nil }
      .map { SystemProxyPlannedWrite(identifier: $0.identifier, configuration: nil) }
    return ClearPlan(writes: writes)
  }

  /// Property-list semantic equality; dictionary key order does not matter.
  static func equivalent(_ lhs: Data?, _ rhs: Data?) -> Bool {
    guard let lhs, let rhs else { return lhs == nil && rhs == nil }
    guard
      let left = try? PropertyListSerialization.propertyList(from: lhs, options: [], format: nil)
        as? NSDictionary,
      let right = try? PropertyListSerialization.propertyList(from: rhs, options: [], format: nil)
        as? NSDictionary
    else { return lhs == rhs }
    return left.isEqual(right)
  }

  static func dictionary(from data: Data?, serviceID: String) throws -> [String: Any] {
    guard let data else { return [:] }
    guard
      let propertyList = try? PropertyListSerialization.propertyList(
        from: data, options: [], format: nil),
      let dictionary = propertyList as? [String: Any]
    else { throw SystemProxyError.invalidStoredConfiguration(serviceID) }
    return dictionary
  }

  static func propertyListData(from dictionary: [String: Any], serviceID: String) throws -> Data {
    do {
      return try PropertyListSerialization.data(
        fromPropertyList: dictionary, format: .binary, options: 0)
    } catch {
      throw SystemProxyError.unreadableService(serviceID)
    }
  }
}
