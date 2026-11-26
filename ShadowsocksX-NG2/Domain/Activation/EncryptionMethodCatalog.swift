import Foundation

/// 加密方式能力目录（与当前随 app 打包的 sslocal 版本保持一致）。
/// 目录值是本地可验证的能力事实，不代表远端服务器一定可达。
enum EncryptionMethodCatalog {
  static let regular: Set<String> = [
    "aes-128-gcm",
    "aes-256-gcm",
    "chacha20-ietf-poly1305",
    "2022-blake3-aes-128-gcm",
    "2022-blake3-aes-256-gcm",
    "2022-blake3-chacha20-poly1305",
    "none",
  ]

  static let deprecated: Set<String> = [
    "aes-128-cfb", "aes-128-cfb1", "aes-128-cfb8", "aes-128-cfb128", "aes-128-ctr", "aes-128-ofb",
    "aes-192-cfb", "aes-192-cfb1", "aes-192-cfb8", "aes-192-cfb128", "aes-192-ctr", "aes-192-ofb",
    "aes-256-cfb", "aes-256-cfb1", "aes-256-cfb8", "aes-256-cfb128", "aes-256-ctr", "aes-256-ofb",
    "camellia-128-cfb", "camellia-128-cfb1", "camellia-128-cfb8", "camellia-128-cfb128",
    "camellia-128-ctr", "camellia-128-ofb",
    "camellia-192-cfb", "camellia-192-cfb1", "camellia-192-cfb8", "camellia-192-cfb128",
    "camellia-192-ctr", "camellia-192-ofb",
    "camellia-256-cfb", "camellia-256-cfb1", "camellia-256-cfb8", "camellia-256-cfb128",
    "camellia-256-ctr", "camellia-256-ofb",
    "chacha20-ietf", "rc4", "rc4-md5", "table",
  ]

  private static let supported = regular.union(deprecated)

  static func isSupported(_ method: String) -> Bool {
    supported.contains(method)
  }
}
