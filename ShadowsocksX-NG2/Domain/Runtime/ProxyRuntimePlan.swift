import Foundation

/// LaunchAgent 注册态（GUI 视角）：SMAppService.Status 的纯域
/// 映射。SMAppService 不暴露运行中 agent 的 pid，wrapper 活性另由
/// `WrapperProcessState` 表达。
enum LaunchAgentStatus: Equatable, Sendable {
  case notRegistered
  /// 已注册（无论 wrapper 进程当前是否在运行）。
  case registered
  /// 需要用户在系统设置的登录项中批准。
  case requiresApproval
  /// 注册清单缺失（bundle 内 plist 不在）。
  case notFound
}

/// wrapper 进程活性：GUI 读 `agent.pid` 并以 `kill(pid, 0)` 判定。
enum WrapperProcessState: Equatable, Sendable {
  case notRunning
  case running(pid: Int32)
}

/// GUI 对代理运行时的意图：运行给定义档，或停止并清理。
enum RuntimeIntent: Equatable {
  case run(SslocalRuntimeDocument)
  case stop
}

/// 控制器按序执行的动作。
enum RuntimeAction: Equatable, Sendable {
  /// 原子写契约文件（权限与替换基线由 RuntimeFileStore 保证）。
  case writeContract
  /// 注册 LaunchAgent；launchd 随即拉起 wrapper，wrapper 启动时读契约。
  case registerAgent
  /// 注销 LaunchAgent：launchd 以 SIGTERM 结束 wrapper，触发显式停止协议
  /// （wrapper 停 sslocal 并等待退出）。
  case unregisterAgent
  /// 通知运行中的 wrapper 重读契约；热重载或优雅重启由 wrapper 按监听
  /// 指纹判定遵循变更协议。
  case signalReload(pid: Int32)
  /// 删除运行时文件（契约、pid 文件与残留临时文件）。
  case deleteRuntimeFiles
}

/// 纯决策层：把「代理意图 + launchd 注册态 + wrapper 活性
/// + 磁盘契约」推到有序动作序列。GUI 启动重同步、目录提交重展开与代理开关
/// 共用同一决策；相同契约内容跳过写入，兑现激活状态机的幂等注记。
enum ProxyRuntimePlan {
  static func actions(
    intent: RuntimeIntent,
    agentStatus: LaunchAgentStatus,
    wrapper: WrapperProcessState,
    configurationIsCurrent: Bool
  ) -> [RuntimeAction] {
    switch intent {
    case .run:
      switch agentStatus {
      case .notRegistered, .notFound, .requiresApproval:
        // 首次启用或从未注册：写盘后注册，launchd 拉起的 wrapper 直接读新档。
        return [.writeContract, .registerAgent]
      case .registered:
        switch wrapper {
        case .running(let pid):
          if configurationIsCurrent { return [] }
          return [.writeContract, .signalReload(pid: pid)]
        case .notRunning:
          // 已注册但 wrapper 已干净退出（如契约曾被清理）：强制重新拉起。
          // SMAppService 对已注册服务重复 register 不保证重跑，先注销再注册。
          return [.writeContract, .unregisterAgent, .registerAgent]
        }
      }
    case .stop:
      switch agentStatus {
      case .registered:
        // 显式停止协议次序：注销即 SIGTERM wrapper → wrapper 停 sslocal
        // 并等待 → 控制器确认 wrapper 退出后才删文件（执行侧保证次序）。
        return [.unregisterAgent, .deleteRuntimeFiles]
      case .notRegistered, .requiresApproval, .notFound:
        return [.deleteRuntimeFiles]
      }
    }
  }
}
