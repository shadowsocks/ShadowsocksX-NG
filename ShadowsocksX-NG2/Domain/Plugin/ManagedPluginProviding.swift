import Foundation

/// 插件解析 seam：路径、本地启动参数与传输模式，以及一次派生使用的只读目录快照。
/// nil 表示本地不可用；托管与用户映射共用这一激活语义。
struct ResolvedPlugin: Equatable, Sendable {
  let path: String
  let arguments: [String]
  var mode: PluginTransportMode = .tcpOnly
}

protocol PluginExecutableResolving {
  func resolve(program: String) -> ResolvedPlugin?
  func catalogSnapshot() -> PluginCatalogSnapshot
}

extension PluginExecutableResolving {
  func catalogSnapshot() -> PluginCatalogSnapshot {
    PluginCatalogSnapshot(
      entries: ManagedPluginCatalog.plugins.flatMap { info in
        info.names.map { program in
          let resolved = resolve(program: program)
          return PluginCatalogSnapshot.Entry(
            program: program, path: resolved?.path, source: .managed,
            availability: resolved == nil ? .missing : .available, managedInfo: info,
            arguments: resolved?.arguments ?? [], mode: resolved?.mode ?? .tcpOnly)
        }
      })
  }
}

/// Executable contracts are generated from Vendor manifests, independently of display metadata.
struct ManagedPluginInfo: Equatable, Sendable {
  let program: String
  let names: [String]
  let executableName: String
  let signIdentifier: String
  let defaultArguments: [String]
  var dependency: BundledDependency?
}

enum ManagedPluginCatalog {
  static let plugins = plugins(in: Bundle.main.bundleURL)

  static func plugins(in bundleURL: URL) -> [ManagedPluginInfo] {
    let catalog = try? BundledDependencyCatalog(bundleURL: bundleURL)
    return definitions.map { definition in
      var info = definition
      info.dependency = catalog?.dependencies.first { $0.id == info.program }
      return info
    }
  }

  static func info(forProgram program: String) -> ManagedPluginInfo? {
    plugins.first { $0.names.contains(program) }
  }
}

/// 生产实现：受管集内且 bundle 内可执行文件在位才返回绝对路径。GUI 仅在生成
/// 配置时检查可执行文件是否存在，运行时不逐次哈希复验（bundle 签名 +
/// 公证即信任边界）；受管集外引用一律视为「本版本未提供」，路径只从静态表
/// 派生，不拼接任何用户输入。
struct BundleManagedPluginProvider: PluginExecutableResolving {
  /// 插件宿主 bundle 根；生产为应用 bundle，测试注入临时目录。
  var bundleURL: URL = Bundle.main.bundleURL
  var fileManager: FileManager = .default

  func resolve(program: String) -> ResolvedPlugin? {
    guard let info = ManagedPluginCatalog.info(forProgram: program) else { return nil }
    let url =
      bundleURL
      .appendingPathComponent("Contents/Helpers/Plugins")
      .appendingPathComponent(info.executableName)
    guard fileManager.isExecutableFile(atPath: url.path) else { return nil }
    return ResolvedPlugin(path: url.path, arguments: info.defaultArguments)
  }
}

/// 显式「本版本什么都不提供」的实现（测试与不涉插件的场景注入用）：任何插件
/// 引用都是无效激活候选（点名原因），不是静默失败。
struct NoManagedPluginProvider: PluginExecutableResolving {
  func resolve(program: String) -> ResolvedPlugin? { nil }
}
