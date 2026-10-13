import Darwin
import Foundation

/// An isolated process group owns sslocal and every SIP003 child. No formal
/// runtime file, ACL, activity selection, or system proxy is touched.
@MainActor
struct ConnectivityRuntime {
  let executable: URL
  var temporaryRoot: URL = FileManager.default.temporaryDirectory

  func measure(
    _ server: SslocalServerDocument, url: URL, preparationDeadline deadline: ContinuousClock.Instant
  ) async -> ServerConnectivity.Outcome {
    let directory = temporaryRoot.appendingPathComponent(UUID().uuidString)
    var pid: pid_t = 0
    var reaped = false
    var result: ServerConnectivity.Outcome = .startup
    do {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      try Task.checkCancellation()
      guard ContinuousClock.now < deadline else {
        try? FileManager.default.removeItem(at: directory)
        return .preparationTimeout
      }
      let port = try freePort()
      let config = directory.appendingPathComponent("test.json")
      // A single TCP HTTP inbound, no ACL: every request must use this server.
      let data = try JSONSerialization.data(withJSONObject: [
        "servers": [try JSONSerialization.jsonObject(with: JSONEncoder().encode(server))],
        "locals": [
          [
            "protocol": "http", "local_address": "127.0.0.1",
            "local_port": port, "mode": "tcp_only",
          ]
        ],
      ])
      try AtomicFileWriter.write(data, to: config)
      pid = try spawn(config)
      while ContinuousClock.now < deadline {
        try Task.checkCancellation()
        var status: Int32 = 0
        if waitpid(pid, &status, WNOHANG) == pid {
          reaped = true
          break
        }
        if RuntimeSocketOwnershipProbe.process(pid, ownsTCPListenerOn: port),
          EndpointHealthProbe.probe(host: "127.0.0.1", port: port, timeout: 0.02) == .reachable
        {
          if ContinuousClock.now >= deadline { break }
          result = await ConnectivityHTTPRequest().perform(url: url, proxyPort: port)
          break
        }
        try await Task.sleep(for: .milliseconds(25))
      }
      if ContinuousClock.now >= deadline, result == .startup { result = .preparationTimeout }
    } catch is CancellationError {
      result = .network
    } catch {
      result = .startup
    }
    await cleanup(pid: pid, reaped: reaped, directory: directory)
    return result
  }

  private func cleanup(pid child: pid_t, reaped alreadyReaped: Bool, directory: URL) async {
    // Cleanup is not cancelled with the measurement. Slots remain occupied until
    // the group has been terminated and its leader reaped.
    await Task {
      if child > 0 {
        _ = kill(-child, SIGTERM)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        var reaped = alreadyReaped
        while ContinuousClock.now < deadline {
          if !reaped {
            var status: Int32 = 0
            reaped = waitpid(child, &status, WNOHANG) == child
          }
          if kill(-child, 0) != 0 { break }
          try? await Task.sleep(for: .milliseconds(25))
        }
        _ = kill(-child, SIGKILL)
        if !reaped {
          var status: Int32 = 0
          _ = waitpid(child, &status, 0)
        }
      }
      try? FileManager.default.removeItem(at: directory)
    }.value
  }

  private func freePort() throws -> Int {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw RuntimeError.failed }
    defer { close(descriptor) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bound == 0 else { throw RuntimeError.failed }
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let read = withUnsafeMutablePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
    }
    guard read == 0 else { throw RuntimeError.failed }
    return Int(UInt16(bigEndian: address.sin_port))
  }

  private func spawn(_ config: URL) throws -> pid_t {
    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
    posix_spawnattr_setpgroup(&attributes, 0)
    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    // Child output can contain plugin options and credentials; discard it.
    for descriptor in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
      posix_spawn_file_actions_addopen(&actions, descriptor, "/dev/null", O_RDWR, 0)
    }
    let strings = [executable.path, "-c", config.path].map { strdup($0) }
    defer { strings.forEach { free($0) } }
    var argv = strings + [nil]
    var pid: pid_t = 0
    let status = argv.withUnsafeMutableBufferPointer {
      posix_spawn(&pid, executable.path, &actions, &attributes, $0.baseAddress!, environ)
    }
    guard status == 0 else { throw RuntimeError.failed }
    return pid
  }

  private enum RuntimeError: Error { case failed }
}
