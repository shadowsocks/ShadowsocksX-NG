import SwiftUI

struct AboutScenes: Scene {
  let windowActivation: WindowActivationPolicyCoordinator

  var body: some Scene {
    Window("关于 ShadowsocksX-NG2", id: AboutView.sceneID) {
      AboutView()
        .modifier(WindowActivationPolicy(coordinator: windowActivation))
    }
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)
    .commandsRemoved()
    .windowResizability(.contentSize)

    Window("第三方组件与许可证", id: ThirdPartyComponentsView.sceneID) {
      ThirdPartyComponentsView()
        .modifier(WindowActivationPolicy(coordinator: windowActivation))
    }
    .defaultLaunchBehavior(.suppressed)
    .restorationBehavior(.disabled)
    .commandsRemoved()
    .defaultSize(width: 1000, height: 680)
  }
}
