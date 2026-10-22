import Darwin
import Foundation

/// An isolated process group owns sslocal and every SIP003 child. No formal
/// runtime file, ACL, activity selection, or system proxy is touched.
@MainActor
struct ConnectivityRuntime {
  private struct MeasurementContext {
    let id: UUID
    let url: URL
    let started: ContinuousClock.Instant
    let deadline: ContinuousClock.Instant
    let startupDeadline: ContinuousClock.Instant
    let directory: URL
  }

  private struct ProbeProcess {
    let pid: pid_t
    let port: Int
  }

  private struct ProbeRunResult {
    let outcome: ServerConnectivity.Outcome
    let pid: pid_t
    let reaped: Bool
    let startupCompleted: Bool
  }

  let executable: URL
  var measurement = ConnectivityMeasurement()
  var temporaryRoot: URL = FileManager.default.temporaryDirectory

  func measure(
    _ server: SslocalServerDocument, url: URL, preparationDeadline deadline: ContinuousClock.Instant
  ) async -> ServerConnectivity.Outcome {
    let started = ContinuousClock.now
    let context = MeasurementContext(
      id: UUID(), url: url, started: started, deadline: deadline,
      startupDeadline: min(deadline, started.advanced(by: .seconds(10))),
      directory: temporaryRoot.appendingPathComponent(UUID().uuidString))
    let run = await run(server, context: context)
    await cleanup(pid: run.pid, reaped: run.reaped, directory: context.directory)
    return run.outcome
  }

  private func run(
    _ server: SslocalServerDocument, context: MeasurementContext
  ) async -> ProbeRunResult {
    var pid: pid_t = 0
    var reaped = false
    var startupCompleted = false
    var result: ServerConnectivity.Outcome = .startup
    do {
      try FileManager.default.createDirectory(
        at: context.directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      try Task.checkCancellation()
      guard ContinuousClock.now < context.deadline else {
        return ProbeRunResult(
          outcome: .preparationTimeout, pid: 0, reaped: false, startupCompleted: false)
      }
      let process = try launch(server, in: context.directory)
      pid = process.pid
      let readiness = try await waitForServer(process, context: context)
      reaped = readiness.reaped
      startupCompleted = readiness.startupCompleted
      result = readiness.outcome
    } catch is CancellationError {
      result = .network
    } catch {
      result = .startup
    }
    if !startupCompleted {
      emitStartupFailure(result, context: context)
    }
    return ProbeRunResult(
      outcome: result, pid: pid, reaped: reaped, startupCompleted: startupCompleted)
  }

  private func launch(_ server: SslocalServerDocument, in directory: URL) throws -> ProbeProcess {
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
    return ProbeProcess(pid: try spawn(config), port: port)
  }

  private func waitForServer(
    _ process: ProbeProcess, context: MeasurementContext
  ) async throws -> ProbeRunResult {
    var reaped = false
    while ContinuousClock.now < context.startupDeadline {
      try Task.checkCancellation()
      var status: Int32 = 0
      if waitpid(process.pid, &status, WNOHANG) == process.pid {
        reaped = true
        break
      }
      if ownsHealthyListener(process) {
        guard ContinuousClock.now < context.deadline else { break }
        emitStartupSuccess(context)
        let measured = await measurement.measure(
          url: context.url, proxyPort: process.port, preparationDeadline: context.deadline)
        for entry in measured.trace {
          RuntimeLog.emit(.connectivityMeasurement(id: context.id, entry: entry))
        }
        return ProbeRunResult(
          outcome: measured.outcome, pid: process.pid, reaped: reaped, startupCompleted: true)
      }
      try await Task.sleep(for: .milliseconds(25))
    }
    let outcome: ServerConnectivity.Outcome =
      ContinuousClock.now >= context.startupDeadline
      ? .preparationTimeout : .startup
    return ProbeRunResult(
      outcome: outcome, pid: process.pid, reaped: reaped, startupCompleted: false)
  }

  private func ownsHealthyListener(_ process: ProbeProcess) -> Bool {
    RuntimeSocketOwnershipProbe.process(process.pid, ownsTCPListenerOn: process.port)
      && EndpointHealthProbe.probe(
        host: "127.0.0.1", port: process.port, timeout: 0.02) == .reachable
  }

  private func emitStartupSuccess(_ context: MeasurementContext) {
    let parts = context.started.duration(to: .now).components
    RuntimeLog.emit(
      .connectivityMeasurement(
        id: context.id,
        entry: ConnectivityTrace(
          phase: .startup, status: .success,
          milliseconds: Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15)))
  }

  private func emitStartupFailure(
    _ outcome: ServerConnectivity.Outcome, context: MeasurementContext
  ) {
    let parts = context.started.duration(to: .now).components
    let status: ConnectivityTrace.Status =
      Task.isCancelled
      ? .cancelled : outcome == .preparationTimeout ? .timeout : .network
    RuntimeLog.emit(
      .connectivityMeasurement(
        id: context.id,
        entry: ConnectivityTrace(
          phase: .startup, status: status,
          milliseconds: Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15,
          failureStage: .startup)))
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
    defer {
      for string in strings {
        free(string)
      }
    }
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
