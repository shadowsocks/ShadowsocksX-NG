import Foundation
import XCTest

@testable import ShadowsocksX_NG2

extension ProxyRuntimeFixture {
  /// 可暂停探测替身：arm 后的下一次探测异步等待测试放行，在启动健康门的
  /// await 窗口内确定性插入交错命令，不占用线程池工作线程。
  final class BlockingProbe: EndpointProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var gate: TestAsyncGate?
    private var started: XCTestExpectation?

    func arm(started: XCTestExpectation) {
      lock.lock()
      defer { lock.unlock() }
      precondition(gate == nil, "上一次 arm 尚未 release")
      gate = TestAsyncGate("runtime fixture release")
      self.started = started
    }

    func release() {
      lock.lock()
      let gate = self.gate
      self.gate = nil
      self.started = nil
      lock.unlock()
      gate?.release()
    }

    func probe(host: String, port: Int, timeout: TimeInterval) async
      -> EndpointHealthProbe.Outcome
    {
      let (gate, started) = armedGate()
      if let gate {
        started?.fulfill()
        _ = await gate.wait()
      }
      return .reachable
    }

    private func armedGate() -> (TestAsyncGate?, XCTestExpectation?) {
      lock.lock()
      let gate = self.gate
      let started = self.started
      lock.unlock()
      return (gate, started)
    }
  }

  /// 按调用序返回预设结果，并可在指定调用处异步等待测试放行。
  final class BlockingFirewallChecker: FirewallStatusChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private let outcomes: [FirewallBlockStatus]
    private let blockOnCall: Int
    private let started: XCTestExpectation
    private let gate = TestAsyncGate("runtime fixture release")

    init(outcomes: [FirewallBlockStatus], blockOnCall: Int, started: XCTestExpectation) {
      precondition(!outcomes.isEmpty)
      self.outcomes = outcomes
      self.blockOnCall = blockOnCall
      self.started = started
    }

    func release() { gate.release() }

    func status(for executableURL: URL) async -> FirewallBlockStatus {
      let call = nextCall()
      if call == blockOnCall {
        started.fulfill()
        _ = await gate.wait()
      }
      return outcomes[min(call, outcomes.count) - 1]
    }

    private func nextCall() -> Int {
      lock.lock()
      callCount += 1
      let call = callCount
      lock.unlock()
      return call
    }
  }
}
