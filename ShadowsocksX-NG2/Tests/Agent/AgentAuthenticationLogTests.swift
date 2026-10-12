import Darwin
import Foundation
import Testing

@testable import ShadowsocksX_NG2

struct AgentAuthenticationLogTests {
  @Test func wrapperHidesPasswordsAcrossChunksAndDiscardsOversizedLines() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let contract = directory.appendingPathComponent("sslocal-active.json")
    var listen = SslocalListenSettings()
    listen.socksPort = Int.random(in: 30_000...60_000)
    listen.httpPort = listen.socksPort + 1
    try RuntimeFileStore(fileURL: contract).write(
      SslocalRuntimeDocument(servers: [], listen: listen))
    let stub = directory.appendingPathComponent("sslocal-stub")
    let script = """
      #!/bin/sh
      /usr/bin/awk 'BEGIN {
        print "authentication rejected, password: secret-one";
        printf "password: ";
        for (i=0; i<70000; i++) printf "x";
        fflush(); system("/bin/sleep 0.05");
        print "secret-tail"; print "ordinary event";
        fflush(); system("/bin/sleep 0.1");
      }'
      """
    try script.write(to: stub, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stub.path)
    let process = Process()
    process.executableURL = AppArtifact.bundleURL.appendingPathComponent(
      "Contents/MacOS/ShadowsocksX-NG2Agent")
    var environment = ProcessInfo.processInfo.environment
    environment["SSXNG_CONTRACT_PATH"] = contract.path
    environment["SSXNG_SSLOCAL_PATH"] = stub.path
    environment["SSXNG_RUNTIME_DIR"] = directory.path
    process.environment = environment
    try process.run()
    defer {
      if process.isRunning { kill(process.processIdentifier, SIGKILL) }
      process.waitUntilExit()
    }
    let deadline = Date().addingTimeInterval(5)
    while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
    #expect(!process.isRunning)
    let log = try String(contentsOf: directory.appendingPathComponent("agent.log"), encoding: .utf8)
    #expect(!log.contains("secret-one"))
    #expect(!log.contains("secret-tail"))
    #expect(log.contains("password: [redacted]"))
    #expect(log.contains("ordinary event"))
  }
}
