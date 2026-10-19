import Foundation

/// 静默启动偏好持久化（ADR 0017）：存于应用标准 defaults 域（键
/// `silentLaunch`）的 GUI 呈现偏好，与代理控制偏好和监听配置分别管理。
/// 键缺失或外部错误类型按安全侧默认「不静默」（启动照常呈现主窗口）。
/// ADR 0017 初版为独立 JSON 文件，发布链从未包含该形态，仅存量开发机文件
/// 需一次性迁移（`migrateLegacyFileIfPresent`）。
struct SilentLaunchStore {
  private static let key = "silentLaunch"
  /// ADR 0017 初版（文件形态）的落盘位置，仅迁移路径使用。
  static let legacyFileURL = RuntimePaths.silentLaunchLegacyFileURL()

  private static let currentVersion = 1

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

  /// 一次性迁移（初版文件形态 → defaults）：文件存在则读取 v1 值写入 defaults
  /// 后删除文件；损坏或版本未知不写入（安全侧默认），文件仍删除。
  static func migrateLegacyFileIfPresent(at fileURL: URL, into defaults: UserDefaults) {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
    let payload = try? JSONDecoder().decode(
      SilentLaunchPayload.self, from: Data(contentsOf: fileURL))
    if let payload, payload.version == currentVersion {
      defaults.set(payload.silentLaunchEnabled, forKey: key)
    }
    try? FileManager.default.removeItem(at: fileURL)
  }
}

/// 初版文件形态的落盘文档：版本号 + 偏好布尔（仅迁移读取）。
private struct SilentLaunchPayload: Codable {
  var version: Int
  var silentLaunchEnabled: Bool
}
