import Foundation
import Testing

@testable import ShadowsocksX_NG2

struct SubscriptionInformationPresentationTests {
  @Test func usageRequiresBothCountsAndNonzeroTotal() {
    #expect(SubscriptionInformation(bytesUsed: 25, bytesRemaining: 75).usedFraction == 0.25)
    #expect(SubscriptionInformation(bytesUsed: 0, bytesRemaining: 0).usedFraction == nil)
    #expect(SubscriptionInformation(bytesUsed: 25).usedFraction == nil)
    #expect(SubscriptionInformation(bytesRemaining: 75).usedFraction == nil)
    #expect(SubscriptionInformation(bytesUsed: 0, bytesRemaining: 75).usedFraction == 0)
    #expect(SubscriptionInformation(bytesUsed: 25, bytesRemaining: 0).usedFraction == 1)
    #expect(
      SubscriptionInformation(bytesUsed: .max, bytesRemaining: .max).usedFraction == 0.5)
  }
  @Test func byteCountFormattingUsesLocaleAndDoesNotClampToSignedRange() {
    let locale = Locale(identifier: "en_US")
    #expect(SubscriptionInformation.byteCountText(0, locale: locale) == "0 bytes")
    #expect(SubscriptionInformation.byteCountText(1024, locale: locale) == "1 kB")
    #expect(SubscriptionInformation.byteCountText(.max, locale: locale) == "16,384 PB")
  }

}
