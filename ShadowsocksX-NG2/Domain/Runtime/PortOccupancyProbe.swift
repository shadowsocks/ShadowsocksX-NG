import Darwin
import Foundation

/// 端口占用判定结果。空闲与占用之外还有「无法判定」：绑定测试自身失败
/// （特权端口、socket 不可用等）时如实呈现，不冒充空闲。监听地址由
/// `ListenerMode.bindAddress` 封闭集合保证可解析，属编程错误而非判定结果。
enum PortOccupancy: Equatable, Sendable {
  case free
  /// 端口不可绑定；进程名/PID 尽力解析并按地址族记录。`unverifiedFamilyDetail`
  /// 表示双栈另一地址族无法判定，但不抹去已确认的占用。
  case occupied(PortOccupancyFacts)
  case unknown(detail: String)
}

struct PortOccupancyFacts: Equatable, Sendable {
  let occupier: String?
  let processIDsByFamily: [PortOccupancyAddressFamily: Set<Int32>]
  let occupiedFamilies: Set<PortOccupancyAddressFamily>
  let verifiedFamilies: Set<PortOccupancyAddressFamily>
  let unverifiedFamilyDetail: String?

  init(
    occupier: String?, ipv4ProcessIDs: Set<Int32> = [], ipv6ProcessIDs: Set<Int32> = [],
    occupiedFamilies: Set<PortOccupancyAddressFamily> = [],
    verifiedFamilies: Set<PortOccupancyAddressFamily> = [], unverifiedFamilyDetail: String? = nil
  ) {
    self.occupier = occupier
    processIDsByFamily = [
      .ipv4: ipv4ProcessIDs,
      .ipv6: ipv6ProcessIDs,
    ]
    self.occupiedFamilies = occupiedFamilies
    self.verifiedFamilies = verifiedFamilies
    self.unverifiedFamilyDetail = unverifiedFamilyDetail
  }

  init(merging facts: [PortOccupancyFacts], unverifiedFamilyDetail: String?) {
    occupier = facts.lazy.compactMap(\.occupier).first
    processIDsByFamily = Dictionary(
      uniqueKeysWithValues: PortOccupancyAddressFamily.allCases.map { family in
        (family, facts.reduce(into: Set<Int32>()) { $0.formUnion($1.processIDs(for: family)) })
      })
    occupiedFamilies = facts.reduce(into: Set<PortOccupancyAddressFamily>()) {
      $0.formUnion($1.occupiedFamilies)
    }
    verifiedFamilies = facts.reduce(into: Set<PortOccupancyAddressFamily>()) {
      $0.formUnion($1.verifiedFamilies)
    }
    self.unverifiedFamilyDetail =
      unverifiedFamilyDetail ?? facts.lazy.compactMap(\.unverifiedFamilyDetail).first
  }

  func processIDs(for family: PortOccupancyAddressFamily) -> Set<Int32> {
    processIDsByFamily[family, default: []]
  }

  var occupiedProcessIDs: Set<Int32> {
    occupiedFamilies.reduce(into: Set<Int32>()) { processIDs, family in
      processIDs.formUnion(self.processIDs(for: family))
    }
  }
}

enum PortOccupancyAddressFamily: CaseIterable, Hashable, Sendable {
  case ipv4
  case ipv6

  var lsofFilter: String {
    switch self {
    case .ipv4: "-i4TCP"
    case .ipv6: "-i6TCP"
    }
  }
}

private struct PortOccupierFamilyFacts {
  let name: String?
  let processIDs: Set<Int32>
  let isVerified: Bool
}

private struct PortOccupierFacts {
  let ipv4: PortOccupierFamilyFacts
  let ipv6: PortOccupierFamilyFacts

  var verifiedFamilies: Set<PortOccupancyAddressFamily> {
    var families: Set<PortOccupancyAddressFamily> = []
    if ipv4.isVerified { families.insert(.ipv4) }
    if ipv6.isVerified { families.insert(.ipv6) }
    return families
  }
}

extension RuntimeListenFacts {
  func port(for endpoint: ProxyEndpointKind) -> Int {
    switch endpoint {
    case .socks: socksPort
    case .http: httpPort
    case .lanSocks: lan.socksPort
    case .lanHTTP: lan.httpPort
    }
  }

  func replacingPort(_ port: Int, for endpoint: ProxyEndpointKind) -> RuntimeListenFacts {
    var result = self
    switch endpoint {
    case .socks:
      result = RuntimeListenFacts(listenerMode: listenerMode, socksPort: port, httpPort: httpPort)
      result.lan = lan
    case .http:
      result = RuntimeListenFacts(listenerMode: listenerMode, socksPort: socksPort, httpPort: port)
      result.lan = lan
    case .lanSocks: result.lan.socksPort = port
    case .lanHTTP: result.lan.httpPort = port
    }
    return result
  }
}

/// A port probe request carries the complete effective listener identity. The
/// requested port may differ from `listen.port(for:)` only for a suggested
/// candidate; the rest of the listener facts remain part of the request.
struct PortOccupancyProbeRequest: Equatable, Sendable {
  let endpoint: ProxyEndpointKind
  let listen: RuntimeListenFacts
  let port: Int

  init(
    endpoint: ProxyEndpointKind,
    listen: RuntimeListenFacts,
    port: Int? = nil
  ) {
    self.endpoint = endpoint
    self.listen = listen
    self.port = port ?? listen.port(for: endpoint)
  }

  var listenerMode: ListenerMode {
    switch endpoint {
    case .socks, .http: listen.listenerMode
    case .lanSocks, .lanHTTP: listen.lan.effectiveMode
    }
  }

  var bindAddress: String { listenerMode.bindAddress }
}

/// 端口占用探测缝：设置编辑期的即时占用校验。激活是否成功
/// 仍以 runtime 实际绑定为准（健康门禁），本探测不构成权威判定。
protocol PortOccupancyProbing: Sendable {
  func occupancy(for request: PortOccupancyProbeRequest) -> PortOccupancy
}

/// 系统实现：对 `bindAddress:port` 做一次不带复用选项的 TCP bind + listen，
/// 能实际开始监听才算空闲；`EADDRINUSE` 即占用。部分地址族组合在 bind 阶段
/// 允许共存，到 listen 阶段才报告冲突，因此两步都要覆盖。占用时尽力以
/// `lsof` 解析监听进程名。探测不设置 SO_REUSEADDR/SO_REUSEPORT，避免假空闲。
struct SystemPortOccupancyProbe: PortOccupancyProbing {
  func occupancy(for request: PortOccupancyProbeRequest) -> PortOccupancy {
    occupancy(port: request.port, listenerMode: request.listenerMode)
  }

  func occupancy(port: Int, listenerMode: ListenerMode) -> PortOccupancy {
    switch listenerMode {
    case .disabled, .allIPv4Interfaces:
      return ipv4Occupancy(port: port, listenerMode: listenerMode)
    case .allIPv4AndIPv6Interfaces:
      return dualStackOccupancy(port: port, listenerMode: listenerMode)
    case .allIPv6Interfaces:
      return ipv6Occupancy(port: port, listenerMode: listenerMode)
    }
  }

  /// A dual-stack listener needs both families available. Some macOS versions
  /// permit an IPv4 listener and a v6 socket with `IPV6_V6ONLY=false` to bind at
  /// once, so probe IPv4 separately instead of relying on that socket conflict.
  private func dualStackOccupancy(port: Int, listenerMode: ListenerMode) -> PortOccupancy {
    let ipv6 = ipv6Occupancy(port: port, listenerMode: listenerMode)
    let ipv4 = ipv4Occupancy(port: port, listenerMode: .allIPv4Interfaces)
    var occupiedFacts: [PortOccupancyFacts] = []
    for result in [ipv6, ipv4] {
      guard case .occupied(let facts) = result else { continue }
      occupiedFacts.append(facts)
    }
    if !occupiedFacts.isEmpty {
      return .occupied(
        PortOccupancyFacts(
          merging: occupiedFacts, unverifiedFamilyDetail: Self.unknownDetail(in: [ipv6, ipv4])))
    }
    if case .unknown(let detail) = ipv6 { return .unknown(detail: detail) }
    if case .unknown(let detail) = ipv4 { return .unknown(detail: detail) }
    return .free
  }

  private static func unknownDetail(in results: [PortOccupancy]) -> String? {
    for result in results {
      if case .unknown(let detail) = result { return detail }
      if case .occupied(let facts) = result, let detail = facts.unverifiedFamilyDetail {
        return detail
      }
    }
    return nil
  }

  private func ipv4Occupancy(port: Int, listenerMode: ListenerMode) -> PortOccupancy {
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(port).bigEndian
    // 本函数只处理 IPv4 模式（disabled / allIPv4Interfaces），其 bindAddress
    // 恒为 127.0.0.1 或 0.0.0.0；"::" 走 ipv6Occupancy，不经此路径。
    let parsed = inet_pton(AF_INET, listenerMode.bindAddress, &address.sin_addr)
    precondition(parsed == 1, "IPv4 探测的 ListenerMode.bindAddress 必须可解析")
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
      return .unknown(detail: String(cString: strerror(errno)))
    }
    defer { close(descriptor) }
    return bindAndListen(descriptor: descriptor, port: port, addressFamily: .ipv4) {
      withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
      }
    }
  }

  private func ipv6Occupancy(port: Int, listenerMode: ListenerMode) -> PortOccupancy {
    var address = sockaddr_in6()
    address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
    address.sin6_family = sa_family_t(AF_INET6)
    address.sin6_port = in_port_t(port).bigEndian
    address.sin6_addr = in6addr_any
    let descriptor = socket(AF_INET6, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
      return .unknown(detail: String(cString: strerror(errno)))
    }
    defer { close(descriptor) }

    var ipv6Only = Int32(listenerMode.ipv6Only == true ? 1 : 0)
    let optionResult = withUnsafePointer(to: &ipv6Only) { pointer in
      setsockopt(
        descriptor, IPPROTO_IPV6, IPV6_V6ONLY, pointer,
        socklen_t(MemoryLayout<Int32>.size))
    }
    guard optionResult == 0 else {
      return .unknown(detail: String(cString: strerror(errno)))
    }
    return bindAndListen(descriptor: descriptor, port: port, addressFamily: .ipv6) {
      withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
        }
      }
    }
  }

  private func bindAndListen(
    descriptor: Int32, port: Int, addressFamily: PortOccupancyAddressFamily,
    bind: () -> Int32
  ) -> PortOccupancy {
    guard bind() == 0 else { return socketFailure(errno, port: port, addressFamily: addressFamily) }
    guard listen(descriptor, 1) == 0 else {
      return socketFailure(errno, port: port, addressFamily: addressFamily)
    }
    return .free
  }

  private func socketFailure(
    _ code: Int32, port: Int, addressFamily: PortOccupancyAddressFamily
  ) -> PortOccupancy {
    guard code == EADDRINUSE else { return .unknown(detail: String(cString: strerror(code))) }
    let owner = Self.occupierFacts(port: port)
    return .occupied(
      PortOccupancyFacts(
        occupier: owner.ipv4.name ?? owner.ipv6.name,
        ipv4ProcessIDs: owner.ipv4.processIDs,
        ipv6ProcessIDs: owner.ipv6.processIDs,
        occupiedFamilies: [addressFamily],
        verifiedFamilies: owner.verifiedFamilies))
  }

  /// `lsof` 尽力解析监听进程名：本产品代理进程与 GUI 同用户运行，无需特权；
  /// lsof 缺失、失败或无匹配时返回 nil，不影响占用判定本身。
  private static func occupierFacts(port: Int) -> PortOccupierFacts {
    PortOccupierFacts(
      ipv4: occupierFacts(port: port, addressFamily: .ipv4),
      ipv6: occupierFacts(port: port, addressFamily: .ipv6))
  }

  private static func occupierFacts(
    port: Int, addressFamily: PortOccupancyAddressFamily
  ) -> PortOccupierFamilyFacts {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
    process.arguments = lsofArguments(port: port, addressFamily: addressFamily)
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
      try process.run()
    } catch {
      return PortOccupierFamilyFacts(name: nil, processIDs: [], isVerified: false)
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(data: data, encoding: .utf8) ?? ""
    let isVerified =
      process.terminationStatus == 0 || (process.terminationStatus == 1 && output.isEmpty)
    return PortOccupierFamilyFacts(
      name: occupierProcessName(fromLsofOutput: output),
      processIDs: occupierProcessIDs(fromLsofOutput: output),
      isVerified: isVerified)
  }

  static func lsofArguments(port: Int, addressFamily: PortOccupancyAddressFamily) -> [String] {
    ["-nP", "\(addressFamily.lsofFilter):\(port)", "-sTCP:LISTEN"]
  }

  /// 从 lsof 输出解析第一个数据行的进程名（首字段）；表头与空行跳过。
  static func occupierProcessName(fromLsofOutput output: String) -> String? {
    for line in output.split(whereSeparator: \.isNewline) {
      let fields = line.split(
        maxSplits: 1, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
      guard let name = fields.first, name != "COMMAND" else { continue }
      return String(name)
    }
    return nil
  }

  static func occupierProcessIDs(fromLsofOutput output: String) -> Set<Int32> {
    Set(
      output.split(whereSeparator: \.isNewline).compactMap { line in
        let fields = line.split(
          maxSplits: 2, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
        guard fields.first != "COMMAND", fields.count > 1 else { return nil }
        return Int32(fields[1])
      })
  }
}
