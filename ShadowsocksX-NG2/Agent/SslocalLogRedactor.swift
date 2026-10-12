import Foundation

/// 上游认证失败日志包含客户端提交的密码；按完整行隐藏密码后写入私有日志。
/// FileHandle 回调通过锁串行访问缓冲区，避免分块输入绕过隐藏规则。
final class SslocalLogRedactor: @unchecked Sendable {
  private let lock = NSLock()
  private var buffer = Data()
  private var discardingOversizedLine = false

  func write(_ data: Data) {
    lock.lock()
    defer { lock.unlock() }
    if discardingOversizedLine {
      guard let newline = data.firstIndex(of: 10) else { return }
      discardingOversizedLine = false
      buffer.append(data.suffix(from: data.index(after: newline)))
    } else {
      buffer.append(data)
    }
    while let newline = buffer.firstIndex(of: 10) {
      emit(buffer.prefix(through: newline))
      buffer.removeSubrange(...newline)
    }
    if data.isEmpty && !buffer.isEmpty {
      emit(buffer)
      buffer.removeAll()
    } else if buffer.count > 65_536 {
      buffer.removeAll()
      discardingOversizedLine = true
      FileHandle.standardError.write(Data("sslocal: log line truncated\n".utf8))
    }
  }

  private func emit(_ line: Data) {
    guard let text = String(data: line, encoding: .utf8) else { return }
    let sanitized = text.replacingOccurrences(
      of: "password: [^\\r\\n]*",
      with: "password: [redacted]", options: .regularExpression)
    FileHandle.standardError.write(Data(sanitized.utf8))
  }
}
