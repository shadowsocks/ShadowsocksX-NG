import XCTest

@testable import ShadowsocksX_NG2

/// 激活缝测试共享夹具：受管插件替身与完整记录、无插件叶子、
/// 激活与重展开的便捷调用、原子失败断言。
enum ActivationFixture {
  /// 受管插件测试集：只提供表内程序，值即写入文档的 bundle 内路径。
  struct TestManagedPlugins: PluginExecutableResolving {
    let pathsByProgram: [String: String]

    func resolve(program: String) -> ResolvedPlugin? {
      pathsByProgram[program].map { ResolvedPlugin(path: $0, arguments: []) }
    }
  }

  static let plugins = TestManagedPlugins(pathsByProgram: [
    "v2ray-plugin": "/bundle/Helpers/Plugins/v2ray-plugin"
  ])

  static let listen = SslocalListenSettings()

  /// 无插件叶子字段（插件语义单独覆盖）。
  static func plainFields(remark: String, password: String = "password") -> ServerFields {
    ServerFields(
      address: "203.0.113.7", port: 8388, encryptionMethod: "aes-256-gcm",
      password: password, remark: remark)
  }

  @discardableResult
  static func addPlainServer(
    _ remark: String, to parent: NodeID? = nil, in catalog: inout ConfigurationCatalog
  ) throws -> NodeID {
    try catalog.addServer(plainFields(remark: remark, password: "pw-\(remark)"), to: parent)
  }

  static func activate(
    _ machine: inout ActivationStateMachine,
    _ target: NodeID,
    in catalog: ConfigurationCatalog
  ) throws -> RuntimeConfiguration {
    try machine.activate(
      target, in: catalog, plugins: plugins,
      options: RuntimeDocumentOptions(listen: listen))
  }

  static func commit(
    _ machine: inout ActivationStateMachine,
    _ catalog: ConfigurationCatalog
  ) -> ActivationEffect? {
    machine.catalogDidCommit(
      catalog, plugins: plugins,
      options: RuntimeDocumentOptions(listen: listen))
  }

  /// 断言激活以指定原因原子失败（错误类型与值都点名）。
  static func assertThrows(
    _ expected: ActivationFailure,
    _ activation: () throws -> RuntimeConfiguration,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    do {
      _ = try activation()
      XCTFail("应被拒绝：\(expected)", file: file, line: line)
    } catch let failure as ActivationFailure {
      XCTAssertEqual(failure, expected, file: file, line: line)
    } catch {
      XCTFail("错误应为 ActivationFailure，实际 \(error)", file: file, line: line)
    }
  }

  enum FixtureError: Error {
    case unexpectedEffect
  }

  /// 解包「原子更新」效应；否则 XCTFail 并抛错终止用例。
  static func requireDeployed(
    _ effect: ActivationEffect?, file: StaticString = #filePath, line: UInt = #line
  ) throws -> RuntimeConfiguration {
    guard case .deployed(let configuration)? = effect else {
      XCTFail("应产出原子更新，实际 \(String(describing: effect))", file: file, line: line)
      throw FixtureError.unexpectedEffect
    }
    return configuration
  }

  /// 解包「清除并停止」效应的点名原因；否则 XCTFail 并抛错终止用例。
  static func requireCleared(
    _ effect: ActivationEffect?, file: StaticString = #filePath, line: UInt = #line
  ) throws -> ActivationFailure {
    guard case .clearedAndStopped(let failure)? = effect else {
      XCTFail("应清除并停止，实际 \(String(describing: effect))", file: file, line: line)
      throw FixtureError.unexpectedEffect
    }
    return failure
  }

  /// 取叶子当前的服务器字段（非叶子即夹具错误）。
  static func serverFields(
    of leaf: NodeID,
    in catalog: ConfigurationCatalog,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws -> ServerFields {
    let kind = try XCTUnwrap(catalog.entry(for: leaf)?.kind, file: file, line: line)
    guard case .server(let fields) = kind else {
      XCTFail("夹具应是服务器叶子", file: file, line: line)
      throw FixtureError.unexpectedEffect
    }
    return fields
  }
}
