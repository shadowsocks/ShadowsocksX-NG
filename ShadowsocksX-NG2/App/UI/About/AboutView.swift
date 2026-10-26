import AppKit
import SwiftUI

struct AboutCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(replacing: .appInfo) {
      Button("关于 ShadowsocksX-NG2") {
        openWindow(id: AboutView.sceneID)
      }
    }
  }
}

struct AboutView: View {
  static let sceneID = "about"
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(spacing: 16) {
      Image(nsImage: NSApplication.shared.applicationIconImage)
        .resizable()
        .frame(width: 96, height: 96)
        .accessibilityHidden(true)
      Text(
        verbatim: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
          ?? "ShadowsocksX-NG2"
      )
      .font(.title2.bold())
      HStack {
        Text("版本")
        Text(verbatim: version)
      }
      Text(
        verbatim: Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
          ?? ""
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
      Button("第三方组件与许可证…") {
        openWindow(id: ThirdPartyComponentsView.sceneID)
      }
    }
    .textSelection(.enabled)
    .padding(32)
    .frame(width: 380)
  }

  private var version: String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    return [version, build.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
  }
}
