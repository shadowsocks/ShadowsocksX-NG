import Foundation

/// 叶子预检：一次完成激活阻塞判定与凭据/插件解析。插件参数保持 opaque，不
/// 在此判断其语法或远端握手；空 issues 只表示没有已知的本地激活阻塞原因。
/// 已解析事实供运行时文档装配复用，目录树只取 `invalidReasons`。
///
/// 不变量：`issues` 为空 ⇒ `password` 非空；`pluginProgram` 存在且无
/// `pluginNotProvided` ⇒ `plugin` 非空。
struct LeafPreparation: Equatable, Sendable {
  let issues: [LeafInvalidationReason]
  let password: String?
  let plugin: ResolvedPlugin?
  let pluginOptions: String?

  /// 运行时装配入口：一次解析并给出全部阻塞原因与已解析事实。
  static func prepare(
    _ fields: ServerFields,
    plugins: PluginExecutableResolving
  ) -> LeafPreparation {
    var issues: [LeafInvalidationReason] = []
    appendAddressIssue(fields.address, to: &issues)
    appendPortIssue(fields.port, to: &issues)
    appendMethodIssue(fields.encryptionMethod, to: &issues)

    let password = fields.password.isEmpty ? nil : fields.password
    if password == nil { issues.append(.missingPassword) }
    var plugin: ResolvedPlugin?
    var pluginOptions: String?
    if let program = fields.pluginProgram {
      if let resolved = plugins.resolve(program: program) {
        plugin = resolved
      } else {
        issues.append(.pluginNotProvided(program: program))
      }
      pluginOptions = fields.pluginOptions
    }
    return LeafPreparation(
      issues: issues, password: password, plugin: plugin, pluginOptions: pluginOptions)
  }

  /// validation-only 入口：目录树等只读呈现取全部阻塞原因，不组装运行时文档。
  static func invalidReasons(
    _ fields: ServerFields,
    plugins: PluginExecutableResolving
  ) -> [LeafInvalidationReason] {
    prepare(fields, plugins: plugins).issues
  }

  private static func appendAddressIssue(
    _ address: String, to issues: inout [LeafInvalidationReason]
  ) {
    if address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(.invalidAddress)
    }
  }

  private static func appendPortIssue(
    _ port: Int, to issues: inout [LeafInvalidationReason]
  ) {
    if !(1...65_535).contains(port) { issues.append(.invalidPort(port)) }
  }

  private static func appendMethodIssue(
    _ method: String, to issues: inout [LeafInvalidationReason]
  ) {
    let trimmed = method.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      issues.append(.missingEncryptionMethod)
    } else if !EncryptionMethodCatalog.isSupported(trimmed) {
      issues.append(.unsupportedEncryptionMethod(trimmed))
    }
  }
}
