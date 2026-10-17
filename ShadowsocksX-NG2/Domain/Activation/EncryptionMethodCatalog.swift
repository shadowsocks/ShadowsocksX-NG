import Foundation

/// 加密方式能力目录（与当前随 app 打包的 sslocal 版本保持一致）。
/// 目录值是本地可验证的能力事实，不代表远端服务器一定可达。
enum EncryptionMethodCatalog {
  static let supported: Set<String> = [
    "aes-128-gcm",
    "aes-256-gcm",
    "chacha20-ietf-poly1305",
    "2022-blake3-aes-128-gcm",
    "2022-blake3-aes-256-gcm",
    "2022-blake3-chacha20-poly1305",
    "none",
  ]

  static func isSupported(_ method: String) -> Bool {
    supported.contains(method)
  }
}
