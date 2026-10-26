import SwiftUI

struct PluginManagementRowView: View {
  let entry: PluginManagementRow
  @ObservedObject var catalog: PluginCatalog
  let beginManagedSettings: (String) -> Void
  let beginOverriding: (String) -> Void
  let beginEditing: (UUID) -> Void
  let remove: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      VStack(alignment: .leading, spacing: 3) {
        HStack(alignment: .top, spacing: 16) {
          pluginIdentity
            .frame(maxWidth: .infinity, alignment: .leading)
          actionButtons
        }
        if let path = entry.path {
          Text(path).font(.caption).foregroundStyle(.secondary)
            .lineLimit(1).truncationMode(.middle).help(path).textSelection(.enabled)
        }
      }
      if !entry.overriddenNames.isEmpty {
        Text("已被用户覆盖：" + entry.overriddenNames.joined(separator: ", "))
          .font(.caption).foregroundStyle(.secondary)
      }
      availabilityNotice
      if let program = entry.securityProgram, entry.availability == .available {
        PluginSecurityDetails(facts: catalog.securityFacts[program])
      }
    }
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private var pluginIdentity: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(entry.names.joined(separator: ", ")).font(.body)
      if let program = entry.managedProgram,
        let info = ManagedPluginCatalog.plugins.first(where: { $0.program == program })
      {
        managedIdentity(info)
      } else {
        Text(identityKind)
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private func managedIdentity(_ info: ManagedPluginInfo) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text("内置").foregroundStyle(.secondary)
      if let dependency = info.dependency {
        Text(verbatim: dependency.version).foregroundStyle(.secondary)
        if let projectURL = URL(string: dependency.projectURL) {
          Link(destination: projectURL) {
            projectLink(dependency.projectURL)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        Text("版本信息不可用").foregroundStyle(.secondary)
      }
    }
    .font(.caption)
  }

  private func projectLink(_ url: String) -> some View {
    Text(verbatim: url)
      .textSelection(.enabled)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var identityKind: String {
    if entry.managedProgram != nil { return String(localized: "内置") }
    return entry.overridesManaged ? String(localized: "用户覆盖") : String(localized: "用户添加")
  }

  @ViewBuilder
  private var actionButtons: some View {
    if let program = entry.managedProgram {
      Button {
        beginManagedSettings(program)
      } label: {
        HStack(spacing: 8) {
          Text("设置")
          Image(systemName: "chevron.right").font(.caption.weight(.semibold))
        }
      }
      .buttonStyle(.bordered)
      Menu(String(localized: "覆盖名称")) {
        ForEach(entry.names, id: \.self) { name in
          Button(name) { beginOverriding(name) }
            .disabled(entry.overriddenNames.contains(name))
        }
      }
    } else if let id = entry.recordID {
      Button {
        beginEditing(id)
      } label: {
        HStack(spacing: 8) {
          Text("编辑")
          Image(systemName: "chevron.right").font(.caption.weight(.semibold))
        }
      }
      .buttonStyle(.bordered)
      Button("删除", action: remove)
    }
  }

  @ViewBuilder
  private var availabilityNotice: some View {
    if let availability = entry.availability,
      let issue = PluginManagementCopy.availability(availability)
    {
      Label(issue, systemImage: "exclamationmark.triangle.fill")
        .font(.caption).foregroundStyle(.red)
    }
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
