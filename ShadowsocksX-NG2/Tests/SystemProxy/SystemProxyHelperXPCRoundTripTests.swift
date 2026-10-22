import Foundation
import XCTest

@testable import ShadowsocksX_NG2

/// 真实 XPC 装配层的契约 round-trip：匿名监听器挂真实 listener
/// delegate（注入假特权写入器，不触真实系统设置）+ listenerEndpoint 连接，覆盖
/// fakes 与纯逻辑单测覆盖不到的层：NSXPCInterface 方法签名、客户端签名
/// identifier 校验、Data payload 传输与 XPC 内部队列应答路径。去宿主化
/// （ADR 0021）后连接方是 xctest runner 本进程，delegate 期望身份按本进程
/// 实际签名 identifier 注入，无需 launchd。
/// 注意：NSXPCListener.delegate 是弱引用，delegate 必须由测试强持有。
final class SystemProxyHelperXPCRoundTripTests: XCTestCase {
  func testTypedApplyAndClearRoundTripThroughRealXPCConnection() async throws {
    let engine = SystemProxyHelperEngine(perform: { request in
      switch request {
      case .apply: return .applied(.written)
      case .clear: return .cleared
      }
    })
    let delegate = SystemProxyHelperListenerDelegate(
      engine: engine,
      expectedClientIdentifier: try XCTUnwrap(ProcessSigningIdentifier.current()))
    let listener = NSXPCListener.anonymous()
    listener.delegate = delegate
    listener.resume()
    defer { listener.invalidate() }

    let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
    connection.remoteObjectInterface = NSXPCInterface(with: SystemProxyHelperControlling.self)
    connection.resume()
    defer { connection.invalidate() }

    let proxy = try XCTUnwrap(
      connection.remoteObjectProxyWithErrorHandler { (error: Error) in
        XCTFail("XPC 错误回调不应触发：\(error)")
      } as? SystemProxyHelperControlling)

    let configuration = SystemProxyConfiguration(
      socks: .init(host: "127.0.0.1", port: 1086),
      http: .init(host: "127.0.0.1", port: 1087), https: .init(host: "127.0.0.1", port: 1087),
      exceptions: ["localhost"])
    let payload = try SystemProxyHelperWire.encodeConfiguration(configuration)

    let applyReplied = expectation(description: "apply reply")
    var appliedResponse: SystemProxyHelperResponse?
    proxy.apply(payload) { data in
      do {
        appliedResponse = try SystemProxyHelperWire.decode(data)
      } catch {
        XCTFail("apply 应答无法解码：\(error)")
      }
      applyReplied.fulfill()
    }
    await fulfillment(of: [applyReplied], timeout: 10)
    XCTAssertEqual(appliedResponse, .applied(.written))

    let clearReplied = expectation(description: "clear reply")
    var clearedResponse: SystemProxyHelperResponse?
    proxy.clear { data in
      do {
        clearedResponse = try SystemProxyHelperWire.decode(data)
      } catch {
        XCTFail("clear 应答无法解码：\(error)")
      }
      clearReplied.fulfill()
    }
    await fulfillment(of: [clearReplied], timeout: 10)
    XCTAssertEqual(clearedResponse, .cleared)
  }
}
