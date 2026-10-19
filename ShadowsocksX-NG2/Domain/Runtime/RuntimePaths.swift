import Foundation

/// GUI 发布与 Agent 监管共享的运行目录规则；所有受管引用保持在同一目录。
struct RuntimePaths {
  let fileURL: URL

  init(directoryURL: URL) {
    fileURL = directoryURL.appendingPathComponent("sslocal-active.json")
  }

  init(fileURL: URL) {
    self.fileURL = fileURL
  }

  var directoryURL: URL { fileURL.deletingLastPathComponent() }
  var supervisionFileURL: URL { directoryURL.appendingPathComponent("agent-supervision.json") }
  var failureFileURL: URL { directoryURL.appendingPathComponent("agent-deployment-failure.json") }
  var pidFileURL: URL { directoryURL.appendingPathComponent("agent.pid") }
  var childPIDFileURL: URL { directoryURL.appendingPathComponent("sslocal.pid") }
  var aclFileURL: URL { directoryURL.appendingPathComponent("acl-active.ini") }
  var runtimeStatusFileURL: URL { directoryURL.appendingPathComponent("agent-runtime-status.json") }
  var generationFileURL: URL { directoryURL.appendingPathComponent("runtime-generation") }
  var publicationLockURL: URL { directoryURL.appendingPathComponent("runtime.lock") }
  var agentLockURL: URL { directoryURL.appendingPathComponent("agent.lock") }

  /// 停止只清理部署产物；高水位和两把锁跨停止保留。
  var removableFileNames: Set<String> {
    Set(
      [
        fileURL, supervisionFileURL, failureFileURL, pidFileURL, childPIDFileURL,
        aclFileURL, runtimeStatusFileURL,
      ].map(\.lastPathComponent))
  }
}

/// ACL 活动链接的防逃逸校验（ADR-0011）：解析 symlink 后必须仍是运行目录
/// 内的普通文件。目录与目标都做 symlink 解析，避免 `/var` vs `/private/var`
/// 造成假阴性。GUI 写入侧与 Agent 加载侧共用此判定。
enum ACLActiveLinkPolicy {
  static func resolvesToRegularFile(inside directory: URL, linkURL: URL) -> Bool {
    let fileManager = FileManager.default
    let linkPath = linkURL.standardizedFileURL.path
    guard fileManager.fileExists(atPath: linkPath) else { return false }
    let resolved = URL(fileURLWithPath: linkPath).resolvingSymlinksInPath().standardizedFileURL
    let resolvedDirectory = URL(fileURLWithPath: directory.path).resolvingSymlinksInPath()
      .standardizedFileURL.path
    guard resolved.path == resolvedDirectory || resolved.path.hasPrefix(resolvedDirectory + "/")
    else { return false }
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory) else {
      return false
    }
    return !isDirectory.boolValue
  }
}
