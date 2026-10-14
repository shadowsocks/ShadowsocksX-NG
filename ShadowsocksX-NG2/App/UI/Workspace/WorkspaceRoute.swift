import Combine

/// 单一主 workspace 的有限 destination 词汇。它只描述导航位置，不携带功能区
/// 的选择、sheet、alert 或编辑草稿。
enum WorkspaceDestination: String, CaseIterable, Hashable, Identifiable, Sendable {
  case home
  case servers
  case rules
  case settings

  var id: Self { self }
}

/// workspace route module：集中 destination 与 workspace 内部导航。路由状态
/// 只存在于进程内，新实例始终从 home 开始。主窗口的呈现：启动由 Window
/// scene 的 defaultLaunchBehavior(.presented) 自动呈现，关窗后由状态菜单经
/// SwiftUI `openWindow` 重开（scene id 单点定义见 workspaceSceneID）；本
/// module 不依赖任何 UI framework，也不持有开窗 effect。
@MainActor
final class WorkspaceRoute: ObservableObject {
  /// 主 workspace 的 SwiftUI `Window` scene id：scene 在组合根（MainApp）
  /// 以此常量声明，状态菜单是关窗后的重开入口。字面量单点定义在此，防
  /// scene id 散落（架构测试锚定）。
  static let workspaceSceneID = "workspace"

  /// 实例初始 destination。MainWindowView 标签页 @State 选中项的初值须与此
  /// 对齐，否则首帧选中标签不一致。
  static let initialDestination: WorkspaceDestination = .home

  @Published private(set) var destination: WorkspaceDestination = initialDestination

  /// workspace 内部导航只改变 route destination；开窗不由 route 驱动。
  /// 同值导航必须是无操作：外部导航经 onChange 回填标签选中项后会再触发
  /// 一次 selection onChange（导航回声），由同值短路变成无操作；publish
  /// 一旦发生在视图更新期间（系统控件的选择同步回写）
  /// 会触发 "Publishing changes from within view updates" 运行时警告。
  func navigate(to destination: WorkspaceDestination) {
    guard destination != self.destination else { return }
    self.destination = destination
  }
}
