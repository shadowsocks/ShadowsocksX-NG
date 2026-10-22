import Foundation
import Testing

/// 签名身份注入守卫：证书与 Team 都不入库（开源仓库），由 config 基线 + 本机
/// xcconfig 在构建期决定。
///
/// 这条约束容易被无声破坏：`project.yml` 一旦重新设置 `DEVELOPMENT_TEAM` 或
/// `CODE_SIGN_IDENTITY`，pbxproj 里的构建设置会盖掉 `Configs/Signing-*.xcconfig`
/// （Xcode 构建设置优先级，实测），注入失效却不报错。本套用例把整条链条钉住：
/// 工程定义不碰签名键 → config 基线各自正确且本机文件能（或不能）盖掉它 →
/// 本机文件不入库 → 供应链脚本与发布门槛跟着基线走。
struct SigningConfigurationTests {
  private static let ng2Root = TestSourceTree.ng2Root()
  private static let repositoryRoot = ng2Root.deletingLastPathComponent()

  /// 逐行匹配：`String.CompareOptions` 没有 `.anchorsMatchLines`，整段文本上
  /// `^`/`$` 只锚定字符串首尾，因此把行切开再套正则。
  private static func matchingLines(_ pattern: String, in text: String) -> [String] {
    text.split(separator: "\n", omittingEmptySubsequences: false)
      .filter { $0.range(of: pattern, options: .regularExpression) != nil }
      .map(String.init)
  }

  private static func firstLineIndex(matching pattern: String, in text: String) -> Int? {
    text.split(separator: "\n", omittingEmptySubsequences: false)
      .firstIndex { $0.range(of: pattern, options: .regularExpression) != nil }
  }

  private static func text(_ relativePath: String) throws -> String {
    try String(contentsOf: ng2Root.appendingPathComponent(relativePath), encoding: .utf8)
  }

  /// 只命中 YAML 键（行首为 `KEY:`），注释行以 `#` 开头，不算设置。
  private static func yamlKeyPattern(_ key: String) -> String { #"^\s*\#(key)\s*:"# }

  private static let identityAssignment = #"^\s*CODE_SIGN_IDENTITY\s*="#
  private static let localInclude = #"^\s*#include\?\s+"Signing\.local\.xcconfig"#

  @Test
  func projectSpecDoesNotPinSigningKeys() throws {
    let spec = try Self.text("project.yml")
    for key in ["DEVELOPMENT_TEAM", "CODE_SIGN_IDENTITY"] {
      let pinned = Self.matchingLines(Self.yamlKeyPattern(key), in: spec)
      #expect(
        pinned.isEmpty,
        "project.yml 不得设置 \(key)（pbxproj 设置会静默盖掉 Configs/Signing-*.xcconfig，且证书/Team 不应入库）：\(pinned)"
      )
    }
  }

  @Test
  func projectSpecInjectsPerConfigurationBaselines() throws {
    let spec = try Self.text("project.yml")
    let expected = [
      "Debug": "Configs/Signing-Debug.xcconfig",
      "Release": "Configs/Signing-Release.xcconfig",
    ]
    for (configuration, path) in expected {
      let pattern = #"^\s*\#(configuration):\s*\#(path)\s*$"#
      #expect(
        !Self.matchingLines(pattern, in: spec).isEmpty,
        "project.yml 的 configFiles 必须把 \(configuration) 挂到 \(path)")
    }
  }

  /// Debug 必须无证书可构建：基线 ad-hoc，且本机文件能把它升级成真证书。
  @Test
  func debugBaselineIsAdHocAndUpgradableByLocalFile() throws {
    let config = try Self.text("Configs/Signing-Debug.xcconfig")
    #expect(
      Self.matchingLines(#"^\s*CODE_SIGN_IDENTITY\s*=\s*-\s*$"#, in: config).count == 1,
      "Configs/Signing-Debug.xcconfig 必须恰好有一条 ad-hoc（-）CODE_SIGN_IDENTITY 基线")
    let baseline = try #require(
      Self.firstLineIndex(matching: Self.identityAssignment, in: config),
      "Configs/Signing-Debug.xcconfig 缺少 CODE_SIGN_IDENTITY 基线")
    let include = try #require(
      Self.firstLineIndex(matching: Self.localInclude, in: config),
      "Configs/Signing-Debug.xcconfig 必须包含 Configs/Signing.local.xcconfig")
    #expect(
      baseline < include,
      "Debug 的 #include? 必须在 ad-hoc 基线之后：xcconfig 后赋值者胜，本机文件才能升级身份")
  }

  /// Release 必须真签名：本机文件只能补 Team，不能把发布身份改成 ad-hoc。
  @Test
  func releaseBaselineStaysDeveloperID() throws {
    let config = try Self.text("Configs/Signing-Release.xcconfig")
    let assignments = Self.matchingLines(Self.identityAssignment, in: config)
    #expect(
      assignments.last?.contains("Developer ID Application") == true,
      "Configs/Signing-Release.xcconfig 最后生效的 CODE_SIGN_IDENTITY 必须是 Developer ID Application：\(assignments)"
    )
    let include = try #require(
      Self.firstLineIndex(matching: Self.localInclude, in: config),
      "Configs/Signing-Release.xcconfig 必须包含 Configs/Signing.local.xcconfig")
    let baseline = try #require(
      Self.firstLineIndex(matching: Self.identityAssignment, in: config),
      "Configs/Signing-Release.xcconfig 缺少 CODE_SIGN_IDENTITY 基线")
    #expect(include < baseline, "Release 的 #include? 必须在 Developer ID 基线之前，发布身份不被本机文件削弱")
  }

  @Test
  func committedBaselinesDoNotPinTeamID() throws {
    for path in ["Configs/Signing-Debug.xcconfig", "Configs/Signing-Release.xcconfig"] {
      let config = try Self.text(path)
      #expect(
        Self.matchingLines(#"^\s*DEVELOPMENT_TEAM\s*="#, in: config).isEmpty,
        "入库的 \(path) 不得固化 DEVELOPMENT_TEAM")
    }
  }

  @Test
  func localSigningConfigIsGitIgnored() throws {
    let ignoreList = try String(
      contentsOf: Self.repositoryRoot.appendingPathComponent(".gitignore"), encoding: .utf8)
    #expect(
      ignoreList.contains("ShadowsocksX-NG2/Configs/Signing.local.xcconfig"),
      ".gitignore 必须忽略 Configs/Signing.local.xcconfig（本机证书/Team 不入库）")
  }

  /// 嵌套二进制重签必须跟着基线走：ad-hoc 构建没有 secure timestamp。
  @Test
  func embeddedHelperSigningHandlesAdHocIdentity() throws {
    let script = try Self.text("Scripts/sign-embedded-helpers.sh")
    #expect(
      !Self.matchingLines(#"--sign -"#, in: script).isEmpty,
      "sign-embedded-helpers.sh 必须有无证书（ad-hoc）分支，否则 Debug 基线无法封套嵌套二进制")
  }

  /// 发布门槛的 Team 期望值同样不许写死：只能取自同一个注入文件或显式环境变量。
  @Test
  func packagingGateDerivesTeamIDFromInjectedConfig() throws {
    let gate = try Self.text("Scripts/packaging-gate.sh")
    #expect(
      gate.contains("Signing.local.xcconfig"),
      "packaging-gate.sh 必须从 Configs/Signing.local.xcconfig 读取期望 Team ID")
    #expect(
      Self.matchingLines(#":-[A-Z0-9]{10}\}"#, in: gate).isEmpty,
      "packaging-gate.sh 不得给 Team ID 留 10 位写死的默认值")
  }
}
