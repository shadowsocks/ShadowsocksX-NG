import XCTest

@testable import ShadowsocksX_NG2

/// 受管插件提供：受管集内且 bundle 内可执行文件在位才返回
/// 绝对路径；集外引用与文件缺失都归一为「本版本未提供」（nil → 状态机点名
/// 拒绝）。路径只从静态事实表派生，绝不拼接引用原文。
final class BundleManagedPluginProviderTests: XCTestCase {
  private var bundleRoot: URL!
  private var credentials: InMemoryCredentialStore!

  override func setUpWithError() throws {
    try super.setUpWithError()
    bundleRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("ssxng-plugin-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: bundleRoot.appendingPathComponent("Contents/Helpers/Plugins"),
      withIntermediateDirectories: true)
    credentials = InMemoryCredentialStore()
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: bundleRoot)
    try super.tearDownWithError()
  }

  private var pluginBinaryName: String { ManagedPluginCatalog.plugins[0].program }

  private var pluginURL: URL {
    bundleRoot.appendingPathComponent("Contents/Helpers/Plugins/\(pluginBinaryName)")
  }

  private func writePluginBinary(permissions: Int) throws {
    try Data("#!/bin/sh\n".utf8).write(to: pluginURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: permissions], ofItemAtPath: pluginURL.path)
  }

  private func makeProvider() -> BundleManagedPluginProvider {
    BundleManagedPluginProvider(bundleURL: bundleRoot)
  }

  func testMajorVersionAliasResolvesToSameBundledExecutable() throws {
    try writePluginBinary(permissions: 0o755)
    XCTAssertEqual(
      makeProvider().resolve(program: "v2ray-plugin-v1")?.path,
      makeProvider().resolve(program: "v2ray-plugin")?.path)
    XCTAssertNotNil(makeProvider().resolve(program: "v2ray-plugin-v1")?.path)
  }

  func testCloakAliasesUseClientBinaryAndPreserveOptions() throws {
    let client = bundleRoot.appendingPathComponent("Contents/Helpers/Plugins/ck-client")
    try Data("#!/bin/sh\n".utf8).write(to: client)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: client.path)
    let provider = makeProvider()
    for name in ["cloak", "cloak-v2"] {
      XCTAssertEqual(provider.resolve(program: name)?.path, client.path)
      XCTAssertEqual(provider.resolve(program: name)?.mode, .tcpOnly)
      var catalog = ConfigurationCatalog()
      var fields = ActivationFixture.plainFields(remark: "Cloak", password: "password")
      fields.pluginProgram = name
      fields.pluginOptions = "options"
      let options = "UID=test;PublicKey=test;ServerName=example.com;EncryptionMethod=plain"
      fields.password = "pw"
      fields.pluginOptions = options
      let id = try catalog.addServer(fields)
      var machine = ActivationStateMachine()
      let runtime = try machine.activate(
        id, in: catalog, plugins: provider,
        options: RuntimeDocumentOptions(listen: ActivationFixture.listen))
      let server = try XCTUnwrap(runtime.document.servers.first)
      XCTAssertEqual(server.plugin, client.path)
      XCTAssertEqual(server.pluginOpts, options)
    }
    XCTAssertNil(provider.resolve(program: "ck-client"))
    XCTAssertNil(provider.resolve(program: "Cloak"))
  }

  func testReturnsBundleAbsolutePathForProvidedManagedProgram() throws {
    try writePluginBinary(permissions: 0o755)
    let path = try XCTUnwrap(makeProvider().resolve(program: pluginBinaryName)?.path)
    XCTAssertEqual(path, pluginURL.path, "配置生成的 plugin 字段是 bundle 内绝对路径")
    XCTAssertTrue(path.hasPrefix(bundleRoot.path))
  }

  func testMissingBinaryIsNotProvided() {
    XCTAssertNil(makeProvider().resolve(program: pluginBinaryName)?.path)
  }

  func testNonExecutableBinaryIsNotProvided() throws {
    try writePluginBinary(permissions: 0o644)
    XCTAssertNil(makeProvider().resolve(program: pluginBinaryName)?.path)
  }

  func testUnmanagedProgramIsNeverProvided() throws {
    try writePluginBinary(permissions: 0o755)
    let provider = makeProvider()
    XCTAssertNil(provider.resolve(program: "obfs-local")?.path, "集外程序名一律未提供")
    XCTAssertNil(provider.resolve(program: "sslocal")?.path, "非插件的 bundle 内二进制不算插件")
    XCTAssertNil(provider.resolve(program: "../Helpers/sslocal")?.path, "路径形态引用不拼接")
    XCTAssertNil(provider.resolve(program: "v2ray-plugin/child")?.path, "子路径引用不拼接")
    XCTAssertNil(provider.resolve(program: "")?.path)
  }

  /// 组合根事实：app bundle（生产默认 provider 的取值来源，经 AppArtifact 按
  /// 构建产物定位、不依赖测试宿主）内受管插件在位——防止打包回归静默断开激
  /// 活链路（编辑器显示提供而激活拒绝）。
  func testHostAppBundleProvidesManagedPlugin() throws {
    let path = try XCTUnwrap(
      BundleManagedPluginProvider(bundleURL: AppArtifact.bundleURL)
        .resolve(program: pluginBinaryName)?.path,
      "app bundle 未嵌入受管插件（先跑 fetch-external-binaries.sh）")
    XCTAssertTrue(path.hasSuffix("Contents/Helpers/Plugins/\(pluginBinaryName)"))
  }

  func testHostAppBundleProvidesCloakAliasesAndNotices() throws {
    let bundle = AppArtifact.bundleURL
    let provider = BundleManagedPluginProvider(bundleURL: bundle)
    let path = try XCTUnwrap(provider.resolve(program: "cloak")?.path)
    XCTAssertTrue(path.hasSuffix("Contents/Helpers/Plugins/ck-client"))
    XCTAssertEqual(provider.resolve(program: "cloak-v2")?.path, path)
    for name in ["LICENSE", "NOTICE", "THIRD-PARTY-NOTICES"] {
      XCTAssertTrue(
        FileManager.default.fileExists(
          atPath:
            bundle.appendingPathComponent("Contents/Resources/ThirdParty/Cloak/" + name).path))
    }
  }

  /// 与状态机缝的契约：文件缺失 → provider nil → 激活以 pluginNotProvided
  /// 原子拒绝（app 降级丢插件时同一语义）。
  func testActivationRejectsMissingPluginByNamedReason() throws {
    var catalog = ConfigurationCatalog()
    var fields = ActivationFixture.plainFields(remark: "带插件", password: "password")
    fields.pluginProgram = pluginBinaryName
    fields.password = "pw"
    let id = try catalog.addServer(fields)
    var machine = ActivationStateMachine()

    ActivationFixture.assertThrows(
      .invalidLeaf(node: id, reason: .pluginNotProvided(program: pluginBinaryName))
    ) {
      try machine.activate(
        id, in: catalog, plugins: makeProvider(),
        options: RuntimeDocumentOptions(listen: ActivationFixture.listen))
    }
  }

  /// 在位 → 派生文档携带 bundle 内绝对路径（与 opts 解析），激活成功。
  func testActivationDerivesBundlePathWhenProvided() throws {
    try writePluginBinary(permissions: 0o755)
    var catalog = ConfigurationCatalog()
    var fields = ActivationFixture.plainFields(remark: "带插件", password: "password")
    fields.pluginProgram = pluginBinaryName
    fields.password = "pw"
    let id = try catalog.addServer(fields)
    var machine = ActivationStateMachine()

    let configuration = try machine.activate(
      id, in: catalog, plugins: makeProvider(),
      options: RuntimeDocumentOptions(listen: ActivationFixture.listen))

    let server = try XCTUnwrap(configuration.document.servers.first)
    XCTAssertEqual(server.plugin, pluginURL.path)
    XCTAssertNil(server.pluginOpts, "无参数引用时整体省略 pluginOpts")
  }
}
