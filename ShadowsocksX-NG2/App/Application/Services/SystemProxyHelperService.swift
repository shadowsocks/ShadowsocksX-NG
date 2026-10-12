import CryptoKit
import Foundation
import ServiceManagement
import SystemConfiguration

/// 系统代理写入缝：异步 typed apply 与无条件 clear 的边界，
/// 形状为 XPC 就绪。GUI 域决策（意图、门禁、值、清理时机）全部在调用方；
/// 本缝只执行。生产实现经特权 helper，测试注入 fake。
@MainActor
protocol SystemProxyControlling {
  @discardableResult
  func apply(_ configuration: SystemProxyConfiguration) async throws -> SystemProxyWriteOutcome
  func clear() async throws
  func readServices() async throws -> [SystemProxyServiceState]
  func repair(_ configuration: SystemProxyConfiguration) async throws
}

/// helper 注册/审批状态缝：注册走 SMAppService.daemon；审批缺失
/// 时 GUI 据此呈现登录项批准路径，不提供直接授权回退。unregister 供注册清单
/// 漂移后的定义刷新使用。单测以 fake 替换（真实注册会改动系统登录项状态）。
@MainActor
protocol SystemProxyHelperServicing {
  var status: SystemProxyHelperStatus { get }
  func register() throws
  func unregister() throws
  func openApprovalPath()
}

enum SystemProxyHelperStatus: Equatable, Sendable {
  case notRegistered
  case requiresApproval
  case approved
}

/// 生产实现：SMAppService.daemon 注册 bundle 内
/// Contents/Library/LaunchDaemons/ 下的 LaunchDaemon 清单。
struct SMAppServiceSystemProxyHelper: SystemProxyHelperServicing {
  private let service = SMAppService.daemon(plistName: SystemProxyHelperIdentity.plistName)

  var status: SystemProxyHelperStatus {
    switch service.status {
    case .requiresApproval:
      return .requiresApproval
    case .enabled:
      return .approved
    case .notRegistered, .notFound:
      return .notRegistered
    @unknown default:
      return .notRegistered
    }
  }

  func register() throws {
    try service.register()
  }

  func unregister() throws {
    try service.unregister()
  }

  func openApprovalPath() {
    SMAppService.openSystemSettingsLoginItems()
  }
}

/// 注册清单漂移指纹：launchd 对 SMAppService 提交的 job
/// 沿用注册时的定义快照，app 更新改动 LaunchDaemon 清单不会自动生效（旧定义
/// spawn 失败时 launchd 以 EX_CONFIG 节流循环）。以清单内容 SHA-256 检测漂移，
/// 漂移才注销重注；审批与 bundle 签名绑定，重注不重新弹授权。
enum SystemProxyHelperRegistrationStamp {
  static let defaultsKey = "systemProxyHelperRegistrationStamp"

  /// 清单不可读时不判漂移（无基准；未注册场景由注册路径自身兜底）。
  static func drifted(plistData: Data?, storedStamp: String?) -> Bool {
    guard let plistData else { return false }
    return stamp(plistData) != storedStamp
  }

  static func stamp(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

/// 经特权 helper 的系统代理写入器：每个请求一条按需连接，
/// MachService 连接触发 launchd 激活已注册的 LaunchDaemon。应答在
/// helper 不可达、连接失效、报错或超时时以 typed 错误呈现。
@MainActor
final class XPCSystemProxyController: SystemProxyControlling {
  private let requestTimeoutNanoseconds: UInt64

  init(requestTimeoutNanoseconds: UInt64 = 10_000_000_000) {
    self.requestTimeoutNanoseconds = requestTimeoutNanoseconds
  }

  func apply(_ configuration: SystemProxyConfiguration) async throws -> SystemProxyWriteOutcome {
    let payload = try SystemProxyHelperWire.encodeConfiguration(configuration)
    let response = try await send { proxy, reply in proxy.apply(payload, withReply: reply) }
    switch response {
    case .applied(let outcome):
      return outcome
    case .failure(let error):
      throw error
    case .cleared:
      throw SystemProxyError.helperUnavailable("apply 收到 clear 应答")
    }
  }

  func clear() async throws {
    let response = try await send { proxy, reply in proxy.clear(withReply: reply) }
    switch response {
    case .cleared:
      return
    case .failure(let error):
      throw error
    case .applied:
      throw SystemProxyError.helperUnavailable("clear 收到 apply 应答")
    }
  }

  /// GUI-side read only; no helper registration or privileged writes.
  func readServices() async throws -> [SystemProxyServiceState] {
    try await Task.detached(priority: .utility) {
      guard let preferences = SCPreferencesCreate(nil, "ShadowsocksX-NG2.Observe" as CFString, nil)
      else { throw SystemProxyError.preferencesUnavailable }
      guard let set = SCNetworkSetCopyCurrent(preferences),
        let locationID = SCNetworkSetGetSetID(set) as String?
      else { throw SystemProxyError.noCurrentNetworkSet }
      let services = SCNetworkSetCopyServices(set) as? [SCNetworkService] ?? []
      guard !services.isEmpty else { throw SystemProxyError.noProxyServices }
      return try services.map { service in
        guard let serviceID = SCNetworkServiceGetServiceID(service) as String?
        else { throw SystemProxyError.unreadableService("unknown") }
        let proxyProtocol = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeProxies)
        let value = proxyProtocol.flatMap { SCNetworkProtocolGetConfiguration($0) }
        let data: Data?
        if let value {
          guard let dictionary = value as? [String: Any]
          else { throw SystemProxyError.unreadableService(serviceID) }
          data = try SystemProxyPlanner.propertyListData(from: dictionary, serviceID: serviceID)
        } else {
          data = nil
        }
        return SystemProxyServiceState(
          identifier: SystemProxyServiceIdentifier(locationID: locationID, serviceID: serviceID),
          configuration: data, name: SCNetworkServiceGetName(service) as String? ?? serviceID)
      }
    }.value
  }

  func repair(_ configuration: SystemProxyConfiguration) async throws {
    // The helper rereads the current location under its preferences lock and plans
    // only differing services, preserving fields outside the managed projection.
    _ = try await apply(configuration)
  }

  // MARK: - XPC 请求

  private func send(
    _ call:
      @escaping @Sendable (
        _ proxy: SystemProxyHelperControlling, _ reply: @escaping @Sendable (Data) -> Void
      ) -> Void
  ) async throws -> SystemProxyHelperResponse {
    let gate = SystemProxyReplyGate()
    // 系统域 LaunchDaemon 的 MachService 注册在系统 launchd 命名空间；不带
    // .privileged 的连接只在 per-user 域查找，永远失败。
    let connection = NSXPCConnection(
      machServiceName: SystemProxyHelperIdentity.machServiceName, options: .privileged)
    defer { connection.invalidate() }
    connection.remoteObjectInterface = NSXPCInterface(with: SystemProxyHelperControlling.self)
    // 回调闭包必须显式 @Sendable（nonisolated）：它们在 @MainActor 方法里形成，
    // 传给非 @Sendable 的 Foundation 参数会被推断为主 actor 隔离，而 Foundation
    // 在 XPC 内部队列上调起它们，Swift 6 动态隔离检查会让跨线程调用直接 trap。
    // 闭包只捕获 Sendable 闸门，无需回主 actor。
    connection.invalidationHandler = { @Sendable in
      gate.finish(.failure(SystemProxyError.helperUnavailable("XPC 连接已失效")))
    }
    guard
      let proxy = connection.remoteObjectProxyWithErrorHandler({ @Sendable (error: Error) in
        gate.finish(.failure(SystemProxyError.helperUnavailable(String(describing: error))))
      }) as? SystemProxyHelperControlling
    else {
      gate.finish(.failure(SystemProxyError.helperUnavailable("无法创建远程对象代理")))
      return try await gate.wait()
    }
    connection.resume()
    call(proxy) { payload in
      gate.finish(Result { try SystemProxyHelperWire.decode(payload) })
    }
    // 超时兜底：已批准但卡死的 helper 不应让 UI 命令永久挂起；应答先到时取消。
    let timeout = requestTimeoutNanoseconds
    let timeoutTask = Task.detached(priority: .utility) {
      do {
        try await Task.sleep(nanoseconds: timeout)
      } catch {
        return
      }
      gate.finish(.failure(SystemProxyError.helperUnavailable("helper 应答超时")))
    }
    defer { timeoutTask.cancel() }
    return try await gate.wait()
  }
}

/// 一次性应答闸门：XPC 回调与超时兜底来自任意队列，只有第一个 finish 生效；
/// finish 先于 wait 到达时由闸门暂存结果。
private final class SystemProxyReplyGate: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<SystemProxyHelperResponse, Error>?
  private var result: Result<SystemProxyHelperResponse, Error>?

  func finish(_ result: Result<SystemProxyHelperResponse, Error>) {
    lock.lock()
    if let continuation {
      self.continuation = nil
      lock.unlock()
      continuation.resume(with: result)
      return
    }
    if self.result == nil {
      self.result = result
    }
    lock.unlock()
  }

  func wait() async throws -> SystemProxyHelperResponse {
    try await withCheckedThrowingContinuation { continuation in
      lock.lock()
      if let result {
        lock.unlock()
        continuation.resume(with: result)
        return
      }
      if self.continuation == nil {
        self.continuation = continuation
        lock.unlock()
        return
      }
      lock.unlock()
      continuation.resume(throwing: SystemProxyError.helperUnavailable("重复等待应答"))
    }
  }
}
