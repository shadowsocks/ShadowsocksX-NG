import Combine
import Foundation

@testable import ShadowsocksX_NG2

/// 测试专用地址便捷构造（数组字面量内以 `.ipv4("…")` 使用）。
extension LocalInterfaceAddress {
  static func ipv4(_ text: String) -> LocalInterfaceAddress {
    LocalInterfaceAddress(address: text, family: .ipv4, isIPv6LinkLocal: false, v6Flags: nil)
  }

  static func ipv6(
    _ text: String, linkLocal: Bool = false, flags: LocalInterfaceV6Flags? = nil
  ) -> LocalInterfaceAddress {
    LocalInterfaceAddress(address: text, family: .ipv6, isIPv6LinkLocal: linkLocal, v6Flags: flags)
  }
}

/// 可编程本机接口事实替身：原始接口事实可编程（含枚举失败
/// nil），变化通知同步手动发值。替身只提供原始事实，让生产策略实际完成
/// 过滤、排序、名称回退与地址选择。
@MainActor
final class FakeLocalInterfaceFacts: LocalInterfaceFactsReading {
  var interfaces: [LocalInterfaceFacts]?
  private let changeSubject = PassthroughSubject<Void, Never>()
  var changes: AnyPublisher<Void, Never> { changeSubject.eraseToAnyPublisher() }

  init(interfaces: [LocalInterfaceFacts]? = []) {
    self.interfaces = interfaces
  }

  func emitChange() { changeSubject.send() }

  // MARK: - 事实构造辅助

  /// Wi-Fi 接口事实（类型 IEEE80211）。
  static func wifi(
    bsdName: String = "en0", localizedName: String? = "Wi-Fi",
    addresses: [LocalInterfaceAddress]
  ) -> LocalInterfaceFacts {
    LocalInterfaceFacts(
      bsdName: bsdName, isLoopback: false, interfaceType: "IEEE80211",
      localizedName: localizedName, addresses: addresses)
  }

  /// Ethernet 接口事实（类型 Ethernet，名称缺失回退 BSD 名的常见形态）。
  static func ethernet(
    bsdName: String = "en1", localizedName: String? = nil,
    addresses: [LocalInterfaceAddress]
  ) -> LocalInterfaceFacts {
    LocalInterfaceFacts(
      bsdName: bsdName, isLoopback: false, interfaceType: "Ethernet",
      localizedName: localizedName, addresses: addresses)
  }

  /// VPN 接口事实（utun，无 SystemConfiguration 类型映射）。
  static func vpn(bsdName: String = "utun4") -> LocalInterfaceFacts {
    LocalInterfaceFacts(
      bsdName: bsdName, isLoopback: false, interfaceType: nil, localizedName: nil,
      addresses: [.ipv4("198.18.0.1")])
  }

  /// 非白名单虚拟接口事实（如桥接，通用 Ethernet 类型不可采信的场景以
  /// 其他类型呈现）。
  static func virtual(bsdName: String = "bridge0") -> LocalInterfaceFacts {
    LocalInterfaceFacts(
      bsdName: bsdName, isLoopback: false, interfaceType: "VirtualInterface",
      localizedName: nil, addresses: [.ipv4("192.168.9.1")])
  }

  /// 回环接口事实（IFF_LOOPBACK；无类型映射）。策略不消费回环事实——
  /// 回环候选由策略合成，此事实仅用于验证白名单不误收。
  static func loopback() -> LocalInterfaceFacts {
    LocalInterfaceFacts(
      bsdName: "lo0", isLoopback: true, interfaceType: nil, localizedName: nil,
      addresses: [.ipv4("127.0.0.1"), .ipv6("::1"), .ipv6("fe80::1", linkLocal: true)])
  }
}
