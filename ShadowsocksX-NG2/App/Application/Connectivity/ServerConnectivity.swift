import Combine
import Foundation

/// Process-lifetime observations. Secrets stay inside the configuration adapter.
@MainActor
final class ServerConnectivity: ObservableObject {
  enum Outcome: Equatable, Sendable {
    case success(milliseconds: Int)
    case unsupported, preparationTimeout, requestTimeout, configuration, startup, network
    case http(Int)
  }
  enum ConfigurationFailure: Error { case unsupported }
  struct Record: Equatable, Identifiable {
    let id = UUID()
    let finishedAt: Date
    let outcome: Outcome
    var networkExpired = false
    func isExpired(at date: Date) -> Bool {
      networkExpired || date.timeIntervalSince(finishedAt) >= 300
    }
  }
  struct Batch {
    let targets: [NodeID]
    let cooling: [NodeID]
    var completedIDs: Set<NodeID> = []
    var completed: Int { completedIDs.count }
  }
  struct Summary {
    let serverID: NodeID?
    let record: Record?
    let hasResults: Bool
    let isTesting: Bool
  }
  static let defaultURL = URL(string: "http://www.gstatic.com/generate_204")!
  @Published private(set) var testing: Set<NodeID> = []
  @Published private var records: [NodeID: [Record]] = [:]
  @Published private var batches: [UUID: Batch] = [:]
  private var versions: [NodeID: String] = [:]
  private var cooldown: [NodeID: Date] = [:]
  private var jobs: [NodeID: Task<Void, Never>] = [:]
  private var queue: [(NodeID, UUID)] = []
  private var tokens: [NodeID: UUID] = [:]
  private var running = 0
  private var generation = 0
  private var stopped = false
  private var targetURL: URL? = defaultURL
  private let revision: (NodeID) -> String
  private let configuration: (NodeID) throws -> SslocalServerDocument
  private let now: () -> Date
  private let measure: (SslocalServerDocument, URL, ContinuousClock.Instant) async -> Outcome

  init(
    configuration: @escaping (NodeID) throws -> SslocalServerDocument,
    revision: ((NodeID) -> String)? = nil,
    now: @escaping () -> Date = Date.init,
    measure: @escaping (SslocalServerDocument, URL, ContinuousClock.Instant) async -> Outcome
  ) {
    self.configuration = configuration
    self.revision =
      revision ?? { id in
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let server = try? configuration(id), let data = try? encoder.encode(server) else {
          return "invalid"
        }
        return ProxyACLDocument.digest(data)
      }
    self.now = now
    self.measure = measure
  }

  nonisolated static func validURL(_ raw: String) -> URL? {
    guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
      url.scheme?.lowercased() == "http",
      let host = url.host, !host.isEmpty, url.fragment == nil,
      url.user == nil, url.password == nil,
      url.port.map({ (1...65535).contains($0) }) ?? true
    else { return nil }
    return url
  }

  func history(for id: NodeID) -> [Record] { records[id] ?? [] }
  func batch(_ id: UUID) -> Batch? { batches[id] }
  func isCooling(_ id: NodeID) -> Bool { cooldown[id].map { now() < $0 } ?? false }

  /// Captures target identities, reuses queued work, and skips cooling identities.
  @discardableResult
  func test(_ ids: [NodeID]) -> UUID {
    configurationsChanged()
    let batchID = UUID()
    var seen = Set<NodeID>()
    let ids = ids.filter { seen.insert($0).inserted }
    let skipped = ids.filter { !testing.contains($0) && isCooling($0) }
    let targets = stopped ? [] : ids.filter { !skipped.contains($0) }
    batches[batchID] = Batch(targets: targets, cooling: skipped)
    // Bound transient batch metadata; active batches are retained.
    if batches.count > 100 {
      for (key, value) in batches where value.completed == value.targets.count && key != batchID {
        batches.removeValue(forKey: key)
      }
    }
    for id in targets where !testing.contains(id) {
      let token = UUID()
      versions[id] = revision(id)
      tokens[id] = token
      testing.insert(id)
      queue.append((id, token))
    }
    pump()
    return batchID
  }

  func wait(for batchID: UUID) async {
    while let batch = batches[batchID], batch.completed < batch.targets.count {
      await Task.yield()
    }
  }

  func summary(for ids: [NodeID], at date: Date) -> Summary {
    let values = ids.compactMap { id in records[id]?.first.map { (id, $0) } }
    let successes = values.filter {
      if case .success = $0.1.outcome { return true }
      return false
    }
    let fresh = successes.filter { !$0.1.isExpired(at: date) }
    let candidates = fresh.isEmpty ? successes : fresh
    let fastest = candidates.min { lhs, rhs in
      guard case .success(let leftMilliseconds) = lhs.1.outcome,
        case .success(let rightMilliseconds) = rhs.1.outcome
      else {
        return false
      }
      return leftMilliseconds < rightMilliseconds
    }
    return Summary(
      serverID: fastest?.0, record: fastest?.1,
      hasResults: !values.isEmpty, isTesting: ids.contains { testing.contains($0) })
  }

  /// Re-read values, including secrets with unchanged references and plugin mappings.
  func configurationsChanged() {
    for (id, previous) in versions where revision(id) != previous { invalidate(id) }
  }

  func setURL(_ url: URL?) {
    guard url != targetURL else { return }
    targetURL = url
    generation += 1
    records = [:]
    for id in testing { invalidate(id) }
  }

  func networkChanged() {
    generation += 1
    for id in records.keys {
      records[id] = records[id]?.map { record in
        var copy = record
        copy.networkExpired = true
        return copy
      }
    }
    for id in testing { jobs[id]?.cancel() }
  }

  func shutdown() async {
    stopped = true
    generation += 1
    for id in testing { invalidate(id) }
    let active = Array(jobs.values)
    for job in active { await job.value }
  }

  private func invalidate(_ id: NodeID) {
    records.removeValue(forKey: id)
    versions.removeValue(forKey: id)
    jobs[id]?.cancel()
    // Queued identities are completed internally and enter cooldown too.
    if jobs[id] == nil, testing.contains(id) { finish(id) }
  }

  private func pump() {
    while running < 1, !queue.isEmpty, !stopped {
      let (id, token) = queue.removeFirst()
      guard tokens[id] == token else { continue }
      let preparationDeadline = ContinuousClock.now.advanced(by: .seconds(30))
      guard versions[id] == revision(id) else {
        records.removeValue(forKey: id)
        finish(id)
        continue
      }
      running += 1
      let epoch = generation
      let url = targetURL
      let version = versions[id]
      let server: SslocalServerDocument?
      let failure: Outcome
      do {
        server = try configuration(id)
        failure = .configuration
      } catch ConfigurationFailure.unsupported {
        server = nil
        failure = .unsupported
      } catch {
        server = nil
        failure = .configuration
      }
      jobs[id] = Task { [self] in
        let result: Outcome
        if let server, let url {
          result =
            ContinuousClock.now >= preparationDeadline
            ? .preparationTimeout : await measure(server, url, preparationDeadline)
        } else {
          result = url == nil ? .configuration : failure
        }
        let current = revision(id)
        if !Task.isCancelled, epoch == generation, tokens[id] == token, current == version {
          let record = Record(finishedAt: now(), outcome: result)
          records[id] = Array(([record] + (records[id] ?? [])).prefix(10))
        }
        running -= 1
        jobs.removeValue(forKey: id)
        finish(id)
        pump()
      }
    }
  }

  private func finish(_ id: NodeID) {
    tokens.removeValue(forKey: id)
    testing.remove(id)
    cooldown[id] = now().addingTimeInterval(10)
    for key in batches.keys where batches[key]?.targets.contains(id) == true {
      batches[key]?.completedIDs.insert(id)
    }
  }
}
