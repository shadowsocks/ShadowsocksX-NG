import SwiftUI

/// Browsing and offline testing go through the workflow.
struct RulesView: View {
  @ObservedObject var workflow: RulesWorkflow
  @Environment(\.openWindow) private var openWindow
  /// 规则编辑草稿与编辑 sheet 由本页自持：@State 生命周期绑定在 rules
  /// destination 分支上，离开分区即丢弃（与壳级清稿等价）。
  @State private var ruleDraft: CustomRuleDraft?
  /// 删除确认由本页自持，工具栏按钮与右键菜单共用同一确认弹窗。
  @State private var deletionConfirmation: CustomRuleDeletion?

  var body: some View {
    VStack(spacing: 0) {
      RulesAddressTestView(workflow: workflow)
      Divider()
      HStack(spacing: 0) {
        VStack(spacing: 0) {
          sourceList
          if let source = workflow.snapshot.sources.first(where: {
            $0.id == workflow.snapshot.query.source && $0.metadata != nil
          }) {
            Divider()
            RulesSourceSummaryView(source: source) {
              if workflow.openSourceReport(source.id) {
                openWindow(id: RulesReportView.sceneID)
              }
            }.padding(10)
          }
        }.frame(width: 180)
        Divider()
        VStack(spacing: 8) {
          filters
          ruleTable.overlay { emptyState }
          if let row = workflow.selectedRelationshipRow {
            Divider()
            RulesRelationshipsView(row: row)
              .frame(maxHeight: 180)
          }
        }.frame(minWidth: 400, maxWidth: .infinity)
      }
    }
    .task {
      if workflow.snapshot.version.isEmpty { await workflow.refresh() }
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(RulesCopy.text("新增规则"), systemImage: "plus") {
          ruleDraft = workflow.makeCustomRuleDraft()
        }
        .disabled(!workflow.snapshot.isComplete)
      }
      ToolbarItem(placement: .primaryAction) {
        Button(RulesCopy.text("删除规则"), systemImage: "trash") {
          deletionConfirmation = workflow.prepareCustomRuleDeletion()
        }
        .disabled(!canDeleteSelection)
      }
    }
    .sheet(item: $ruleDraft) { draft in
      CustomRuleEditorSheet(workflow: workflow, draft: draft)
    }
    .alert(
      countText("删除 %lld 条自定义规则？", deletionConfirmation?.customIDs.count ?? 0),
      isPresented: Binding(
        get: { deletionConfirmation != nil }, set: { if !$0 { deletionConfirmation = nil } }),
      presenting: deletionConfirmation
    ) { captured in
      Button(RulesCopy.text("删除"), role: .destructive) {
        deletionConfirmation = nil
        Task { await workflow.deleteCustomRules(captured) }
      }
      Button(RulesCopy.text("取消"), role: .cancel) { deletionConfirmation = nil }
    } message: { _ in
      Text(RulesCopy.text("只删除所选自定义条目。其他来源的规则和已有禁用记录将保留。"))
    }
  }

  @ViewBuilder
  private var emptyState: some View {
    if workflow.snapshot.operationStatus == .initialLoading {
      ProgressView(RulesCopy.text("正在加载规则…"))
    } else if workflow.snapshot.rows.isEmpty && !workflow.snapshot.isLoading {
      if workflow.snapshot.issues.isEmpty {
        ContentUnavailableView(
          RulesCopy.text("没有符合条件的规则"), systemImage: "line.3.horizontal.decrease.circle")
      } else {
        VStack(spacing: 10) {
          Label(RulesCopy.text("集合不完整"), systemImage: "exclamationmark.triangle")
          RulesCollectionIssuesView(issues: workflow.snapshot.issues)
          Button(RulesCopy.text("刷新规则")) {
            Task { await workflow.refresh(retryFailedSources: true) }
          }
          .disabled(workflow.snapshot.isCommitting)
        }.padding()
      }
    }
  }

  private var sourceList: some View {
    List(selection: sourceBinding) {
      ForEach([RulesSource.custom] + workflow.preset.sources + [.fixed]) { source in
        HStack {
          Text(source.label)
          Spacer()
          if let metadata = workflow.snapshot.sources.first(where: { $0.id == source }) {
            Text(metadata.count, format: .number).foregroundStyle(.secondary)
          } else if !workflow.snapshot.isLoading && !workflow.snapshot.version.isEmpty {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
          }
        }.tag(source)
      }
    }
  }

  private var filters: some View {
    VStack(spacing: 8) {
      HStack {
        actionFilter
          .fixedSize()
        enabledFilter
          .fixedSize()
        RulesOperationStatusView(workflow: workflow)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      TextField(
        RulesCopy.text("搜索规则"),
        text: Binding(
          get: { workflow.snapshot.query.search },
          set: { value in updateQuery { $0.search = value } })
      )
      .textFieldStyle(.roundedBorder)
    }
    .padding(8)
  }

  private var actionFilter: some View {
    Picker(
      RulesCopy.text("行动"),
      selection: Binding(
        get: { workflow.snapshot.query.action },
        set: { value in updateQuery { $0.action = value } })
    ) {
      Text(RulesCopy.text("全部行动")).tag(Optional<RuleAction>.none)
      Text(RulesCopy.text("直连")).tag(Optional(RuleAction.direct))
      Text(RulesCopy.text("代理")).tag(Optional(RuleAction.proxy))
    }
    .pickerStyle(.segmented)
    .labelsHidden()
  }

  private var enabledFilter: some View {
    Picker(
      RulesCopy.text("启用"),
      selection: Binding(
        get: { workflow.snapshot.query.enabled },
        set: { value in updateQuery { $0.enabled = value } })
    ) {
      Text(RulesCopy.text("全部")).tag(Optional<Bool>.none)
      Text(RulesCopy.text("已启用")).tag(Optional(true))
      Text(RulesCopy.text("已禁用")).tag(Optional(false))
    }
    .pickerStyle(.segmented)
    .labelsHidden()
  }

  private var ruleTable: some View {
    Table(
      workflow.snapshot.rows,
      selection: Binding(
        get: { workflow.snapshot.selection },
        set: { ids in DispatchQueue.main.async { workflow.select(ids) } })
    ) {
      TableColumn(RulesCopy.text("启用")) { row in
        Toggle(
          RulesCopy.text("启用"),
          isOn: Binding(
            get: { row.isEnabled },
            set: { enabled in
              guard let identity = row.identity else { return }
              Task { await workflow.setEnabled(enabled, identities: [identity]) }
            })
        )
        .labelsHidden()
        .disabled(row.isFixed || !workflow.snapshot.isComplete || workflow.snapshot.isCommitting)
      }.width(45)
      TableColumn(RulesCopy.text("匹配内容")) { row in Text(verbatim: row.displayContent) }
        .width(min: 120, ideal: 170)
      TableColumn(RulesCopy.text("类型")) { row in Text(verbatim: row.matchType) }
        .width(min: 70, ideal: 80)
      TableColumn(RulesCopy.text("行动")) { row in Text(row.actionLabel) }
        .width(50)
      TableColumn(RulesCopy.text("来源")) { row in Text(row.sourceLabels) }
        .width(min: 75, ideal: 90)
      TableColumn(RulesCopy.text("状态")) { row in Text(row.statusLabel) }
        .width(min: 80, ideal: 110)
      TableColumn("") { row in
        if let id = row.customIDs.first {
          Button(RulesCopy.text("编辑规则"), systemImage: "pencil") {
            ruleDraft = workflow.makeCustomRuleDraft(editing: id)
          }
          .labelStyle(.iconOnly)
          .help(RulesCopy.text("编辑规则"))
          .disabled(!workflow.snapshot.isComplete)
        }
      }.width(30)
    }.frame(minWidth: 0, maxWidth: .infinity)
      .contextMenu {
        ForEach([true, false], id: \.self) { enabled in
          Button {
            let identities = workflow.actionableSelection
            Task { await workflow.setEnabled(enabled, identities: identities) }
          } label: {
            Text(
              RulesCopy.text(enabled ? "启用" : "禁用") + " ("
                + String(workflow.actionableSelection.count) + ")")
          }
          .disabled(
            workflow.actionableSelection.isEmpty || !workflow.snapshot.isComplete
              || workflow.snapshot.isCommitting)
        }
        if workflow.snapshot.query.source == .custom {
          Divider()
          Button(role: .destructive) {
            deletionConfirmation = workflow.prepareCustomRuleDeletion()
          } label: {
            Text(
              RulesCopy.text("删除") + " ("
                + String(workflow.deletableSelection.count) + ")")
          }
          .disabled(!canDeleteSelection)
        }
      }
  }

  private var sourceBinding: Binding<RulesSource?> {
    Binding(
      get: {
        workflow.snapshot.query.source ?? .custom
      },
      set: { choice in
        guard let choice else { return }
        updateQuery {
          $0.source = choice
        }
      })
  }

  /// 删除只针对自定义条目：左侧须选“自定义规则”，且所选行含自定义规则、页完整。
  private var canDeleteSelection: Bool {
    workflow.snapshot.query.source == .custom && workflow.snapshot.isComplete
      && !workflow.deletableSelection.isEmpty
  }

  private func countText(_ key: String, _ count: Int) -> String {
    String.localizedStringWithFormat(RulesCopy.text(key), Int64(count))
  }

  // Native controls can write their bindings during a SwiftUI update. Publish
  // after that pass, and merge each edit into the latest query so queued edits
  // to different filters do not overwrite one another.
  private func updateQuery(_ update: @escaping @MainActor (inout RulesQuery) -> Void) {
    DispatchQueue.main.async {
      var query = workflow.snapshot.query
      update(&query)
      workflow.query(query)
    }
  }

}

struct RulesRelationshipsView: View {
  let row: RulesRow

  var body: some View {
    ScrollView { RulesRelationshipsContent(row: row).padding() }
  }
}

struct RulesRelationshipsContent: View {
  let row: RulesRow

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach([RuleRelationship.Kind.absorption, .shadowing], id: \.self) { kind in
        let relationships = row.relationships.filter { $0.kind == kind }
        let fixed = row.fixedCoverage.flatMap { coverage in
          row.action == (kind == .absorption ? .direct : .proxy) ? coverage : nil
        }
        if !relationships.isEmpty || fixed != nil {
          VStack(alignment: .leading, spacing: 4) {
            Text(RulesCopy.text(kind == .absorption ? "被同行动规则覆盖" : "被相反行动规则遮蔽"))
            ForEach(relationships, id: \.kind) { relationship in
              let covering = relationship.covering.filter { identity in
                !(identity.action == .direct
                  && (fixed?.matches.contains(identity.match) ?? false))
              }
              if !covering.isEmpty && relationship.extent == .partial {
                Text(RulesCopy.text("部分重叠"))
              }
              ForEach(covering, id: \.self) { identity in
                Text(
                  verbatim: identity.match.browsingContent + " · "
                    + identity.match.browsingType + " · "
                    + RulesCopy.text(identity.action == .direct ? "直连" : "代理"))
              }
            }
            if let fixed {
              Text(
                RulesCopy.text("固定本地策略")
                  + (fixed.extent == .partial ? " · " + RulesCopy.text("部分重叠") : ""))
              ForEach(fixed.matches, id: \.self) { match in
                Text(verbatim: match.browsingContent)
              }
              if fixed.includesSimpleHostname { Text(RulesCopy.text("简单主机名")) }
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .textSelection(.enabled)
  }
}

enum RulesCopy {
  static func text(_ key: String) -> String {
    NSLocalizedString(key, tableName: "Rules", bundle: .main, value: key, comment: "")
  }
}

extension RulesSource {
  var label: String {
    switch self {
    case .custom: RulesCopy.text("自定义规则")
    case .fixed: RulesCopy.text("固定本地策略")
    case .geolocationCN: "geolocation-cn"
    case .chinaIPv4: "china-ipv4"
    case .gfwlist: "GFWList"
    }
  }
}

extension RulesRow {
  var displayContent: String { identity?.match.editingContent ?? RulesCopy.text("简单主机名") }
  var sourceLabels: String {
    guard hasCurrentSource else { return RulesCopy.text("无当前来源") }
    return RulesSource.allCases.filter { sources.contains($0) }.map(\.label).joined(separator: ", ")
  }
  var actionLabel: String { RulesCopy.text(action == .direct ? "直连" : "代理") }
  var matchType: String { identity?.match.browsingType ?? RulesCopy.text("简单主机名") }
  var statusLabel: String {
    if isFixed { return RulesCopy.text("固定本地策略") }
    if !isEnabled { return RulesCopy.text("已禁用") }
    var labels = relationships.map(\.browsingLabel)
    if let fixedCoverage {
      let label =
        RulesCopy.text(action == .direct ? "被同行动规则覆盖" : "被相反行动规则遮蔽")
        + " · " + RulesCopy.text("固定本地策略")
      labels.append(
        fixedCoverage.extent == .partial ? label + " · " + RulesCopy.text("部分重叠") : label)
    }
    return labels.isEmpty ? RulesCopy.text("独立候选") : labels.joined(separator: "; ")
  }
}

extension RuleRelationship {
  var browsingLabel: String {
    let label = RulesCopy.text(kind == .absorption ? "被同行动规则覆盖" : "被相反行动规则遮蔽")
    return extent == .partial ? label + " · " + RulesCopy.text("部分重叠") : label
  }
}

extension RuleMatch {
  var browsingType: String {
    if editingKind == .ipAddress { return RulesCopy.text("IP 地址") }
    return switch pattern {
    case .domainExact: RulesCopy.text("精确域名")
    case .domainSuffix: RulesCopy.text("域名后缀")
    case .ipv4CIDR: "IPv4 CIDR"
    case .ipv6CIDR: "IPv6 CIDR"
    }
  }
}
