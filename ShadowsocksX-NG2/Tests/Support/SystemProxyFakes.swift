@testable import ShadowsocksX_NG2

/// 系统代理相关替身：从 ProxyRuntimeFixture 主文件分出，
/// 保持 `ProxyRuntimeFixture.` 限定名不变。
extension ProxyRuntimeFixture {
  @MainActor
  final class FakeSystemProxy: SystemProxyControlling {
    private(set) var applied: [SystemProxyConfiguration] = []
    private(set) var clearCount = 0
    var services: [SystemProxyServiceState] = [
      SystemProxyServiceState(
        identifier: SystemProxyServiceIdentifier(locationID: "home", serviceID: "wifi"),
        configuration: nil, name: "Wi-Fi")
    ]
    var readError: Error?
    var beforeRead: (@MainActor () async -> Void)?
    private(set) var readCount = 0
    private(set) var repairedServices: [SystemProxyServiceIdentifier] = []
    var beforeRepair: (@MainActor () async -> Void)?
    var preserveConfigurationOnApply = false
    var applyError: Error?
    var clearError: Error?
    var onClear: (@MainActor () -> Void)?
    /// 注入返回值：模拟系统值已与期望等价的免授权跳过路径。
    var applyOutcome: SystemProxyWriteOutcome = .written
    /// 可选共享事件日志（次序断言用）。
    weak var eventLog: ProxyRuntimeEventLog?

    func apply(
      _ configuration: SystemProxyConfiguration
    ) async throws -> SystemProxyWriteOutcome {
      eventLog?.record("apply")
      if let applyError { throw applyError }
      applied.append(configuration)
      if !preserveConfigurationOnApply {
        let plan = try SystemProxyPlanner.makeApplyPlan(
          services: services, configuration: configuration)
        for write in plan.writes {
          if let index = services.firstIndex(where: { $0.identifier == write.identifier }) {
            services[index] = SystemProxyServiceState(
              identifier: write.identifier, configuration: write.configuration,
              name: services[index].name)
          }
        }
      }
      return applyOutcome
    }

    func readServices() async throws -> [SystemProxyServiceState] {
      readCount += 1
      if let readError { throw readError }
      let snapshot = services
      await beforeRead?()
      return snapshot
    }

    func repair(_ configuration: SystemProxyConfiguration) async throws {
      await beforeRepair?()
      let plan = try SystemProxyPlanner.makeApplyPlan(
        services: services, configuration: configuration)
      repairedServices = plan.writes.map(\.identifier)
      _ = try await apply(configuration)
    }

    func clear() async throws {
      clearCount += 1
      eventLog?.record("clear")
      onClear?()
      if let clearError { throw clearError }
      services = services.map {
        SystemProxyServiceState(identifier: $0.identifier, configuration: nil, name: $0.name)
      }
    }
  }

  /// 特权 helper 注册/审批状态可编程替身。
  @MainActor
  final class FakeSystemProxyHelperService: SystemProxyHelperServicing {
    private(set) var currentStatus: SystemProxyHelperStatus
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var registerError: Error?
    private(set) var unregisterError: Error?
    private(set) var openApprovalPathCount = 0
    /// register 成功后迁移到的状态（模拟 BTM 批准立即达成）。
    var statusAfterRegister: SystemProxyHelperStatus = .approved

    init(initialStatus: SystemProxyHelperStatus = .approved) {
      currentStatus = initialStatus
    }

    var status: SystemProxyHelperStatus { currentStatus }

    func setStatus(_ status: SystemProxyHelperStatus) {
      currentStatus = status
    }

    func setRegisterError(_ error: Error?) {
      registerError = error
    }

    func setUnregisterError(_ error: Error?) {
      unregisterError = error
    }

    func register() throws {
      registerCount += 1
      if let registerError { throw registerError }
      currentStatus = statusAfterRegister
    }

    func unregister() throws {
      unregisterCount += 1
      if let unregisterError { throw unregisterError }
      currentStatus = .notRegistered
    }

    func openApprovalPath() {
      openApprovalPathCount += 1
    }
  }

  @MainActor
  final class FakeSystemProxyNetworkChangeMonitor: SystemProxyNetworkChangeMonitoring {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var isObserving = false
    private var handler: (@MainActor @Sendable (SystemProxyNetworkChange) -> Void)?

    func start(
      handler: @escaping @MainActor @Sendable (SystemProxyNetworkChange) -> Void
    ) {
      startCount += 1
      isObserving = true
      self.handler = handler
    }

    func stop() {
      stopCount += 1
      isObserving = false
      handler = nil
    }

    func emit(_ change: SystemProxyNetworkChange) {
      handler?(change)
    }
  }
}
