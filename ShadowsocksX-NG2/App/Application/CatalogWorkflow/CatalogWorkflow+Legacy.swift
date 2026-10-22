import Foundation

/// Legacy 导入编排：读取当前不可变快照、经导入服务原子提交
/// 携带秘密的手动记录，随后对齐已提交状态并发布结构化报告。导入不启动代理、
/// 不写系统代理设置、不触发普通目录提交的运行时收敛；导入后的
/// 2.0 自身运行时边界由组合根注入的 `postLegacyImport` 闭包一次性接线。
extension CatalogWorkflow {
  /// 显式请求导入：`reimport` 为 `false` 时导入首次发现的
  /// 快照（成功后不再自动重复）；`true` 时读取当前快照创建新的独立手动分组。
  /// 返回含新建分组身份的结构化导入报告（导入/跳过/身份重生成计数），秘密值
  /// 不出现在报告中；分组身份供统一导入面板成功后选中。
  @discardableResult
  func importLegacy(reimport: Bool = false) async throws -> LegacyImportOutcome {
    let snapshot: LegacySnapshot
    if reimport {
      guard let current = try dependencies.legacyImportService.readSnapshot() else {
        throw LegacyImportError.noSnapshot
      }
      snapshot = current
    } else if let discoveredLegacySnapshot {
      snapshot = discoveredLegacySnapshot
    } else {
      guard let current = try dependencies.legacyImportService.readSnapshot() else {
        throw LegacyImportError.noSnapshot
      }
      snapshot = current
    }
    let outcome = try dependencies.legacyImportService.importSnapshot(
      snapshot, reimport: reimport)
    // 导入服务独立落盘各 store 后对齐内存已提交状态；不经普通提交管线，
    // 因此不触发运行时收敛。
    dependencies.coordinator.reloadCommittedStateFromStore()
    republishCommittedState()
    refreshLegacyImportState()
    await dependencies.postLegacyImport?(outcome)
    return outcome
  }

  /// 重读磁盘发现状态，不写任何标记或 Legacy 数据。
  func refreshLegacyImportState() {
    let completed = (try? dependencies.legacyImportService.isCompleted()) ?? false
    discoveredLegacySnapshot = try? dependencies.legacyImportService.readSnapshot()
    publishLegacyImportState(
      LegacyImportAvailability(
        snapshotFound: discoveredLegacySnapshot != nil, completed: completed))
  }
}
