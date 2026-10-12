import Darwin
import XCTest

@testable import ShadowsocksX_NG2

final class RealSslocalPluginSmokeTests: RealSslocalSmokeTests {
  // MARK: - 受管插件端到端

  /// v2ray-plugin v1.3.2 端到端边界：契约携带 bundle 内插件绝对路径 → sslocal
  /// 拉起 → SIP003 插件进程建立 → 停止链随 sslocal 一并退出。插件进程退出会
  /// 连带 sslocal 退出（以 sslocal 信号为准）；真实服务器数据面验证属发布
  /// 真实服务器数据面验证属于发布门槛人工项；此处只验证进程边界。
  func testRealSslocalLaunchesManagedV2rayPluginProcess() throws {
    let pluginURL = AppArtifact.bundleURL.appendingPathComponent(
      "Contents/Helpers/Plugins/v2ray-plugin")
    _ = try XCTUnwrap(
      FileManager.default.isExecutableFile(atPath: pluginURL.path) ? pluginURL : nil,
      "v2ray-plugin 未嵌入 app bundle（先跑 fetch-external-binaries.sh）")
    var ports = Set<Int>()
    while ports.count < 2 {
      ports.insert(try grabEphemeralLoopbackPort())
    }
    let selectedPorts = Array(ports)
    let socksPort = selectedPorts[0]
    let httpPort = selectedPorts[1]
    let document = SslocalRuntimeDocument(
      servers: [
        SslocalServerDocument(
          id: "smoke-plugin-server",
          server: "127.0.0.1",
          serverPort: 1,  // 远端必然拒绝：只验证本地链路与插件进程边界
          password: "smoke-password",
          method: "aes-256-gcm",
          plugin: pluginURL.path,
          pluginOpts: "mode=websocket")
      ],
      listen: SslocalListenSettings(
        socksPort: socksPort, httpPort: httpPort))
    let wrapper = try launchWrapper(document)
    let store = RuntimeFileStore(fileURL: contractURL)
    XCTAssertTrue(try waitForCondition(timeout: 15) { store.readRuntimeReceipt() != nil })
    let child = try XCTUnwrap(store.readRuntimeReceipt()).processID

    var pluginPIDs: [Int32] = []

    // 插件进程建立：sslocal 按 SIP003 拉起 bundle 内 v2ray-plugin 并保持运行
    // （sslocal 先等插件就绪再绑定本地监听，进程先于端口出现）。
    XCTAssertTrue(
      try waitForCondition(timeout: 15) {
        pluginPIDs = self.pluginProcessIDs(path: pluginURL.path, parent: child)
        return !pluginPIDs.isEmpty
      },
      "sslocal 应拉起 bundle 内 v2ray-plugin 进程")

    XCTAssertTrue(
      try waitForCondition(timeout: 15) {
        EndpointHealthProbe.probe(host: "127.0.0.1", port: socksPort, timeout: 1) == .reachable
      },
      "15 秒内本地 SOCKS 端口应完成监听绑定")

    stopWrapperAndAssertCleanExit(wrapper, description: "wrapper exits")
    XCTAssertTrue(
      try waitForCondition(timeout: 8) {
        pluginPIDs.allSatisfy { kill($0, 0) != 0 }
      },
      "停止链应连带结束插件进程")
  }

  /// 按完整可执行路径检索进程（pgrep 全命令行匹配）。
  private func pluginProcessIDs(path: String, parent: Int32) -> [Int32] {
    let pgrep = Process()
    pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    pgrep.arguments = ["-P", String(parent), "-f", path]
    let pipe = Pipe()
    pgrep.standardOutput = pipe
    pgrep.standardError = FileHandle.nullDevice
    do {
      try pgrep.run()
    } catch {
      return []
    }
    guard (try? waitForCondition(timeout: 2) { !pgrep.isRunning }) == true else {
      kill(pgrep.processIdentifier, SIGKILL)
      return []
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return (String(data: data, encoding: .utf8) ?? "")
      .split(whereSeparator: \.isWhitespace).compactMap { Int32($0) }
  }
}
