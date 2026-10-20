import Testing

@testable import ShadowsocksX_NG2

struct SystemLogSwitchTests {
  @Test func systemLogIsDisabledOnlyByExplicitZero() {
    #expect(SystemLog.isSystemLogEnabled([:]))
    #expect(SystemLog.isSystemLogEnabled(["SSXNG_SYSTEM_LOG": "1"]))
    #expect(!SystemLog.isSystemLogEnabled(["SSXNG_SYSTEM_LOG": "0"]))
  }
}
