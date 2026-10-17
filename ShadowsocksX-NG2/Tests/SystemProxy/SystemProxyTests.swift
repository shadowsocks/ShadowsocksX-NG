import XCTest

@testable import ShadowsocksX_NG2

/// System proxy mode mapping and declarative planning are pure/testable seams;
/// no test in this file writes the host's real SystemConfiguration state.
/// Closed typed 配置覆盖 HTTPS/PAC/自动发现/简单主机名与例外列表，
/// 无条件清理计划与 helper XPC 契约（含序列化 last-writer）都在此验证。
final class SystemProxyTests: XCTestCase {
  func testSupportedModesProjectTheSameLocalEndpoints() {
    let document = ProxyRuntimeFixture.makeDocument(
      listenerMode: .allIPv4Interfaces, localPort: 2086)

    let expected = SystemProxyConfiguration(
      socks: .init(host: "127.0.0.1", port: 2086),
      http: .init(host: "127.0.0.1", port: SslocalListenSettings.defaultHTTPPort),
      https: .init(host: "127.0.0.1", port: SslocalListenSettings.defaultHTTPPort),
      exceptions: FixedLocalProxyRanges.systemProxyExceptions)
    XCTAssertEqual(
      ProxyMode.rule.systemProxyConfiguration(for: document),
      expected)
    XCTAssertEqual(
      ProxyMode.global.systemProxyConfiguration(for: document),
      expected,
      "全局模式的系统例外使用固定本地范围，与 ACL 安全策略一致")
  }

  func testIPv6LANModeKeepsSystemProxyOnLocalIPv4Loopback() {
    let document = SslocalRuntimeDocument(
      servers: [], listen: SslocalListenSettings(listenerMode: .allIPv6Interfaces))

    let configuration = ProxyMode.rule.systemProxyConfiguration(for: document)

    XCTAssertEqual(configuration.socks.host, "127.0.0.1")
    XCTAssertEqual(configuration.http.host, "127.0.0.1")
    XCTAssertEqual(configuration.https.host, "127.0.0.1", "HTTPS 显式赋值，与 HTTP 同端点")
  }

  func testMissingHTTPInboundIsRejectedInsteadOfPointingAtAWildcardPort() throws {
    var dictionary = try XCTUnwrap(
      JSONSerialization.jsonObject(
        with: SslocalRuntimeDocument(servers: [], listen: SslocalListenSettings()).jsonData()
      ) as? [String: Any])
    dictionary["locals"] = [
      [
        "protocol": "socks", "local_address": "127.0.0.1",
        "local_port": 11086, "mode": "tcp_and_udp",
      ]
    ]
    let data = try JSONSerialization.data(withJSONObject: dictionary)
    XCTAssertNil(SslocalRuntimeDocument.decodeValidated(data), "每组必须同时提供 SOCKS 与 HTTP")
  }

  func testModeProjectionCarriesClosedTypedPolicyDefaults() {
    let document = ProxyRuntimeFixture.makeDocument(localPort: 2086)

    let configuration = ProxyMode.rule.systemProxyConfiguration(
      for: document, exceptions: ["example.com"])

    XCTAssertTrue(configuration.pacEnabled == false, "PAC 显式关闭")
    XCTAssertTrue(configuration.autoDiscoveryEnabled == false, "自动发现显式关闭")
    XCTAssertTrue(configuration.excludeSimpleHostnames, "简单主机名排除由 GUI 拥有，默认开")
    XCTAssertEqual(
      configuration.exceptions,
      FixedLocalProxyRanges.systemProxyExceptions(including: ["example.com"]),
      "例外列表 = 固定本地范围 + 用户补充项，全量给出")
  }

  // MARK: - Property-list projection

  private let configuration = SystemProxyConfiguration(
    socks: .init(host: "127.0.0.1", port: 1086),
    http: .init(host: "127.0.0.1", port: 1087),
    https: .init(host: "127.0.0.1", port: 1087),
    exceptions: ["localhost", "127.0.0.1"])

  func testSystemConfigurationProjectionEnablesSOCKSHTTPAndHTTPS() {
    let original: [String: Any] = [
      SystemProxyPropertyList.httpEnabled: 1,
      SystemProxyPropertyList.httpsEnabled: 1,
      SystemProxyPropertyList.socksEnabled: 1,
      SystemProxyPropertyList.pacEnabled: 1,
      SystemProxyPropertyList.pacURL: "http://127.0.0.1:1089/v1/proxy.pac",
      "ExceptionsList": ["stale.example"],
    ]

    let applied = SystemProxyPropertyList.applying(configuration, to: original)
    XCTAssertEqual(applied[SystemProxyPropertyList.pacEnabled] as? Int, 0)
    XCTAssertNil(applied[SystemProxyPropertyList.pacURL])
    XCTAssertNil(applied[SystemProxyPropertyList.pacJavaScript])
    XCTAssertEqual(applied[SystemProxyPropertyList.socksEnabled] as? Int, 1)
    XCTAssertEqual(applied[SystemProxyPropertyList.socksProxy] as? String, "127.0.0.1")
    XCTAssertEqual(applied[SystemProxyPropertyList.socksPort] as? Int, 1086)
    XCTAssertEqual(applied[SystemProxyPropertyList.httpEnabled] as? Int, 1)
    XCTAssertEqual(applied[SystemProxyPropertyList.httpProxy] as? String, "127.0.0.1")
    XCTAssertEqual(applied[SystemProxyPropertyList.httpPort] as? Int, 1087)
    XCTAssertEqual(applied[SystemProxyPropertyList.httpsEnabled] as? Int, 1)
    XCTAssertEqual(applied[SystemProxyPropertyList.httpsProxy] as? String, "127.0.0.1")
    XCTAssertEqual(applied[SystemProxyPropertyList.httpsPort] as? Int, 1087)
    XCTAssertEqual(applied[SystemProxyPropertyList.excludeSimpleHostnames] as? Int, 1)
    XCTAssertEqual(applied[SystemProxyPropertyList.autoDiscoveryEnabled] as? Int, 0)
    XCTAssertEqual(
      applied[SystemProxyPropertyList.exceptionsList] as? [String],
      ["localhost", "127.0.0.1"],
      "例外列表全量覆盖，不保留旧值")
  }

  /// 显式简单主机名排除值：GUI 拥有该策略（当前恒开），helper 只翻译。
  func testSimpleHostnameExclusionFollowsExplicitFlag() {
    let withFlagOn = SystemProxyPropertyList.applying(configuration, to: [:])
    XCTAssertEqual(withFlagOn[SystemProxyPropertyList.excludeSimpleHostnames] as? Int, 1)

    var flagOff = configuration
    flagOff.excludeSimpleHostnames = false
    let withFlagOff = SystemProxyPropertyList.applying(
      flagOff, to: [SystemProxyPropertyList.excludeSimpleHostnames: 1])
    XCTAssertEqual(withFlagOff[SystemProxyPropertyList.excludeSimpleHostnames] as? Int, 0)
  }

  /// 空例外列表也是显式值：写入空数组而非保留旧列表。
  func testEmptyExceptionListIsWrittenExplicitly() {
    var withoutExceptions = configuration
    withoutExceptions.exceptions = []
    let applied = SystemProxyPropertyList.applying(
      withoutExceptions, to: ["ExceptionsList": ["stale.example"]])
    XCTAssertEqual(applied[SystemProxyPropertyList.exceptionsList] as? [String], [])
  }

  /// 未建模键保留：typed 字段集之外的 Proxies 键不被擦除。
  func testUnmodeledKeysArePreservedOnApply() {
    let original: [String: Any] = [
      "ThirdPartyKey": "third-party value",
      SystemProxyPropertyList.socksEnabled: 0,
    ]
    let applied = SystemProxyPropertyList.applying(configuration, to: original)
    XCTAssertEqual(applied["ThirdPartyKey"] as? String, "third-party value")
  }

  /// PAC 显式关闭时移除 URL 与 JavaScript 残值。
  func testDisabledPACRemovesURLAndJavaScriptValues() {
    let original: [String: Any] = [
      SystemProxyPropertyList.pacEnabled: 1,
      SystemProxyPropertyList.pacURL: "http://proxy.example/proxy.pac",
      SystemProxyPropertyList.pacJavaScript: "function FindProxyForURL() {}",
    ]
    let applied = SystemProxyPropertyList.applying(configuration, to: original)
    XCTAssertEqual(applied[SystemProxyPropertyList.pacEnabled] as? Int, 0)
    XCTAssertNil(applied[SystemProxyPropertyList.pacURL])
    XCTAssertNil(applied[SystemProxyPropertyList.pacJavaScript])
  }

  // MARK: - Declarative planner

  private func serialized(_ dictionary: [String: Any]) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)
  }

  /// 字典等价：断言「写出什么」，不与生产的语义归一（semanticallyNormalized）混用。
  private func plistsEqual(_ lhs: Data?, _ rhs: Data?) -> Bool {
    guard let lhs, let rhs else { return lhs == nil && rhs == nil }
    guard
      let left = try? PropertyListSerialization.propertyList(from: lhs, options: [], format: nil)
        as? NSDictionary,
      let right = try? PropertyListSerialization.propertyList(from: rhs, options: [], format: nil)
        as? NSDictionary
    else { return lhs == rhs }
    return left.isEqual(right)
  }

  private func service(
    _ id: String, location: String = "location-1", configuration data: Data?
  ) -> SystemProxyServiceState {
    SystemProxyServiceState(
      identifier: SystemProxyServiceIdentifier(locationID: location, serviceID: id),
      configuration: data)
  }

  func testApplyPlannerWritesEveryActiveServiceToDesiredValues() throws {
    let applied = try serialized(SystemProxyPropertyList.applying(configuration, to: [:]))
    let foreign = try serialized(["HTTPEnable": 1, "HTTPProxy": "proxy.example"])

    let plan = try SystemProxyPlanner.makeApplyPlan(
      services: [
        service("service-1", configuration: applied),
        service("service-2", configuration: foreign),
      ], configuration: configuration)

    XCTAssertEqual(plan.writes.map(\.identifier.serviceID), ["service-2"], "等值服务零写入")
    XCTAssertEqual(plan.outcome, .written)
    let projected = try XCTUnwrap(plan.writes.first?.configuration)
    XCTAssertTrue(plistsEqual(projected, applied))
  }

  func testEquivalentDisabledFlagsAndExceptionOrderProduceNoDifference() throws {
    var values = SystemProxyPropertyList.applying(configuration, to: ["Unmanaged": "keep"])
    values.removeValue(forKey: "ProxyAutoConfigEnable")
    values.removeValue(forKey: "ProxyAutoDiscoveryEnable")
    values["ExceptionsList"] = ["127.0.0.1", "localhost", "localhost"]
    let plan = try SystemProxyPlanner.makeApplyPlan(
      services: [service("wifi", configuration: serialized(values))], configuration: configuration)
    XCTAssertTrue(plan.writes.isEmpty, "系统语义等价，不报告差异也不写入")
  }

  func testApplyPlannerIsIdempotentWhenAllServicesMatch() throws {
    let applied = try serialized(SystemProxyPropertyList.applying(configuration, to: [:]))

    let plan = try SystemProxyPlanner.makeApplyPlan(
      services: [service("service-1", configuration: applied)], configuration: configuration)

    XCTAssertTrue(plan.writes.isEmpty)
    XCTAssertEqual(plan.outcome, .unchanged, "重试不产生无谓的 SC 写入（issue #71 AC31）")
  }

  /// 清理计划无条件：凡持有 Proxies 实体的服务（跨位置、不校验端点或来源）
  /// 都整字典移除。
  func testCleanupPlannerClearsWholeDictionaryEverywhereUnconditionally() throws {
    let ng2Values = try serialized(SystemProxyPropertyList.applying(configuration, to: [:]))
    let foreignValues = try serialized([
      "HTTPEnable": 1, "HTTPProxy": "proxy.example", "HTTPPort": 9090,
    ])
    let services = [
      service("same-id", location: "location-a", configuration: ng2Values),
      service("same-id", location: "location-b", configuration: foreignValues),
      service("bare-service", location: "location-b", configuration: nil),
    ]

    let plan = SystemProxyPlanner.makeClearPlan(services: services)

    XCTAssertEqual(
      Set(plan.writes.map(\.identifier)),
      [services[0].identifier, services[1].identifier],
      "不校验来源：NG2 与其他应用写入的服务都被清空")
    XCTAssertTrue(plan.writes.allSatisfy { $0.configuration == nil }, "清除完整 Proxies 字典")
    XCTAssertFalse(
      plan.writes.contains { $0.identifier == services[2].identifier },
      "没有 Proxies 实体的服务无需写入")
  }

  // MARK: - 注册清单漂移指纹

  /// launchd 沿用注册提交时的 job 定义快照，清单变更须注销重注才生效；
  /// 指纹检测决定是否重注。
  func testRegistrationStampDriftDetection() {
    let data = Data("plist-content".utf8)
    XCTAssertTrue(
      SystemProxyHelperRegistrationStamp.drifted(plistData: data, storedStamp: nil),
      "无指纹（首次带检测代码启动）视为漂移")
    XCTAssertTrue(
      SystemProxyHelperRegistrationStamp.drifted(plistData: data, storedStamp: "outdated"),
      "清单内容变更视为漂移")
    XCTAssertFalse(
      SystemProxyHelperRegistrationStamp.drifted(
        plistData: data, storedStamp: SystemProxyHelperRegistrationStamp.stamp(data)),
      "指纹一致不漂移")
    XCTAssertFalse(
      SystemProxyHelperRegistrationStamp.drifted(plistData: nil, storedStamp: nil),
      "清单不可读无基准，不判漂移")
    XCTAssertNotEqual(
      SystemProxyHelperRegistrationStamp.stamp(Data("a".utf8)),
      SystemProxyHelperRegistrationStamp.stamp(Data("b".utf8)),
      "不同清单内容指纹不同")
  }
}
