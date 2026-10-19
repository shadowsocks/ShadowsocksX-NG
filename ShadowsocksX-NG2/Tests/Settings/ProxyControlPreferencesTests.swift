import Foundation
import Testing

@testable import ShadowsocksX_NG2

struct ProxyControlPreferencesTests {
  @Test func freshPreferencesUseFactoryIntentWithoutChangingExistingPreferences() throws {
    let suite = "proxy-control-defaults-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: "silentLaunch")
    defaults.set("http://example.com/probe", forKey: "connectivityTestURL")

    let settings = ProxyRuntimeSettings(
      listen: ProxyListeningConfiguration(),
      preferences: ProxyControlPreferences(defaults: defaults))

    #expect(settings.preferredMode == .rule)
    #expect(settings.ruleDefaultAction == .proxyWhenUnmatched)
    #expect(!settings.agentEnabled)
    #expect(!settings.systemProxyEnabled)
    #expect(settings.proxyExceptions.isEmpty)
    #expect(defaults.bool(forKey: "silentLaunch"))
    #expect(defaults.string(forKey: "connectivityTestURL") == "http://example.com/probe")
  }

  @Test func rebuildingSnapshotRestoresIndependentPreferencesAndCurrentListeningConfiguration()
    throws
  {
    let suite = "proxy-control-roundtrip-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ProxyControlPreferences(defaults: defaults)
    preferences.preferredMode = .direct
    preferences.ruleDefaultAction = .directWhenUnmatched
    preferences.agentEnabled = true
    preferences.systemProxyEnabled = true
    preferences.proxyExceptions = "example.com, localhost"
    var listen = ProxyListeningConfiguration()
    listen.socksPort = 23001
    listen.httpPort = 23002

    let reopened = ProxyControlPreferences(defaults: try #require(UserDefaults(suiteName: suite)))
    let settings = ProxyRuntimeSettings(listen: listen, preferences: reopened)

    #expect(settings.preferredMode == .direct)
    #expect(settings.ruleDefaultAction == .directWhenUnmatched)
    #expect(settings.agentEnabled)
    #expect(settings.systemProxyEnabled)
    #expect(settings.proxyExceptionList == ["example.com", "localhost"])
    #expect(settings.listen.socksPort == 23001)
    #expect(settings.listen.httpPort == 23002)
  }
}
