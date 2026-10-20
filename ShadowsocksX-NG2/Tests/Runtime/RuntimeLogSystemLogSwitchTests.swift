import Testing

@testable import ShadowsocksX_NG2

struct RuntimeLogSystemLogSwitchTests {
  @Test func systemLogIsDisabledOnlyByExplicitZero() {
    #expect(RuntimeLog.isSystemLogEnabled([:]))
    #expect(RuntimeLog.isSystemLogEnabled(["SSXNG_SYSTEM_LOG": "1"]))
    #expect(!RuntimeLog.isSystemLogEnabled(["SSXNG_SYSTEM_LOG": "0"]))
  }
}
