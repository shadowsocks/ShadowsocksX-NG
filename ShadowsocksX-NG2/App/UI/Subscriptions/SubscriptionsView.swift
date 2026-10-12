import SwiftUI

/// 订阅分区：每个订阅以一张卡片呈现
/// （图标 + 名称 + 「HTTPS 订阅地址已隐藏」+ 状态徽标 + 更新/重试 + 「…」菜单 +
/// 三列元数据 + 脱敏说明行），失败卡警告色描边。「添加订阅」与「更新全部」
/// 均由本页自挂工具栏（呈现于窗口工具栏右端，与服务器分区同法）。卡片数据
/// 来自订阅 projection（非敏感）；结构化刷新状态在呈现层本地化。
struct SubscriptionsView: View {
  @ObservedObject var workflow: CatalogWorkflow
  /// 共享错误弹窗呈现（UI 持有；typed error → 本地化文案的呈现边缘）。
  @StateObject private var errors = ErrorAlertPresenter()
  /// 删除完成后回调（被删身份集合；主窗口据此清除失效选择）。
  let onNodesRemoved: (Set<NodeID>) -> Void

  @State private var editTarget: SubscriptionSummary?
  @State private var deleteTarget: SubscriptionSummary?
  /// 添加订阅表单：本页自持（2026-10-04 自窗口壳「添加」菜单移回本页工具栏）。
  @State private var isPresentingAddSubscription = false

  var body: some View {
    ScrollView {
      VStack(spacing: 14) {
        ForEach(workflow.subscriptions) { summary in
          SubscriptionCard(
            summary: summary,
            groupName: workflow.displayName(for: summary.groupID),
            isRefreshing: workflow.refreshingSubscriptionIDs.contains(summary.id),
            onRefresh: { Task { await workflow.refreshSubscription(summary.id) } },
            onEdit: { editTarget = summary },
            onDelete: { deleteTarget = summary })
        }
      }
      .frame(maxWidth: 960, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.leading, 28)
      .padding(.trailing, 32)
      .padding(.top, 24)
      .padding(.bottom, 36)
    }
    .overlay {
      if workflow.subscriptions.isEmpty {
        ContentUnavailableView(
          "暂无订阅", systemImage: "arrow.triangle.2.circlepath",
          description: Text("用工具栏的「添加订阅」按钮添加 HTTPS 订阅地址（SIP-008 JSON）")
        )
        .allowsHitTesting(false)
      }
    }
    .sheet(item: $editTarget) { summary in
      EditSubscriptionURLSheet(workflow: workflow, errors: errors, summary: summary)
    }
    .sheet(isPresented: $isPresentingAddSubscription) {
      AddSubscriptionSheet(workflow: workflow, errors: errors)
    }
    .confirmationDialog(
      "删除订阅「\(deleteTarget?.name ?? "")」及其整棵子树？",
      isPresented: Binding(
        get: { deleteTarget != nil },
        set: { if !$0 { deleteTarget = nil } }),
      titleVisibility: .visible
    ) {
      Button("删除订阅", role: .destructive) { commitDelete() }
      Button("取消", role: .cancel) { deleteTarget = nil }
    } message: {
      Text(
        "将移除订阅源、固定分组与全部远端成员；若代理正走此订阅，代理会停止。此操作不可撤销。"
      )
    }
    .presentingErrors(errors)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("添加订阅", systemImage: "plus") {
          isPresentingAddSubscription = true
        }
      }
      ToolbarItem(placement: .primaryAction) {
        HStack(spacing: 8) {
          if !workflow.refreshingSubscriptionIDs.isEmpty {
            ProgressView()
              .controlSize(.small)
          }
          Button("更新全部", systemImage: "arrow.triangle.2.circlepath") {
            Task { await workflow.refreshAllSubscriptions() }
          }
          .disabled(workflow.subscriptions.isEmpty)
        }
      }
    }
  }

  private func commitDelete() {
    guard let target = deleteTarget else { return }
    deleteTarget = nil
    Task {
      do {
        let outcome = try await workflow.removeSubscription(target.id)
        onNodesRemoved(outcome.removedNodeIDs)
      } catch {
        errors.present(error)
      }
    }
  }
}

/// 刷新状态 → 呈现文案（本地化在 UI 呈现层，不在 module 内）。
extension SubscriptionRefreshStatus {
  var badgeText: String {
    switch self {
    case .never: "尚未刷新"
    case .succeeded: "已同步"
    case .failed: "刷新失败"
    }
  }

  var failureDetail: String? {
    if case .failed(_, let failure) = self {
      return AppPresentation.message(for: failure)
    }
    return nil
  }

  var isFailed: Bool {
    if case .failed = self { return true }
    return false
  }

  /// 脱敏说明行：失败卡说明保留快照语义。
  var footerNote: String {
    isFailed
      ? "保留最后一次成功快照 · 不会清空现有节点"
      : "远端结构由订阅管理，本地仅保留远端快照"
  }
}

/// 单张订阅卡片：头部、三列元数据与脱敏说明；失败态警告色描边。
private struct SubscriptionCard: View {
  @Environment(\.locale) private var locale
  @Environment(\.timeZone) private var timeZone
  let summary: SubscriptionSummary
  let groupName: String
  let isRefreshing: Bool
  let onRefresh: () -> Void
  let onEdit: () -> Void
  let onDelete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
        .padding(.top, 16)
      meta
        .padding(.top, 14)
      if let information = summary.information {
        subscriptionInformation(information)
          .padding(.top, 14)
      }
      if let detail = summary.status.failureDetail {
        Text(detail)
          .font(.footnote)
          .foregroundStyle(.red)
          .lineLimit(2)
          .padding(.top, 10)
      }
      footer
        .padding(.top, 14)
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      .background.secondary,
      in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(summary.status.isFailed ? Color.orange.opacity(0.55) : Color.clear)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(.quaternary)
    )
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(
            summary.status.isFailed ? Color.orange.opacity(0.14) : Color.accentColor.opacity(0.12))
        Image(systemName: "arrow.triangle.2.circlepath")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(summary.status.isFailed ? Color.orange : Color.accentColor)
      }
      .frame(width: 38, height: 38)
      VStack(alignment: .leading, spacing: 2) {
        Text(summary.name)
          .font(.title3.weight(.semibold))
          .lineLimit(1)
        Text("HTTPS 订阅地址已隐藏")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .help("订阅主机：\(summary.host)（完整地址不入诊断与日志）")
      }
      Spacer(minLength: 12)
      badge
      if isRefreshing {
        ProgressView()
          .controlSize(.small)
          .padding(.horizontal, 6)
      } else {
        Button(summary.status.isFailed ? "重试" : "更新", action: onRefresh)
          .buttonStyle(.plain)
          .foregroundStyle(.tint)
          .font(.callout.weight(.medium))
      }
      Menu {
        Button("编辑 URL…", action: onEdit)
        Button("删除…", role: .destructive, action: onDelete)
      } label: {
        Image(systemName: "ellipsis")
          .font(.callout.weight(.medium))
          .foregroundStyle(.secondary)
          .frame(width: 24, height: 24)
          .contentShape(Rectangle())
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .accessibilityLabel("订阅操作")
    }
  }

  private var badge: some View {
    Text(summary.status.badgeText)
      .font(.caption.weight(.semibold))
      .foregroundStyle(badgeForeground)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(badgeBackground, in: Capsule())
  }

  private var badgeForeground: Color {
    switch summary.status {
    case .succeeded: .green
    case .failed: .orange
    case .never: .secondary
    }
  }

  private var badgeBackground: Color {
    switch summary.status {
    case .succeeded: Color.green.opacity(0.14)
    case .failed: Color.orange.opacity(0.14)
    case .never: Color(nsColor: .quaternaryLabelColor).opacity(0.3)
    }
  }

  /// 三列元数据：固定分组 | 服务器 | 上次成功刷新。
  private var meta: some View {
    HStack(alignment: .top, spacing: 24) {
      metaColumn("固定分组") {
        Text(groupName)
          .lineLimit(1)
          .help(groupName)
      }
      metaColumn("服务器") {
        Text("\(summary.serverCount) 台")
      }
      metaColumn("上次成功刷新") {
        if let date = summary.lastSucceededAt {
          dateText(date)
        } else {
          Text("—")
        }
      }
      Spacer(minLength: 0)
    }
  }

  @ViewBuilder
  private func subscriptionInformation(_ information: SubscriptionInformation) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if information.bytesUsed != nil || information.bytesRemaining != nil {
        HStack(alignment: .top, spacing: 24) {
          if let used = information.bytesUsed {
            metaColumn("已用流量") {
              Text(SubscriptionInformation.byteCountText(used, locale: locale))
            }
          }
          if let remaining = information.bytesRemaining {
            metaColumn("剩余流量") {
              Text(SubscriptionInformation.byteCountText(remaining, locale: locale))
            }
          }
        }
        if let fraction = information.usedFraction {
          ProgressView(value: fraction)
            .accessibilityLabel("流量消耗")
        }
      }
      if information.expiresAt != nil || information.trafficResetAt != nil {
        HStack(alignment: .top, spacing: 24) {
          if let expiresAt = information.expiresAt {
            metaColumn("到期时间") { dateText(expiresAt) }
          }
          if let resetAt = information.trafficResetAt {
            metaColumn("重置时间") { dateText(resetAt) }
          }
        }
      }
    }
  }

  private func dateText(_ date: Date) -> Text {
    Text(
      date,
      format: Date.FormatStyle(
        date: .abbreviated, time: .shortened, locale: locale, timeZone: timeZone))
  }

  private func metaColumn<Content: View>(
    _ label: LocalizedStringKey, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
      content()
        .font(.callout.weight(.medium))
        .foregroundStyle(.primary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var footer: some View {
    HStack(spacing: 6) {
      Image(systemName: "checkmark.shield")
        .font(.footnote)
        .foregroundStyle(.secondary)
      Text(summary.status.footerNote)
        .font(.footnote)
        .foregroundStyle(.secondary)
      Spacer(minLength: 0)
    }
  }
}

/// 「添加订阅」表单（工具栏入口）：粘贴 HTTPS 订阅地址；创建后立即首次刷新。
struct AddSubscriptionSheet: View {
  let workflow: CatalogWorkflow
  let errors: ErrorAlertPresenter
  @Environment(\.dismiss) private var dismiss

  @State private var urlString = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("粘贴订阅地址（必须 HTTPS，返回 SIP-008 JSON；Content-Type 需为 application/json; charset=utf-8）。")
        .font(.callout)
        .foregroundStyle(.secondary)
      TextField("https://example.com/subscription.json", text: $urlString)
        .textFieldStyle(.roundedBorder)
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
        _ = try await workflow.createSubscription(urlString: urlString)
        dismiss()
      } catch {
        errors.present(error)
      }
    }
  }
}

/// 「编辑订阅 URL」表单（保留订阅与固定分组身份）；保存后立即刷新。
/// URL 明文经显式命令读取。
private struct EditSubscriptionURLSheet: View {
  let workflow: CatalogWorkflow
  let errors: ErrorAlertPresenter
  let summary: SubscriptionSummary
  @Environment(\.dismiss) private var dismiss

  @State private var urlString = ""
  @State private var loaded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("编辑订阅地址。订阅身份与固定分组全部保留；新地址刷新成功前保留最后一次成功内容。")
        .font(.callout)
        .foregroundStyle(.secondary)
      TextField("https://example.com/subscription.json", text: $urlString)
        .textFieldStyle(.roundedBorder)
      HStack {
        Spacer()
        Button("取消", role: .cancel) { dismiss() }
        Button("保存并刷新") { save() }
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
      } catch {
        errors.present(error)
      }
    }
  }

  private func save() {
    Task {
      do {
        try await workflow.editSubscriptionURL(summary.id, urlString: urlString)
        dismiss()
      } catch {
        errors.present(error)
      }
    }
  }
}
