import AppKit
import SwiftUI

struct PluginManagementSection: View {
  @ObservedObject var model: PluginManagementModel
  @ObservedObject private var catalog: PluginCatalog
  @State private var editor: PluginEditorSession?
  @State private var removal: PluginCatalogSnapshot.Entry?
  @State private var failure: String?

  init(model: PluginManagementModel) {
    self.model = model
    catalog = model.catalog
  }

  var body: some View {
    Section {
      if model.snapshot.mappingsUnreadable {
        Text(PluginManagementCopy.error(PluginMappingError.unreadable))
          .foregroundStyle(.red)
        Button("重试读取") {
          do { try model.retryReading() } catch { failure = PluginManagementCopy.error(error) }
        }
      } else {
        ForEach(model.snapshot.entries, id: \.program) { entry in
          pluginRow(entry)
        }
        HStack {
          Button("新增插件…") { editor = model.beginAdding() }
          Spacer()
          Button("刷新") { model.refresh() }
        }
      }
    } header: {
      Text("插件").font(.headline).padding(.vertical, 2)
    }
    .onAppear { model.refresh() }
    .onReceive(
      NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
    ) { _ in
      model.refresh()
    }
    .sheet(item: $editor) { session in
      PluginEditorSheet(model: model, session: session)
    }
    .confirmationDialog(
      removalIsOverride ? String(localized: "恢复内置插件？") : String(localized: "删除用户插件？"),
      isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }),
      titleVisibility: .visible, presenting: removal
    ) { entry in
      Button(
        removalIsOverride ? String(localized: "恢复内置") : String(localized: "删除"),
        role: .destructive
      ) {
        do { try model.remove(entry.program) } catch { failure = PluginManagementCopy.error(error) }
      }
      Button("取消", role: .cancel) {}
    } message: { entry in
      Text(
        entry.program + "\n\n"
          + (removalIsOverride
            ? String(localized: "服务器配置将保留，后续连接使用同名内置插件。")
            : String(localized: "服务器配置将保留，使用此名称的服务器可能无法连接。")))
    }
    .alert(
      "插件配置操作失败",
      isPresented: Binding(
        get: { failure != nil }, set: { if !$0 { failure = nil } }
      )
    ) {
      Button("确定", role: .cancel) { failure = nil }
    } message: {
      Text(failure ?? "")
    }
  }

  private var removalIsOverride: Bool {
    removal.map { ManagedPluginCatalog.info(forProgram: $0.program) != nil } ?? false
  }

  private func pluginRow(_ entry: PluginCatalogSnapshot.Entry) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .top, spacing: 16) {
        VStack(alignment: .leading, spacing: 3) {
          Text(entry.program).font(.body)
          Text(PluginManagementCopy.source(entry)).font(.caption).foregroundStyle(.secondary)
          if let path = entry.path {
            Text(path).font(.caption).foregroundStyle(.secondary)
              .lineLimit(1).truncationMode(.middle).help(path).textSelection(.enabled)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if entry.source == .managed {
          Button("覆盖…") { editor = model.beginOverriding(entry.program) }
        } else {
          Button("编辑…") { editor = model.beginEditing(entry.program) }
          Button(
            ManagedPluginCatalog.info(forProgram: entry.program) == nil
              ? String(localized: "删除…") : String(localized: "恢复内置…")
          ) { removal = entry }
        }
      }
      if let issue = PluginManagementCopy.availability(entry.availability) {
        Label(issue, systemImage: "exclamationmark.triangle.fill")
          .font(.caption).foregroundStyle(.red)
      }
      if entry.source == .user && entry.availability == .available {
        PluginSecurityDetails(facts: catalog.securityFacts[entry.program])
      }
    }
    .padding(.vertical, 4)
  }
}

private struct PluginSecurityDetails: View {
  let facts: PluginSecurityFacts?
  @State private var isExpanded = false

  var body: some View {
    if let facts {
      if let warning = PluginManagementCopy.securitySummary(facts) {
        Label(warning, systemImage: "exclamationmark.triangle")
          .font(.caption).foregroundStyle(.orange)
      }
      DisclosureGroup(isExpanded: $isExpanded) {
        VStack(alignment: .leading, spacing: 3) {
          Text(PluginManagementCopy.quarantine(facts.quarantine))
          Text(PluginManagementCopy.signature(facts.signature))
          Text(PluginManagementCopy.policy(facts.policy))
          Text("检查结果仅供参考，不能保证 macOS 允许或禁止运行。")
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      } label: {
        // macOS 上 DisclosureGroup 默认仅三角图标可点，整行铺开让文字也响应点击。
        Text("安全检查详情")
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
          .onTapGesture { withAnimation { isExpanded.toggle() } }
      }
      .font(.caption)
    } else {
      Text("正在检查安全信息…").font(.caption).foregroundStyle(.secondary)
    }
  }
}
