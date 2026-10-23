import Combine
import Foundation
import Observation

/// 状态显示 debounce 呈现模型：首页运行控制卡与菜单栏状态卡共用的两个意图
/// （代理服务、系统代理）状态呈现，从代理控制工作流的整体 snapshot 派生
/// payload 后经瞬态门控发布。稳定态（已应用/失败/待批准等）立即可见；瞬态
/// （启动中/应用中/修复中）延迟上屏、短命即被吞掉，已上屏瞬态保持最短时
/// 长——快速切换代理模式这类多数瞬间成功的操作不再让状态行闪中间态。
/// 行、色调与点名 detail 复用 StatusCardModel 的既有口径，此处只做派生
/// 捆绑（hint 一并随系统代理流更新，行与说明文案不会短暂不一致）。
@Observable
@MainActor
final class StatusDisplayModel {
  /// 代理服务意图的状态呈现：状态行与点名原因。
  struct AgentStatus: Equatable {
    let row: StatusCardModel.Row
    let detail: StatusCardModel.DetailLine?
  }

  /// 系统代理意图的状态呈现：状态行、点名原因与运行控制卡说明文案。
  struct SystemProxyStatus: Equatable {
    let row: StatusCardModel.Row
    /// 点名原因不在此抑制：面板把它作为暂停说明行渲染，首页按 isPaused
    /// 抑制（沿两侧原有口径）。
    let detail: StatusCardModel.DetailLine?
    let hint: String
    /// 已暂停时详情与提示文案重复（hint 已是暂停说明），首页据此不渲染
    /// detail；面板无 hint，仍渲染 detail 作为暂停说明。
    let isPaused: Bool
  }

  private(set) var agent: AgentStatus
  private(set) var systemProxy: SystemProxyStatus

  private let agentGate: TransientDelayGate<AgentStatus>
  private let systemProxyGate: TransientDelayGate<SystemProxyStatus>
  private var cancellables: Set<AnyCancellable> = []

  /// 当前排队的迟显任务；无排队为 nil。供测试等待迟显完成。
  var scheduledAgentDisplayTask: Task<Void, Never>? { agentGate.scheduledDisplayTask }
  var scheduledSystemProxyDisplayTask: Task<Void, Never>? {
    systemProxyGate.scheduledDisplayTask
  }

  /// 生产接线：订阅代理控制工作流的整体 snapshot 发布。
  convenience init(
    control: ProxyControlWorkflow,
    interval: TimeInterval = 0.4,
    now: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate },
    sleep: @escaping (TimeInterval) async throws -> Void = {
      try await Task.sleep(for: .seconds($0))
    }
  ) {
    self.init(snapshots: control.$snapshot, interval: interval, now: now, sleep: sleep)
  }

  /// 测试缝：直接注入 snapshot 流（订阅即送达当前值，两流首值立即上屏）。
  init<Snapshots: Publisher>(
    snapshots: Snapshots,
    interval: TimeInterval = 0.4,
    now: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate },
    sleep: @escaping (TimeInterval) async throws -> Void = {
      try await Task.sleep(for: .seconds($0))
    }
  ) where Snapshots.Output == ProxyControlSnapshot, Snapshots.Failure == Never {
    agent = AgentStatus(row: .init(label: "", text: "", tone: .neutral), detail: nil)
    systemProxy = SystemProxyStatus(
      row: .init(label: "", text: "", tone: .neutral), detail: nil, hint: "", isPaused: false)
    agentGate = TransientDelayGate(interval: interval, now: now, sleep: sleep)
    systemProxyGate = TransientDelayGate(interval: interval, now: now, sleep: sleep)
    // 存储属性至此完整初始化，显示回调才可捕获 self。
    agentGate.display = { [weak self] in self?.agent = $0 }
    systemProxyGate.display = { [weak self] in self?.systemProxy = $0 }
    // 订阅即送达当前 snapshot：两流首值立即上屏（门控首值语义）。
    snapshots
      .sink { [weak self] snapshot in self?.handle(snapshot) }
      .store(in: &cancellables)
  }

  private func handle(_ snapshot: ProxyControlSnapshot) {
    agentGate.update(
      Self.agentStatus(from: snapshot),
      isTransient: snapshot.runtime.status == .starting)
    systemProxyGate.update(
      Self.systemProxyStatus(from: snapshot),
      isTransient: Self.isSystemProxyTransient(snapshot.systemProxyApplication))
  }

  // MARK: - payload 派生

  static func agentStatus(from snapshot: ProxyControlSnapshot) -> AgentStatus {
    let card = StatusCardModel.card(from: snapshot)
    return AgentStatus(row: card.runtimeRow, detail: card.runtimeDetail)
  }

  static func systemProxyStatus(from snapshot: ProxyControlSnapshot) -> SystemProxyStatus {
    let card = StatusCardModel.card(from: snapshot)
    return SystemProxyStatus(
      row: card.systemProxyRow,
      detail: card.systemProxyDetail,
      hint: systemProxyHint(from: snapshot),
      isPaused: snapshot.systemProxyApplication == .paused)
  }

  /// 系统代理侧瞬态 = 正在写入/修复系统代理配置；pending（待批准/待应用）是
  /// 需要用户行动的 resting 态，不算瞬态。
  static func isSystemProxyTransient(_ application: SystemProxyApplicationFacts) -> Bool {
    application == .applying || application == .repairing
  }

  /// 运行控制卡的说明文案（原视图内派生移入，随系统代理流一起门控/去重）。
  private static func systemProxyHint(from snapshot: ProxyControlSnapshot) -> String {
    let exitRequirement =
      snapshot.proxyMode == .direct
      ? String(localized: "直连模式不依赖活动服务器")
      : String(localized: "规则/全局模式需要可用的活动服务器")
    if snapshot.systemProxyApprovalRequired {
      return String(localized: "系统代理助手等待批准。请在系统设置 → 登录项与扩展中允许。")
    }
    return switch snapshot.systemProxyApplication {
    case .idle:
      String(localized: "开启后让 macOS 系统代理指向本地入口；\(exitRequirement)")
    case .pending:
      String(localized: "已请求应用系统代理，等待本地入口就绪；\(exitRequirement)")
    case .applied:
      String(localized: "系统代理已指向本地入口")
    case .failed, .repairFailed, .clearFailed:
      String(localized: "操作失败，原因见下方")
    case .paused:
      AppPresentation.systemProxyPausedNotice
    case .changed:
      String(localized: "当前系统代理配置与预期存在差异")
    case .unreadable:
      String(localized: "无法检查当前系统代理配置")
    case .applying:
      String(localized: "正在应用系统代理配置…")
    case .repairing:
      String(localized: "正在修复系统代理配置…")
    }
  }
}
