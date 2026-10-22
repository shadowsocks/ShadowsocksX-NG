import SwiftUI

struct ConnectivityURLSettings: View {
  @ObservedObject var workflow: SettingsWorkflow
  @State private var editing = false
  @State private var value = ""
  @State private var displayedURL = ""
  @State private var failure = false

  var body: some View {
    Section {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(ConnectivityCopy.text("测试链接")).font(.headline)
          Text(displayedURL)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Button(action: beginEditing) {
          HStack(spacing: 6) {
            Text(String(localized: "编辑"))
            Image(systemName: "chevron.right")
              .font(.caption.weight(.semibold))
              .accessibilityHidden(true)
          }
        }
        .buttonStyle(.bordered)
      }

      if failure {
        Text(ConnectivityCopy.text("无法保存测试 URL"))
          .font(.caption)
          .foregroundStyle(.red)
      }
    } header: {
      Text(ConnectivityCopy.text("延迟测试"))
    }
    .onAppear(perform: refreshDisplayedURL)
    .sheet(isPresented: $editing) {
      VStack(alignment: .leading, spacing: 16) {
        Text(ConnectivityCopy.text("测试链接")).font(.headline)
        TextField("HTTP", text: $value).textFieldStyle(.roundedBorder)
        Text(ConnectivityCopy.text("仅支持 HTTP。预热后采样 3 次，至少成功 2 次；显示成功样本的中位数。"))
          .font(.caption).foregroundStyle(.secondary)
        if failure { Text(ConnectivityCopy.text("无法保存测试 URL")).foregroundStyle(.red) }
        HStack {
          Button(ConnectivityCopy.text("恢复默认")) {
            value = ServerConnectivity.defaultURL.absoluteString
          }
          Spacer()
          Button(ConnectivityCopy.text("取消")) { editing = false }.keyboardShortcut(.cancelAction)
          Button(ConnectivityCopy.text("保存")) {
            Task {
              if await workflow.saveConnectivityURL(value) {
                displayedURL = ServerConnectivity.validURL(value)?.absoluteString ?? value
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

  private func refreshDisplayedURL() {
    displayedURL = workflow.beginConnectivityURLEditing()
    failure = false
  }

  private func beginEditing() {
    value = workflow.beginConnectivityURLEditing()
    displayedURL = value
    failure = false
    editing = true
  }
}
