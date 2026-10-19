import Combine
import Foundation
import XCTest

@testable import ShadowsocksX_NG2

/// 轮询等待异步投影落定（设置工作流测试共享）。
@MainActor
func waitUntil(
  _ condition: @autoclosure () -> Bool,
  timeout: TimeInterval = 2,
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  let deadline = Date().addingTimeInterval(timeout)
  while !condition() && Date() < deadline {
    try? await Task.sleep(nanoseconds: 10_000_000)
  }
  XCTAssertTrue(condition(), file: file, line: line)
}

/// 等待工作流发布探测结果；发布前订阅，避免依赖轮询与线程调度耗时。
/// 调用方用测试框架的 timeLimit 保护永不发布的回归。
@MainActor
func waitForPortEditorOccupancy(
  _ workflow: SettingsWorkflow, draft: SettingsPortDraft, port: SettingsPortID
) async {
  let (events, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
  let observation = workflow.objectWillChange.sink { continuation.yield(()) }
  defer {
    observation.cancel()
    continuation.finish()
  }
  continuation.yield(())
  for await _ in events
  where workflow.portFieldState(for: port, editorDraft: draft).occupancy != nil {
    return
  }
}

/// 设置工作流测试的写入缝替身：记录提交调用，可注入失败；
/// 不触碰真实偏好文件、钥匙串或运行时。
@MainActor
final class FakeSettingsCommitter: SettingsCommitting {
  var committedSettings: ProxyRuntimeSettings = ProxyRuntimeSettings()
  var runtimeListenFacts: RuntimeListenFacts?
  var runtimeListenerProcessID: Int32?
  var updateError: Error?
  var updateGate: AsyncGate?
  private(set) var updateCalls: [ProxyRuntimeSettings] = []

  var isProxyRunning: Bool {
    get { runtimeListenFacts != nil }
    set {
      runtimeListenFacts = newValue ? RuntimeListenFacts(listen: committedSettings.listen) : nil
    }
  }

  func updateListening(_ proposed: ProxyListeningConfiguration) async throws {
    if let updateError { throw updateError }
    try proposed.enforcePersistenceConstraints()
    if let updateGate { await updateGate.wait() }
    committedSettings.listen = proposed
    updateCalls.append(committedSettings)
  }

  func updateProxyExceptions(_ value: String) async {
    if let updateGate { await updateGate.wait() }
    committedSettings.proxyExceptions = value
    updateCalls.append(committedSettings)
  }

  func updateListenerMode(_ mode: ListenerMode) async throws {
    var proposed = committedSettings.listen
    proposed.listenerMode = mode
    try await updateListening(proposed)
  }

}

/// 可重复使用的异步门闩，用于证明 workflow 在提交等待期间拒绝第二次命令。
final class AsyncGate: @unchecked Sendable {
  private let lock = NSLock()
  private var released = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    await withCheckedContinuation { continuation in
      lock.lock()
      if released {
        lock.unlock()
        continuation.resume()
      } else {
        waiters.append(continuation)
        lock.unlock()
      }
    }
  }

  func release() {
    lock.lock()
    released = true
    let waiters = self.waiters
    self.waiters.removeAll()
    lock.unlock()
    waiters.forEach { $0.resume() }
  }
}

/// 占用探测替身：按端口预设占用/不可判定，记录全部探测请求。
final class FakeOccupancyProbe: PortOccupancyProbing, @unchecked Sendable {
  private let lock = NSLock()
  private let occupiedPorts: Set<Int>
  private let unknownPorts: Set<Int>
  private let occupierName: String
  private let occupierIPv4ProcessIDs: Set<Int32>
  private let occupierIPv6ProcessIDs: Set<Int32>
  private let explicitOccupiedFamilies: Set<PortOccupancyAddressFamily>?
  private let unverifiedFamilyDetail: String?
  private var requestedPorts: [Int] = []
  private var requestedRequests: [PortOccupancyProbeRequest] = []
  private var answerOverride: PortOccupancy?

  init(
    occupiedPorts: Set<Int> = [], unknownPorts: Set<Int> = [], occupierName: String = "other-app",
    occupierProcessIDs: Set<Int32> = [], occupierIPv6ProcessIDs: Set<Int32> = [],
    occupiedFamilies: Set<PortOccupancyAddressFamily>? = nil,
    unverifiedFamilyDetail: String? = nil
  ) {
    self.occupiedPorts = occupiedPorts
    self.unknownPorts = unknownPorts
    self.occupierName = occupierName
    occupierIPv4ProcessIDs = occupierProcessIDs
    self.occupierIPv6ProcessIDs = occupierIPv6ProcessIDs
    explicitOccupiedFamilies = occupiedFamilies
    self.unverifiedFamilyDetail = unverifiedFamilyDetail
  }

  var requested: [Int] {
    lock.lock()
    defer { lock.unlock() }
    return requestedPorts
  }

  var callCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return requestedPorts.count
  }

  var requests: [PortOccupancyProbeRequest] {
    lock.lock()
    defer { lock.unlock() }
    return requestedRequests
  }

  /// 覆盖全部端口的应答（占用代际测试用）。
  func setAnswer(_ answer: PortOccupancy?) {
    lock.lock()
    defer { lock.unlock() }
    answerOverride = answer
  }

  func occupancy(for request: PortOccupancyProbeRequest) -> PortOccupancy {
    lock.lock()
    defer { lock.unlock() }
    requestedPorts.append(request.port)
    requestedRequests.append(request)
    if let answerOverride { return answerOverride }
    if unknownPorts.contains(request.port) {
      return .unknown(detail: "无法判定")
    }
    return occupiedPorts.contains(request.port)
      ? .occupied(
        PortOccupancyFacts(
          occupier: occupierName, ipv4ProcessIDs: occupierIPv4ProcessIDs,
          ipv6ProcessIDs: occupierIPv6ProcessIDs,
          occupiedFamilies: explicitOccupiedFamilies
            ?? occupiedFamilies(for: request.listenerMode),
          verifiedFamilies: Set(PortOccupancyAddressFamily.allCases),
          unverifiedFamilyDetail: unverifiedFamilyDetail)) : .free
  }

  private func occupiedFamilies(for mode: ListenerMode) -> Set<PortOccupancyAddressFamily> {
    switch mode {
    case .disabled, .allIPv4Interfaces:
      [.ipv4]
    case .allIPv4AndIPv6Interfaces:
      [.ipv4, .ipv6]
    case .allIPv6Interfaces:
      [.ipv6]
    }
  }
}

/// 分阶段占用探测替身（占用代际测试用）：门闩阶段的调用先记下自己的应答再
/// 被扣住，`passThrough` 之后的调用立即返回新应答。用于把「旧一轮」结果钉在
/// 新一轮之后落盘，验证过期结果不得覆盖。
final class GatedOccupancyProbe: PortOccupancyProbing, @unchecked Sendable {
  private let lock = NSLock()
  private let gate = TestBlockingGate("occupancy probe release")
  private var isGated = true
  private var enteredCount = 0
  private let entry = XCTestExpectation(description: "occupancy probe entered")
  private var gatedAnswer: PortOccupancy
  private var passThroughAnswer: PortOccupancy

  init(gatedAnswer: PortOccupancy, passThroughAnswer: PortOccupancy) {
    self.gatedAnswer = gatedAnswer
    self.passThroughAnswer = passThroughAnswer
  }

  /// 已进入探测的调用数（按端口标识序，socks 先于 http）。
  var entered: Int {
    lock.lock()
    defer { lock.unlock() }
    return enteredCount
  }

  func waitUntilEntered() async throws {
    try await requireTestPhase([entry])
  }

  /// 之后的调用立即返回 `answer`；已进入且被扣住的调用仍持有各自应答。
  func passThrough(_ answer: PortOccupancy) {
    lock.lock()
    defer { lock.unlock() }
    isGated = false
    passThroughAnswer = answer
  }

  /// 放行全部被扣住的调用（广播门闩）。
  func releaseGatedCalls() {
    lock.lock()
    isGated = false
    lock.unlock()
    gate.release()
  }

  func occupancy(for request: PortOccupancyProbeRequest) -> PortOccupancy {
    lock.lock()
    enteredCount += 1
    let firstEntry = enteredCount == 1
    let gated = isGated
    let answer = gated ? gatedAnswer : passThroughAnswer
    lock.unlock()
    if firstEntry { entry.fulfill() }
    if gated, !gate.wait() {
      return .unknown(detail: "Test fixture release timed out")
    }
    return answer
  }
}
