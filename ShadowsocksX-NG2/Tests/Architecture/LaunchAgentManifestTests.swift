import Foundation
import Testing

@testable import ShadowsocksX_NG2

/// LaunchAgent manifest 双份 artifact 的一致性守卫：bundle 内打包 plist
/// （SMAppService 审批用）与 writeUserPlist 运行时重建（launchctl bootstrap
/// 用）承载同一 crash 重放协议（KeepAlive={SuccessfulExit:false} +
/// ThrottleInterval），任一份漂移都会让注册行为与审批所见分叉。
/// ProgramArguments 的 bundle 相对 vs 绝对路径是文档化的刻意差异
/// （SMAppService 对相对 ProgramArguments 解析不可靠），只断言形状等价。
struct LaunchAgentManifestTests {
  @Test func bundledManifestMatchesCodeBuiltKeys() throws {
    // 打包 plist 经 copyFiles 部署在 Contents/Library/LaunchAgents/（SMAppService
    // 的固定读取位置）；按部署路径直读，路径缺失即用例失败。
    let bundledURL = AppArtifact.bundleURL
      .appendingPathComponent("Contents/Library/LaunchAgents")
      .appendingPathComponent("com.qiuyuzhou.ShadowsocksX-NG2.agent.plist")
    let data = try Data(contentsOf: bundledURL)
    let bundled = try #require(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

    let programName = "ShadowsocksX-NG2Agent"
    let built = SMAppLaunchAgentService.manifestDictionary(programArguments: [
      "/Applications/ShadowsocksX-NG2.app/Contents/MacOS/\(programName)"
    ])

    #expect(bundled["Label"] as? String == built["Label"] as? String)
    #expect(bundled["KeepAlive"] as? [String: Bool] == built["KeepAlive"] as? [String: Bool])
    #expect(bundled["ThrottleInterval"] as? Int == built["ThrottleInterval"] as? Int)

    let bundledArguments = try #require(bundled["ProgramArguments"] as? [String])
    let builtArguments = try #require(built["ProgramArguments"] as? [String])
    #expect(bundledArguments.count == 1)
    #expect(builtArguments.count == 1)
    #expect((bundledArguments[0] as NSString).lastPathComponent == programName)
    #expect((builtArguments[0] as NSString).lastPathComponent == programName)
  }
}
