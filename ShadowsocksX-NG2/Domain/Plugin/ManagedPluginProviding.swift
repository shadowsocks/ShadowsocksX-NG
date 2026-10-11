import Foundation

/// 插件解析 seam：路径与本地启动参数，以及一次派生使用的只读目录快照。
/// nil 表示本地不可用；托管与用户映射共用这一激活语义。
struct ResolvedPlugin: Equatable, Sendable {
  let path: String
  let arguments: [String]
}

protocol PluginExecutableResolving {
  func resolve(program: String) -> ResolvedPlugin?
  func catalogSnapshot() -> PluginCatalogSnapshot
}

extension PluginExecutableResolving {
  func executablePath(forProgram program: String) -> String? {
    resolve(program: program)?.path
  }

  func catalogSnapshot() -> PluginCatalogSnapshot {
    PluginCatalogSnapshot(
      entries: ManagedPluginCatalog.plugins.flatMap { info in
        info.names.map { program in
          let resolved = resolve(program: program)
          return PluginCatalogSnapshot.Entry(
            program: program, path: resolved?.path, source: .managed,
            availability: resolved == nil ? .missing : .available, managedInfo: info,
            arguments: resolved?.arguments ?? [])
        }
      })
  }
}

/// 受管插件静态事实（#38）：来源项目、许可证、固定版本与重签标识，供编辑器
/// 插件区与诊断导出展示。事实只随发版变更（D6「升级前重做静态清单」）：新增
/// 或升级插件须同步 `Vendor/<name>/manifest.json` 与锚点测试
/// `ManagedPluginCatalogTests`，两处漂移即构建期失败。
struct ManagedPluginInfo: Equatable, Sendable {
  /// 内置记录的固定身份，与可引用名称及打包文件名分别维护。
  let program: String
  let names: [String]
  let executableName: String
  /// 来源项目（GitHub owner/repo）。
  let project: String
  let projectURL: String
  /// 固定版本 tag（禁止 latest 漂移）。
  let release: String
  let license: String
  /// 构建期 Developer ID 重签的 identifier（`<bundle-id>.plugin.<name>`）。
  let signIdentifier: String
}

/// 本版本受管集（D10）：首版仅 v2ray-plugin v1.3.2；shadow-tls、Cloak 暂缓，
/// 此目录只描述随 app 发布的程序；用户自备程序由 PluginCatalog 的本机映射提供。
enum ManagedPluginCatalog {
  static let plugins: [ManagedPluginInfo] = [
    ManagedPluginInfo(
      program: "v2ray-plugin",
      names: ["v2ray-plugin", "v2ray-plugin-v1"],
      executableName: "v2ray-plugin",
      project: "shadowsocks/v2ray-plugin",
      projectURL: "https://github.com/shadowsocks/v2ray-plugin",
      release: "v1.3.2",
      license: "MIT",
      signIdentifier: "com.qiuyuzhou.ShadowsocksX-NG2.plugin.v2ray-plugin")
  ]

  static func info(forProgram program: String) -> ManagedPluginInfo? {
    plugins.first { $0.names.contains(program) }
  }
}

/// 生产实现：受管集内且 bundle 内可执行文件在位才返回绝对路径。D10——GUI
/// 仅在生成配置时检查可执行文件存在，运行时不逐次哈希复验（bundle 签名 +
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
    return ResolvedPlugin(path: url.path, arguments: [])
  }
}

/// 显式「本版本什么都不提供」的实现（测试与不涉插件的场景注入用）：任何插件
/// 引用都是无效激活候选（点名原因），不是静默失败。
struct NoManagedPluginProvider: PluginExecutableResolving {
  func resolve(program: String) -> ResolvedPlugin? { nil }
}
