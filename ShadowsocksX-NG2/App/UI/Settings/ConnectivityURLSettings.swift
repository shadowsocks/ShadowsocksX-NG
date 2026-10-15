import SwiftUI

struct ConnectivityURLSettings: View {
  @ObservedObject var workflow: SettingsWorkflow
  @State private var editing = false
  @State private var value = ""
  @State private var failure = false

  var body: some View {
    Section {
      Button(ConnectivityCopy.text("测试 URL…")) {
        do {
          value = try workflow.beginConnectivityURLEditing()
          failure = false
          editing = true
        } catch { failure = true }
      }
      if failure { Text(ConnectivityCopy.text("无法读取或保存测试 URL")).foregroundStyle(.red) }
    } header: {
      Text(ConnectivityCopy.text("连通性测试"))
    }
    .sheet(isPresented: $editing) {
      VStack(alignment: .leading, spacing: 16) {
        Text(ConnectivityCopy.text("测试 URL")).font(.headline)
        TextField("HTTP", text: $value).textFieldStyle(.roundedBorder)
        Text(ConnectivityCopy.text("仅支持 HTTP。预热后采样 3 次，至少成功 2 次；显示成功样本的中位数。"))
          .font(.caption).foregroundStyle(.secondary)
        if failure { Text(ConnectivityCopy.text("无法读取或保存测试 URL")).foregroundStyle(.red) }
        HStack {
          Button(ConnectivityCopy.text("恢复默认")) {
            value = ServerConnectivity.defaultURL.absoluteString
          }
          Spacer()
          Button(ConnectivityCopy.text("取消")) { editing = false }.keyboardShortcut(.cancelAction)
          Button(ConnectivityCopy.text("保存")) {
            Task {
              if await workflow.saveConnectivityURL(value) {
                editing = false
                failure = false
              } else {
                failure = true
              }
            }
          }
          .keyboardShortcut(.defaultAction)
          .disabled(ServerConnectivity.validURL(value) == nil || workflow.isCommitting)
        }
      }
      .padding(24).frame(width: 520)
      .interactiveDismissDisabled(workflow.isCommitting)
    }
  }
}
