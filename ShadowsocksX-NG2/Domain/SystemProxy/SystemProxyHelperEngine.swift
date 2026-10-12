import Foundation

/// 特权 helper 的请求引擎：解码 closed typed 请求 → 注入的特权
/// 写入器 → 编码应答。引擎本身不含任何产品策略，只在 payload 无效时拒绝。
/// 所有连接共享一条串行队列：请求逐个执行，最后接受的请求决定设备级配置
/// （last-writer-wins）。
final class SystemProxyHelperEngine: NSObject, SystemProxyHelperControlling {
  /// 注入的特权写入器：真正触到 SystemConfiguration 的唯一边界。
  typealias Performing =
    @Sendable (SystemProxyHelperEngine.Request) throws ->
    SystemProxyHelperEngine.Outcome

  enum Request: Equatable, Sendable {
    case apply(SystemProxyConfiguration)
    case clear
  }

  enum Outcome: Equatable, Sendable {
    case applied(SystemProxyWriteOutcome)
    case cleared
  }

  /// 跨全部 XPC 连接共享的串行执行队列。
  private static let sharedQueue = DispatchQueue(
    label: "\(SystemProxyHelperIdentity.machServiceName).work")

  private let queue: DispatchQueue
  private let perform: Performing

  init(perform: @escaping Performing, queue: DispatchQueue? = nil) {
    self.perform = perform
    self.queue = queue ?? Self.sharedQueue
    super.init()
  }

  func apply(_ payload: Data, withReply reply: @escaping (Data) -> Void) {
    let reply = ReplyBox(reply)
    queue.async { [perform, reply] in
      let request = Result { try SystemProxyHelperWire.decodeConfiguration(payload) }
      reply(Self.responseData(request: request.map { .apply($0) }, perform: perform))
    }
  }

  func clear(withReply reply: @escaping (Data) -> Void) {
    let reply = ReplyBox(reply)
    queue.async { [perform, reply] in
      reply(Self.responseData(request: .success(.clear), perform: perform))
    }
  }

  // MARK: - 请求执行（纯逻辑，可测）

  static func responseData(
    request: Result<Request, Error>, perform: Performing
  ) -> Data {
    SystemProxyHelperWire.encode(response(request: request, perform: perform))
  }

  static func response(
    request: Result<Request, Error>, perform: Performing
  ) -> SystemProxyHelperResponse {
    do {
      let outcome = try perform(request.get())
      switch outcome {
      case .applied(let writeOutcome):
        return .applied(writeOutcome)
      case .cleared:
        return .cleared
      }
    } catch let error as SystemProxyError {
      return .failure(error)
    } catch {
      return .failure(.helperUnavailable(String(describing: error)))
    }
  }
}

/// XPC 应答闭包的 Sendable 桥。@objc 协议里 reply 参数无法标注 @Sendable，
/// 但 XPC 运行时生成的应答块线程安全且恰好调用一次，引擎在串行工作队列上
/// 调用它；装箱只为跨过 queue.async 的 @Sendable 边界。
private final class ReplyBox: @unchecked Sendable {
  private let reply: (Data) -> Void

  init(_ reply: @escaping (Data) -> Void) {
    self.reply = reply
  }

  func callAsFunction(_ data: Data) {
    reply(data)
  }
}
