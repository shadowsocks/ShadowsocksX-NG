import Foundation

/// Localized management feedback shared by the list and editor.
enum PluginManagementCopy {
  static func error(_ error: Error) -> String {
    guard let issue = error as? PluginMappingError else {
      return String(localized: "无法保存插件配置，请检查配置文件的访问权限后重试。")
    }
    switch issue {
    case .unreadable, .unsupportedVersion:
      return String(localized: "无法读取插件配置。请修复配置文件后重试读取。")
    case .invalidName:
      return String(localized: "请至少填写一个非空插件名称。")
    case .nameExists:
      return String(localized: "已有同名用户插件，请编辑现有条目或使用其他名称。")
    case .invalidPath:
      return String(localized: "请输入可执行文件的绝对路径。")
    case .invalidArguments:
      return String(localized: "启动参数不能包含空字符（NUL）。")
    case .unavailableFile:
      return String(localized: "文件不存在或不可执行，请选择可执行文件。")
    case .nameMissing:
      return String(localized: "该用户插件已不存在，请关闭表单后重试。")
    }
  }

  static func source(_ entry: PluginCatalogSnapshot.Entry) -> String {
    if entry.source == .managed { return String(localized: "内置") }
    return ManagedPluginCatalog.info(forProgram: entry.program) == nil
      ? String(localized: "用户添加") : String(localized: "用户覆盖")
  }

  static func availability(_ value: PluginCatalogSnapshot.Availability) -> String? {
    switch value {
    case .available: nil
    case .missing: String(localized: "插件文件不存在。")
    case .notExecutable: String(localized: "插件文件不可执行。")
    case .unreadable: String(localized: "无法读取插件文件。")
    }
  }

  static func securitySummary(_ facts: PluginSecurityFacts) -> String? {
    if facts.policy == .rejected {
      return String(localized: "macOS 安全策略检查未通过，运行可能受到限制。")
    }
    if facts.quarantine == .present {
      return String(localized: "文件带有下载隔离标记，运行时可能需要 macOS 授权。")
    }
    if facts.signature == .invalid {
      return String(localized: "文件签名无效，运行可能受到 macOS 限制。")
    }
    if facts.signature == .unsigned {
      return String(localized: "文件未签名，运行可能受到 macOS 限制。")
    }
    if facts.quarantine == .unknown || facts.signature == .unknown || facts.policy == .unknown {
      return String(localized: "无法完成安全检查。")
    }
    return nil
  }

  static func quarantine(_ value: PluginSecurityFacts.Quarantine) -> String {
    switch value {
    case .present: String(localized: "隔离标记：存在")
    case .absent: String(localized: "隔离标记：无")
    case .unknown: String(localized: "隔离标记：无法判断")
    }
  }

  static func signature(_ value: PluginSecurityFacts.Signature) -> String {
    switch value {
    case .valid: String(localized: "签名：有效")
    case .unsigned: String(localized: "签名：未签名")
    case .invalid: String(localized: "签名：无效")
    case .notApplicable: String(localized: "签名：不适用")
    case .unknown: String(localized: "签名：无法判断")
    }
  }

  static func policy(_ value: PluginSecurityFacts.Policy) -> String {
    switch value {
    case .accepted: String(localized: "安全策略：检查通过")
    case .rejected: String(localized: "安全策略：检查未通过")
    case .notApplicable: String(localized: "安全策略：不适用")
    case .unknown: String(localized: "安全策略：无法判断")
    }
  }
}
