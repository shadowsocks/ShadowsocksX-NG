import AppKit
import SwiftUI

struct PluginManagementSection: View {
  @ObservedObject var model: PluginManagementModel
  @ObservedObject private var catalog: PluginCatalog
  @State private var editor: PluginEditorSession?
  @State private var removal: PluginManagementRow?
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
        ForEach(model.rows) { entry in
          pluginRow(entry)
        }
        HStack {
          Button {
            editor = model.beginAdding()
          } label: {
            HStack(spacing: 8) {
              Text("新增插件")
              Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
            }
          }
          .buttonStyle(.bordered)
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
      String(localized: "删除用户插件？"),
      isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }),
      titleVisibility: .visible, presenting: removal
    ) { entry in
      Button("删除", role: .destructive) {
        guard let id = entry.recordID else { return }
        do { try model.remove(id) } catch { failure = PluginManagementCopy.error(error) }
      }
      Button("取消", role: .cancel) {}
    } message: { entry in
      Text(
        entry.names.joined(separator: ", ") + "\n\n"
          + String(localized: "删除此记录的全部名称。服务器引用保留，同名内置插件恢复；其他名称可能无法连接。"))
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

  private func pluginRow(_ entry: PluginManagementRow) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .top, spacing: 16) {
        VStack(alignment: .leading, spacing: 3) {
          Text(entry.names.joined(separator: ", ")).font(.body)
          Text(
            entry.managedProgram != nil
              ? String(localized: "内置")
              : entry.overridesManaged ? String(localized: "用户覆盖") : String(localized: "用户添加")
          ).font(.caption).foregroundStyle(.secondary)
          if let path = entry.path {
            Text(path).font(.caption).foregroundStyle(.secondary)
              .lineLimit(1).truncationMode(.middle).help(path).textSelection(.enabled)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if let program = entry.managedProgram {
          Button {
            editor = model.beginManagedArguments(program)
          } label: {
            HStack(spacing: 8) {
              Text("启动参数")
              Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
            }
          }
          .buttonStyle(.bordered)
          Button("清空参数") {
            do { try model.clearManagedArguments(program) } catch {
              failure = PluginManagementCopy.error(error)
            }
          }.disabled(model.snapshot.managedArguments[program] == nil)
          Menu("覆盖名称") {
            ForEach(entry.names, id: \.self) { name in
              Button(name) { editor = model.beginOverriding(name) }
                .disabled(entry.overriddenNames.contains(name))
            }
          }
        } else if let id = entry.recordID {
          Button {
            editor = model.beginEditing(id)
          } label: {
            HStack(spacing: 8) {
              Text("编辑")
              Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
            }
          }
          .buttonStyle(.bordered)
          Button("删除") { removal = entry }
        }
      }
      if !entry.overriddenNames.isEmpty {
        Text(String(localized: "已被用户覆盖：") + entry.overriddenNames.joined(separator: ", "))
          .font(.caption).foregroundStyle(.secondary)
      }
      if let availability = entry.availability,
        let issue = PluginManagementCopy.availability(availability)
      {
        Label(issue, systemImage: "exclamationmark.triangle.fill")
          .font(.caption).foregroundStyle(.red)
      }
      if let program = entry.securityProgram, entry.availability == .available {
        PluginSecurityDetails(facts: catalog.securityFacts[program])
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
