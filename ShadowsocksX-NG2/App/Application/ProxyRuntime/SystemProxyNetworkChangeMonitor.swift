import Foundation
import Network
import SystemConfiguration

struct SystemProxyNetworkChange: OptionSet, Sendable {
  let rawValue: Int

  static let networkConfiguration = SystemProxyNetworkChange(rawValue: 1 << 0)
  static let proxyConfiguration = SystemProxyNetworkChange(rawValue: 1 << 1)
  static let networkPath = SystemProxyNetworkChange(rawValue: 1 << 2)
}

@MainActor
protocol SystemProxyNetworkChangeMonitoring: AnyObject {
  func start(
    handler: @escaping @MainActor @Sendable (SystemProxyNetworkChange) -> Void)
  func stop()
}

@MainActor
final class NoopSystemProxyNetworkChangeMonitor: SystemProxyNetworkChangeMonitoring {
  func start(handler: @escaping @MainActor @Sendable (SystemProxyNetworkChange) -> Void) {}
  func stop() {}
}

/// Observes network-location/service setup changes, proxy dictionary changes, and
/// app-visible path changes. Consumers decide which classes matter for each intent.
@MainActor
final class SystemProxyNetworkChangeMonitor: SystemProxyNetworkChangeMonitoring {
  private let callbackBox = SystemProxyNetworkChangeCallbackBox()
  private var dynamicStore: SCDynamicStore?
  private var pathMonitor: NWPathMonitor?

  func start(
    handler: @escaping @MainActor @Sendable (SystemProxyNetworkChange) -> Void
  ) {
    stop()
    callbackBox.setHandler(handler)
    startDynamicStoreObserver()

    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { [weak callbackBox] _ in
      callbackBox?.emit(.networkPath)
    }
    monitor.start(queue: DispatchQueue.global(qos: .utility))
    pathMonitor = monitor
  }

  func stop() {
    callbackBox.setHandler(nil)
    if let dynamicStore {
      SCDynamicStoreSetDispatchQueue(dynamicStore, nil)
      self.dynamicStore = nil
    }
    pathMonitor?.cancel()
    pathMonitor = nil
  }

  private func startDynamicStoreObserver() {
    var context = SCDynamicStoreContext(
      version: 0,
      info: Unmanaged.passUnretained(callbackBox).toOpaque(),
      retain: nil,
      release: nil,
      copyDescription: nil)
    guard
      let store = SCDynamicStoreCreate(
        kCFAllocatorDefault, "ShadowsocksX-NG2.SystemProxy" as CFString,
        systemProxyDynamicStoreCallback, &context)
    else { return }

    let locationKey = SCDynamicStoreKeyCreateLocation(kCFAllocatorDefault)
    let proxiesKey = SCDynamicStoreKeyCreateProxies(kCFAllocatorDefault)
    let keys = [locationKey, proxiesKey].compactMap { $0 } as CFArray
    // Setup changes include service membership/interface configuration and each
    // service's Proxies dictionary. Runtime global proxy notifications are explicit.
    let patterns = ["Setup:/Network/.*"] as CFArray
    guard SCDynamicStoreSetNotificationKeys(store, keys, patterns) else { return }
    guard SCDynamicStoreSetDispatchQueue(store, DispatchQueue.main) else { return }
    dynamicStore = store
  }
}

private final class SystemProxyNetworkChangeCallbackBox: @unchecked Sendable {
  private let lock = NSLock()
  private var handler: (@MainActor @Sendable (SystemProxyNetworkChange) -> Void)?

  func setHandler(
    _ handler: (@MainActor @Sendable (SystemProxyNetworkChange) -> Void)?
  ) {
    lock.withLock { self.handler = handler }
  }

  func emit(_ change: SystemProxyNetworkChange) {
    let currentHandler = lock.withLock { handler }
    guard let currentHandler else { return }
    Task { @MainActor in currentHandler(change) }
  }
}

private let systemProxyDynamicStoreCallback: SCDynamicStoreCallBack = { _, changedKeys, info in
  guard let info else { return }
  let callbackBox = Unmanaged<SystemProxyNetworkChangeCallbackBox>.fromOpaque(info)
    .takeUnretainedValue()
  let keys = changedKeys as? [String] ?? []
  var changes: SystemProxyNetworkChange = []
  for key in keys {
    if key.hasSuffix("/Proxies") || key == "State:/Network/Global/Proxies" {
      changes.insert(.proxyConfiguration)
    } else {
      changes.insert(.networkConfiguration)
    }
  }
  if !changes.isEmpty { callbackBox.emit(changes) }
}
