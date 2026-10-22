import Foundation

/// 构建产物定位：从测试 bundle 落盘位置向上逐层查找 app 产物。覆盖两种布局
/// ——TEST_HOST 过渡期 `.xctest` 嵌于 app bundle 的 `Contents/PlugIns/`（app
/// 是祖先），去宿主化后 `.xctest` 与 `.app` 平级同在 `Build/Products/<config>/`
/// （app 是某层祖先的子项）。测试需要 app 产物（嵌入二进制、Info.plist 打包面
/// 断言）时一律经此定位，不得用 `Bundle.main`（去宿主化后它是 xctest runner
/// 的 bundle）。
enum AppArtifact {
  static let bundleURL: URL = {
    let testBundleURL = Bundle(for: Marker.self).bundleURL
    var directory = testBundleURL
    while directory.path != "/" {
      if directory.lastPathComponent == "ShadowsocksX-NG2.app" {
        return directory
      }
      directory.deleteLastPathComponent()
      let candidate = directory.appendingPathComponent(
        "ShadowsocksX-NG2.app", isDirectory: true)
      if FileManager.default.fileExists(atPath: candidate.path) {
        return candidate
      }
    }
    // 定位失败时返回原目录让用例以「产物缺失」失败并暴露实际路径，不炸进程。
    return testBundleURL
  }()

  /// `bundleURL` 的 Bundle 形态：注入按 Bundle 取资源的生产缝（如
  /// ProxyRuntimeController 的内置规则快照 bundle）。定位失败时退回测试
  /// bundle，让资源缺失以用例失败呈现。
  static let bundle: Bundle = Bundle(url: bundleURL) ?? Bundle(for: Marker.self)

  /// `Bundle(for:)` 需要类对象；marker 只为取得测试 bundle 的落盘位置。
  private final class Marker {}
}
