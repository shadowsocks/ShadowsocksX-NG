import Foundation

// MARK: - 运行时失败事实的呈现（RuntimeFailureFacts / 系统代理应用态）

extension AppPresentation {
  /// 系统代理暂停的统一文案：状态菜单、运行控制卡与错误呈现边三面共用。
  static let systemProxyPausedNotice = String(localized: "后台代理不可用，已清除系统代理配置。恢复后将自动应用。")

  /// 系统代理配置不可读的统一前缀：状态菜单与运行控制卡差异区共用。
  static let systemProxyUnreadablePrefix = String(localized: "无法读取网络接口的代理配置：")

  static func message(for failure: RuntimeFailureFacts) -> String {
    switch failure {
    case .firewallBlocked(let facts):
      return
        String(localized: "macOS 防火墙已阻止 \(facts.executableName) 接受传入连接。请在系统设置中允许传入连接。")
    case .launch(let facts): return launchFailure(facts)
    case .service(let facts): return serviceFailure(facts)
    case .activation(let error): return activation(error)
    case .requiresApproval: return String(localized: "请在系统设置的登录项中允许代理后台服务")
    case .systemProxy(let facts): return systemProxyFailure(facts)
    }
  }

  static func message(for application: SystemProxyApplicationFacts) -> String {
    switch application {
    case .idle: return String(localized: "系统代理未应用")
    case .pending: return String(localized: "系统代理待应用：等待代理就绪或可用出口")
    case .applied: return String(localized: "系统代理已应用")
    case .failed(let facts), .repairFailed(let facts), .clearFailed(let facts),
      .unreadable(let facts):
      return systemProxyFailure(facts)
    case .changed: return String(localized: "系统代理配置已改变")
    case .applying: return String(localized: "系统代理应用中")
    case .repairing: return String(localized: "系统代理修复中")
    case .paused: return systemProxyPausedNotice
    }
  }

  private static func launchFailure(_ facts: LaunchFailureFacts) -> String {
    switch facts {
    case .missingRuntimeDocument: return String(localized: "缺少运行时文档")
    case .localEndpoint(let endpoint, let host, let port, let cause):
      let endpointName = endpoint.uppercased()
      let portText = port.formatted(.number.grouping(.never))
      let failureText = endpointFailure(cause)
      return String(
        localized:
          "本地代理 \(endpointName) 端点 \(host):\(portText) 未就绪（\(failureText)）"
      )
    case .unreadableSettings: return String(localized: "本地代理配置无法读取，未应用新的代理配置")
    }
  }

  private static func serviceFailure(_ facts: ServiceFailureFacts) -> String {
    switch facts {
    case .runtimeFile: return String(localized: "运行时文件读写失败")
    case .agent: return String(localized: "代理后台服务管理失败")
    case .missingDocument: return String(localized: "缺少运行时文档")
    case .persistence: return String(localized: "代理运行状态保存失败")
    case .unknown: return unknownError
    }
  }

  private static func systemProxyFailure(_ facts: SystemProxyFailureFacts) -> String {
    switch facts {
    case .operation(let failure): return systemProxy(failure)
    case .unknown: return String(localized: "系统代理未能应用")
    }
  }

  // 系统代理操作失败的唯一文案映射（ErrorPresentation 的 SystemProxyError
  // 分支经 SystemProxyOperationFailure(error) 桥接到这里）。
  // swiftlint:disable:next cyclomatic_complexity
  static func systemProxy(_ failure: SystemProxyOperationFailure) -> String {
    switch failure {
    case .preferencesUnavailable: return String(localized: "系统网络配置不可用")
    case .preferencesBusy: return String(localized: "系统网络配置正被其他设置操作占用")
    case .noCurrentNetworkSet: return String(localized: "没有当前网络位置")
    case .noNetworkLocations: return String(localized: "没有可检查的网络位置")
    case .noProxyServices: return String(localized: "当前网络位置没有可写入的网络服务")
    case .unreadableService: return String(localized: "无法读取网络服务的代理配置")
    case .invalidStoredConfiguration: return String(localized: "保存的系统代理配置无效")
    case .cannotWriteService: return String(localized: "无法写入网络服务的代理配置")
    case .commitFailed: return String(localized: "系统代理提交失败")
    case .applyFailed: return String(localized: "系统代理应用失败")
    case .invalidRequest: return String(localized: "系统代理助手收到了无效请求")
    case .helperUnavailable: return String(localized: "系统代理助手不可用；请确认已在登录项中允许")
    }
  }

  private static func endpointFailure(_ outcome: RuntimeEndpointFailure) -> String {
    switch outcome {
    case .refused: return String(localized: "连接被拒绝")
    case .timedOut: return String(localized: "连接超时")
    case .invalidResponse: return String(localized: "响应无效")
    case .unknown: return String(localized: "状态无法确定")
    }
  }
}

extension AppPresentation {
  /// The diagnostic window localizes status without changing exported report text.
  static func diagnosticStatus(_ state: DiagnosticProxyState) -> String {
    switch state {
    case .off: String(localized: "已停止")
    case .starting: String(localized: "启动中")
    case .running: String(localized: "运行中")
    case .firewallBlocked: String(localized: "已被 macOS 应用防火墙拦截（主机地址态）")
    case .launchFailed: String(localized: "启动失败（本地代理端点未就绪）")
    case .activationFailed(let reason): String(localized: "激活失败：\(reason)")
    case .requiresApproval: String(localized: "等待在系统设置-登录项中批准")
    case .serviceFailed: String(localized: "服务管理失败")
    case .systemProxyFailed: String(localized: "系统代理未应用")
    }
  }
}
