import AppKit

/// 生产 AppKit image clipboard adapter，与 AppKitTextClipboard 同为 pasteboard
/// replacement 语义的集中点。PNG 为规范类型，另附 TIFF 兼容类型（部分接收方
/// 如聊天应用只认 TIFF）；TIFF 附加失败不影响 PNG 已写入这一结果。
@MainActor
final class AppKitImageClipboard: ImageClipboard {
  private let pasteboard: NSPasteboard

  init(pasteboard: NSPasteboard = .general) {
    self.pasteboard = pasteboard
  }

  func write(_ pngData: Data) throws {
    guard pasteboard.clearContents() != 0, pasteboard.setData(pngData, forType: .png) else {
      throw ImageClipboardFailure.writeFailed
    }
    if let image = NSImage(data: pngData), let tiff = image.tiffRepresentation {
      _ = pasteboard.setData(tiff, forType: .tiff)
    }
  }
}
