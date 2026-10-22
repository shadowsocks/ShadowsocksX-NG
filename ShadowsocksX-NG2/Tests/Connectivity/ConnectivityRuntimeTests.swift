import Darwin
import Foundation
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct ConnectivityRuntimeTests {
  @Test func preparationTimeoutKillsProcessGroupAndRemovesSecretsBeforeCompleting() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let environments = root.appendingPathComponent("environments")
    let pidFile = root.appendingPathComponent("pid")
    let script = root.appendingPathComponent("fake-sslocal")
    // Ignore TERM so this test exercises the two-second force termination path.
    let text = "#!/bin/sh\ntrap '' TERM\necho $$ > '\(pidFile.path)'\nsleep 60 &\nwait\n"
    try text.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
    let adapter = ConnectivityRuntime(executable: script, temporaryRoot: environments)
    let id = NodeID.fresh()
    let server = SslocalServerDocument(
      id: id.rawValue, server: "example.com", serverPort: 443,
      password: "private", method: "aes-256-gcm", plugin: nil, pluginOpts: nil)
    let module = ServerConnectivity(
      configuration: { _ in server },
      measure: { server, url, _ in
        await adapter.measure(
          server, url: url, preparationDeadline: .now.advanced(by: .milliseconds(100)))
      })
    let started = ContinuousClock.now
    await module.wait(for: module.test([id]))
    #expect(module.history(for: id).first?.outcome == .preparationTimeout)
    #expect(ContinuousClock.now - started >= .seconds(2))
    #expect(try FileManager.default.contentsOfDirectory(atPath: environments.path).isEmpty)
    let pid = try #require(
      Int32(
        String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
      ))
    #expect(kill(pid, 0) != 0)
    #expect(module.testing.isEmpty)
    #expect(module.isCooling(id))
  }
}
