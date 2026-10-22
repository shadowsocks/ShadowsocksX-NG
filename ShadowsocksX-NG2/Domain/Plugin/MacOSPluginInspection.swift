import Darwin
import Foundation

struct PluginSecurityFacts: Equatable, Sendable {
  enum Quarantine: Sendable { case present, absent, unknown }
  enum Signature: Sendable { case valid, unsigned, invalid, notApplicable, unknown }
  enum Policy: Sendable { case accepted, rejected, notApplicable, unknown }
  let quarantine: Quarantine
  let signature: Signature
  let policy: Policy
}

protocol PluginInspecting: Sendable {
  func inspect(_ executable: URL) async -> PluginSecurityFacts
}

struct PluginInspectionCommandResult: Sendable {
  let status: Int32
  let output: String
}

/// Read-only evidence, not a prediction that exec will succeed or a security guarantee.
struct MacOSPluginInspection: PluginInspecting {
  typealias CommandRunner = @Sendable (URL, [String]) -> PluginInspectionCommandResult?
  private let runCommand: CommandRunner

  init(
    runCommand: @escaping CommandRunner = { tool, arguments in Self.run(tool, arguments: arguments)
    }
  ) {
    self.runCommand = runCommand
  }

  func inspect(_ executable: URL) async -> PluginSecurityFacts {
    await Task.detached(priority: .utility) { inspectSynchronously(executable) }.value
  }

  private func inspectSynchronously(_ executable: URL) -> PluginSecurityFacts {
    let attributeSize = getxattr(executable.path, "com.apple.quarantine", nil, 0, 0, 0)
    let quarantine: PluginSecurityFacts.Quarantine =
      attributeSize >= 0 ? .present : (errno == ENOATTR ? .absent : .unknown)
    let signature: PluginSecurityFacts.Signature
    let header: Data? = {
      guard let handle = try? FileHandle(forReadingFrom: executable) else { return nil }
      defer { try? handle.close() }
      return try? handle.read(upToCount: 4)
    }()
    if header?.starts(with: [0x23, 0x21]) == true {
      signature = .notApplicable
    } else if let result = runCommand(
      URL(fileURLWithPath: "/usr/bin/codesign"),
      ["--verify", "--strict", "--verbose=2", executable.path])
    {
      if result.status == 0 {
        signature = .valid
      } else if result.output.contains("not signed at all") {
        signature = .unsigned
      } else if result.output.contains("invalid signature")
        || result.output.contains("code or signature have been modified")
      {
        signature = .invalid
      } else {
        signature = .unknown
      }
    } else {
      signature = .unknown
    }
    let policy: PluginSecurityFacts.Policy
    if let result = runCommand(
      URL(fileURLWithPath: "/usr/sbin/spctl"),
      ["--assess", "--type", "execute", "--verbose=2", executable.path])
    {
      if result.status == 0 {
        policy = .accepted
      } else if result.output.contains("does not seem to be an app")
        || result.output.contains("Insufficient Context")
      {
        policy = .notApplicable
      } else if result.output.contains(": rejected") {
        policy = .rejected
      } else {
        policy = .unknown
      }
    } else {
      policy = .unknown
    }
    return PluginSecurityFacts(quarantine: quarantine, signature: signature, policy: policy)
  }

  /// Use a private output file to avoid pipe deadlocks; only read a bounded prefix.
  /// Only fixed Apple tools run here. The plugin itself is never executed.
  private static func run(_ tool: URL, arguments: [String]) -> PluginInspectionCommandResult? {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("plugin-inspection-\(UUID().uuidString)")
    guard
      (try? FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])) != nil
    else { return nil }
    defer { try? FileManager.default.removeItem(at: directory) }
    let outputURL = directory.appendingPathComponent("output")
    guard
      FileManager.default.createFile(
        atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600]),
      let output = try? FileHandle(forWritingTo: outputURL)
    else { return nil }
    defer { try? output.close() }
    let process = Process()
    process.executableURL = tool
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = output
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    do { try process.run() } catch { return nil }
    guard finished.wait(timeout: .now() + 3) == .success else {
      // A timed-out assessment is unknown, never rejected.
      kill(process.processIdentifier, SIGKILL)
      _ = finished.wait(timeout: .now() + 1)
      return nil
    }
    guard let input = try? FileHandle(forReadingFrom: outputURL) else { return nil }
    defer { try? input.close() }
    guard let data = try? input.read(upToCount: 16_384) else { return nil }
    return PluginInspectionCommandResult(
      status: process.terminationStatus, output: String(bytes: data, encoding: .utf8) ?? "")
  }
}

/// Reject evidence for another file, including a changed symlink target.
struct PluginFileIdentity: Equatable, Sendable {
  let resolvedPath: String
  let inode: UInt64
  let device: Int32
  let size: Int64
  let modifiedSeconds: Int
  let modifiedNanoseconds: Int
  let changedSeconds: Int
  let changedNanoseconds: Int
  let permissions: UInt16

  init?(path: String) {
    let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    var facts = stat()
    guard stat(resolved.path, &facts) == 0 else { return nil }
    self.resolvedPath = resolved.path
    self.inode = facts.st_ino
    self.device = facts.st_dev
    self.size = facts.st_size
    self.modifiedSeconds = facts.st_mtimespec.tv_sec
    self.modifiedNanoseconds = facts.st_mtimespec.tv_nsec
    self.changedSeconds = facts.st_ctimespec.tv_sec
    self.changedNanoseconds = facts.st_ctimespec.tv_nsec
    self.permissions = facts.st_mode
  }
}
