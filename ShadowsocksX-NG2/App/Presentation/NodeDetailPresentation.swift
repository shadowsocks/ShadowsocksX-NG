import Foundation

extension CatalogTreeNode {
  var isRootSubscriptionGroup: Bool {
    isGroup && source == .subscription && parentID == nil
  }
}

/// 详情会话的展示值；包含参数明文，不进入目录工作流的非秘密投影或持久快照。
@MainActor
struct NodeDetailPresentation {
  struct Property: Equatable {
    let label: String
    let value: String
  }

  enum PropertiesID: Hashable {
    case subscription
    case information
    case connection
    case pluginParameters
  }

  struct Properties: Equatable, Identifiable {
    let id: PropertiesID
    let title: String
    let items: [Property]
  }

  let title: String
  let subtitle: String
  let activationMessages: [String]
  let secondarySubtitle: String?
  var properties: [Properties]

  init(
    node: CatalogTreeNode, server: ServerDetailPresentation?,
    eligibility: ActivationEligibility?, isActiveTarget: Bool,
    subscription: SubscriptionSummary? = nil,
    locale: Locale = .current, timeZone: TimeZone = .current
  ) {
    title = node.name
    let isRootSubscriptionGroup = node.isRootSubscriptionGroup
    secondarySubtitle =
      isRootSubscriptionGroup
      ? String(localized: "配置由远端管理，本地不能修改。", table: "ServerDetails")
      : nil
    var descriptions = [
      node.isGroup
        ? (node.isManual
          ? String(localized: "本地", table: "ServerDetails")
          : String(localized: "订阅", table: "ServerDetails"))
        : (node.isManual
          ? String(localized: "本地配置", table: "ServerDetails")
          : String(localized: "订阅配置", table: "ServerDetails"))
    ]
    if isActiveTarget { descriptions.append(String(localized: "活动目标", table: "ServerDetails")) }
    subtitle = descriptions.joined(separator: " · ")
    var messages: [String] = []
    if node.isGroup {
      if let reason = eligibility?.ineligibility {
        switch reason {
        case .emptyGroup:
          messages.append(String(localized: "空分组，暂无子节点，不能激活。", table: "ServerDetails"))
        case .noCandidates:
          messages.append(String(localized: "分组中没有可激活的有效服务器。", table: "ServerDetails"))
        }
      }
      if let count = eligibility?.skippedInvalidCount, count > 0, eligibility?.canActivate == true {
        messages.append(
          String(localized: "激活时将跳过 \(count) 个存在已知阻塞问题的服务器。", table: "ServerDetails"))
      }
    } else {
      messages += node.invalidReasons.map { reason in
        if case .pluginNotProvided(let program) = reason,
          let warning = server?.plugin.availabilityWarning(for: program)
        {
          return warning
        }
        return AppPresentation.message(
          for: ActivationFailure.invalidLeaf(node: node.id, reason: reason))
      }
    }
    activationMessages = messages
    properties = []
    if isRootSubscriptionGroup,
      let subscriptionProperties = Self.subscriptionInformation(
        summary: subscription, locale: locale, timeZone: timeZone)
    {
      properties.append(subscriptionProperties)
    }
    properties.append(Self.information(for: node, eligibility: eligibility))
    if let server { properties.append(Self.connection(for: server)) }
  }

  private static func subscriptionInformation(
    summary: SubscriptionSummary?, locale: Locale, timeZone: TimeZone
  ) -> Properties? {
    guard let summary else { return nil }
    var items: [Property] = []
    if let date = summary.lastSucceededAt {
      items.append(
        Property(
          label: String(localized: "最后更新时间", table: "ServerDetails"),
          value: subscriptionTimestamp(date, locale: locale, timeZone: timeZone)))
    }
    if let used = summary.information?.bytesUsed {
      items.append(
        Property(
          label: String(localized: "已用流量", table: "ServerDetails"),
          value: SubscriptionInformation.byteCountText(used, locale: locale)))
    }
    if let remaining = summary.information?.bytesRemaining {
      items.append(
        Property(
          label: String(localized: "剩余流量", table: "ServerDetails"),
          value: SubscriptionInformation.byteCountText(remaining, locale: locale)))
    }
    if let date = summary.information?.expiresAt {
      items.append(
        Property(
          label: String(localized: "到期时间", table: "ServerDetails"),
          value: subscriptionTimestamp(date, locale: locale, timeZone: timeZone)))
    }
    if let date = summary.information?.trafficResetAt {
      items.append(
        Property(
          label: String(localized: "重置时间", table: "ServerDetails"),
          value: subscriptionTimestamp(date, locale: locale, timeZone: timeZone)))
    }
    guard !items.isEmpty else { return nil }
    return Properties(
      id: .subscription, title: String(localized: "订阅", table: "ServerDetails"), items: items)
  }

  private static func subscriptionTimestamp(
    _ date: Date, locale: Locale, timeZone: TimeZone
  ) -> String {
    date.formatted(
      Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: timeZone))
  }

  private static func connection(for server: ServerDetailPresentation) -> Properties {
    let program: String
    switch server.plugin.selection {
    case .none: program = String(localized: "无", table: "ServerDetails")
    case .named(let name), .unknown(let name): program = name
    }
    return Properties(
      id: .connection, title: String(localized: "连接信息", table: "ServerDetails"),
      items: [
        Property(label: String(localized: "地址", table: "ServerDetails"), value: server.address),
        Property(
          label: String(localized: "端口", table: "ServerDetails"), value: String(server.port)),
        Property(
          label: String(localized: "加密方式", table: "ServerDetails"), value: server.encryptionMethod),
        Property(label: String(localized: "插件", table: "ServerDetails"), value: program),
      ])
  }

  private static func information(
    for node: CatalogTreeNode, eligibility: ActivationEligibility?
  ) -> Properties {
    var information = [Property(label: "ID", value: node.id.rawValue)]
    if node.isGroup {
      information += [
        Property(
          label: String(localized: "有效服务器", table: "ServerDetails"),
          value: String(eligibility?.candidateCount ?? 0)),
        Property(
          label: String(localized: "无效服务器", table: "ServerDetails"),
          value: String(eligibility?.skippedInvalidCount ?? 0)),
      ]
    }
    information += [
      Property(
        label: String(localized: "创建时间", table: "ServerDetails"),
        value: Self.timestamp(node.createdAt)),
      Property(
        label: String(localized: "修改时间", table: "ServerDetails"),
        value: Self.timestamp(node.updatedAt)),
    ]
    return Properties(
      id: .information, title: String(localized: "信息", table: "ServerDetails"), items: information)
  }

  mutating func appendPluginParameters(_ raw: String) {
    guard !raw.isEmpty else { return }
    let items: [Property]
    if let parsed = PluginOptionsDraft.parse(raw) {
      items = parsed.items.map { item in
        Property(
          label: item.key,
          value: item.hasValue
            ? (item.value.isEmpty ? String(localized: "空值", table: "ServerDetails") : item.value)
            : String(localized: "开关", table: "ServerDetails"))
      }
    } else {
      items = [Property(label: String(localized: "原始文本", table: "ServerDetails"), value: raw)]
    }
    properties.append(
      Properties(
        id: .pluginParameters, title: String(localized: "插件参数", table: "ServerDetails"),
        items: items))
  }

  mutating func appendPluginParameterFailure() {
    properties.append(
      Properties(
        id: .pluginParameters, title: String(localized: "插件参数", table: "ServerDetails"),
        items: [
          Property(
            label: String(localized: "插件参数", table: "ServerDetails"),
            value: String(localized: "无法读取插件参数", table: "ServerDetails"))
        ]))
  }

  private static func timestamp(_ date: Date?) -> String {
    guard let date else { return "—" }
    return date.formatted(date: .numeric, time: .shortened)
  }
}
