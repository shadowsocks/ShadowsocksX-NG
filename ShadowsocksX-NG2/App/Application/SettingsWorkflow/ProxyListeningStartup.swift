import Foundation

/// 正常应用装配之前完成读取或显式重置，失败期间不构造运行时控制器。
@MainActor
enum ProxyListeningStartup {
  static func load(
    store: ProxyListeningFileStore,
    presentReset: (ProxyListeningStoreError) -> Void
  ) -> ProxyListeningConfiguration {
    var failure: ProxyListeningStoreError
    do { return try store.load() } catch { failure = listeningFailure(error) }
    while true {
      presentReset(failure)
      do { return try store.reset() } catch { failure = listeningFailure(error) }
    }
  }

  private static func listeningFailure(_ error: Error) -> ProxyListeningStoreError {
    (error as? ProxyListeningStoreError) ?? .ioFailure(detail: String(describing: error))
  }
}
