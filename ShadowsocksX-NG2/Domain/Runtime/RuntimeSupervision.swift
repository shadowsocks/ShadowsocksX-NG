import Darwin
import Foundation

/// Agent 的输入只包含非秘密运行事实。部署身份为随机值，不从凭据或配置摘要派生。
struct RuntimeSupervision: Codable, Equatable, Sendable {
  struct Endpoint: Codable, Equatable, Sendable {
    let inboundProtocol: String
    let localAddress: String
    let localPort: Int
    let mode: String

    var probeHost: String {
      switch localAddress {
      case "0.0.0.0": "127.0.0.1"
      case "::": "::1"
      default: localAddress
      }
    }
  }

  struct ACL: Codable, Equatable, Sendable {
    let file: String
    let sha256: String
    let size: Int
  }

  let version: Int
  let generation: UInt64
  let deploymentID: String
  let configuration: String
  /// 配置字节未变时复用的随机身份；旧监管资料缺失时保守重载配置。
  let configurationID: String?
  /// GUI 私有意图摘要的同代文件；Agent 只保留引用，不读取正文。
  let intentMetadata: String
  let locals: [Endpoint]
  let ipv6Only: Bool?
  let authenticationID: String?
  let authenticationFiles: [String]
  let acl: ACL?
  let aclVariants: [String: ACL]

  var retainedFiles: Set<String> {
    Set([configuration, intentMetadata] + authenticationFiles + aclVariants.values.map(\.file))
      .union(acl.map { [$0.file] } ?? [])
  }

  func requiresRestart(from old: Self) -> Bool {
    locals != old.locals || ipv6Only != old.ipv6Only
      || authenticationID != old.authenticationID
  }

  func reloadSignals(from old: Self) -> Set<Int32> {
    var signals = Set<Int32>()
    if configurationID == nil || configurationID != old.configurationID {
      signals.insert(SIGUSR1)
    }
    if acl != old.acl { signals.insert(SIGUSR2) }
    return signals
  }

  var hasValidStructure: Bool {
    guard version == 2, generation > 0, UUID(uuidString: deploymentID) != nil,
      configuration.hasPrefix("config-"), intentMetadata.hasPrefix("config-"),
      RuntimePublication.generation(of: configuration) == generation,
      RuntimePublication.generation(of: intentMetadata) == generation,
      configuration != intentMetadata,
      configurationID.map({ UUID(uuidString: $0) != nil }) ?? true,
      authenticationFiles.allSatisfy({ $0.hasPrefix("auth-") && $0.hasSuffix(".json") }),
      aclVariants.values.allSatisfy({ $0.file.hasPrefix("acl-") && $0.file.hasSuffix(".ini") }),
      authenticationID.map({ UUID(uuidString: $0) != nil }) ?? true,
      authenticationFiles.count == (authenticationID == nil ? 0 : 2),
      [2, 4].contains(locals.count),
      Set(locals.map(\.localPort)).count == locals.count,
      locals.allSatisfy({
        (1025...65535).contains($0.localPort)
          && ["socks", "http"].contains($0.inboundProtocol)
          && ["127.0.0.1", "0.0.0.0", "::"].contains($0.localAddress)
          && ["tcp_only", "tcp_and_udp"].contains($0.mode)
      }),
      retainedFiles.allSatisfy({ name in
        guard let fileGeneration = RuntimePublication.generation(of: name),
          fileGeneration <= generation
        else { return false }
        return true
      })
    else { return false }
    return true
  }
  func validated(in directory: URL) -> Bool {
    hasValidStructure
      && retainedFiles.allSatisfy {
        RuntimePublication.isRegularFile(directory.appendingPathComponent($0))
      }
  }

}

/// 发布、引用复用和回收共享同一把 flock。Agent 持有旧快照时，回收还必须合并
/// 锁内读取的最新发布引用；GUI 只能从该发布引用复用，不能复活已退休文件。
enum RuntimePublication {
  static func withLock<T>(in directory: URL, _ body: () throws -> T) throws -> T {
    try AtomicFileWriter.prepareDirectory(at: directory)
    let descriptor = open(
      RuntimePaths(directoryURL: directory).publicationLockURL.path,
      O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
    guard descriptor >= 0 else { throw POSIXError(.EIO) }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else { throw POSIXError(.EIO) }
    defer { flock(descriptor, LOCK_UN) }
    return try body()
  }

  static func generation(of name: String) -> UInt64? {
    let parts = name.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count >= 3, ["config", "acl", "auth"].contains(String(parts[0])),
      parts[1].count == 20, parts[1].allSatisfy(\.isNumber),
      !name.contains("/"), !name.contains("..")
    else { return nil }
    return UInt64(parts[1])
  }

  static func isRegularFile(_ url: URL) -> Bool {
    (try? FileManager.default.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType
      == .typeRegular
  }

  /// 身份读取不依赖运行资源是否仍存在，缺失资源不得解除持久失败屏障。
  static func metadata(at url: URL) -> RuntimeSupervision? {
    guard let data = try? Data(contentsOf: url),
      let value = try? JSONDecoder().decode(RuntimeSupervision.self, from: data),
      value.hasValidStructure
    else { return nil }
    return value
  }

  static func load(at url: URL) -> RuntimeSupervision? {
    guard let value = metadata(at: url), value.validated(in: url.deletingLastPathComponent())
    else { return nil }
    return value
  }

  static func select(_ snapshot: RuntimeSupervision, configurationLink: URL, aclLink: URL) throws {
    let directory = configurationLink.deletingLastPathComponent()
    try withLock(in: directory) {
      guard snapshot.validated(in: directory) else { throw POSIXError(.EINVAL) }
      if let acl = snapshot.acl { try link(acl.file, at: aclLink) }
      try link(snapshot.configuration, at: configurationLink)
    }
  }

  private static func link(_ name: String, at url: URL) throws {
    let temporary = AtomicFileWriter.temporaryURL(for: url)
    defer { try? FileManager.default.removeItem(at: temporary) }
    try FileManager.default.createSymbolicLink(atPath: temporary.path, withDestinationPath: name)
    guard rename(temporary.path, url.path) == 0,
      ACLActiveLinkPolicy.resolvesToRegularFile(
        inside: url.deletingLastPathComponent(), linkURL: url)
    else { throw POSIXError(.EIO) }
  }

  /// 唯一回收者是 Agent。活进程与已选择快照引用由调用方传入；持锁保护扫描、
  /// 最新发布读取及删除的整个区间，避免 GUI 在扫描后重新引用退休文件。
  static func retire(
    before snapshot: RuntimeSupervision, publishedAt url: URL,
    protecting: Set<String>
  ) throws {
    let directory = url.deletingLastPathComponent()
    try withLock(in: directory) {
      guard let published = load(at: url) else { throw POSIXError(.EINVAL) }
      let keep = protecting.union(snapshot.retainedFiles).union(published.retainedFiles)
      for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
        guard let generation = generation(of: name), generation < snapshot.generation,
          !keep.contains(name)
        else { continue }
        try FileManager.default.removeItem(at: directory.appendingPathComponent(name))
      }
    }
  }
}

/// Receipt records Agent operations and listener ownership, not upstream application acknowledgement.
struct RuntimeDeploymentReceipt: Codable, Equatable, Sendable {
  let processID: Int32
  let deploymentID: String
}

/// Both processes preserve a confirmed failure until an explicit retry or a new intent.
struct RuntimeDeploymentFailure: Codable, Equatable, Sendable {
  let deploymentID: String
  let reason: String
}
