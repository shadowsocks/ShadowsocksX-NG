import Foundation
import Security

/// 本进程的代码签名 identifier（与生产 SystemProxyClientValidator 同一
/// SecCode 查询路径，对自身用 SecCodeCopySelf 取 code）。去宿主化（ADR 0021）
/// 后单测运行于 xctest runner，XPC 连接方身份随宿主改变；helper XPC 装配
/// 测试以本值注入期望客户端身份，无需 launchd。
enum ProcessSigningIdentifier {
  static func current() -> String? {
    var code: SecCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
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
