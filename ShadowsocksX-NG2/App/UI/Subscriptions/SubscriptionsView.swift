import SwiftUI

enum SubscriptionDeletionConfirmation {
  static func title(for name: String) -> String {
    String(localized: "删除订阅「\(name)」及其整棵子树？")
  }

  static let actionTitle = String(localized: "删除订阅")
  static let message =
    String(localized: "将移除订阅源、固定分组与全部远端成员；若代理正走此订阅，代理会停止。此操作不可撤销。")
}

/// 「添加订阅」表单（工具栏入口）：粘贴 HTTPS 订阅地址；创建后立即首次刷新。
struct AddSubscriptionSheet: View {
  let workflow: CatalogWorkflow
  let errors: ErrorAlertPresenter
  @Environment(\.dismiss) private var dismiss

  @State private var urlString = ""
  @State private var autoUpdate = SubscriptionAutoUpdate()

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("添加订阅").font(.title2)
      Text("粘贴订阅地址（必须 HTTPS，返回 SIP-008 JSON；Content-Type 需为 application/json; charset=utf-8）。")
        .font(.callout)
        .foregroundStyle(.secondary)
      TextField(
        "订阅地址", text: $urlString,
        prompt: Text(verbatim: "https://example.com/subscription.json")
          .foregroundStyle(.placeholder)
      )
      SubscriptionAutoUpdateForm(settings: $autoUpdate)
      HStack {
        Spacer()
        Button("取消", role: .cancel) { dismiss() }
        Button("添加并刷新") { create() }
          .keyboardShortcut(.defaultAction)
          .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(20)
    .frame(minWidth: 480)
  }

  private func create() {
    Task {
      do {
        _ = try await workflow.createSubscription(urlString: urlString, autoUpdate: autoUpdate)
        dismiss()
      } catch {
        errors.present(error)
      }
    }
  }
}

/// 「编辑订阅 URL」表单（保留订阅与固定分组身份）；保存后立即刷新。
/// URL 明文经显式命令读取。
struct EditSubscriptionURLSheet: View {
  let workflow: CatalogWorkflow
  let errors: ErrorAlertPresenter
  let summary: SubscriptionSummary
  @Environment(\.dismiss) private var dismiss

  @State private var urlString = ""
  @State private var autoUpdate = SubscriptionAutoUpdate()
  @State private var loaded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("编辑订阅").font(.title2)
      Text("编辑订阅地址。订阅身份与固定分组全部保留；新地址刷新成功前保留最后一次成功内容。")
        .font(.callout)
        .foregroundStyle(.secondary)
      TextField(
        "订阅地址", text: $urlString,
        prompt: Text(verbatim: "https://example.com/subscription.json")
          .foregroundStyle(.placeholder)
      )
      SubscriptionAutoUpdateForm(settings: $autoUpdate)
      HStack {
        Spacer()
        Button("取消", role: .cancel) { dismiss() }
        Button("保存") { save() }
          .keyboardShortcut(.defaultAction)
          .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(20)
    .frame(minWidth: 480)
    .onAppear {
      guard !loaded else { return }
      loaded = true
      do {
        urlString = try workflow.subscriptionURL(for: summary.id)
        autoUpdate = summary.autoUpdate
      } catch {
        errors.present(error)
      }
    }
  }

  private func save() {
    Task {
      do {
        try await workflow.editSubscriptionURL(
          summary.id, urlString: urlString, autoUpdate: autoUpdate)
        dismiss()
      } catch {
        errors.present(error)
      }
    }
  }
}

private struct SubscriptionAutoUpdateForm: View {
  @Binding var settings: SubscriptionAutoUpdate

  var body: some View {
    GroupBox("自动更新") {
      VStack(alignment: .leading, spacing: 10) {
        if settings.allowsUserOverride {
          Picker(
            "设置来源",
            selection: Binding(
              get: { settings.userOverride != nil },
              set: { settings.userOverride = $0 ? .off : nil }
            )
          ) {
            Text("跟随供应商").tag(false)
            Text("自定义").tag(true)
          }
          if settings.userOverride != nil {
            Toggle(
              "启用自动更新",
              isOn: Binding(
                get: { settings.userOverride != .off },
                set: { settings.userOverride = $0 ? settings.interval : .off }
              ))
            Picker("更新间隔", selection: $settings.interval) {
              Text(SubscriptionUpdateMode.daily.displayName).tag(SubscriptionUpdateMode.daily)
              Text(SubscriptionUpdateMode.weekly.displayName).tag(SubscriptionUpdateMode.weekly)
            }
            .onChange(of: settings.interval) { _, interval in
              if settings.userOverride != .off { settings.userOverride = interval }
            }
          } else {
            Text(settings.effectiveMode.displayName).foregroundStyle(.secondary)
          }
        } else {
          LabeledContent("供应商设置", value: settings.effectiveMode.displayName)
          Text("供应商禁止覆盖自动更新设置")
            .font(.callout).foregroundStyle(.secondary)
        }
      }
      .pickerStyle(.segmented)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(6)
    }
  }
}
