import Foundation

/// 内置规则目录：从 bundle 资源加载已固定的 geolocation-cn、
/// china-ipv4 与 gfwlist 快照。普通构建只读本地快照，运行时不抓取或转换；
/// 快照缺失/损坏/版本不匹配时加载失败，不生成空规则 ACL。
struct BuiltinRuleCatalog {
  /// 生产加载缝：bundle 内固定快照（`rules/<source>/snapshot.json`）。
  static func loadGeolocationCN(from bundle: Bundle = .main) throws -> RuleSnapshot {
    try loadSnapshot(named: "geolocation-cn", from: bundle)
  }

  /// china-operator-ip 中国 IPv4 CIDR 直连候选。
  static func loadChinaIPv4(from bundle: Bundle = .main) throws -> RuleSnapshot {
    try loadSnapshot(named: "china-ipv4", from: bundle)
  }

  /// GFWList 代理候选：仅含可准确表达且未被更宽代理规则遮蔽的规则。
  static func loadGFWList(from bundle: Bundle = .main) throws -> RuleSnapshot {
    try loadSnapshot(named: "gfwlist", from: bundle)
  }

  fileprivate static func loadSnapshot(named name: String, from bundle: Bundle) throws
    -> RuleSnapshot
  {
    // folder reference 保留 `rules/<source>/snapshot.json` 目录结构。
    guard
      let url = bundle.url(
        forResource: "snapshot", withExtension: "json", subdirectory: "rules/\(name)")
    else {
      throw RuleSnapshotError.missing
    }
    return try RuleSnapshotStore(fileURL: url).load()
  }

  /// 供 ACL 编译的中国直连候选（`.cn` 后缀 + geolocation-cn + china-ipv4）。
  static func chinaDirectRules(from snapshot: RuleSnapshot) -> [ProxyRule] {
    snapshot.rules.filter { $0.action == .direct }
  }

  /// 合并多份快照的直连候选；保持输入顺序（域名在前，CIDR 在后）。
  static func chinaDirectRules(from snapshots: [RuleSnapshot]) -> [ProxyRule] {
    snapshots.flatMap { chinaDirectRules(from: $0) }
  }

  /// 供 ACL 编译的 GFWList 候选：可准确表达且未被遮蔽的规则
  /// （代理候选 + 未遮蔽例外），两种动作都参与编译。
  static func gfwlistRules(from snapshot: RuleSnapshot) -> [ProxyRule] {
    snapshot.rules
  }
}

/// App-process source facts. Concurrent consumers share one attempt per source;
/// successful bundled snapshots never expire, failed attempts require explicit retry.
actor BuiltinRuleSnapshots {
  typealias Loader = @Sendable (RulesSource) throws -> RuleSnapshot
  private struct Attempt {
    let id: UUID
    let task: Task<RuleSnapshot, Error>
  }
  private let loader: Loader
  private var attempts: [RulesSource: Attempt] = [:]
  private var failures: Set<RulesSource> = []

  init(bundle: Bundle = .main, loader: Loader? = nil) {
    self.loader =
      loader ?? { source in
        guard let kind = source.sourceKind, kind != .custom else {
          throw RuleSnapshotError.missing
        }
        return try BuiltinRuleCatalog.loadSnapshot(named: kind.rawValue, from: bundle)
      }
  }

  func load(_ source: RulesSource, retryFailure: Bool = false) async throws -> RuleSnapshot {
    if retryFailure, failures.remove(source) != nil { attempts[source] = nil }
    let attempt: Attempt
    if let existing = attempts[source] {
      attempt = existing
    } else {
      let loader = loader
      attempt = Attempt(
        id: UUID(),
        task: Task.detached(priority: .userInitiated) {
          let snapshot = try loader(source)
          guard let kind = source.sourceKind, kind != .custom else {
            throw RuleSnapshotError.missing
          }
          guard snapshot.metadata.source.kind == kind
          else { throw RuleSnapshotError.corrupt(detail: "Unexpected rule source") }
          return snapshot
        })
      attempts[source] = attempt
    }
    do {
      return try await attempt.task.value
    } catch {
      if attempts[source]?.id == attempt.id { failures.insert(source) }
      throw error
    }
  }

  func browsingSources(retryFailures: Bool = false) async -> [RulesSource: Result<
    RuleSnapshot, Error
  >] {
    var results: [RulesSource: Result<RuleSnapshot, Error>] = [:]
    for source in [RulesSource.geolocationCN, .chinaIPv4, .gfwlist] {
      do { results[source] = .success(try await load(source, retryFailure: retryFailures)) } catch {
        results[source] = .failure(error)
      }
    }
    return results
  }
}
