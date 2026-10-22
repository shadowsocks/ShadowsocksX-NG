import SwiftUI

/// 浏览操作留在首页，测试与激活始终经过两页共享的 module。
struct HomeTargetCard: View {
  @ObservedObject var workflow: CatalogWorkflow
  @ObservedObject var browser: HomeTargetBrowser
  @ObservedObject var activation: ActivationFeedbackState
  let activeTargetID: NodeID?
  let showServers: () -> Void
  @State private var revealID: NodeID?
  @State private var revealRevision = 0

  private var rows: [CatalogTreeRow] {
    browser.rows(in: workflow.tree, favorites: workflow.favorites)
  }

  /// 子树含活动目标的分组集合（空心闪电候选）。
  private var activeAncestors: Set<NodeID> {
    workflow.tree.ancestors(of: activeTargetID)
  }

  private var selected: CatalogTreeNode? {
    browser.selection.flatMap { workflow.tree.node(withID: $0) }
  }

  var body: some View {
    ScrollViewReader { proxy in
      HomeCard(
        title: activeName,
        subtitle: activeTargetID.map { path(for: $0) },
        trailing: {
          Button(String(localized: "定位", table: "HomeTargets")) {
            requestReveal(
              browser.locate(activeTargetID, in: workflow.tree, favorites: workflow.favorites))
          }
          .disabled(activeTargetID == nil)
        },
        content: {
          VStack(alignment: .leading, spacing: 12) {
            toolbar
            directory
            Divider()
            selectionSummary
          }
          .padding(.top, 14)
        }
      )
      .disabled(activation.isPending)
      .onAppear {
        browser.reconcile(in: workflow.tree, favorites: workflow.favorites)
        requestReveal(
          browser.enterHome(
            current: activeTargetID, in: workflow.tree, favorites: workflow.favorites))
      }
      .task(id: revealRevision) {
        guard let revealID else { return }
        await Task.yield()
        guard !Task.isCancelled else { return }
        proxy.scrollTo(revealID, anchor: .center)
      }
    }
  }

  private var activeName: String {
    activeTargetID.flatMap { workflow.tree.node(withID: $0)?.name }
      ?? String(localized: "未选择活动目标", table: "HomeTargets")
  }

  private var toolbar: some View {
    HStack {
      Picker(
        String(localized: "目录视图", table: "HomeTargets"),
        selection: Binding(
          get: { browser.mode },
          set: { browser.setMode($0, in: workflow.tree, favorites: workflow.favorites) })
      ) {
        Text(String(localized: "全部", table: "HomeTargets")).tag(HomeTargetBrowser.Mode.all)
        Text(String(localized: "收藏", table: "HomeTargets")).tag(HomeTargetBrowser.Mode.favorites)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var directory: some View {
    VStack(spacing: 4) {
      HStack {
        Text(String(localized: "名称", table: "HomeTargets"))
        Spacer()
        Text(ConnectivityCopy.text("响应延迟"))
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 8)
      if rows.isEmpty {
        emptyDirectory
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(rows) { row in
              HomeTargetRow(
                row: row, workflow: workflow,
                selected: browser.selection == row.id, active: activeTargetID == row.id,
                containsActiveTarget: activeAncestors.contains(row.id),
                expandable: browser.mode == .all && row.node.isGroup,
                expanded: browser.expandedGroupIDs.contains(row.id),
                path: path(for: row.id),
                select: { browser.select(row.id) },
                toggle: { browser.toggleGroup(row.id, in: workflow.tree) }
              )
              .id(row.id)
            }
          }
        }
        .frame(height: min(CGFloat(rows.count) * HomeTargetRow.height, 360))
      }
    }
  }

  private var emptyDirectory: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(
        browser.mode == .all
          ? String(localized: "目录为空，请到服务器页添加配置。", table: "HomeTargets")
          : String(localized: "暂无收藏，请到服务器页收藏配置或分组。", table: "HomeTargets")
      )
      .foregroundStyle(.secondary)
      Button(String(localized: "前往服务器页", table: "HomeTargets"), action: showServers)
    }
    .font(.callout)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 12)
  }

  private var selectionSummary: some View {
    HStack(alignment: .top, spacing: 4) {
      VStack(alignment: .leading, spacing: 4) {
        if let selected {
          Text(selected.name).font(.callout.weight(.medium))
            .lineLimit(1).help(path(for: selected.id))
          Text(path(for: selected.id)).font(.caption).foregroundStyle(.secondary)
            .lineLimit(2).help(path(for: selected.id))
          if selected.isGroup, let eligibility = workflow.activationEligibility(for: selected.id) {
            Text(
              String(
                localized:
                  "可激活 \(eligibility.candidateCount) 个配置，将跳过 \(eligibility.skippedInvalidCount) 个已知无效配置。",
                table: "HomeTargets")
            )
            .font(.caption).foregroundStyle(.secondary)
          }
        } else {
          Text(String(localized: "请选择服务器或分组", table: "HomeTargets"))
            .font(.callout).foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Spacer()
      actions
    }
  }

  private var actions: some View {
    VStack(alignment: .trailing, spacing: 8) {
      HStack(alignment: .center, spacing: 8) {
        if let module = workflow.connectivity, let selected {
          ConnectivityTestButton(module: module, node: selected)
        } else {
          Button(ConnectivityCopy.text("延迟测试")) {}.disabled(true)
        }
        Button(
          activation.isPending
            ? String(localized: "激活中…", table: "HomeTargets")
            : String(localized: "激活", table: "HomeTargets"),
          systemImage: "bolt.fill"
        ) {
          guard let selected else { return }
          Task { @MainActor in
            // 现有运行状态卡片呈现失败；这里不重复弹窗或增加内联错误。
            _ = try? await activation.activate(selected.id, via: workflow)
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(activationDisabledReason != nil)
        .help(activationDisabledReason ?? String(localized: "激活所选目标", table: "HomeTargets"))
      }
      Text(activationDisabledReason ?? "")
        .font(.caption).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var activationDisabledReason: String? {
    if activation.isPending { return String(localized: "激活中…", table: "HomeTargets") }
    guard let selected else { return String(localized: "尚未选择目标", table: "HomeTargets") }
    if selected.id == activeTargetID { return String(localized: "当前项已激活", table: "HomeTargets") }
    guard let eligibility = workflow.activationEligibility(for: selected.id),
      eligibility.canActivate
    else {
      if selected.isGroup {
        return String(localized: "分组中没有可激活的有效服务器。", table: "ServerDetails")
      }
      return selected.invalidReasons.first.map {
        AppPresentation.message(for: ActivationFailure.invalidLeaf(node: selected.id, reason: $0))
      } ?? String(localized: "配置不满足本地激活条件", table: "HomeTargets")
    }
    return nil
  }

  private func path(for id: NodeID) -> String {
    guard let node = workflow.tree.node(withID: id) else { return "" }
    let source = node.isManual ? String(localized: "本地") : String(localized: "订阅")
    return ([source] + (workflow.tree.pathComponents(for: id) ?? [])).joined(separator: " / ")
  }

  private func requestReveal(_ id: NodeID?) {
    guard let id else { return }
    revealID = id
    revealRevision += 1
  }
}
