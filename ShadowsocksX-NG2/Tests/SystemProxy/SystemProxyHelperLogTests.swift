import Foundation
import Testing

@testable import ShadowsocksX_NG2

/// 特权 helper 事件的统一日志路由与发射缝测试（ADR-0047）：route 是纯
/// 函数，断言 level/category/公开文本与 privacy 拆分；engine 与 listener
/// 经注入替身断言发射调用。测试不写真实系统日志 store（scheme 注入
/// SSXNG_SYSTEM_LOG=0），也不触真实 SystemConfiguration。
@Suite struct SystemProxyHelperLogTests {
  private let configuration = SystemProxyConfiguration(
    socks: .init(host: "127.0.0.1", port: 1086),
    http: .init(host: "127.0.0.1", port: 1087),
    https: .init(host: "127.0.0.1", port: 1087),
    exceptions: ["localhost"])

  /// 并发闭包与断言之间的线程安全事件交接。
  private final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [SystemProxyHelperLogEvent] = []

    func append(_ event: SystemProxyHelperLogEvent) {
      lock.lock()
      events.append(event)
      lock.unlock()
    }

    var all: [SystemProxyHelperLogEvent] {
      lock.lock()
      defer { lock.unlock() }
      return events
    }
  }

  // MARK: - route（纯函数）

  @Test func lifecycleEventsRouteToSystemProxyCategory() {
    let ready = SystemProxyHelperLogEvent.listenerReady.logRoute
    #expect(ready.level == .default)
    #expect(ready.category == "system-proxy")
    #expect(ready.text == "system proxy helper listening")
    #expect(ready.privateDetail == nil)

    let accepted = SystemProxyHelperLogEvent.connectionAccepted(pid: 42).logRoute
    #expect(accepted.level == .default)
    #expect(accepted.text == "system proxy helper connection accepted (pid=42)")
    #expect(accepted.privateDetail == nil)

    let rejected = SystemProxyHelperLogEvent.connectionRejected(pid: 7).logRoute
    #expect(rejected.level == .error)
    #expect(rejected.text == "system proxy helper connection rejected (pid=7)")
    #expect(rejected.privateDetail == nil)
  }

  @Test func requestResultsRouteAsMilestones() {
    let written = SystemProxyHelperLogEvent.applyCompleted(.written).logRoute
    #expect(written.level == .default)
    #expect(written.text == "system proxy helper apply completed (outcome=written)")

    let unchanged = SystemProxyHelperLogEvent.applyCompleted(.unchanged).logRoute
    #expect(unchanged.level == .default)
    #expect(unchanged.text == "system proxy helper apply completed (outcome=unchanged)")

    let cleared = SystemProxyHelperLogEvent.clearCompleted.logRoute
    #expect(cleared.level == .default)
    #expect(cleared.text == "system proxy helper clear completed")
  }

  @Test func requestFailureKeepsFreeDetailPrivate() {
    let event = SystemProxyHelperLogEvent.requestFailed(
      .commitFailed("SCPreferencesCommitChanges: busy"))
    let route = event.logRoute
    #expect(route.level == .error)
    #expect(route.category == "system-proxy")
    #expect(route.text == "system proxy helper request failed: commit failed: ")
    #expect(route.privateDetail == "SCPreferencesCommitChanges: busy")
    #expect(route.text + route.privateDetail! == event.description, "text+detail == description")
  }

  @Test func requestFailureWithoutDetailHasNoPrivateSegment() {
    let event = SystemProxyHelperLogEvent.requestFailed(.preferencesBusy)
    #expect(event.logRoute.text == "system proxy helper request failed: preferences busy")
    #expect(event.logRoute.privateDetail == nil)
    #expect(event.description == "system proxy helper request failed: preferences busy")
  }

  @Test func errorCasesSplitDetailFromPublicText() {
    #expect(SystemProxyError.unreadableService("svc-1").logParts.text == "unreadable service")
    #expect(SystemProxyError.unreadableService("svc-1").logParts.detail == "svc-1")
    #expect(SystemProxyError.invalidRequest("bad json").logParts.detail == "bad json")
    #expect(SystemProxyError.helperUnavailable("timeout").logParts.detail == "timeout")
    #expect(SystemProxyError.preferencesUnavailable.logParts.detail == nil)
    #expect(SystemProxyError.noProxyServices.logParts.detail == nil)
    #expect(SystemProxyError.noCurrentNetworkSet.logParts.detail == nil)
    #expect(SystemProxyError.noNetworkLocations.logParts.detail == nil)
    #expect(SystemProxyError.invalidStoredConfiguration("svc-2").logParts.detail == "svc-2")
    #expect(SystemProxyError.cannotWriteService("svc-3").logParts.detail == "svc-3")
    #expect(SystemProxyError.applyFailed("SCError").logParts.detail == "SCError")
  }

  @Test func eventsDeriveFromTypedResponses() {
    #expect(SystemProxyHelperLogEvent(response: .applied(.written)) == .applyCompleted(.written))
    #expect(SystemProxyHelperLogEvent(response: .cleared) == .clearCompleted)
    #expect(
      SystemProxyHelperLogEvent(response: .failure(.noProxyServices))
        == .requestFailed(.noProxyServices))
  }

  // MARK: - 发射缝（engine 注入替身）

  @Test func engineEmitsTypedApplyResult() async throws {
    let recorder = EventRecorder()
    let engine = SystemProxyHelperEngine(perform: { _ in .applied(.written) }, log: recorder.append)
    let payload = try SystemProxyHelperWire.encodeConfiguration(configuration)
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      engine.apply(payload) { _ in continuation.resume() }
    }
    #expect(recorder.all == [.applyCompleted(.written)])
  }

  @Test func engineEmitsClearResult() async {
    let recorder = EventRecorder()
    let engine = SystemProxyHelperEngine(perform: { _ in .cleared }, log: recorder.append)
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      engine.clear { _ in continuation.resume() }
    }
    #expect(recorder.all == [.clearCompleted])
  }

  @Test func engineEmitsFailureForUndecodablePayload() async {
    let recorder = EventRecorder()
    let engine = SystemProxyHelperEngine(perform: { _ in .cleared }, log: recorder.append)
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      engine.apply(Data("not json".utf8)) { _ in continuation.resume() }
    }
    guard case .requestFailed(let error) = recorder.all.first else {
      Issue.record("无效 payload 应发射 requestFailed，实际 \(recorder.all)")
      return
    }
    #expect(error.logParts.text == "invalid request")
    #expect(error.logParts.detail != nil)
  }

  // MARK: - 发射缝（listener 注入替身，真实匿名 XPC）

  @Test func listenerEmitsAcceptedConnectionBeforeRequestResult() async throws {
    let recorder = EventRecorder()
    let engine = SystemProxyHelperEngine(perform: { _ in .cleared }, log: recorder.append)
    let delegate = SystemProxyHelperListenerDelegate(
      engine: engine,
      expectedClientIdentifier: try #require(ProcessSigningIdentifier.current()),
      log: recorder.append)
    let listener = NSXPCListener.anonymous()
    listener.delegate = delegate
    listener.resume()
    defer { listener.invalidate() }

    let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
    connection.remoteObjectInterface = NSXPCInterface(with: SystemProxyHelperControlling.self)
    connection.resume()
    defer { connection.invalidate() }

    let proxy = try #require(
      connection.remoteObjectProxyWithErrorHandler { _ in } as? SystemProxyHelperControlling)
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      proxy.clear { _ in continuation.resume() }
    }
    #expect(recorder.all == [.connectionAccepted(pid: getpid()), .clearCompleted])
  }

  @Test func listenerEmitsRejectedConnection() async {
    let recorder = EventRecorder()
    let engine = SystemProxyHelperEngine(perform: { _ in .cleared }, log: recorder.append)
    let delegate = SystemProxyHelperListenerDelegate(
      engine: engine,
      expectedClientIdentifier: "com.example.not-the-client",
      log: recorder.append)
    let listener = NSXPCListener.anonymous()
    listener.delegate = delegate
    listener.resume()
    defer { listener.invalidate() }

    let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
    connection.remoteObjectInterface = NSXPCInterface(with: SystemProxyHelperControlling.self)
    // XPC 惰性连接：发一条消息才触发服务端签名校验；被拒绝的连接以失效
    // （或代理错误回调）告终。超时兜底避免挂死，超时后事件断言自然失败。
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let once = ResumeOnce(continuation)
      connection.invalidationHandler = { once.resume() }
      connection.resume()
      let proxy = connection.remoteObjectProxyWithErrorHandler { _ in once.resume() }
      (proxy as? SystemProxyHelperControlling)?.clear { _ in }
      DispatchQueue.global().asyncAfter(deadline: .now() + 10) { once.resume() }
    }
    connection.invalidate()
    #expect(recorder.all == [.connectionRejected(pid: getpid())])
  }
}

/// 只恢复一次的 continuation 装箱：失效回调与超时兜底竞争同一恢复权。
private final class ResumeOnce: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Never>?

  init(_ continuation: CheckedContinuation<Void, Never>) {
    self.continuation = continuation
  }

  func resume() {
    lock.lock()
    let taken = continuation
    continuation = nil
    lock.unlock()
    taken?.resume()
  }
}
