import Foundation

/// App Support 目录全部文件的路径清单：GUI 配置与跨进程运行时契约共用同一
/// 目录。运行时契约子集是 GUI 写、wrapper 读的固定
/// 位置；GUI 配置文件 wrapper 不经手。目录 0700、文件 0600，由写入方与
/// wrapper 共同维护。
enum RuntimePaths {
  static func runtimeDirectory() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("ShadowsocksX-NG2", isDirectory: true)
  }

  /// Agent 切换的稳定配置链接；sslocal 启动与 SIGUSR1 重读均使用此路径。
  static func runtimeFileURL() -> URL {
    runtimeDirectory().appendingPathComponent("sslocal-active.json")
  }

  /// ACL 稳定链接：sslocal 经配置 `acl` 键读取，由 Agent 切换到不可变变体。
  static func aclFileURL() -> URL {
    runtimeDirectory().appendingPathComponent("acl-active.ini")
  }

  /// wrapper 进程 pid 文件：SMAppService.Status 不暴露运行中 agent 的 pid，
  /// wrapper 自写此文件供 GUI 判活（kill(pid, 0)）并投递 SIGUSR1。
  static func agentPIDFileURL() -> URL {
    runtimeDirectory().appendingPathComponent("agent.pid")
  }

  /// The wrapper's sslocal deployment receipt. ACL-backed receipts are written
  /// after the child owns the configured TCP listeners; the GUI checks its
  /// deployment identity and PID during direct-mode health checks.
  static func agentRuntimeStatusURL() -> URL {
    runtimeDirectory().appendingPathComponent("agent-runtime-status.json")
  }

  /// wrapper 与 sslocal 的收敛日志（stderr 重定向目标）。不支持滚动或诊断导出；
  /// 不属于「运行时文件」，显式停止时不删除。
  static func agentLogURL() -> URL {
    runtimeDirectory().appendingPathComponent("agent.log")
  }

  // 旧版端点签名/所有权文件（system-proxy-endpoint-signature.json、
  // system-proxy-ownership.json）就地遗留：不读取、不迁移、
  // 不删除。

  // MARK: - GUI 配置文件（GUI 私有读写，wrapper 不经手）

  /// 服务器目录（CatalogFileStore）。
  static func catalogFileURL() -> URL {
    runtimeDirectory().appendingPathComponent("catalog.enc")
  }

  /// 代理偏好（ProxySettingsFileStore）。
  static func settingsFileURL() -> URL {
    runtimeDirectory().appendingPathComponent("settings.json")
  }

  /// 自定义规则文档（CustomRuleStore）。
  static func customRulesFileURL() -> URL {
    runtimeDirectory().appendingPathComponent("custom-rules.json")
  }

  /// 活动目标（ActivationStateFileStore）。
  static func activationStateFileURL() -> URL {
    runtimeDirectory().appendingPathComponent("activation.json")
  }

  /// 静默启动偏好的 ADR 0017 初版文件形态，仅遗留迁移路径使用
  /// （SilentLaunchStore.migrateLegacyFileIfPresent）。
  static func silentLaunchLegacyFileURL() -> URL {
    runtimeDirectory().appendingPathComponent("silent-launch.json")
  }
}

/// ACL 活动链接的防逃逸校验（ADR-0011）：解析 symlink 后必须仍是运行目录
/// 内的普通文件。目录与目标都做 symlink 解析，避免 `/var` vs `/private/var`
/// 造成假阴性。GUI 写入侧与 Agent 加载侧共用此判定。
enum ACLActiveLinkPolicy {
  static func resolvesToRegularFile(inside directory: URL, linkURL: URL) -> Bool {
    let fileManager = FileManager.default
    let linkPath = linkURL.standardizedFileURL.path
    guard fileManager.fileExists(atPath: linkPath) else { return false }
    let resolved = URL(fileURLWithPath: linkPath).resolvingSymlinksInPath().standardizedFileURL
    let resolvedDirectory = URL(fileURLWithPath: directory.path).resolvingSymlinksInPath()
      .standardizedFileURL.path
    guard resolved.path == resolvedDirectory || resolved.path.hasPrefix(resolvedDirectory + "/")
    else { return false }
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory) else {
      return false
    }
    return !isDirectory.boolValue
  }
}
