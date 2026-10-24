import Foundation
import Testing
import XCTest

@testable import ShadowsocksX_NG2

/// 内置规则目录：bundle 快照加载与中国直连候选投影。
final class BuiltinRuleCatalogTests: XCTestCase {
  func testConcurrentConsumersShareOneSourceLoad() async throws {
    let started = expectation(description: "source read")
    let loader = SharedRuleSourceLoader(started: started)
    defer { loader.release.release() }
    let snapshots = BuiltinRuleSnapshots(loader: { try await loader.load($0) })
    async let first = snapshots.load(.gfwlist)
    await fulfillment(of: [started], timeout: 3)
    async let second = snapshots.load(.gfwlist)
    loader.release.release()
    let (one, two) = try await (first, second)
    XCTAssertEqual(one, two)
    _ = try await snapshots.load(.gfwlist)
    XCTAssertEqual(loader.count(.gfwlist), 1)
  }

  func testRetryReadsOnlyFailedSourcesAndSuccessNeverExpires() async throws {
    let loader = SharedRuleSourceLoader()
    let snapshots = BuiltinRuleSnapshots(loader: { try await loader.load($0) })
    let first = await snapshots.browsingSources()
    XCTAssertThrowsError(try first[.chinaIPv4]?.get())
    _ = await snapshots.browsingSources()
    XCTAssertEqual(loader.count(.chinaIPv4), 1, "Ordinary requests retain the failure")
    let retried = await snapshots.browsingSources(retryFailures: true)
    XCTAssertNoThrow(try retried[.chinaIPv4]?.get())
    XCTAssertEqual(loader.count(.chinaIPv4), 2)
    XCTAssertEqual(loader.count(.geolocationCN), 1)
    XCTAssertEqual(loader.count(.gfwlist), 1)
  }

  @MainActor
  func testFirstBrowsingRetainsRuntimeSourceFailureUntilExplicitRetry() async throws {
    let loader = SharedRuleSourceLoader()
    let snapshots = BuiltinRuleSnapshots(loader: { try await loader.load($0) })
    do {
      _ = try await snapshots.load(.chinaIPv4)
      XCTFail("The first runtime source request should fail")
    } catch {}
    let workflow = RulesWorkflow(loadCustom: { [] }, builtinSnapshots: snapshots)
    await workflow.refresh()
    XCTAssertFalse(workflow.snapshot.isComplete)
    XCTAssertEqual(loader.count(.chinaIPv4), 1)
    await workflow.refresh(retryFailedSources: true)
    XCTAssertTrue(workflow.snapshot.isComplete)
    XCTAssertEqual(loader.count(.chinaIPv4), 2)
    XCTAssertEqual(loader.count(.geolocationCN), 1)
    XCTAssertEqual(loader.count(.gfwlist), 0)
  }

  func testGeolocationCNSnapshotLoadsFromBundleOrSourceTree() throws {
    // 优先 bundle（随 App 分发）；测试环境回退到源码树固定快照。
    let snapshot: RuleSnapshot
    do {
      snapshot = try BuiltinRuleCatalog.loadGeolocationCN()
    } catch {
      let sourceURL = TestSourceTree.ng2Root()
        .appendingPathComponent("Vendor/rules/geolocation-cn/snapshot.json")
      snapshot = try RuleSnapshotStore(fileURL: sourceURL).load()
    }

    XCTAssertEqual(snapshot.metadata.source.kind, .geolocationCN)
    XCTAssertEqual(
      snapshot.metadata.converterVersion, RuleSnapshotStore.currentConverterVersion)
    XCTAssertFalse(snapshot.metadata.license.isEmpty)
    XCTAssertFalse(snapshot.metadata.attribution.isEmpty)
    XCTAssertFalse(snapshot.metadata.inputDigest.isEmpty)
    XCTAssertFalse(snapshot.metadata.upstreamReference.isEmpty)

    let rules = BuiltinRuleCatalog.chinaDirectRules(from: snapshot)
    XCTAssertFalse(rules.isEmpty)
    XCTAssertTrue(rules.allSatisfy { $0.action == .direct })
    XCTAssertTrue(
      rules.contains { $0.match.pattern == .domainSuffix("cn") },
      "快照应含 .cn 后缀直连规则")

    // 转换期已删除被 .cn 吸收的域名条目。
    let independentCN = rules.filter {
      switch $0.match.pattern {
      case .domainSuffix(let value): return value.hasSuffix(".cn") && value != "cn"
      case .domainExact(let value): return value.hasSuffix(".cn")
      default: return false
      }
    }
    XCTAssertTrue(independentCN.isEmpty, "快照不保留被吸收的规则")
  }

  /// china-ipv4 快照：从 bundle 或源码树加载，直连候选为 IPv4 CIDR。
  func testChinaIPv4SnapshotLoadsFromBundleOrSourceTree() throws {
    let snapshot: RuleSnapshot
    do {
      snapshot = try BuiltinRuleCatalog.loadChinaIPv4()
    } catch {
      let sourceURL = TestSourceTree.ng2Root()
        .appendingPathComponent("Vendor/rules/china-ipv4/snapshot.json")
      snapshot = try RuleSnapshotStore(fileURL: sourceURL).load()
    }

    XCTAssertEqual(snapshot.metadata.source.kind, .chinaIPv4)
    XCTAssertEqual(
      snapshot.metadata.converterVersion, RuleSnapshotStore.currentConverterVersion)
    XCTAssertFalse(snapshot.metadata.license.isEmpty)
    XCTAssertFalse(snapshot.metadata.attribution.isEmpty)
    XCTAssertFalse(snapshot.metadata.inputDigest.isEmpty)
    XCTAssertFalse(snapshot.metadata.upstreamReference.isEmpty)

    let rules = BuiltinRuleCatalog.chinaDirectRules(from: snapshot)
    XCTAssertFalse(rules.isEmpty)
    XCTAssertTrue(rules.allSatisfy { $0.action == .direct })
    XCTAssertTrue(
      rules.allSatisfy {
        if case .ipv4CIDR = $0.match.pattern { return true }
        return false
      }, "china-ipv4 快照应只含 IPv4 CIDR 直连候选")
  }

  /// gfwlist 快照：从 bundle 或源码树加载，代理候选为域名后缀。
  func testGFWListSnapshotLoadsFromBundleOrSourceTree() throws {
    let snapshot: RuleSnapshot
    do {
      snapshot = try BuiltinRuleCatalog.loadGFWList()
    } catch {
      snapshot = try loadSourceTreeSnapshot(path: "Vendor/rules/gfwlist/snapshot.json")
    }

    XCTAssertEqual(snapshot.metadata.source.kind, .gfwlist)
    XCTAssertEqual(
      snapshot.metadata.converterVersion, RuleSnapshotStore.currentConverterVersion)
    XCTAssertFalse(snapshot.metadata.license.isEmpty)
    XCTAssertFalse(snapshot.metadata.attribution.isEmpty)
    XCTAssertFalse(snapshot.metadata.inputDigest.isEmpty)
    XCTAssertFalse(snapshot.metadata.upstreamReference.isEmpty)

    let rules = BuiltinRuleCatalog.gfwlistRules(from: snapshot)
    XCTAssertFalse(rules.isEmpty)
    XCTAssertTrue(
      rules.allSatisfy {
        if case .domainSuffix = $0.match.pattern { return true }
        return false
      }, "gfwlist 快照候选应为域名后缀")

    // 损失报告保留来源、摘要、许可证/归属与转换损失（含遮蔽例外）。
    XCTAssertGreaterThan(snapshot.lossReport.absorbedCount, 0)
    XCTAssertNil(snapshot.lossReport.skipped["shadowedException"])
  }

  /// 合并投影：域名 + CIDR 直连候选一起进入 ACL 编译输入。
  func testChinaDirectRulesMergeDomainAndCIDRSnapshots() throws {
    let geolocation = try loadSourceTreeSnapshot(path: "Vendor/rules/geolocation-cn/snapshot.json")
    let chinaIPv4 = try loadSourceTreeSnapshot(path: "Vendor/rules/china-ipv4/snapshot.json")
    let merged = BuiltinRuleCatalog.chinaDirectRules(from: [geolocation, chinaIPv4])

    XCTAssertTrue(
      merged.contains { rule in
        if case .domainSuffix("cn") = rule.match.pattern { return true }
        return false
      }, "合并结果应含 .cn 域名直连候选")
    XCTAssertTrue(
      merged.contains { rule in
        if case .ipv4CIDR = rule.match.pattern { return true }
        return false
      }, "合并结果应含 IPv4 CIDR 直连候选")
    XCTAssertTrue(merged.allSatisfy { $0.action == .direct })
  }

  private func loadSourceTreeSnapshot(path: String) throws -> RuleSnapshot {
    let sourceURL = TestSourceTree.ng2Root().appendingPathComponent(path)
    return try RuleSnapshotStore(fileURL: sourceURL).load()
  }

  func testRuleDefaultActionLabelsAndFallback() throws {
    XCTAssertEqual(RuleDefaultAction.proxyWhenUnmatched.label, "代理")
    XCTAssertEqual(RuleDefaultAction.directWhenUnmatched.label, "直连")
    XCTAssertEqual(RuleDefaultAction.proxyWhenUnmatched.fallbackAction, .proxy)
    XCTAssertEqual(RuleDefaultAction.directWhenUnmatched.fallbackAction, .direct)
    XCTAssertEqual(RuleDefaultAction.allCases, [.proxyWhenUnmatched, .directWhenUnmatched])
  }

}

private final class SharedRuleSourceLoader: @unchecked Sendable {
  private let lock = NSLock()
  private var counts: [RulesSource: Int] = [:]
  private let started: XCTestExpectation?
  let release = TestAsyncGate("shared rule source release")
  init(started: XCTestExpectation? = nil) { self.started = started }
  func count(_ source: RulesSource) -> Int { lock.withLock { counts[source, default: 0] } }
  func load(_ source: RulesSource) async throws -> RuleSnapshot {
    let count = lock.withLock {
      counts[source, default: 0] += 1
      return counts[source, default: 0]
    }
    if let started {
      started.fulfill()
      _ = await release.wait()
    } else if source == .chinaIPv4 && count == 1 {
      throw RuleSnapshotError.missing
    }
    return rulesFixture(source)
  }
}

@Test func builtinSnapshotsRejectNonBuiltinSources() async {
  let snapshots = BuiltinRuleSnapshots(loader: { _ in rulesFixture(.custom) })
  for source in [RulesSource.custom, .fixed] {
    do {
      _ = try await snapshots.load(source)
      Issue.record("Non-builtin source must not load a snapshot")
    } catch {
      #expect(error as? RuleSnapshotError == .missing)
    }
  }
}

@Test func builtinSnapshotsRejectMismatchedMetadata() async {
  let snapshots = BuiltinRuleSnapshots(loader: { _ in rulesFixture(.chinaIPv4) })
  do {
    _ = try await snapshots.load(.geolocationCN)
    Issue.record("Mismatched source metadata must be rejected")
  } catch {
    #expect(error as? RuleSnapshotError == .corrupt(detail: "Unexpected rule source"))
  }
}
