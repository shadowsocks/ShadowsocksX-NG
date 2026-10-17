import Foundation

/// The single application presentation edge. Domain and workflow modules expose
/// typed errors/facts; this file is the only place that turns them into text.
extension Error {
  var presentableMessage: String {
    AppPresentation.message(for: self)
  }
}

enum AppPresentation {
  static let unknownError = String(localized: "操作失败，请重试或检查设置")
}

extension AppPresentation {
  // The presentation edge deliberately dispatches across the app's typed
  // failure families; keeping this switch explicit makes the whitelist auditable.
  // swiftlint:disable:next cyclomatic_complexity function_body_length
  static func message(for error: Error) -> String {
    switch error {
    case let error as CatalogError:
      return catalog(error)
    case let error as ActivationFailure:
      return activation(error)
    case let error as ServerFormError:
      return serverForm(error)
    case let error as SsUriError:
      return ssURI(error)
    case let error as CredentialStoreError:
      return credential(error)
    case let error as SubscriptionFormError:
      return subscriptionForm(error)
    case let error as SubscriptionFetchError:
      return subscriptionFetch(error)
    case let error as SubscriptionParseError:
      return subscriptionParse(error)
    case let error as SubscriptionRefreshCommitError:
      return message(
        for: .commit(
          category: error.category,
          rollback: SubscriptionRefreshFailure.rollbackStatus(for: error.rollback)))
    case let error as SettingsWorkflowFailure:
      return message(for: error)
    case let error as RuntimeFailureFacts:
      return message(for: error)
    case let error as ImportLineFailureReason:
      return importLine(error)
    case let error as ImportSourceFailure:
      return importSource(error)
    case let error as LegacySkippedRecord.Reason:
      return reason(error)
    case let error as CommitError:
      return commit(error)
    case let error as PortSettingError:
      return port(error)
    case let error as ProxySettingsStoreError:
      return settingsStore(error)
    case let error as LegacyImportError:
      return legacyImport(error)
    case let error as SystemProxyError:
      return systemProxy(SystemProxyOperationFailure(error))
    case let error as TextClipboardFailure:
      return textClipboard(error)
    case let error as TerminalCommandFailure:
      switch error {
      case .credentialUnreadable: return String(localized: "局域网身份验证密码不可读，请重试。")
      case .addressUnavailable: return String(localized: "命令地址已失效，请重新选择 IP。")
      }
    case let error as ImageClipboardFailure:
      return imageClipboard(error)
    case let error as QrImageSaveFailure:
      return qrImageSave(error)
    case let error as DiagnosticReportFailure:
      return diagnosticReport(error)
    case let error as DiagnosticReportExportFailure:
      return diagnosticReportExport(error)
    case let error as ConfigurationGroupExportFailure:
      return configurationGroupExport(error)
    case let error as ConfigurationGroupFileExportFailure:
      return error == .writeFailed
        ? String(localized: "SIP-008 文件写入失败") : String(localized: "URI 链接列表文本文件写入失败")
    default:
      return unknownError
    }
  }

  // swiftlint:disable:next cyclomatic_complexity
  static func message(for failure: SubscriptionRefreshFailure) -> String {
    switch failure {
    case .invalidURL:
      return String(localized: "订阅地址无效")
    case .unsupportedScheme:
      return String(localized: "订阅地址必须是 HTTPS")
    case .insecureRedirect:
      return String(localized: "订阅地址重定向到了非 HTTPS 站点，已拒绝")
    case .transport(let category):
      switch category {
      case .timedOut: return String(localized: "订阅获取超时")
      case .tls: return String(localized: "订阅安全连接失败")
      case .connection: return String(localized: "订阅连接失败")
      case .unknown: return String(localized: "订阅获取失败")
      }
    case .httpStatus(let code):
      return String(localized: "订阅服务器返回 HTTP \(code)")
    case .contentType(let category):
      return category == .missing
        ? String(localized: "订阅响应缺少 JSON Content-Type")
        : String(localized: "订阅响应类型不是 JSON")
    case .decodingFailure:
      return String(localized: "订阅内容不是合法的 SIP-008 JSON 文档")
    case .unsupportedSchemaVersion:
      return String(localized: "订阅文档版本不受支持")
    case .missingServers:
      return String(localized: "订阅文档缺少 servers 列表")
    case .recordValidation(let index, let field):
      return String(localized: "订阅第 \(index + 1) 条服务器记录的\(recordFieldName(field))无效")
    case .duplicateIdentity:
      return String(localized: "订阅包含重复的服务器身份")
    case .credential(let category):
      switch category {
      case .missing: return String(localized: "订阅凭据不存在")
      case .read: return String(localized: "订阅凭据读取失败")
      case .write: return String(localized: "订阅凭据写入失败")
      }
    case .commit(let category, let rollback):
      let commitMessage =
        category == .credentials ? String(localized: "订阅凭据提交失败") : String(localized: "订阅快照保存失败")
      switch rollback {
      case .notNeeded: return commitMessage
      case .restored: return String(localized: "\(commitMessage)，旧凭据已恢复")
      case .incomplete: return String(localized: "\(commitMessage)，凭据恢复不完整；最后一次成功快照仍保留")
      }
    case .legacy:
      return String(localized: "订阅刷新失败（旧版失败记录）")
    case .unknown:
      return unknownError
    }
  }

  static func message(for issue: SettingsFieldIssue) -> String {
    switch issue {
    case .port(_, let error):
      return message(for: error)
    }
  }

  static func message(for failure: SettingsWorkflowFailure) -> String {
    switch failure {
    case .store(let error): return settingsStore(error)
    case .unknown: return unknownError
    }
  }

  // 显式白名单 switch，与 message(for:) 同一可审计惯例。
  // swiftlint:disable:next cyclomatic_complexity
  private static func catalog(_ error: CatalogError) -> String {
    switch error {
    case .nodeNotFound: return String(localized: "节点不存在（可能已被删除）")
    case .parentNotFound: return String(localized: "目标分组不存在")
    case .parentNotAGroup: return String(localized: "目标位置不是分组")
    case .notAServer: return String(localized: "该节点不是服务器")
    case .notAGroup: return String(localized: "该节点不是分组")
    case .duplicateID: return String(localized: "节点身份冲突")
    case .crossSourcePlacement(_, let container):
      return container == .subscription
        ? String(localized: "不能把手动节点移入订阅子树") : String(localized: "不能把订阅节点移入手动子树")
    case .subscriptionNodeImmutable: return String(localized: "订阅节点由远端管理：结构、连接字段与名称只读")
    case .subscriptionServerAtRoot: return String(localized: "订阅服务器不能移出其订阅分组")
    case .cycleDetected: return String(localized: "不能把分组移动进它自己的子树")
    case .indexOutOfRange: return String(localized: "插入位置超出范围")
    case .invalidStructure: return String(localized: "配置目录结构不一致")
    }
  }

  static func activation(_ error: ActivationFailure) -> String {
    switch error {
    case .noActiveTarget: return String(localized: "尚未激活任何服务器或分组，请先选择一个目标")
    case .targetNotFound: return String(localized: "活动目标不存在，已清除目标；本地监听不受影响")
    case .targetExpandsToNothing: return String(localized: "目标没有可激活的服务器")
    case .invalidLeaf(let node, let reason):
      return String(localized: "服务器不可用：\(leaf(reason))（\(shortNodeID(node))）")
    }
  }

  private static func leaf(_ reason: LeafInvalidationReason) -> String {
    switch reason {
    case .invalidAddress: return String(localized: "地址无效")
    case .invalidPort: return String(localized: "端口无效")
    case .missingEncryptionMethod: return String(localized: "缺少加密方法")
    case .unsupportedEncryptionMethod: return String(localized: "加密方法不受支持")
    case .pluginNotProvided: return String(localized: "插件未提供")
    case .credentialUnresolved: return String(localized: "凭据不存在")
    case .credentialReadFailed: return String(localized: "凭据读取失败")
    }
  }

  private static func serverForm(_ error: ServerFormError) -> String {
    switch error {
    case .invalidAddress: return String(localized: "服务器地址不能为空")
    case .invalidPort: return String(localized: "端口必须是 1–65535 之间的整数")
    case .missingEncryptionMethod: return String(localized: "必须选择加密方法")
    case .unsupportedEncryptionMethod: return String(localized: "当前 sslocal 不支持该加密方法")
    case .invalidPassword: return String(localized: "密码不能为空")
    case .emptyName: return String(localized: "名称不能为空")
    case .pluginUnknown: return String(localized: "本版本未提供所选插件")
    }
  }

  private static func ssURI(_ error: SsUriError) -> String {
    switch error {
    case .notSsUri: return String(localized: "不是 ss:// 链接")
    case .malformed: return String(localized: "无法解析 ss:// 链接")
    }
  }

  private static func credential(_ error: CredentialStoreError) -> String {
    switch error {
    case .keychainStatus: return String(localized: "钥匙串操作失败")
    case .secretNotUTF8: return String(localized: "钥匙串中的凭据不是文本")
    }
  }

  private static func subscriptionForm(_ error: SubscriptionFormError) -> String {
    switch error {
    case .invalidURL: return String(localized: "订阅地址必须是有效的 HTTPS URL")
    case .notFound: return String(localized: "订阅不存在（可能已被删除）")
    }
  }

  private static func subscriptionFetch(_ error: SubscriptionFetchError) -> String {
    message(for: SubscriptionRefreshFailure.from(fetchError: error))
  }

  private static func subscriptionParse(_ error: SubscriptionParseError) -> String {
    message(for: SubscriptionRefreshFailure.from(parseError: error))
  }

  private static func importLine(_ error: ImportLineFailureReason) -> String {
    switch error {
    case .decode(let error): return ssURI(error)
    case .credential(let error): return credential(error)
    }
  }

  /// 统一导入的来源级失败：解析失败复用订阅解析文案族，提交失败复用
  /// CommitError 口径（含回滚状态），其余点名具体原因。
  private static func importSource(_ error: ImportSourceFailure) -> String {
    switch error {
    case .parse(let error): return subscriptionParse(error)
    case .undecodableImage: return String(localized: "图片无法识别，请使用常见图片格式")
    case .qrPayloadNotFound: return String(localized: "未识别到 ss:// 二维码")
    case .noImportableLines: return String(localized: "没有可导入的 ss:// 链接")
    case .commit(let error): return message(for: error)
    }
  }

  private static func reason(_ error: LegacySkippedRecord.Reason) -> String {
    switch error {
    case .notDictionary: return String(localized: "记录不是字典")
    case .invalidAddress: return String(localized: "服务器地址缺失或无效")
    case .invalidPort: return String(localized: "服务器端口缺失或无效")
    case .invalidEncryptionMethod: return String(localized: "加密方式缺失或无效")
    case .missingPassword: return String(localized: "密码缺失或为空")
    }
  }

  private static func commit(_ error: CommitError) -> String {
    switch error.credentialRollback {
    case .partial:
      return String(localized: "\(message(for: error.underlying))；凭据恢复不完整，请检查配置后重试")
    case .nothingToRestore, .restored:
      return message(for: error.underlying)
    }
  }

  private static func port(_ error: PortSettingError) -> String {
    switch error {
    case .portOutOfRange(let endpoint, let portNumber):
      let port = portNumber.formatted(.number.grouping(.never))
      return String(
        localized:
          "\(endpoint.displayName) 端口 \(port) 无效，必须是 1025–65535 之间的整数"
      )
    case .duplicatePort(let endpoint, let otherEndpoint, let portNumber):
      let port = portNumber.formatted(.number.grouping(.never))
      return
        String(
          localized:
            "\(endpoint.displayName) 端口与 \(otherEndpoint.displayName) 端口冲突（都是 \(port)），请为每个端点配置不同的端口"
        )
    }
  }

  private static func settingsStore(_ error: ProxySettingsStoreError) -> String {
    switch error {
    case .corrupt: return String(localized: "偏好文件损坏")
    case .invalid(let errors): return errors.map(port).joined(separator: "；")
    case .ioFailure: return String(localized: "偏好文件读写失败")
    case .credentialFailure(let detail): return String(localized: "凭据操作失败：\(detail)")
    }
  }

  private static func legacyImport(_ error: LegacyImportError) -> String {
    switch error {
    case .noSnapshot: return String(localized: "没有发现可导入的 Legacy 配置")
    case .alreadyCompleted: return String(localized: "Legacy 配置已经导入；如需再次导入，请明确选择再次导入")
    case .malformedSnapshot: return String(localized: "Legacy 快照无效")
    case .commitFailed: return String(localized: "Legacy 导入未完成，2.0 写入未完成")
    }
  }

  private static func textClipboard(_ error: TextClipboardFailure) -> String {
    switch error {
    case .writeFailed: return String(localized: "剪贴板写入失败，请重试")
    }
  }

  private static func imageClipboard(_ error: ImageClipboardFailure) -> String {
    switch error {
    case .writeFailed: return String(localized: "剪贴板写入失败，请重试")
    }
  }

  private static func qrImageSave(_ error: QrImageSaveFailure) -> String {
    switch error {
    case .writeFailed: return String(localized: "二维码图片写入失败，请选择其他位置或重试")
    }
  }

  private static func diagnosticReport(_ error: DiagnosticReportFailure) -> String {
    switch error {
    case .encodingFailed: return String(localized: "诊断报告无法安全构造，请重试")
    }
  }

  private static func diagnosticReportExport(_ error: DiagnosticReportExportFailure) -> String {
    switch error {
    case .writeFailed: return String(localized: "诊断报告写入失败，请选择其他位置或重试")
    }
  }

  private static func configurationGroupExport(_ error: ConfigurationGroupExportFailure) -> String {
    switch error {
    case .groupNotFound: return String(localized: "分组不存在（可能已被删除）")
    case .targetIsNotGroup: return String(localized: "所选节点不是分组")
    case .noServers: return String(localized: "分组中没有服务器配置")
    case .invalidServer(_, let problem): return invalidServerExport(problem)
    case .credentialUnavailable(_, let credential):
      return credential == .password
        ? String(localized: "服务器密码无法读取，无法导出 SIP-008 文件")
        : String(localized: "插件参数无法读取，无法导出 SIP-008 文件")
    case .pluginOptionsWithoutProgram:
      return String(localized: "服务器配置了插件参数但没有插件名称，无法导出 SIP-008 文件")
    case .documentEncodingFailed:
      return String(localized: "SIP-008 文档生成失败")
    }
  }

  private static func invalidServerExport(_ problem: ConfigurationGroupExportFailure.RecordProblem)
    -> String
  {
    switch problem {
    case .invalidAddress: return String(localized: "服务器地址为空，无法导出 SIP-008 文件")
    case .invalidPort: return String(localized: "服务器端口无效，无法导出 SIP-008 文件")
    case .missingEncryptionMethod: return String(localized: "服务器缺少加密方式，无法导出 SIP-008 文件")
    case .missingPassword: return String(localized: "服务器密码为空，无法导出 SIP-008 文件")
    }
  }

  private static func recordFieldName(_ field: SubscriptionRefreshFailure.RecordField) -> String {
    switch field {
    case .address: return String(localized: "服务器地址")
    case .port: return String(localized: "服务器端口")
    case .method: return String(localized: "加密方法")
    case .password: return String(localized: "密码")
    case .identity: return String(localized: "身份")
    }
  }

  private static func shortNodeID(_ id: NodeID) -> String {
    String(id.rawValue.suffix(8))
  }
}
