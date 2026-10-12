import Combine
import Foundation

// MARK: - 原始接口事实

/// IPv6 地址的内核标志（经 `SIOCGIFAFLAG_IN6` 逐地址查询，netinet6/in6_var.h
/// 的 `IN6_IFF_*` 子集）。仅 IPv6 单播地址携带；IPv4 或查询失败为 nil。
struct LocalInterfaceV6Flags: OptionSet, Sendable {
  let rawValue: Int32
  /// `IN6_IFF_AUTOCONF`：SLAAC 自动配置地址。
  static let autoconf = Self(rawValue: IN6_IFF_AUTOCONF)
  /// `IN6_IFF_TEMPORARY`：RFC 4941 隐私临时地址（会轮换）。
  static let temporary = Self(rawValue: IN6_IFF_TEMPORARY)
  /// `IN6_IFF_SECURED`：稳定接口标识生成的地址。
  static let secured = Self(rawValue: IN6_IFF_SECURED)
  /// `IN6_IFF_DYNAMIC`：DHCPv6 分配的地址。
  static let dynamic = Self(rawValue: IN6_IFF_DYNAMIC)
}

/// 单个本机接口单播地址的原始事实：族与 IPv6 标记已判明，过滤、排序与
/// 取舍全部由工作流层策略完成。
struct LocalInterfaceAddress: Equatable, Sendable {
  enum Family: Equatable, Sendable {
    case ipv4
    case ipv6
  }

  /// 规范化 IP 文本（inet_ntop 呈现形，无作用域后缀）。
  let address: String
  let family: Family
  /// IPv6 链路本地（fe80::/10）；IPv4 链路本地不置位（属于允许接口的单播
  /// 地址时可以列出）。
  let isIPv6LinkLocal: Bool
  /// IPv6 地址内核标志（含临时地址、DHCPv6 等类型事实）；IPv4 或查询失败
  /// 为 nil——nil 不触发过滤，也不注记。
  let v6Flags: LocalInterfaceV6Flags?
}

/// 单个本机接口的原始事实：系统适配器逐接口提供，类型白名单、
/// 地址族过滤、名称回退与排序均不在适配器内发生。
struct LocalInterfaceFacts: Equatable, Sendable {
  /// BSD 接口名（lo0/en0/…）：地址关联与地址身份的锚点。
  let bsdName: String
  /// IFF_LOOPBACK。
  let isLoopback: Bool
  /// SCNetworkInterfaceGetInterfaceType 原文；无 SystemConfiguration 映射
  /// （如回环）为 nil。
  let interfaceType: String?
  /// SCNetworkInterfaceGetLocalizedDisplayName；缺失为 nil。
  let localizedName: String?
  /// 该接口的全部单播地址（未过滤）。
  let addresses: [LocalInterfaceAddress]
}

/// 本机接口事实来源缝：唯一的工作流层可注入事实来源，统一
/// 提供接口地址、类型、名称及变化通知；系统 API 查询细节封装于生产适配器，
/// 不为每个底层 API 另设 mock 协议。测试注入可编程替身。
@MainActor
protocol LocalInterfaceFactsReading: AnyObject {
  /// 当前全部本机接口的原始事实（未过滤、未排序）；枚举失败为 nil，
  /// 调用方按「仅兼容回环候选」退化。
  var interfaces: [LocalInterfaceFacts]? { get }
  /// 接口事实变化通知（网络变化后发值）；生产实现去抖，fake 同步手动。
  var changes: AnyPublisher<Void, Never> { get }
}
