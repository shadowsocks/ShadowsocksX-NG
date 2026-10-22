import Foundation

/// 静默启动偏好持久化（ADR 0017）：存于应用标准 defaults 域（键
/// `silentLaunch`）的 GUI 呈现偏好，与代理控制偏好和监听配置分别管理。
/// 键缺失或外部错误类型按安全侧默认「不静默」（启动照常呈现主窗口）。
/// 初版开发文件不再迁移，旧平铺目录保持不变。
struct SilentLaunchStore {
  private static let key = "silentLaunch"
  let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// 键缺失或外部错误类型（无法按 Bool 桥接）→ `false`（安全侧：不静默），
  /// 严格性与初版文件形态的 decode 一致，无需 register(defaults:)。
  func loadSilentLaunchEnabled() -> Bool {
    defaults.object(forKey: Self.key) as? Bool ?? false
  }

  /// UserDefaults 无失败信号：极端落盘失败表现为下次启动回退默认（尽力而为，
  /// ADR 0017 修正后放弃文件版的失败点名路径）。
  func save(silentLaunchEnabled: Bool) {
    defaults.set(silentLaunchEnabled, forKey: Self.key)
  }

}
