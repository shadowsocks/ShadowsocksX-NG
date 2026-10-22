import Foundation
import SystemConfiguration

/// root 进程内的 SystemConfiguration 写入器：GUI 域决策的机械
/// 执行者。apply 覆盖活动网络位置的每个服务，只改 typed 字段并保留未建模
/// 键，值已等价时跳过提交；clear 无条件移除全部位置全部服务的完整 Proxies
/// 字典。root 身份直接创建 SCPreferences，不走授权对话框。
enum SystemProxyWriter {
  static func perform(
    _ request: SystemProxyHelperEngine.Request
  ) throws -> SystemProxyHelperEngine.Outcome {
    switch request {
    case .apply(let configuration):
      return .applied(try apply(configuration))
    case .clear:
      try clear()
      return .cleared
    }
  }

  static func apply(_ configuration: SystemProxyConfiguration) throws -> SystemProxyWriteOutcome {
    try withPreferences { preferences in
      try lockPreferencesOrThrow(preferences)
      defer { SCPreferencesUnlock(preferences) }

      let services = try activeServiceSnapshots(in: preferences)
      guard !services.isEmpty else { throw SystemProxyError.noProxyServices }
      let plan = try SystemProxyPlanner.makeApplyPlan(
        services: services.map(\.plannerState), configuration: configuration)

      guard !plan.writes.isEmpty else { return .unchanged }
      let servicesByID = Dictionary(uniqueKeysWithValues: services.map { ($0.identifier, $0) })
      for write in plan.writes {
        guard let service = servicesByID[write.identifier] else {
          throw SystemProxyError.cannotWriteService(write.identifier.serviceID)
        }
        if service.proxyProtocol == nil {
          _ = SCNetworkServiceAddProtocolType(
            service.networkService, kSCNetworkProtocolTypeProxies)
        }
        guard
          let proxyProtocol = service.proxyProtocol
            ?? SCNetworkServiceCopyProtocol(service.networkService, kSCNetworkProtocolTypeProxies),
          setConfiguration(write.configuration, on: proxyProtocol)
        else { throw SystemProxyError.cannotWriteService(write.identifier.serviceID) }
      }
      try commitAndApply(preferences)
      return .written
    }
  }

  static func clear() throws {
    try withPreferences { preferences in
      try lockPreferencesOrThrow(preferences)
      defer { SCPreferencesUnlock(preferences) }

      let services = try allServiceSnapshots(in: preferences)
      let plan = SystemProxyPlanner.makeClearPlan(services: services.map(\.plannerState))
      guard !plan.writes.isEmpty else { return }

      let servicesByID = Dictionary(uniqueKeysWithValues: services.map { ($0.identifier, $0) })
      for write in plan.writes {
        guard let service = servicesByID[write.identifier],
          let proxyProtocol = service.proxyProtocol,
          setConfiguration(nil, on: proxyProtocol)
        else { throw SystemProxyError.cannotWriteService(write.identifier.serviceID) }
      }
      try commitAndApply(preferences)
    }
  }

  // MARK: - SystemConfiguration 读取与写入

  private struct ServiceSnapshot {
    let identifier: SystemProxyServiceIdentifier
    let networkService: SCNetworkService
    let proxyProtocol: SCNetworkProtocol?
    let configuration: Data?

    var plannerState: SystemProxyServiceState {
      SystemProxyServiceState(identifier: identifier, configuration: configuration)
    }
  }

  private static func withPreferences<T>(_ body: (SCPreferences) throws -> T) throws -> T {
    guard
      let preferences = SCPreferencesCreate(
        nil, SystemProxyHelperIdentity.machServiceName as CFString, nil)
    else { throw SystemProxyError.preferencesUnavailable }
    return try body(preferences)
  }

  private static func activeServiceSnapshots(
    in preferences: SCPreferences
  ) throws -> [ServiceSnapshot] {
    guard let set = SCNetworkSetCopyCurrent(preferences) else {
      throw SystemProxyError.noCurrentNetworkSet
    }
    guard let locationID = SCNetworkSetGetSetID(set) as String? else {
      throw SystemProxyError.noCurrentNetworkSet
    }
    return try serviceSnapshots(in: set, locationID: locationID)
  }

  private static func allServiceSnapshots(
    in preferences: SCPreferences
  ) throws -> [ServiceSnapshot] {
    guard let sets = SCNetworkSetCopyAll(preferences) as? [SCNetworkSet], !sets.isEmpty else {
      throw SystemProxyError.noNetworkLocations
    }
    return try sets.flatMap { set -> [ServiceSnapshot] in
      guard let locationID = SCNetworkSetGetSetID(set) as String? else {
        return [ServiceSnapshot]()
      }
      return try serviceSnapshots(in: set, locationID: locationID)
    }
  }

  private static func serviceSnapshots(
    in set: SCNetworkSet, locationID: String
  ) throws -> [ServiceSnapshot] {
    guard let services = SCNetworkSetCopyServices(set) as? [SCNetworkService] else {
      return []
    }
    return try services.compactMap { service in
      guard let serviceID = SCNetworkServiceGetServiceID(service) as String? else { return nil }
      let proxyProtocol = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeProxies)
      let configurationValue: CFPropertyList?
      if let proxyProtocol {
        configurationValue = SCNetworkProtocolGetConfiguration(proxyProtocol)
      } else {
        configurationValue = nil
      }
      return ServiceSnapshot(
        identifier: SystemProxyServiceIdentifier(
          locationID: locationID, serviceID: serviceID),
        networkService: service,
        proxyProtocol: proxyProtocol,
        configuration: try propertyListData(from: configurationValue, serviceID: serviceID))
    }
  }

  private static func propertyListData(
    from value: CFPropertyList?, serviceID: String
  ) throws -> Data? {
    guard let value else { return nil }
    guard let dictionary = value as? [String: Any] else {
      throw SystemProxyError.unreadableService(serviceID)
    }
    return try SystemProxyPlanner.propertyListData(from: dictionary, serviceID: serviceID)
  }

  private static func setConfiguration(_ data: Data?, on proxyProtocol: SCNetworkProtocol) -> Bool {
    guard let data else { return SCNetworkProtocolSetConfiguration(proxyProtocol, nil) }
    guard
      let propertyList = try? PropertyListSerialization.propertyList(
        from: data, options: [], format: nil),
      let dictionary = propertyList as? [String: Any]
    else { return false }
    return SCNetworkProtocolSetConfiguration(proxyProtocol, dictionary as CFDictionary)
  }

  private static func commitAndApply(_ preferences: SCPreferences) throws {
    guard SCPreferencesCommitChanges(preferences) else {
      throw SystemProxyError.commitFailed(systemConfigurationError())
    }
    guard SCPreferencesApplyChanges(preferences) else {
      throw SystemProxyError.applyFailed(systemConfigurationError())
    }
  }

  private static func systemConfigurationError() -> String {
    String(cString: SCErrorString(SCError()))
  }
}

private func lockPreferencesOrThrow(_ preferences: SCPreferences) throws {
  guard SCPreferencesLock(preferences, true) else {
    throw SystemProxyError.preferencesBusy
  }
}
