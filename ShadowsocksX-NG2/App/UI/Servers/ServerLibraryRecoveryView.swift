import SwiftUI

struct ServerLibraryRecoveryView: View {
  @ObservedObject var workflow: CatalogWorkflow
  let failure: ServerLibraryFailure
  @State private var confirmsReset = false

  var body: some View {
    ContentUnavailableView {
      Label("服务器库无法读取", systemImage: "lock.doc")
    } description: {
      Text(message)
      Text("原配置文件和正在运行的代理保持不变。")
      if case .authorization(let status) = failure {
        Text("钥匙串状态码：\(Int(status))")
      }
    } actions: {
      Button("重试并解锁") { workflow.unlockLibrary() }
        .buttonStyle(.borderedProminent)
      Button("放弃原配置…", role: .destructive) { confirmsReset = true }
    }
    .confirmationDialog("放弃原配置并创建空库？", isPresented: $confirmsReset) {
      Button("放弃原配置并创建空库", role: .destructive) { workflow.resetLibrary() }
      Button("取消", role: .cancel) {}
    } message: {
      Text("新空库将覆盖原服务器库，并撤下原代理出口。未另存的原配置将无法恢复。")
    }
  }

  private var message: String {
    switch failure {
    case .authorization: String(localized: "钥匙串访问需要授权，或用户取消了授权。请重试并解锁。")
    case .keyUnavailable: String(localized: "找不到服务器库的主密钥。请恢复原钥匙串后重试。")
    case .authenticationFailed: String(localized: "服务器库认证失败，文件或密钥不匹配。")
    case .unsupportedVersion: String(localized: "此版本无法读取服务器库格式。请使用兼容的应用版本。")
    case .malformedFile: String(localized: "服务器库文件损坏或格式无效。")
    case .storage: String(localized: "服务器库读取或保存失败。请检查存储权限后重试。")
    }
  }
}
