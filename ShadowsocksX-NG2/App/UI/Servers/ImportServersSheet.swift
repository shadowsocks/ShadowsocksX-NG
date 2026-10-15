import SwiftUI
import UniformTypeIdentifiers

/// 统一导入面板（docs/design/unified-server-import.md）：拖放多文件（二维码
/// 图片 / SIP-008 JSON / ss:// 文本）、剪贴板 ss:// 一键导入与旧版直接导入
/// 共用同一落点（随侧栏选中）与逐来源结果区。来源独立解码、独立提交；
/// 成功与失败同位呈现，面板不自动关闭。
struct ImportServersSheet: View {
  let workflow: CatalogWorkflow
  let clipboard: any TextClipboard
  @Binding var selection: NodeID?
  var selectNewNodes = false
  @Environment(\.dismiss) private var dismiss

  @State private var resultRows: [ImportResultRow] = []
  @State private var isImporting = false
  @State private var showFileImporter = false
  @State private var hovering = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("导入Shadowsocks服务器配置")
          .font(.title2.weight(.semibold))
        Spacer()
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.title3)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("关闭")
      }
      targetHint
      dropZone
      if !resultRows.isEmpty {
        resultList
      }
      HStack {
        Button("从剪贴板中导入 ss:// 链接") { importClipboard() }
          .disabled(isImporting)
        if workflow.legacyImportState.snapshotFound {
          Button(legacyButtonTitle) { importLegacy() }
            .disabled(isImporting)
        }
      }
    }
    .padding(24)
    .frame(minWidth: 520)
    .fileImporter(
      isPresented: $showFileImporter,
      allowedContentTypes: [.image, .json, .plainText],
      allowsMultipleSelection: true
    ) { result in
      importFiles((try? result.get()) ?? [])
    }
  }

  /// 落点提示随侧栏选中实时变化（选中手动组→组内；选中服务器→其父组；
  /// 其余→目录根）。
  private var targetHint: some View {
    let parent = workflow.importTargetParent(for: selection)
    let path = parent.flatMap { workflow.tree.pathSummary(for: $0) } ?? String(localized: "目录根")
    return Text("将导入到：\(path)")
      .font(.callout)
      .foregroundStyle(.secondary)
  }

  private var dropZone: some View {
    VStack(spacing: 8) {
      Image(systemName: "tray.and.arrow.down")
        .font(.system(size: 34))
        .foregroundStyle(hovering ? .orange : .secondary)
      Text("拖动文件到这里")
        .font(.headline)
      Text("二维码图片\nSIP008 JSON 文件\n包含 ss:// 链接的 txt 文件")
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 170)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(hovering ? Color.orange.opacity(0.08) : Color.primary.opacity(0.03))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
        .foregroundStyle(hovering ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.separator))
    )
    .contentShape(Rectangle())
    .onTapGesture { showFileImporter = true }
    .dropDestination(for: URL.self) { urls, _ in
      importFiles(urls)
      return !urls.isEmpty
    } isTargeted: {
      hovering = $0
    }
    .help("选择文件…")
  }

  private var resultList: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        ForEach(resultRows) { row in
          VStack(alignment: .leading, spacing: 4) {
            Label("\(row.sourceName)：\(row.title)", systemImage: iconName(row.style))
              .foregroundStyle(iconColor(row.style))
            ForEach(row.details, id: \.self) { detail in
              Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxHeight: 200)
  }

  private var legacyButtonTitle: String {
    workflow.legacyImportState.completed
      ? String(localized: "再次导入旧版本服务器") : String(localized: "从旧版本 ShadowsocksX-NG 导入")
  }

  // MARK: - 导入动作

  private func importFiles(_ urls: [URL]) {
    var sources: [ImportSource] = []
    for url in urls {
      guard let data = try? Data(contentsOf: url) else {
        resultRows.append(
          ImportOutcomePresentation.unreadableFileRow(fileName: url.lastPathComponent))
        continue
      }
      sources.append(.file(name: url.lastPathComponent, data: data))
    }
    guard !sources.isEmpty else { return }
    run(sources)
  }

  private func importClipboard() {
    // 空剪贴板也走统一管线：来源级失败「没有可导入的 ss:// 链接」入结果区。
    run([.clipboardText(clipboard.read() ?? "")])
  }

  /// 统一入口：来源独立提交；成功来源切换侧栏选中到其落点/新建分组。
  private func run(_ sources: [ImportSource]) {
    guard !isImporting else { return }
    isImporting = true
    let parent = workflow.importTargetParent(for: selection)
    Task {
      let outcome = await workflow.importServers(from: sources, into: parent)
      resultRows.append(
        contentsOf: outcome.sources.map { sourceOutcome in
          ImportOutcomePresentation.row(
            for: sourceOutcome, targetName: targetDisplayName(for: sourceOutcome.result))
        })
      if let candidate = selectNewNodes
        ? outcome.newNodeSelectionCandidate : outcome.selectionCandidate
      {
        selection = candidate
      }
      isImporting = false
    }
  }

  private func importLegacy() {
    guard !isImporting else { return }
    isImporting = true
    let reimport = workflow.legacyImportState.completed
    Task {
      do {
        let outcome = try await workflow.importLegacy(reimport: reimport)
        resultRows.append(ImportOutcomePresentation.row(for: outcome.report))
        selection = outcome.groupID
      } catch {
        resultRows.append(ImportOutcomePresentation.failureRow(error))
      }
      isImporting = false
    }
  }

  private func targetDisplayName(for result: ImportSourceResult) -> String {
    guard case .imported(_, let groupID) = result else { return "" }
    guard let groupID else { return String(localized: "目录根") }
    let name = workflow.displayName(for: groupID)
    return name.isEmpty ? String(localized: "目录根") : name
  }

  // MARK: - 结果行样式

  private func iconName(_ style: ImportResultRow.Style) -> String {
    switch style {
    case .success: return "checkmark.circle.fill"
    case .partial: return "exclamationmark.triangle.fill"
    case .failure: return "xmark.circle.fill"
    }
  }

  private func iconColor(_ style: ImportResultRow.Style) -> Color {
    switch style {
    case .success: return .green
    case .partial: return .orange
    case .failure: return .red
    }
  }
}
