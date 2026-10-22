import Foundation

// MARK: - 事实输入

/// 单个文件的存在性/权限/大小/时间事实（导出允许的元数据类目；只读元数据，
/// 永不读文件内容）。
struct DiagnosticFileFacts: Equatable, Sendable {
  let label: String
  let exists: Bool
  let isDirectory: Bool
  /// POSIX 权限八进制文本（如 "0600"）；文件不存在时为 nil。
  let permissionsOctal: String?
  let sizeBytes: Int?
  let modifiedAt: Date?
}

/// 文件事实收集：只取存在性/权限/大小/修改时间。
enum DiagnosticFileCollector {
  static func collect(
    label: String, url: URL, fileManager: FileManager = .default
  ) -> DiagnosticFileFacts {
    let missing = DiagnosticFileFacts(
      label: label, exists: false, isDirectory: false,
      permissionsOctal: nil, sizeBytes: nil, modifiedAt: nil)
    guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
      return missing
    }
    let isDirectory = (attributes[.type] as? FileAttributeType) == .typeDirectory
    let permissions = (attributes[.posixPermissions] as? NSNumber).map {
      String(format: "%04o", $0.int32Value)
    }
    return DiagnosticFileFacts(
      label: label,
      exists: true,
      isDirectory: isDirectory,
      permissionsOctal: permissions,
      sizeBytes: (attributes[.size] as? NSNumber)?.intValue,
      modifiedAt: attributes[.modificationDate] as? Date)
  }
}

/// 代理状态的安全呈现：控制器状态收敛为固定文案，不透传任意
/// 错误 detail（导出只含白名单类目，原始错误文本一律丢弃）；激活失败
/// 原因来自领域的点名文案（短节点片段 + 固定文本，无秘密）。
enum DiagnosticProxyState: Equatable, Sendable {
  case off
  case starting
  case running
  case firewallBlocked
  case launchFailed
  case activationFailed(reason: String)
  case requiresApproval
  case serviceFailed
  case systemProxyFailed

  var label: String {
    switch self {
    case .off:
      return "已停止"
    case .starting:
      return "启动中"
    case .running:
      return "运行中"
    case .firewallBlocked:
      return "已被 macOS 应用防火墙拦截（主机地址态）"
    case .launchFailed:
      return "启动失败（本地代理端点未就绪）"
    case .activationFailed(let reason):
      return "激活失败：\(reason)"
    case .requiresApproval:
      return "等待在系统设置-登录项中批准"
    case .serviceFailed:
      return "服务管理失败"
    case .systemProxyFailed:
      return "系统代理未应用"
    }
  }
}

// MARK: - 快照与构建器

/// 目录聚合诊断事实：数量元数据与已知无效数。原始
/// 目录、目录条目、服务器地址、备注与凭据引用不进入本类型——构造它的唯一
/// 生产入口是目录 workflow 的 domain-neutral 事实缝，报告 builder 只接受
/// 已经裁剪的聚合事实。
struct DiagnosticCatalogFacts: Equatable, Sendable {
  var counts = DiagnosticReportBuilder.CatalogCounts()
  /// 已知无效服务器数（应用层以当前凭据与插件供应事实计算；nil = 未知）。
  var knownInvalidServerCount: Int?
}

/// 诊断快照：导出报告的全部输入。字段要么是数量/布尔/时间等
/// 元数据，要么是已脱敏文本（由夹具测试验证），构建器不再接触任何秘密来源
/// ——不读 Keychain、不读契约与目录的文件内容；目录事实只以聚合计数进入快照。
struct DiagnosticSnapshot: Sendable {
  var generatedAt = Date()
  var appVersion: String?
  var systemSummary: String?
  var proxyState = DiagnosticProxyState.off
  var hasActiveTarget = false
  var listen: RuntimeListenFacts?
  /// `Redactor.documentSummary` 产出的契约脱敏摘要（数量与模式）。
  var runtimeDocumentSummary: String?
  /// 自定义规则安全摘要：数量 + 内容版本，无原始域名。
  var customRuleSummary: CustomRuleSummary?
  /// 目录聚合事实；nil = 目录事实源不可用（报告中明确标注，不静默丢失）。
  var catalogFacts: DiagnosticCatalogFacts?
  var fileFacts: [DiagnosticFileFacts] = []
  /// 渲染好的运行事件行（旧→新，调用方负责封顶；行文本必须来自白名单
  /// 清洗投影。
  var eventLines: [String] = []
  /// bundle 内受管插件清单（名称/版本/存在性，不含参数与路径）。
  var managedPlugins: [DiagnosticPluginFacts] = []
  /// 长路径脱敏基准：文本中出现的该前缀一律改写为「~」。
  var homePathForRedaction: String?
}

/// 受管插件事实：程序名、固定版本与二进制是否在位。存在性属
/// 允许的导出类目；插件参数与文件路径不进导出。
struct DiagnosticPluginFacts: Equatable, Sendable {
  let program: String
  let version: String
  let present: Bool
  var source: PluginCatalogSnapshot.Source = .managed
}

/// 诊断报告构建器：只输出状态、存在性、权限、
/// 大小/时间、数量与脱敏元数据。测试夹具以投毒数据验证导出不含任何敏感
/// 类目（密码、插件参数、Keychain 值、完整订阅 URL 及其 token、运行时
/// JSON 内容、服务器地址与备注）。测试 URL 为非敏感信息，无需脱敏。
enum DiagnosticReportBuilder {
  /// 目录数量元数据（只含计数，不含名称/地址/备注）。
  struct CatalogCounts: Equatable, Sendable {
    var servers = 0
    var groups = 0
    var serversWithPlugin = 0
    var manualServers = 0
    var subscriptionServers = 0
  }

  static func counts(in catalog: ConfigurationCatalog) -> CatalogCounts {
    var counts = CatalogCounts()
    for entry in catalog.entries.values {
      switch entry.kind {
      case .server(let fields):
        counts.servers += 1
        if entry.source == .manual {
          counts.manualServers += 1
        } else {
          counts.subscriptionServers += 1
        }
        if fields.pluginProgram != nil {
          counts.serversWithPlugin += 1
        }
      case .group:
        counts.groups += 1
      }
    }
    return counts
  }

  static func markdown(from snapshot: DiagnosticSnapshot) -> String {
    var lines: [String] = []
    lines.append("# ShadowsocksX-NG2 诊断报告")
    lines.append("")
    lines.append("- 生成时间：\(timestamp(snapshot.generatedAt))")
    lines.append("- 应用版本：\(snapshot.appVersion ?? "未提供")")
    lines.append("- 系统：\(snapshot.systemSummary ?? "未提供")")
    lines.append("")
    lines.append("本报告仅含状态、存在性、权限、大小/时间、数量与脱敏元数据；不包含")
    lines.append("密码、插件参数、钥匙串值、完整订阅 URL 及其 token、运行时 JSON")
    lines.append("内容、服务器地址与备注。")
    lines.append("")
    lines.append(contentsOf: statusLines(snapshot))
    lines.append(contentsOf: fileTableLines(snapshot))
    lines.append("## 运行事件（最近 \(snapshot.eventLines.count) 条）")
    lines.append("")
    if snapshot.eventLines.isEmpty {
      lines.append("（无事件）")
    } else {
      lines.append(contentsOf: snapshot.eventLines)
    }
    let text = lines.joined(separator: "\n") + "\n"
    return redactingHomePaths(text, home: snapshot.homePathForRedaction)
  }

  /// 家目录前缀改写为「~」：错误 detail 可能携带文件路径，避免导出暴露
  /// 用户目录名。
  static func redactingHomePaths(_ text: String, home: String?) -> String {
    guard let home, !home.isEmpty, home != "/" else { return text }
    return text.replacingOccurrences(of: home, with: "~")
  }

  private static func statusLines(_ snapshot: DiagnosticSnapshot) -> [String] {
    var lines: [String] = []
    lines.append("## 代理状态")
    lines.append("")
    lines.append("- 代理状态：\(snapshot.proxyState.label)")
    lines.append("- 活动目标：\(snapshot.hasActiveTarget ? "已设置" : "未设置")")
    if let listen = snapshot.listen {
      let binding = listen.lan.isEnabled ? "（\(listen.lan.mode.bindAddress)）" : ""
      let lanMode = listen.lan.isEnabled ? listen.lan.mode.displayName : String(localized: "关闭")
      lines.append(
        "- 局域网监听：\(lanMode)\(binding)，SOCKS \(listen.lan.socksPort) / HTTP \(listen.lan.httpPort)"
      )
      lines.append("- 本地监听：\(listenDescription(listen))")
    }
    if let summary = snapshot.runtimeDocumentSummary {
      lines.append("- 运行时契约摘要：\(summary)")
    } else {
      lines.append("- 运行时契约摘要：不可用")
    }
    if let rules = snapshot.customRuleSummary {
      lines.append("- 自定义规则：\(rules.count) 条（版本 \(rules.contentVersion)）")
    } else {
      lines.append("- 自定义规则：不可用")
    }
    lines.append("")
    lines.append("## 配置目录（数量）")
    lines.append("")
    if let facts = snapshot.catalogFacts {
      lines.append(contentsOf: catalogCountLines(facts))
    } else {
      lines.append("- 配置目录不可用")
    }
    lines.append("")
    lines.append("## 受管插件")
    lines.append("")
    if snapshot.managedPlugins.isEmpty {
      lines.append("（本版本未打包任何插件）")
    } else {
      for plugin in snapshot.managedPlugins {
        let version = plugin.source == .managed ? plugin.version : plugin.source.rawValue
        lines.append(
          "- \(plugin.program) \(version)：\(plugin.present ? "已提供" : "缺失")"
        )
      }
    }
    lines.append("")
    return lines
  }

  private static func fileTableLines(_ snapshot: DiagnosticSnapshot) -> [String] {
    var lines: [String] = []
    lines.append("## 运行时文件（存在性 / 权限 / 大小 / 时间）")
    lines.append("")
    lines.append("| 文件 | 存在 | 权限 | 字节 | 修改时间 |")
    lines.append("|---|---|---|---|---|")
    for facts in snapshot.fileFacts {
      lines.append(fileRow(facts))
    }
    lines.append("")
    return lines
  }

  /// 目录行只呈现聚合事实：目录条目本身永不进入快照与渲染。
  private static func catalogCountLines(_ facts: DiagnosticCatalogFacts) -> [String] {
    let counts = facts.counts
    let invalid = facts.knownInvalidServerCount.map { "已知无效 \($0)；" } ?? ""
    return [
      "- 服务器：\(counts.servers)（\(invalid)"
        + "配置插件 \(counts.serversWithPlugin)；"
        + "手动 \(counts.manualServers) / 订阅 \(counts.subscriptionServers)）",
      "- 分组：\(counts.groups)",
    ]
  }

  /// 本地端点只以端口事实呈现。
  private static func listenDescription(_ listen: RuntimeListenFacts) -> String {
    var parts = ["SOCKS5 端口 \(listen.socksPort)"]
    parts.append("HTTP 端口 \(listen.httpPort)")
    return parts.joined(separator: "；")
  }

  private static func fileRow(_ facts: DiagnosticFileFacts) -> String {
    let size: String
    if facts.isDirectory {
      size = "—"
    } else if let sizeBytes = facts.sizeBytes {
      size = String(sizeBytes)
    } else {
      size = "—"
    }
    let modified = facts.modifiedAt.map(timestamp) ?? "—"
    let permission = facts.permissionsOctal ?? "—"
    let existence = facts.exists ? "是" : "否"
    return "| \(facts.label) | \(existence) | \(permission) | \(size) | \(modified) |"
  }

  private static func timestamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: date)
  }
}
