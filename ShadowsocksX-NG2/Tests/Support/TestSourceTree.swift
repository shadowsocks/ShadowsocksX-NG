import Foundation

/// 测试源码树位置。
///
/// 断言需要读源码树（`Vendor/` 快照、`App/`、`Domain/`）时，把 `#filePath` 交给
/// 这里定位：从该文件所在目录沿父目录上溯，返回含 `project.yml` 的目录，即
/// `ShadowsocksX-NG2/`。
///
/// 刻意不写死 `deletingLastPathComponent` 的层数：那等于把「测试文件在
/// `Tests/` 根层」编进代码，文件移进子目录后会静默指错；而测试文件处于不同
/// 深度时（`Tests/Agent/` 与 `Tests/Rules/Custom/`）也无法共用一个层数。
enum TestSourceTree {
  /// `#filePath` 作为默认参数在**调用点**求值，因此拿到的是调用者所在文件。
  static func ng2Root(filePath: String = #filePath) -> URL {
    var directory = URL(fileURLWithPath: filePath).deletingLastPathComponent()
    while directory.path != "/" {
      if FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("project.yml").path)
      {
        return directory
      }
      directory = directory.deletingLastPathComponent()
    }
    preconditionFailure("从 \(filePath) 沿父目录上溯未找到 project.yml（ShadowsocksX-NG2/）")
  }
}
