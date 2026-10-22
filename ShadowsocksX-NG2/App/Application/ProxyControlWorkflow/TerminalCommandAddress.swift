import Foundation
import SystemConfiguration

// MARK: - 命令地址投影

/// 首页命令地址候选（GLOSSARY.md「Terminal command address」）。身份 = BSD
/// 接口身份 + 规范化 IP；显示名与类型注记仅用于呈现，不参与身份，由呈现层
/// 自行组合（菜单项主行 IP、副标题「注记 - 名称」与收起状态说明行）。
struct TerminalCommandAddress: Equatable, Sendable {
  /// BSD 接口名；回环固定为 lo0。
  let bsdName: String
  /// 规范化 IP 文本。
  let address: String
  /// 系统本地化接口名称，缺失回退 BSD 名；回环显示 lo0。
  let displayName: String
  /// IPv6 地址类型注记（与 ifconfig 同源：autoconf secured / autoconf /
  /// dynamic）；IPv4 或标志缺失为 nil。
  let annotation: String?

  init(bsdName: String, address: String, displayName: String, annotation: String? = nil) {
    self.bsdName = bsdName
    self.address = address
    self.displayName = displayName
    self.annotation = annotation
  }

  /// 跨刷新匹配既有选择的身份（不含显示名与注记；两者变化不使选择失效）。
  var identity: TerminalCommandAddressIdentity {
    TerminalCommandAddressIdentity(bsdName: bsdName, address: address)
  }
}

/// 命令地址身份：BSD 接口名 + 规范化 IP。
struct TerminalCommandAddressIdentity: Equatable, Hashable, Sendable {
  let bsdName: String
  let address: String
}

/// 首页命令地址选择器投影：可见性、候选与生效选择一次观察
/// 产出，所有字段来自同一时间点。
struct TerminalCommandAddressPicker: Equatable, Sendable {
  /// 局域网关闭时隐藏。
  let isVisible: Bool
  /// 用户可见候选（已过滤、已排序；至少含本地回环项）。
  let candidates: [TerminalCommandAddress]
  /// 当前生效选择；恒为候选之一（选择失效自动回退默认回环）。
  let selected: TerminalCommandAddress
}

// MARK: - 派生策略

/// 首页命令地址策略：接口原始事实 + 已保存局域网监听方式 → 用户可见
/// 候选与生效选择。纯派生：类型白名单、地址族过滤、链路本地/通配排除、名称
/// 回退、排序合并与失效回退全部在此。测试以原始事实替身驱动本策略，不直接
/// 注入已过滤候选。
enum TerminalCommandAddressPolicy {
  /// 非回环接口的严格类型白名单：仅 SystemConfiguration 的 Wi‑Fi（IEEE80211）
  /// 与 Ethernet 类型；不以接口名前缀或通用链路类型代替，无法确认属于允许
  /// 类型的非回环接口排除。
  private static let allowedInterfaceTypes: Set<String> = [
    kSCNetworkInterfaceTypeIEEE80211 as String,
    kSCNetworkInterfaceTypeEthernet as String,
  ]

  /// 通配绑定地址不能用作命令目标。
  private static let wildcardAddresses: Set<String> = ["0.0.0.0", "::"]

  /// 一次观察的完整选择器事实。`selection` 不在候选中（地址消失、地址族
  /// 不兼容或枚举失败）时回退本地入口 127.0.0.1。
  static func picker(
    mode: ListenerMode,
    interfaces: [LocalInterfaceFacts]?,
    selection: TerminalCommandAddressIdentity?
  ) -> TerminalCommandAddressPicker {
    let candidates = candidates(for: mode, interfaces: interfaces)
    let selected = candidates.first { $0.identity == selection } ?? defaultLoopback(for: mode)
    return TerminalCommandAddressPicker(
      isVisible: mode != .disabled,
      candidates: candidates,
      selected: selected)
  }

  /// 候选列表：本地入口 127.0.0.1 置顶，其余来自白名单接口；
  /// 仅本机方式监听器只绑定 127.0.0.1，候选不含接口地址。枚举失败（nil）
  /// 仅提供本地回环候选。
  static func candidates(
    for mode: ListenerMode,
    interfaces: [LocalInterfaceFacts]?
  ) -> [TerminalCommandAddress] {
    let loopbacks = [defaultLoopback(for: mode)]
    guard mode != .disabled, let interfaces else { return loopbacks }
    return loopbacks + interfaceCandidates(mode: mode, interfaces: interfaces)
  }

  /// 始终有效的本地回环地址。
  static func defaultLoopback(for mode: ListenerMode) -> TerminalCommandAddress {
    TerminalCommandAddress(
      bsdName: "lo0", address: "127.0.0.1", displayName: "lo0", annotation: nil)
  }

  // MARK: - 派生细节

  /// 待排序的接口分组：显示名 + BSD 名 + 该接口的地址候选。
  private struct InterfaceGroup {
    let name: String
    let bsdName: String
    let addresses: [TerminalCommandAddress]
  }

  private static func interfaceCandidates(
    mode: ListenerMode,
    interfaces: [LocalInterfaceFacts]
  ) -> [TerminalCommandAddress] {
    var groups: [InterfaceGroup] = []
    for interface in interfaces where !interface.isLoopback {
      guard let type = interface.interfaceType, allowedInterfaceTypes.contains(type) else {
        continue
      }
      // 显示名缺失回退 BSD 名；回退不放宽类型过滤。
      let name = interface.localizedName ?? interface.bsdName
      var seen = Set<String>()
      let accepted = interface.addresses
        .filter { isAcceptable($0, mode: mode) }
        .filter { seen.insert($0.address).inserted }  // 同一接口重复 IP 合并
      let addresses =
        accepted
        .sorted { lhs, rhs in
          // 同一接口先 IPv4 后 IPv6，再按地址稳定排序。
          if lhs.family != rhs.family { return lhs.family == .ipv4 }
          return lhs.address < rhs.address
        }
        .map {
          TerminalCommandAddress(
            bsdName: interface.bsdName,
            address: $0.address,
            displayName: name,
            annotation: annotation(for: $0))
        }
      if !addresses.isEmpty {
        groups.append(InterfaceGroup(name: name, bsdName: interface.bsdName, addresses: addresses))
      }
    }
    return
      groups
      .sorted { lhs, rhs in
        // 其余项按接口名称排序（大小写不敏感，BSD 回退名与本地化名混排）；
        // 同显示名以 BSD 名保持稳定。
        let lhsName = lhs.name.lowercased()
        let rhsName = rhs.name.lowercased()
        return lhsName == rhsName ? lhs.bsdName < rhs.bsdName : lhsName < rhsName
      }
      .flatMap(\.addresses)
  }

  private static func isAcceptable(
    _ address: LocalInterfaceAddress, mode: ListenerMode
  ) -> Bool {
    guard !wildcardAddresses.contains(address.address) else { return false }
    // IPv6 链路本地需要额外接口作用域，不作为命令目标；IPv4 链路本地允许。
    if address.family == .ipv6, address.isIPv6LinkLocal { return false }
    // RFC 4941 隐私临时地址会轮换，不适合作为其他设备长期使用的命令目标。
    if address.v6Flags?.contains(.temporary) == true { return false }
    switch (mode, address.family) {
    case (.allIPv4Interfaces, .ipv4):
      return true
    case (.allIPv4AndIPv6Interfaces, _):
      return true
    case (.allIPv6Interfaces, .ipv6):
      return true
    default:
      return false
    }
  }

  /// IPv6 地址类型注记（与 ifconfig 同源的打印逻辑）；无标志（标志查询
  /// 失败或纯回环）不注记。
  private static func annotation(for address: LocalInterfaceAddress) -> String? {
    guard let flags = address.v6Flags else { return nil }
    if flags.contains(.autoconf) {
      if flags.contains(.secured) { return "autoconf secured" }
      if flags.contains(.temporary) { return "autoconf temporary" }
      return "autoconf"
    }
    if flags.contains(.secured) { return "secured" }
    if flags.contains(.dynamic) { return "dynamic" }
    return nil
  }
}
