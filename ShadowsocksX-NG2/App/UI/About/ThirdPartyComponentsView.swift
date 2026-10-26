import SwiftUI

struct ThirdPartyComponentsView: View {
  static let sceneID = "third-party-components"
  @State private var contents: ThirdPartyComponents?
  @State private var failed = false

  var body: some View {
    Group {
      if let contents {
        ThirdPartyComponentsBrowser(contents: contents)
      } else if failed {
        ContentUnavailableView("第三方组件信息不可用", systemImage: "exclamationmark.triangle")
      } else {
        ProgressView()
      }
    }
    .frame(minWidth: 760, minHeight: 460)
    .task {
      contents = nil
      failed = false
      do {
        contents = try ThirdPartyComponents()
      } catch {
        failed = true
      }
    }
  }
}

private struct ThirdPartyComponentsBrowser: View {
  let contents: ThirdPartyComponents
  @State private var selection: String?

  var body: some View {
    HSplitView {
      List(contents.components, selection: $selection) { component in
        VStack(alignment: .leading, spacing: 4) {
          Text(verbatim: component.metadata.name)
            .font(.headline)
          Text(verbatim: component.metadata.version)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .tag(component.id)
      }
      .accessibilityLabel("组件")
      .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
      if let component = contents.components.first(where: { $0.id == selection }) {
        ThirdPartyComponentDetail(component: component)
          .id(component.id)
          .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .onAppear {
      if selection == nil { selection = contents.components.first?.id }
    }
  }
}

private struct ThirdPartyComponentDetail: View {
  let component: ThirdPartyComponents.Component

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Text(verbatim: component.metadata.name)
          .font(.title.bold())
        VStack(alignment: .leading, spacing: 12) {
          LabeledContent("版本") {
            Text(verbatim: component.metadata.version)
          }
          sourceLink("项目", address: component.metadata.projectURL)
          sourceLink("源码来源", address: component.metadata.sourceURL)
          sourceLink("分发来源", address: component.metadata.distributionURL)
        }
        documents("许可证", component.licenses)
        documents("附加声明", component.notices)
        documents("引用的公共许可证", component.sharedLicenses)
      }
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(24)
    }
  }

  private func sourceLink(_ title: LocalizedStringKey, address: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).foregroundStyle(.secondary)
      if let url = URL(string: address) {
        Link(destination: url) {
          Text(verbatim: address)
            .multilineTextAlignment(.leading)
        }
      }
    }
  }

  @ViewBuilder
  private func documents(
    _ title: LocalizedStringKey, _ documents: [ThirdPartyComponents.Document]
  ) -> some View {
    if !documents.isEmpty {
      VStack(alignment: .leading, spacing: 16) {
        Text(title).font(.title2.bold())
        ForEach(documents) { document in
          VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: document.name).font(.headline)
            Text(verbatim: document.text)
              .font(.system(.body, design: .monospaced))
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
  }
}
