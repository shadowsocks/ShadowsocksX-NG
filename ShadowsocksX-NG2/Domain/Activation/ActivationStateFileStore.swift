import Foundation

/// 活动目标持久化：落盘 `~/Library/Application Support/
/// ShadowsocksX-NG2/activation.json`，权限与原子替换基线同 catalog.json。
/// 只含目标身份，永不落秘密明文。损坏或版本未知按安全侧恢复为「无活动目标」
/// （代理保持停止，由状态机重校验同步）；文件系统级错误仍抛出。
struct ActivationStateFileStore {
  enum PersistenceError: Error, Equatable {
    /// 读取或写入时的文件系统错误。
    case ioFailure(detail: String)
  }

  private static let currentVersion = 1
  private static let jsonEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }()

  let fileURL: URL

  /// 默认位置：`~/Library/Application Support/ShadowsocksX-NG2/activation.json`。
  static func defaultFileURL() -> URL {
    RuntimePaths.activationStateFileURL()
  }

  /// 文件缺失/损坏/版本未知 → `nil`（安全侧：无活动目标）。
  func loadActiveTargetID() throws -> NodeID? {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
    let data: Data
    do {
      data = try Data(contentsOf: fileURL)
    } catch {
      throw PersistenceError.ioFailure(detail: String(describing: error))
    }
    let payload = try? JSONDecoder().decode(ActivationStatePayload.self, from: data)
    guard let payload, payload.version == Self.currentVersion else { return nil }
    return payload.activeTargetID
  }

  /// 整体重写并原子替换；失败时保留原文件。目录权限强制为 0700（含自愈）。
  func save(activeTargetID: NodeID?) throws {
    let data: Data
    do {
      data = try Self.jsonEncoder.encode(
        ActivationStatePayload(version: Self.currentVersion, activeTargetID: activeTargetID))
    } catch {
      throw PersistenceError.ioFailure(detail: String(describing: error))
    }
    do {
      try AtomicFileWriter.write(data, to: fileURL)
    } catch {
      throw PersistenceError.ioFailure(detail: String(describing: error))
    }
  }
}

/// 落盘文档形态：版本号 + 活动目标身份（可为 null）。
private struct ActivationStatePayload: Codable {
  var version: Int
  var activeTargetID: NodeID?
}
