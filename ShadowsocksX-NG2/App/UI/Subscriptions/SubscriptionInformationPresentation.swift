import Foundation

extension SubscriptionInformation {
  /// 只在两项都有效且总量非零时给出进度；先转浮点避免 UInt64 相加溢出。
  var usedFraction: Double? {
    guard let bytesUsed, let bytesRemaining, bytesUsed != 0 || bytesRemaining != 0 else {
      return nil
    }
    let used = Double(bytesUsed)
    return used / (used + Double(bytesRemaining))
  }

  static func byteCountText(_ count: UInt64, locale: Locale) -> String {
    // Measurement 的浮点输入覆盖完整 UInt64 范围，不经 Int64 截断。
    Measurement(value: Double(count), unit: UnitInformationStorage.bytes)
      .formatted(.byteCount(style: .binary, spellsOutZero: false).locale(locale))
  }
}
