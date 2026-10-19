import Foundation

/// 敏感配置文件的原子写盘基线：目录 0700（含自愈）、临时文件
/// 创建即 0600、写全校验后原子替换；任一步失败保留原文件。catalog.enc、
/// activation.json 与其他运行时文件共用同一物理安全基线。
enum AtomicFileWriter {
  enum WriteError: Error, Equatable {
    case failure(detail: String)
  }

  /// 隐藏暂存名约定 `.<name>.tmp-<uuid>` 的唯一出处：write 内部使用，同目录
  /// 内的 symlink 暂存也由此派生，保证泄漏的暂存项能被 `isResidueName` 识别。
  static func temporaryURL(for targetURL: URL) -> URL {
    targetURL.deletingLastPathComponent()
      .appendingPathComponent(".\(targetURL.lastPathComponent).tmp-\(UUID().uuidString)")
  }

  /// 目录项是否为本写入器的暂存残留（宽松匹配：0700 私有目录内过扫无害）。
  static func isResidueName(_ name: String) -> Bool {
    name.hasPrefix(".") && name.contains(".tmp-")
  }

  /// 新建的父目录同样使用 0700；已有目标目录修复权限后才允许写入。
  static func prepareDirectory(at directory: URL) throws {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
  }

  /// 把 `data` 原子写入 `fileURL`（含父目录创建与 0700 基线自愈）。
  static func write(_ data: Data, to fileURL: URL) throws {
    do {
      try prepareDirectory(at: fileURL.deletingLastPathComponent())
    } catch {
      throw WriteError.failure(detail: String(describing: error))
    }
    let temporaryURL = temporaryURL(for: fileURL)
    if !FileManager.default.createFile(
      atPath: temporaryURL.path,
      contents: data,
      attributes: [.posixPermissions: 0o600]
    ) {
      throw WriteError.failure(detail: "无法创建临时文件 \(temporaryURL.path)")
    }
    do {
      if FileManager.default.fileExists(atPath: fileURL.path) {
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporaryURL)
      } else {
        try FileManager.default.moveItem(at: temporaryURL, to: fileURL)
      }
    } catch {
      try? FileManager.default.removeItem(at: temporaryURL)
      throw WriteError.failure(detail: String(describing: error))
    }
  }
}
