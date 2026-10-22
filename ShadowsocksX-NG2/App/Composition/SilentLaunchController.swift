import SwiftUI

/// 静默启动偏好（ADR 0017）：启动时不呈现主窗口，直接以菜单栏形态后台运行。
/// 默认关；切换即持久化，当次会话无影响，下次启动生效。代理运行时恢复与
/// 登录项注册都不依赖它。持久化走应用 defaults 域，与监听文件分别管理。
@MainActor
final class SilentLaunchController: ObservableObject {
  @Published private(set) var isEnabled: Bool

  private let store: SilentLaunchStore

  init(store: SilentLaunchStore) {
    self.store = store
    isEnabled = store.loadSilentLaunchEnabled()
  }

  /// 先落盘后翻转内存态：开关呈现不得与下次启动的实际行为脱节。UserDefaults
  /// 无失败信号（cfprefsd 尽力而为），文件版的失败点名路径随迁移移除。
  func setEnabled(_ enabled: Bool) {
    store.save(silentLaunchEnabled: enabled)
    isEnabled = enabled
  }
}
