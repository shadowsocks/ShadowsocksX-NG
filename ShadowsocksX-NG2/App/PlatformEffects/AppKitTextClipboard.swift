import AppKit

/// 生产 AppKit clipboard adapter。所有 NSPasteboard 访问集中在此文件，避免
/// 每个 UI surface 重复 pasteboard replacement 语义。
@MainActor
final class AppKitTextClipboard: TextClipboard {
  private let pasteboard: NSPasteboard

  init(pasteboard: NSPasteboard = .general) {
    self.pasteboard = pasteboard
  }

  func read() -> String? {
    pasteboard.string(forType: .string)
  }

  func write(_ text: String) throws {
    guard pasteboard.clearContents() != 0, pasteboard.setString(text, forType: .string) else {
      throw TextClipboardFailure.writeFailed
    }
  }
}
