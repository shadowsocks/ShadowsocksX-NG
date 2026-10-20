import Foundation
import Security

/// XPC 监听代理：只接受代码签名 identifier 等于 2.0 bundle
/// identifier 的客户端（开源构建换签名团队、其他账号的 2.0 实例均可），
/// 不校验 Team ID 或 UID。校验基于连接对端 pid 的 SecCode 查询。
final class SystemProxyHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
  private let engine: SystemProxyHelperEngine
  private let expectedClientIdentifier: String
  private let log: @Sendable (SystemProxyHelperLogEvent) -> Void

  /// 引擎由进程入口显式注入：特权写入器 SystemProxyWriter 属 helper 专属
  /// （不进共享编译单元），测试注入假写入器。期望客户端身份生产默认为 2.0
  /// bundle identifier；去宿主化（ADR 0021）后单测运行于 xctest runner，
  /// 连接方身份随宿主改变，测试注入本进程实际签名 identifier。`log` 是
  /// 事件发射缝（ADR-0047）：连接接受/拒绝各记一条。
  init(
    engine: SystemProxyHelperEngine,
    expectedClientIdentifier: String = SystemProxyHelperIdentity.clientCodeSigningIdentifier,
    log: @escaping @Sendable (SystemProxyHelperLogEvent) -> Void = SystemProxyHelperLog.emit
  ) {
    self.engine = engine
    self.expectedClientIdentifier = expectedClientIdentifier
    self.log = log
    super.init()
  }

  func listener(
    _ listener: NSXPCListener,
    shouldAcceptNewConnection newConnection: NSXPCConnection
  ) -> Bool {
    guard
      SystemProxyClientValidator.clientSigningIdentifier(newConnection)
        == expectedClientIdentifier
    else {
      log(.connectionRejected(pid: newConnection.processIdentifier))
      return false
    }
    log(.connectionAccepted(pid: newConnection.processIdentifier))
    newConnection.exportedInterface = NSXPCInterface(with: SystemProxyHelperControlling.self)
    newConnection.exportedObject = engine
    newConnection.resume()
    return true
  }
}

/// 客户端代码签名校验。pid 查询与连接建立之间存在理论上的 pid 复用窗口；
/// 连接本身由内核绑定到建立时的进程，这里采用 SecCode 惯用做法。
enum SystemProxyClientValidator {
  static func clientSigningIdentifier(_ connection: NSXPCConnection) -> String? {
    var code: SecCode?
    let attributes =
      [kSecGuestAttributePid: NSNumber(value: connection.processIdentifier)] as CFDictionary
    guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
      let code
    else { return nil }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode
    else { return nil }
    var information: CFDictionary?
    guard SecCodeCopySigningInformation(staticCode, SecCSFlags(), &information) == errSecSuccess,
      let information
    else { return nil }
    return (information as NSDictionary)[kSecCodeInfoIdentifier] as? String
  }
}
