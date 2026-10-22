import Combine

/// 只读详情的参数会话：切换身份清空旧值，刷新失败不展示过时参数。
@MainActor
final class ServerDetailParameters: ObservableObject {
  let options = PluginOptionsDraft()
  @Published private(set) var failure: ServerFormLoadError?
  private var serverID: NodeID?

  func showServer(_ id: NodeID, load: (NodeID) throws -> String) {
    serverID = id
    reload(load: load)
  }

  func reload(load: (NodeID) throws -> String) {
    guard let serverID else { return }
    options.load("")
    do {
      options.load(try load(serverID))
      failure = nil
    } catch {
      failure = (error as? ServerFormLoadError) ?? .credentialsUnavailable
    }
  }

  func didRefresh(affectedServers: Set<NodeID>, load: (NodeID) throws -> String) {
    guard let serverID, affectedServers.contains(serverID) else { return }
    reload(load: load)
  }
}
