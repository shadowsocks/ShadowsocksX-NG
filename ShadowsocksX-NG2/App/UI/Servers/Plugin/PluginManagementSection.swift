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
      "删除用户插件？",
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
    PluginManagementRowView(
      entry: entry, catalog: catalog,
      beginManagedSettings: { editor = model.beginManagedSettings($0) },
      beginOverriding: { editor = model.beginOverriding($0) },
      beginEditing: { editor = model.beginEditing($0) },
      remove: { removal = entry })
  }
}
