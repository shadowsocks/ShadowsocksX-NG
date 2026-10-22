import Foundation

/// 白名单订阅资料，不含服务器连接字段、凭据或原始响应。
struct SubscriptionInformation: Codable, Equatable, Sendable {
  var bytesUsed: UInt64?
  var bytesRemaining: UInt64?
  var expiresAt: Date?
  var trafficResetAt: Date?

  var isEmpty: Bool {
    bytesUsed == nil && bytesRemaining == nil && expiresAt == nil && trafficResetAt == nil
  }

  /// 与服务器及分组扩展的解码分别处理；无效附加资料只影响该项。
  static func parse(_ data: Data) -> Self {
    let root = rootFields(data)
    return Self(
      bytesUsed: byteCount(root["bytes_used"]),
      bytesRemaining: byteCount(root["bytes_remaining"]),
      expiresAt: date(root["expires_at"]),
      trafficResetAt: date(root["traffic_reset_at"]))
  }

  private static func byteCount(_ value: Data?) -> UInt64? {
    guard let value, let raw = String(bytes: value, encoding: .utf8) else { return nil }
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
    return UInt64(text)
  }

  private static func date(_ value: Data?) -> Date? {
    guard let value, let text = try? JSONDecoder().decode(String.self, from: value) else {
      return nil
    }
    let normalized = text.uppercased()
    let pattern =
      #"\A[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T"#
      + #"([01][0-9]|2[0-3]):[0-5][0-9]:([0-5][0-9]|60)(\.[0-9]+)?"#
      + #"(Z|[+-]([01][0-9]|2[0-3]):[0-5][0-9])\z"#
    guard normalized.range(of: pattern, options: .regularExpression) != nil else { return nil }
    // RFC 3339 的偏移可达 23:59，超出 Foundation 时区解析器的 18 小时范围。
    // 先解析原地时间，再应用数值偏移；不创建会失败的 TimeZone。
    let localText = normalized.hasSuffix("Z") ? normalized : String(normalized.dropLast(6)) + "Z"
    guard
      let local = try? Date.ISO8601FormatStyle(
        includingFractionalSeconds: normalized.contains(".")
      ).parse(localText)
    else { return nil }
    let parsed = local.addingTimeInterval(-Double(offsetSeconds(normalized)))
    // Foundation 会把 2 月 30 日等无效日期向后归一化；按原偏移回读以拒绝这些值。
    let parts = normalized.prefix(19).split(whereSeparator: { "-T:".contains($0) }).compactMap {
      Int($0)
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    let isLeapSecond = parts[5] == 60
    let checked = isLeapSecond ? local.addingTimeInterval(-1) : local
    let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
    let components = calendar.dateComponents(fields, from: checked)
    guard components.year == parts[0], components.month == parts[1],
      components.day == parts[2], components.hour == parts[3], components.minute == parts[4],
      components.second == (isLeapSecond ? 59 : parts[5])
    else { return nil }
    if isLeapSecond {
      let utc = calendar.dateComponents(fields, from: parsed.addingTimeInterval(-1))
      guard utc.hour == 23, utc.minute == 59,
        (utc.month == 6 && utc.day == 30) || (utc.month == 12 && utc.day == 31)
      else { return nil }
    }
    return parsed
  }

  private static func offsetSeconds(_ text: String) -> Int {
    guard !text.hasSuffix("Z") else { return 0 }
    let offset = text.suffix(6)
    let hours = Int(offset.dropFirst().prefix(2))!
    let minutes = Int(offset.suffix(2))!
    return (hours * 60 + minutes) * 60 * (offset.first == "-" ? -1 : 1)
  }
  /// JSON 结构已由订阅文档解析器校验。这里只切出根级白名单值的原始片段，
  /// 不把整个正文转换成 Any；某项超大数字因此不会损坏其他项的解码。
  private static func rootFields(_ data: Data) -> [String: Data] {
    let bytes = Array(data)
    let names: Set<String> = ["bytes_used", "bytes_remaining", "expires_at", "traffic_reset_at"]
    var result: [String: Data] = [:]
    // 与现有 JSONDecoder 一致，接受可选的 UTF-8 BOM。
    var cursor = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
    skipWhitespace(bytes, cursor: &cursor)
    guard cursor < bytes.count, bytes[cursor] == 123 else { return result }
    cursor += 1
    while cursor < bytes.count {
      skipWhitespace(bytes, cursor: &cursor)
      guard cursor < bytes.count, bytes[cursor] == 34 else { break }
      let keyStart = cursor
      skipString(bytes, cursor: &cursor)
      let key = try? JSONDecoder().decode(String.self, from: Data(bytes[keyStart..<cursor]))
      skipWhitespace(bytes, cursor: &cursor)
      guard cursor < bytes.count, bytes[cursor] == 58 else { break }
      cursor += 1
      let valueStart = cursor
      skipValue(bytes, cursor: &cursor)
      if let key, names.contains(key) {
        result[key] = Data(bytes[valueStart..<cursor])
      }
      guard cursor < bytes.count, bytes[cursor] == 44 else { break }
      cursor += 1
    }
    return result
  }

  private static func skipValue(_ bytes: [UInt8], cursor: inout Int) {
    var depth = 0
    while cursor < bytes.count {
      switch bytes[cursor] {
      case 34:
        skipString(bytes, cursor: &cursor)
        continue
      case 123, 91:
        depth += 1
      case 125, 93:
        guard depth > 0 else { return }
        depth -= 1
      case 44:
        if depth == 0 { return }
      default:
        break
      }
      cursor += 1
    }
  }

  private static func skipWhitespace(_ bytes: [UInt8], cursor: inout Int) {
    while cursor < bytes.count, [9, 10, 13, 32].contains(bytes[cursor]) { cursor += 1 }
  }

  private static func skipString(_ bytes: [UInt8], cursor: inout Int) {
    cursor += 1
    while cursor < bytes.count {
      if bytes[cursor] == 92 {
        cursor = min(cursor + 2, bytes.count)
      } else if bytes[cursor] == 34 {
        cursor += 1
        return
      } else {
        cursor += 1
      }
    }
  }

}
