import Foundation
import Testing

@testable import ShadowsocksX_NG2

struct PluginSecurityInspectionTests {
  @Test func commandLineAssessmentContextIsNotReportedAsExecutionBlock() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let binary = root.appendingPathComponent("tool")
    try Data([0xcf, 0xfa, 0xed, 0xfe]).write(to: binary)
    let checker = MacOSPluginInspection { tool, _ in
      if tool.lastPathComponent == "codesign" {
        return PluginInspectionCommandResult(status: 0, output: "valid on disk")
      }
      return PluginInspectionCommandResult(
        status: 3, output: "tool: rejected (the code is valid but does not seem to be an app)")
    }
    let facts = await checker.inspect(binary)
    #expect(facts.signature == .valid)
    #expect(facts.policy == .notApplicable)
  }
}
