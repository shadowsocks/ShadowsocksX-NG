import XCTest

@testable import ShadowsocksX_NG2

@MainActor
final class SkeletonTests: XCTestCase {
  // app bundle 断言按构建产物定位（AppArtifact），不依赖测试宿主进程；守住
  // 的是打包面：bundle id 与旧版区分、菜单栏形态（LSUIElement）。

  func testAppBundleIDIsDistinctFromLegacy() throws {
    let bundle = try XCTUnwrap(Bundle(url: AppArtifact.bundleURL))
    XCTAssertEqual(bundle.bundleIdentifier, "com.qiuyuzhou.ShadowsocksX-NG2")
    XCTAssertNotEqual(bundle.bundleIdentifier, "com.qiuyuzhou.ShadowsocksX-NG")
  }

  func testAppIsMenuBarAgent() throws {
    let bundle = try XCTUnwrap(Bundle(url: AppArtifact.bundleURL))
    XCTAssertEqual(bundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool, true)
  }
}

/// 架构 deletion check：UI 源文件不得引用目录工作流的实现
/// 协作者或原始目录/凭据存储类型。
///
/// 扫描范围由目录正面圈定：只扫 `App/UI/`（视图层）。分层因此是目录声明而非
/// 豁免登记——把文件移出 `UI/` 是显式的架构动作；组合根放 `App/Composition/`、
/// 运行时与系统适配器放 `App/Application/`、平台效应 seam 放
/// `App/PlatformEffects/`，天然落在扫描范围之外，新增时无需登记豁免。
/// 规则只点名实现缝，不锁定实现内部的文件划分或私有 helper。
final class CatalogWorkflowArchitectureTests: XCTestCase {
  func testUISourceFilesDoNotReferenceCatalogWorkflowImplementation() throws {
    let uiDirectory = Self.testTargetRoot.appendingPathComponent("App/UI")
    let uiFiles = try Self.swiftSourceFiles(in: uiDirectory)
    XCTAssertFalse(uiFiles.isEmpty, "UI 源文件集合不应为空（App/UI 目录缺失？）")

    var violations: [String] = []
    for file in uiFiles {
      let content = try String(contentsOf: file, encoding: .utf8)
      for (index, line) in content.components(separatedBy: .newlines).enumerated() {
        for pattern in Self.forbiddenPatterns
        where pattern.regex.firstMatch(
          in: line, range: NSRange(line.startIndex..., in: line)) != nil
        {
          violations.append("\(file.lastPathComponent):\(index + 1) → \(pattern.label)")
        }
      }
    }
    XCTAssertTrue(
      violations.isEmpty,
      """
      UI 源文件不得引用代理控制器、目录工作流实现协作者或原始目录/凭据存储类型；
      经 CatalogWorkflow/ProxyControlWorkflow 的 UI-facing interface 表达
      （issue #49；控制器依赖由主窗口壳与服务器分区清零后固化为守卫）：
      \(violations.joined(separator: "\n"))
      """)
  }

  // MARK: - 扫描范围与禁令表

  private static let testTargetRoot = TestSourceTree.ng2Root()

  /// 禁令：实现协作者类型、原始目录/凭据存储类型与 workflow 内部成员缝。
  private static let forbiddenPatterns = makeForbiddenPatterns()

  private static func makeForbiddenPatterns() -> [(label: String, regex: NSRegularExpression)] {
    let typeTokens = [
      "ProxyRuntimeController",
      "CatalogWorkflowDependencies", "CatalogCommitCoordinator", "CatalogFileStore",
      "ConfigurationCatalog", "CatalogEntry", "CommittedCatalogSnapshot",
      "CredentialStoring", "KeychainCredentialStore", "CredentialWriteJournal",
      "CredentialReference", "PluginExecutableResolving", "BundleManagedPluginProvider",
      "SubscriptionFetching", "HTTPSSubscriptionFetcher", "SubscriptionRecord",
      "LegacyImportService", "LegacySnapshot", "Activating", "ServerFields",
    ]
    // workflow 内部成员缝（不作为可访问属性/方法暴露给 UI）。
    let memberTokens = [
      "\\.dependencies\\b", "\\bfileStore\\b", "discoveredLegacySnapshot",
      "republishCommittedState", "commitSubscriptionDocument", "publishLegacyImportState",
      "setRefreshInFlight", "setSubscriptionRefreshFailure",
      "subscriptionSummaries", "credentialRefs",
    ]
    return (typeTokens + memberTokens).map { token in
      do {
        return (label: token, regex: try NSRegularExpression(pattern: token))
      } catch {
        preconditionFailure("禁令正则编译失败：\(token)")
      }
    }
  }

  /// 视图层源文件 = `App/UI/` 下全部 Swift 文件（递归含各子视图目录）。
  private static func swiftSourceFiles(in directory: URL) throws -> [URL] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory, includingPropertiesForKeys: nil)
    else {
      XCTFail("无法枚举 UI 源码目录：\(directory.path)")
      return []
    }
    return enumerator.compactMap { item in
      guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
      return url
    }
  }
}

/// Domain 布局守卫：`Domain/` 是「目录即主题」——根下只放主题子目录，不放平铺
/// 文件，主题口径见 `project.yml` 的 Domain 注释与 GLOSSARY.md 的章节划分。
///
/// 无此守卫时，新增领域文件会默认堆回根下，主题划分靠人工记忆维持；守卫把
/// 该约定固定为可执行的断言。
final class DomainLayoutTests: XCTestCase {
  private static let domainDirectory = TestSourceTree.ng2Root()
    .appendingPathComponent("Domain")

  func testDomainRootHasNoLooseSwiftFiles() throws {
    let rootEntries = try FileManager.default.contentsOfDirectory(
      at: Self.domainDirectory, includingPropertiesForKeys: nil)
    let looseSwiftFiles =
      rootEntries
      .filter { $0.pathExtension == "swift" }
      .map(\.lastPathComponent)
      .sorted()

    XCTAssertTrue(
      looseSwiftFiles.isEmpty,
      """
      Domain/ 根下不得平铺 Swift 文件，应按主题归入子目录（Catalog / Subscription /
      Rules / Rules/Custom / Runtime / Activation / Settings / SystemProxy / Plugin /
      Credentials / LegacyImport / Diagnostics）：
      \(looseSwiftFiles.joined(separator: "\n"))
      """)
  }

  /// `Domain/` 整目录是 app 与 Core target 的 source path：任何非 Swift 文件都会被
  /// XcodeGen 收进 Resources 阶段、封进签名后的 app bundle（同 App/ 的已知行为），
  /// 因此树下不允许出现这类文件——确需随包发布应改走 Vendor/ 并显式声明 buildPhase。
  func testDomainTreeContainsOnlySwiftFiles() throws {
    let domainDirectory = Self.domainDirectory
    let enumerator = try XCTUnwrap(
      FileManager.default.enumerator(at: domainDirectory, includingPropertiesForKeys: nil),
      "无法枚举 Domain 目录：\(domainDirectory.path)")

    var unexpectedFiles: [String] = []
    for case let url as URL in enumerator {
      let isRegularFile =
        try url.resourceValues(forKeys: [.isRegularFileKey])
        .isRegularFile == true
      guard isRegularFile else { continue }
      if url.pathExtension != "swift" {
        unexpectedFiles.append(
          url.path.replacingOccurrences(of: domainDirectory.path + "/", with: ""))
      }
    }

    XCTAssertTrue(
      unexpectedFiles.isEmpty,
      """
      Domain/ 树下只允许 .swift 文件，否则会被收进 app bundle 的 Resources 阶段：
      \(unexpectedFiles.sorted().joined(separator: "\n"))
      """)
  }
}

/// Tests 布局守卫：`Tests/` 同样是目录即主题——根下只放主题子目录，不放平铺
/// 测试文件，主题口径对齐 `Domain/` 的主题与 `App/` 的 `*Workflow`。
///
/// 比 `DomainLayoutTests` 弱一档，只断言根层没有平铺 `.swift`：`Tests/` 树下的
/// 非 Swift 文件是必需的——`Fixtures/RuleSnapshots/*.json` 是随测试 bundle 发布
/// 的 folder resource，根层还有作为 `info.path` 生成的 `Info.plist`，两者都不能
/// 用「树下只有 .swift」那条不变量覆盖。
final class TestsLayoutTests: XCTestCase {
  private static let testsDirectory = TestSourceTree.ng2Root()
    .appendingPathComponent("Tests")

  func testTestsRootHasNoLooseSwiftFiles() throws {
    let rootEntries = try FileManager.default.contentsOfDirectory(
      at: Self.testsDirectory, includingPropertiesForKeys: nil)
    let looseSwiftFiles =
      rootEntries
      .filter { $0.pathExtension == "swift" }
      .map(\.lastPathComponent)
      .sorted()

    XCTAssertTrue(
      looseSwiftFiles.isEmpty,
      """
      Tests/ 根下不得平铺测试文件，应按主题归入子目录（Architecture / Support /
      Agent / Activation / Catalog（含 Workflow）/ Subscription / Rules（含 Custom）/
      ProxyRuntime / ProxyControl / Runtime / Settings / SystemProxy / Plugin /
      Diagnostics / Credentials / Workspace / Servers / Smoke）：
      \(looseSwiftFiles.joined(separator: "\n"))
      """)
  }
}
