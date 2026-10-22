import Foundation

enum FirewallBlockStatus: Equatable, Sendable {
  case permitted
  case blocked
  case unknown
}

protocol FirewallStatusChecking: Sendable {
  func status(for executableURL: URL) -> FirewallBlockStatus
}

/// `socketfilterfw --getappblocked` 是应用防火墙拒绝态的只读系统边界。
/// 命令缺失、输出漂移或执行失败一律降级为 unknown，不阻断回环/本机代理。
struct SocketFilterFirewallChecker: FirewallStatusChecking, @unchecked Sendable {
  typealias CommandRunner = (URL, [String]) throws -> String

  private static let toolURL = URL(
    fileURLWithPath: "/usr/libexec/ApplicationFirewall/socketfilterfw")
  private let runCommand: CommandRunner

  init(_ runCommand: @escaping CommandRunner = Self.run) {
    self.runCommand = runCommand
  }

  func status(for executableURL: URL) -> FirewallBlockStatus {
    guard
      let output = try? runCommand(
        Self.toolURL, ["--getappblocked", executableURL.path])
    else { return .unknown }
    let normalized = output.lowercased()
    if normalized.contains(" is blocked") { return .blocked }
    if normalized.contains(" is permitted") { return .permitted }
    return .unknown
  }

  private static func run(executableURL: URL, arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw CocoaError(.executableLoad)
    }
    guard let output = String(data: data, encoding: .utf8) else {
      throw CocoaError(.fileReadInapplicableStringEncoding)
    }
    return output
  }
}
