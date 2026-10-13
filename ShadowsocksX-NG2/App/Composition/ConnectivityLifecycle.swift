import AppKit
import Network

/// Held by the composition, independently of workspace windows.
@MainActor
final class ConnectivityLifecycle: NSObject, NSApplicationDelegate {
  let module: ServerConnectivity
  private let monitor = NWPathMonitor()
  private var receivedInitialPath = false
  private var terminating = false

  init(module: ServerConnectivity) {
    self.module = module
    super.init()
    monitor.pathUpdateHandler = { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        if self.receivedInitialPath { self.module.networkChanged() }
        self.receivedInitialPath = true
      }
    }
    monitor.start(queue: DispatchQueue(label: "connectivity.network"))
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !terminating else { return .terminateLater }
    terminating = true
    monitor.cancel()
    Task {
      await module.shutdown()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}

@MainActor
final class ConnectivityApplicationDelegate: NSObject, NSApplicationDelegate {
  var lifecycle: ConnectivityLifecycle?
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    lifecycle?.applicationShouldTerminate(sender) ?? .terminateNow
  }
}
