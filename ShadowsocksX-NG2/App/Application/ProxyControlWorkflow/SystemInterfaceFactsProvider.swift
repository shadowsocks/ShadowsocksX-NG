import Combine
import Foundation
import SystemConfiguration

/// 生产本机接口事实来源：getifaddrs 提供当前启用接口、回环
/// 标记与单播地址（族与 IPv6 链路本地判定），SCNetworkInterfaceCopyAll 以
/// BSD 名关联系统接口类型与本地化名称，SCDynamicStore 监视接口状态变化。
/// 所有系统 API 细节封装于此；类型白名单与过滤排序在工作流层策略。
@MainActor
final class SystemInterfaceFactsProvider: LocalInterfaceFactsReading {
  /// getifaddrs 只看得到链路层事实；「当前启用」以 IFF_UP 判定，未启用
  /// 接口不进入事实。
  var interfaces: [LocalInterfaceFacts]? { Self.enumerate() }

  private let changeSubject = PassthroughSubject<Void, Never>()
  private let changesPublisher: AnyPublisher<Void, Never>
  /// SCDynamicStore 过渡期会按变化键连发事件，去抖避免反复枚举。
  var changes: AnyPublisher<Void, Never> { changesPublisher }

  private let observation = InterfaceFactsObservation()

  init() {
    changesPublisher =
      changeSubject
      .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
      .eraseToAnyPublisher()
    startObserving()
  }

  private func startObserving() {
    // 变化通知是尽力而为的增强：监视创建失败（罕见）只失去推送刷新，
    // 进入首页与复制前刷新仍保证候选新鲜。
    var context = SCDynamicStoreContext(
      version: 0,
      info: Unmanaged.passUnretained(observation).toOpaque(),
      retain: nil,
      release: nil,
      copyDescription: nil)
    guard
      let store = SCDynamicStoreCreate(
        kCFAllocatorDefault, "ShadowsocksX-NG2.InterfaceFacts" as CFString,
        interfaceFactsDynamicStoreCallback, &context)
    else { return }
    // 接口状态键（State:/Network/Interface/<bsd>/IPv4|IPv6）覆盖地址增删与
    // 接口启停；全局 IPv4/IPv6 键覆盖主服务切换。
    let globalKeys =
      [
        "State:/Network/Global/IPv4" as CFString, "State:/Network/Global/IPv6" as CFString,
      ] as CFArray
    let patterns = ["State:/Network/Interface/.*"] as CFArray
    guard SCDynamicStoreSetNotificationKeys(store, globalKeys, patterns) else { return }
    guard SCDynamicStoreSetDispatchQueue(store, DispatchQueue.main) else { return }
    observation.attach(store)
    observation.setHandler { [weak self] in self?.changeSubject.send() }
  }

  // MARK: - 枚举

  private static func enumerate() -> [LocalInterfaceFacts]? {
    var interfacesPtr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&interfacesPtr) == 0, let first = interfacesPtr else { return nil }
    defer { freeifaddrs(first) }

    // IPv6 地址标志查询共用一个 DGRAM socket；打开失败只失去标志事实
    // （nil = 不过滤、不注记），不阻断枚举。
    let flagsSocket = socket(AF_INET6, SOCK_DGRAM, 0)
    defer {
      if flagsSocket >= 0 {
        close(flagsSocket)
      }
    }

    // 按首次出现顺序逐接口累积；同一接口的多个地址条目归并到同一事实。
    var order: [String] = []
    var loopbackByBSDName: [String: Bool] = [:]
    var addressesByBSDName: [String: [LocalInterfaceAddress]] = [:]
    var pointer: UnsafeMutablePointer<ifaddrs>? = first
    while let current = pointer {
      pointer = current.pointee.ifa_next
      guard let name = current.pointee.ifa_name, let socketAddress = current.pointee.ifa_addr
      else { continue }
      let bsdName = String(cString: name)
      // Darwin 的 ifaddrs.ifa_flags 是值字段。
      let flags = Int32(current.pointee.ifa_flags)
      guard flags & IFF_UP == IFF_UP else { continue }
      if loopbackByBSDName[bsdName] == nil {
        order.append(bsdName)
        loopbackByBSDName[bsdName] = flags & IFF_LOOPBACK == IFF_LOOPBACK
      }
      if let address = interfaceAddress(socketAddress, flagsSocket: flagsSocket, bsdName: bsdName) {
        addressesByBSDName[bsdName, default: []].append(address)
      }
    }

    let metadata = systemInterfaceMetadata()
    return order.map { bsdName in
      LocalInterfaceFacts(
        bsdName: bsdName,
        isLoopback: loopbackByBSDName[bsdName] ?? false,
        interfaceType: metadata[bsdName]?.type,
        localizedName: metadata[bsdName]?.name,
        addresses: addressesByBSDName[bsdName] ?? [])
    }
  }

  /// 单个地址条目的族与链路本地判定；非 IPv4/IPv6 条目（链路层等）或无法
  /// 规范化的地址为 nil。
  private static func interfaceAddress(
    _ socketAddress: UnsafeMutablePointer<sockaddr>, flagsSocket: Int32, bsdName: String
  ) -> LocalInterfaceAddress? {
    switch socketAddress.pointee.sa_family {
    case sa_family_t(AF_INET):
      let socket = socketAddress.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
        $0.pointee
      }
      guard let text = addressText(family: AF_INET, address: socket.sin_addr) else { return nil }
      return LocalInterfaceAddress(
        address: text, family: .ipv4, isIPv6LinkLocal: false, v6Flags: nil)
    case sa_family_t(AF_INET6):
      let socket = socketAddress.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
        $0.pointee
      }
      guard let text = addressText(family: AF_INET6, address: socket.sin6_addr) else { return nil }
      let v6Flags =
        flagsSocket >= 0
        ? v6AddressFlags(flagsSocket: flagsSocket, bsdName: bsdName, address: socketAddress)
        : nil
      return LocalInterfaceAddress(
        address: text,
        family: .ipv6,
        isIPv6LinkLocal: isIPv6LinkLocal(socket.sin6_addr),
        v6Flags: v6Flags)
    default:
      return nil
    }
  }

  /// `SIOCGIFAFLAG_IN6` 逐地址查询内核 IPv6 标志（与 ifconfig 的
  /// 「autoconf secured / autoconf temporary / dynamic」注记同源）。查询
  /// 失败返回 nil。
  private static func v6AddressFlags(
    flagsSocket: Int32, bsdName: String, address: UnsafeMutablePointer<sockaddr>
  ) -> LocalInterfaceV6Flags? {
    var request = in6_ifreq()
    // _IOWR('i', 73, struct in6_ifreq) 手工展开：Darwin 模块不导出带结构体
    // 参数的 ioctl 请求宏。
    let requestCode =
      UInt32(IOC_INOUT)
      | (UInt32(MemoryLayout<in6_ifreq>.size) & UInt32(IOCPARM_MASK)) << 16
      | UInt32(0x69) << 8 | 73
    withUnsafeMutableBytes(of: &request.ifr_name) { nameBuffer in
      _ = strlcpy(
        nameBuffer.baseAddress!.assumingMemoryBound(to: CChar.self), bsdName, Int(IFNAMSIZ))
    }
    address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6 in
      request.ifr_ifru.ifru_addr = sin6.pointee
    }
    guard ioctl(flagsSocket, UInt(requestCode), &request) == 0 else { return nil }
    // ifru_flags 与 ifru_addr 在联合上重叠：内核回写在偏移 IFNAMSIZ 的首
    // 4 字节，直接按位读取（不依赖 Swift 对 C 联合成员的重叠读写语义）。
    let rawFlags = withUnsafeBytes(of: &request) {
      $0.loadUnaligned(fromByteOffset: Int(IFNAMSIZ), as: Int32.self)
    }
    return LocalInterfaceV6Flags(rawValue: rawFlags)
  }

  /// inet_ntop 规范化呈现形；转换失败不产生候选地址。
  private static func addressText<T>(family: Int32, address: T) -> String? {
    var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
    let result = withUnsafePointer(to: address) { pointer in
      pointer.withMemoryRebound(
        to: UInt8.self, capacity: MemoryLayout<T>.size
      ) {
        inet_ntop(family, $0, &buffer, socklen_t(INET6_ADDRSTRLEN))
      }
    }
    guard result != nil else { return nil }
    // inet_ntop 写入 null 结尾字符串且产物恒为 ASCII；先按终止符截断再解码，
    // 校验失败分支不可达。
    return String(bytes: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8)
  }

  /// IPv6 链路本地判定（fe80::/10；`IN6_IS_ADDR_LINKLOCAL` 宏未导入 Swift）。
  private static func isIPv6LinkLocal(_ address: in6_addr) -> Bool {
    let prefix = withUnsafeBytes(of: address) { Array($0.prefix(2)) }
    return prefix.count == 2 && prefix[0] == 0xFE && prefix[1] & 0xC0 == 0x80
  }

  /// BSD 名 → (系统接口类型, 本地化名称)。回环无 SystemConfiguration 映射，
  /// 类型保持 nil；名称缺失由策略回退 BSD 名。
  private static func systemInterfaceMetadata() -> [String: (type: String?, name: String?)] {
    var metadata: [String: (type: String?, name: String?)] = [:]
    for case let interface as SCNetworkInterface in SCNetworkInterfaceCopyAll() as NSArray {
      guard let bsdName = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
      metadata[bsdName] = (
        SCNetworkInterfaceGetInterfaceType(interface) as String?,
        SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?
      )
    }
    return metadata
  }
}

/// SCDynamicStore 观察箱：跨 C 回调向 MainActor 发值，并收拢 store 生命周期
/// ——store 的 context 以 unretained 指针回指本箱，本箱释放时先脱离队列再
/// 释放 store，保证 context 指针不悬挂（Swift 6 禁止在 MainActor 类的
/// nonisolated deinit 直接访问非 Sendable 存储）。
private final class InterfaceFactsObservation: @unchecked Sendable {
  private let lock = NSLock()
  private var handler: (@MainActor @Sendable () -> Void)?
  private var store: SCDynamicStore?

  func attach(_ store: SCDynamicStore) {
    lock.withLock { self.store = store }
  }

  func setHandler(_ handler: (@MainActor @Sendable () -> Void)?) {
    lock.withLock { self.handler = handler }
  }

  func emit() {
    let currentHandler = lock.withLock { handler }
    guard let currentHandler else { return }
    Task { @MainActor in currentHandler() }
  }

  deinit {
    lock.withLock {
      if let store {
        SCDynamicStoreSetDispatchQueue(store, nil)
      }
      handler = nil
    }
  }
}

private let interfaceFactsDynamicStoreCallback: SCDynamicStoreCallBack = { _, _, info in
  guard let info else { return }
  Unmanaged<InterfaceFactsObservation>.fromOpaque(info).takeUnretainedValue().emit()
}
