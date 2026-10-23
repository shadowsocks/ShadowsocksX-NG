import Darwin
import XCTest

@testable import ShadowsocksX_NG2

/// 代理运行时测试共享夹具：临时运行时目录、契约文档构造、LaunchAgent
/// 与探测替身。
/// 跨替身共享的有序事件记录：断言「先清理系统代理、再停止监听」等次序。
final class ProxyRuntimeEventLog: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [String] = []

  func record(_ item: String) {
    lock.lock()
    defer { lock.unlock() }
    items.append(item)
  }

  var events: [String] {
    lock.lock()
    defer { lock.unlock() }
    return items
  }
}

extension ProxyRuntimeFixture {
  /// 在临时目录中建一套隔离的运行时文件组（不触碰真实 ~/Library）。
  struct TemporaryRuntime {
    let directory: URL
    let contract: URL
    let pidFile: URL
  }

  static func makeTemporaryRuntime(file: StaticString = #filePath, line: UInt = #line)
    -> TemporaryRuntime
  {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ssxng-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return TemporaryRuntime(
      directory: directory,
      contract: directory.appendingPathComponent("sslocal-active.json"),
      pidFile: directory.appendingPathComponent("agent.pid"))
  }

  @MainActor
  static func catalogSnapshotReader(at fileURL: URL) -> RuntimeCatalogSnapshotReading {
    CatalogCommitCoordinator.bootstrap(fileStore: makeTestCatalogStore(fileURL: fileURL))
      .catalogSnapshotReader
  }

  /// LaunchAgent 注册态可编程替身，记录全部调用。
  final class FakeLaunchAgent: LaunchAgentControlling {
    private(set) var currentStatus: LaunchAgentStatus
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    var registerError: Error?
    /// register 成功后自动迁移到的状态（模拟 launchd 拉起）。
    var statusAfterRegister: LaunchAgentStatus = .registered
    /// 测试用的运行回执。生产 wrapper 对 ACL 实例需等 sslocal 绑定监听后才写。
    var onRegister: (() -> Void)?
    var onUnregister: (() -> Void)?
    /// 可选共享事件日志（次序断言用）。
    weak var eventLog: ProxyRuntimeEventLog?

    init(initialStatus: LaunchAgentStatus = .notRegistered) {
      currentStatus = initialStatus
    }

    var status: LaunchAgentStatus { currentStatus }

    func setStatus(_ status: LaunchAgentStatus) {
      currentStatus = status
    }

    func register() throws {
      registerCount += 1
      eventLog?.record("register")
      if let registerError {
        currentStatus = .registered
        throw registerError
      }
      currentStatus = statusAfterRegister
      onRegister?()
    }

    func unregister() throws {
      unregisterCount += 1
      eventLog?.record("unregister")
      currentStatus = .notRegistered
      onUnregister?()
    }
  }

  /// 探测替身：按预设序列返回，序列耗尽后停留在最后一项。
  final class FakeProbe: EndpointProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var outcomes: [EndpointHealthProbe.Outcome]
    private var requestedPorts: [Int] = []
    private(set) var callCount = 0

    init(outcomes: [EndpointHealthProbe.Outcome]) {
      self.outcomes = outcomes
    }

    static func reachable() -> FakeProbe {
      FakeProbe(outcomes: [.reachable])
    }

    static func refusing() -> FakeProbe {
      FakeProbe(outcomes: [.refused(detail: "Connection refused")])
    }

    /// 运行中改写探测序列（「条件恢复后自动收敛」类测试用）。
    func setOutcomes(_ newOutcomes: [EndpointHealthProbe.Outcome]) {
      lock.lock()
      defer { lock.unlock() }
      outcomes = newOutcomes
    }

    var ports: [Int] {
      lock.lock()
      defer { lock.unlock() }
      return requestedPorts
    }

    func probe(host: String, port: Int, timeout: TimeInterval) async
      -> EndpointHealthProbe.Outcome
    {
      recordProbe(port: port)
    }

    private func recordProbe(port: Int) -> EndpointHealthProbe.Outcome {
      lock.lock()
      defer { lock.unlock() }
      callCount += 1
      requestedPorts.append(port)
      guard let outcome = outcomes.first else { return .timedOut }
      if outcomes.count > 1 {
        outcomes.removeFirst()
      }
      return outcome
    }
  }

  final class FakeFirewallChecker: FirewallStatusChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var outcomes: [FirewallBlockStatus]
    private var recordedURLs: [URL] = []

    var checkedURLs: [URL] {
      lock.lock()
      defer { lock.unlock() }
      return recordedURLs
    }

    init(_ result: FirewallBlockStatus = .permitted) {
      outcomes = [result]
    }

    init(outcomes: [FirewallBlockStatus]) {
      precondition(!outcomes.isEmpty)
      self.outcomes = outcomes
    }

    func status(for executableURL: URL) async -> FirewallBlockStatus {
      recordStatus(for: executableURL)
    }

    private func recordStatus(for executableURL: URL) -> FirewallBlockStatus {
      lock.lock()
      defer { lock.unlock() }
      recordedURLs.append(executableURL)
      let outcome = outcomes[0]
      if outcomes.count > 1 { outcomes.removeFirst() }
      return outcome
    }
  }

}

/// 每个夹具使用独立 defaults 域，最后一个引用释放时清理持久值。
private final class TestProxyUserDefaults: UserDefaults, @unchecked Sendable {
  private let domain: String

  init() {
    domain = "ng2-proxy-control-tests-\(UUID().uuidString)"
    super.init(suiteName: domain)!
  }

  deinit { removePersistentDomain(forName: domain) }
}

func makeTestProxyControlPreferences() -> ProxyControlPreferences {
  ProxyControlPreferences(defaults: TestProxyUserDefaults())
}

final class InMemoryProxyListeningStore: ProxyListeningStoring {
  var saved: ProxyListeningConfiguration?

  func load() throws -> ProxyListeningConfiguration { saved ?? ProxyListeningConfiguration() }

  func save(_ configuration: ProxyListeningConfiguration) throws {
    try configuration.enforcePersistenceConstraints()
    saved = configuration
  }
}

extension ProxyRuntimeFixture {
  static func controlFlowRuleSnapshot(_ source: RulesSource) throws
    -> RuleSnapshot
  {
    switch source {
    case .geolocationCN:
      return rulesFixture(
        source,
        rules: [
          ProxyRule(action: .direct, match: try RuleMatch(domainExact: "direct.example")),
          ProxyRule(
            action: .direct, match: try RuleMatch(domainSuffix: "fixture-direct.example")),
        ])
    case .chinaIPv4:
      return rulesFixture(
        source,
        rules: [
          ProxyRule(action: .direct, match: try RuleMatch(ipv4CIDR: "1.0.0.0/24"))
        ])
    case .gfwlist:
      return rulesFixture(
        source,
        rules: [
          ProxyRule(action: .proxy, match: try RuleMatch(domainSuffix: "proxy.example")),
          ProxyRule(action: .direct, match: try RuleMatch(domainExact: "safe.proxy.example")),
        ])
    case .custom, .fixed:
      throw RuleSnapshotError.missing
    }
  }
}
