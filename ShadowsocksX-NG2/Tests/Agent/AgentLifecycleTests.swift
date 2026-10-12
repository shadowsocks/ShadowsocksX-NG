import Darwin
import XCTest

@testable import ShadowsocksX_NG2

/// 薄 I/O 缝 ②（spec Testing Decisions）：以 stub sslocal 二进制驱动真实
/// wrapper 可执行文件，验证启停协议次序、SIGTERM 链、崩溃恢复、文件清理与
/// SIGUSR1 变更协议。stub 经环境变量编排行为，全部等待有界。
class AgentLifecycleTests: XCTestCase {
  var workDir: URL!
  var contractURL: URL!
  private var stubStateURL: URL!
  private var stubURL: URL!
  private var wrappers: [Process] = []

  override func setUpWithError() throws {
    try super.setUpWithError()
    workDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ssxng-agent-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    contractURL = workDir.appendingPathComponent("sslocal-active.json")
    stubStateURL = workDir.appendingPathComponent("stub-state.log")
    stubURL = workDir.appendingPathComponent("stub-sslocal.sh")
    try FileManager.default.createDirectory(
      at: childPIDDirectory, withIntermediateDirectories: true)
    try writeStubScript()
  }

  override func tearDownWithError() throws {
    defer {
      try? FileManager.default.removeItem(at: workDir)
      try? super.tearDownWithError()
    }
    try cleanupWrappers()
  }

  // MARK: 夹具

  private var wrapperURL: URL {
    get throws {
      let url = AppArtifact.bundleURL.appendingPathComponent("Contents/MacOS/ShadowsocksX-NG2Agent")
      return try XCTUnwrap(
        FileManager.default.fileExists(atPath: url.path) ? url : nil,
        "wrapper 未嵌入 app bundle（Contents/MacOS/ShadowsocksX-NG2Agent）")
    }
  }

  private func writeStubScript() throws {
    // stub 记录调用参数与收到的信号；行为由 SSLOCAL_STUB_BEHAVIOR 编排。
    let script = """
      #!/bin/sh
      child_pid_file="$SSLOCAL_STUB_PID_DIR/$$"
      trap 'rm -f "$child_pid_file"' EXIT
      trap 'echo "SIGTERM" >> "$SSLOCAL_STUB_STATE"; exit 0' TERM
      trap 'echo "SIGUSR1" >> "$SSLOCAL_STUB_STATE"' USR1
      echo "$$" > "$child_pid_file"
      echo "dns-force-builtin: ${SS_SYSTEM_DNS_RESOLVER_FORCE_BUILTIN:-unset}" >> "$SSLOCAL_STUB_STATE"
      echo "invoked: $*" >> "$SSLOCAL_STUB_STATE"
      case "$SSLOCAL_STUB_BEHAVIOR" in
        crash) exit 7 ;;
        exit0) exit 0 ;;
        *) while :; do sleep 0.05; done ;;
      esac
      """
    try script.write(to: stubURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: stubURL.path)
  }

  func launchWrapper(behavior: String) throws -> Process {
    let wrapper = try wrapperURL
    let process = Process()
    process.executableURL = wrapper
    var environment = ProcessInfo.processInfo.environment
    environment["SSXNG_CONTRACT_PATH"] = contractURL.path
    environment["SSXNG_SSLOCAL_PATH"] = stubURL.path
    environment["SSXNG_RUNTIME_DIR"] = workDir.path
    environment["SSLOCAL_STUB_STATE"] = stubStateURL.path
    environment["SSLOCAL_STUB_PID_DIR"] = childPIDDirectory.path
    environment["SSLOCAL_STUB_BEHAVIOR"] = behavior
    process.environment = environment
    try process.run()
    wrappers.append(process)
    return process
  }

  func writeContract(_ document: SslocalRuntimeDocument) throws {
    try RuntimeFileStore(fileURL: contractURL).write(document)
  }

  func stateLog() -> String {
    (try? String(contentsOf: stubStateURL, encoding: .utf8)) ?? ""
  }

  func pidAlive(_ pid: Int32) -> Bool {
    kill(pid, 0) == 0
  }

  @discardableResult
  func waitUntil(
    timeout: TimeInterval = 10, _ condition: () throws -> Bool
  ) throws -> Bool {
    let deadline = DispatchTime.now() + timeout
    while DispatchTime.now() < deadline {
      if try condition() { return true }
      Thread.sleep(forTimeInterval: 0.05)
    }
    return try condition()
  }

  /// 断言 wrapper 在超时内退出并返回退出码。
  func waitForExit(_ process: Process, timeout: TimeInterval = 10) throws -> Int32 {
    guard try waitUntil(timeout: timeout, { !process.isRunning }) else {
      throw LifecycleWaitError.exitTimedOut(process.processIdentifier)
    }
    return process.terminationStatus
  }

  private var childPIDDirectory: URL {
    workDir.appendingPathComponent("child-pids", isDirectory: true)
  }

  /// 即使用例中途抛错，也先停止所有 wrapper，再清理仍存活的 stub。
  func cleanupWrappers() throws {
    let running = wrappers.filter(\.isRunning)
    for process in running { kill(process.processIdentifier, SIGTERM) }
    _ = try waitUntil(timeout: 12) { running.allSatisfy { !$0.isRunning } }

    let childFiles = try FileManager.default.contentsOfDirectory(
      at: childPIDDirectory, includingPropertiesForKeys: nil)
    let childPIDs = childFiles.compactMap { Int32($0.lastPathComponent) }.filter { $0 > 0 }
    for pid in childPIDs { kill(pid, SIGKILL) }
    for process in running where process.isRunning {
      kill(process.processIdentifier, SIGKILL)
    }
    guard
      try waitUntil(
        timeout: 2,
        {
          running.allSatisfy { !$0.isRunning } && childPIDs.allSatisfy { !self.pidAlive($0) }
        })
    else {
      throw LifecycleWaitError.cleanupTimedOut
    }
  }

  func agentLog() -> String {
    (try? String(contentsOf: workDir.appendingPathComponent("agent.log"), encoding: .utf8)) ?? ""
  }
}

private enum LifecycleWaitError: Error {
  case exitTimedOut(Int32)
  case cleanupTimedOut
}

final class AgentLifecycleCoreTests: AgentLifecycleTests {
  // MARK: 启动协议与 SIGTERM 链

  func testStartProtocolSpawnsSslocalWithAbsoluteConfigPathThenStopsOnSIGTERM() throws {
    try writeContract(ProxyRuntimeFixture.makeDocument())
    let wrapper = try launchWrapper(behavior: "run")

    XCTAssertTrue(
      try waitUntil { self.stateLog().contains("invoked: -c \(self.contractURL.path)") },
      "wrapper 应以契约绝对路径调用 sslocal，实际：\(stateLog())")
    XCTAssertTrue(pidAlive(wrapper.processIdentifier), "sslocal 运行期间 wrapper 应保持常驻")

    XCTAssertThrowsError(try waitForExit(wrapper, timeout: 0.01))
    XCTAssertTrue(wrapper.isRunning, "等待超时应返回错误，不影响被测进程")

    kill(wrapper.processIdentifier, SIGTERM)
    let exitStatus = try waitForExit(wrapper)

    XCTAssertEqual(exitStatus, 0, "显式停止后 wrapper 干净退出（不触发 KeepAlive 重启）")
    XCTAssertTrue(stateLog().contains("SIGTERM"), "SIGTERM 链：wrapper 转发给 sslocal")
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: contractURL.path),
      "停止路径不动契约文件（删除由 GUI 的停止协议末端负责）")
  }

  /// macOS resolv.conf 可能含带 zone id 的链路本地 nameserver，hickory 解析
  /// 失败只会刷 ERROR 后回退：wrapper 应直接注入强制 builtin 的环境变量。
  func testSpawnForcesBuiltinDnsResolverEnvironment() throws {
    try writeContract(ProxyRuntimeFixture.makeDocument())
    let wrapper = try launchWrapper(behavior: "run")

    XCTAssertTrue(
      try waitUntil { self.stateLog().contains("invoked:") },
      "wrapper 应拉起 sslocal，实际：\(stateLog())")
    XCTAssertTrue(
      stateLog().contains("dns-force-builtin: 1"),
      "sslocal 子进程应收到 SS_SYSTEM_DNS_RESOLVER_FORCE_BUILTIN=1，实际：\(stateLog())")

    kill(wrapper.processIdentifier, SIGTERM)
    XCTAssertEqual(try waitForExit(wrapper), 0)
  }

  // MARK: 契约缺失 / 无效 → 停止并清理

  func testMissingContractExitsCleanlyWithoutSpawning() throws {
    let wrapper = try launchWrapper(behavior: "run")

    let exitStatus = try waitForExit(wrapper)

    XCTAssertEqual(exitStatus, 0, "无契约干净退出，KeepAlive（SuccessfulExit:false）不重启")
    XCTAssertFalse(stateLog().contains("invoked"), "不应拉起 sslocal")
  }

  func testInvalidContractIsUnlinkedThenCleanExit() throws {
    try Data("not valid json {".utf8).write(to: contractURL)
    let wrapper = try launchWrapper(behavior: "run")

    let exitStatus = try waitForExit(wrapper)

    XCTAssertEqual(exitStatus, 0)
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: contractURL.path),
      "无效契约按「停止并清理」普通 unlink（D5）")
    XCTAssertFalse(stateLog().contains("invoked"))
  }

  func testStructurallyInvalidContractIsAlsoCleaned() throws {
    // 可解码但本地端口无效：wrapper 校验拒绝，不给 sslocal 反复失败的机会。
    // 空 `servers` 是合法契约——无活动目标时也可部署本地监听。
    try SslocalRuntimeDocument(
      servers: [], listen: SslocalListenSettings(socksPort: 0)
    ).jsonData().write(to: contractURL)
    let wrapper = try launchWrapper(behavior: "run")

    let exitStatus = try waitForExit(wrapper)

    XCTAssertEqual(exitStatus, 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: contractURL.path))
  }

  /// 空服务器契约是合法部署：wrapper 接受并照常拉起 sslocal，
  /// 由本地入站提供无目标的本地监听。
  func testEmptyServerContractIsValidAndRunsSslocal() throws {
    try SslocalRuntimeDocument(
      servers: [], listen: SslocalListenSettings()
    ).jsonData().write(to: contractURL)
    let wrapper = try launchWrapper(behavior: "run")

    XCTAssertTrue(
      try waitUntil { self.stateLog().contains("invoked:") },
      "空服务器契约应照常拉起 sslocal")
    XCTAssertTrue(pidAlive(wrapper.processIdentifier), "空监听会话 wrapper 应保持常驻")

    kill(wrapper.processIdentifier, SIGTERM)
    XCTAssertEqual(try waitForExit(wrapper), 0, "显式停止干净退出")
  }

  // MARK: pid 文件契约

  func testWrapperWritesAndRemovesPIDFile() throws {
    let pidURL = workDir.appendingPathComponent("agent.pid")
    try writeContract(ProxyRuntimeFixture.makeDocument())
    let wrapper = try launchWrapper(behavior: "run")

    XCTAssertTrue(
      try waitUntil { FileManager.default.fileExists(atPath: pidURL.path) },
      "wrapper 启动即写 pid 文件（GUI 判活与 SIGUSR1 投递依据）")
    let recordedPID = Int32(
      String(data: try Data(contentsOf: pidURL), encoding: .utf8)?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ) ?? "")
    XCTAssertEqual(recordedPID, wrapper.processIdentifier, "pid 文件记录 wrapper 自身 pid")

    XCTAssertTrue(try waitUntil { self.stateLog().contains("invoked:") })
    kill(wrapper.processIdentifier, SIGTERM)
    _ = try waitForExit(wrapper)
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: pidURL.path), "退出路径清理 pid 文件")
  }
}
