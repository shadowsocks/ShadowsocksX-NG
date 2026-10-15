import Foundation
import Testing

@testable import ShadowsocksX_NG2

@MainActor
struct AppLanguagePreferencesTests {
  @Test func missingApplicationOverrideUsesAutomatic() throws {
    let suite = "language-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    let preferences = AppLanguagePreferences(defaults: defaults, applicationID: suite)

    #expect(preferences.selection == .automatic)
  }

  @Test func languageSelectionSurvivesRelaunchAndAutomaticRemovesOverride() throws {
    let suite = "language-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: "silentLaunch")
    let preferences = AppLanguagePreferences(defaults: defaults, applicationID: suite)

    for language in [AppLanguage.english, .simplifiedChinese] {
      preferences.select(language)
      #expect(preferences.selection == language)
      #expect(
        AppLanguagePreferences(defaults: defaults, applicationID: suite).selection == language)
      #expect(defaults.stringArray(forKey: "AppleLanguages") == [language.rawValue])
    }

    preferences.select(.automatic)
    #expect(
      AppLanguagePreferences(defaults: defaults, applicationID: suite).selection == .automatic)
    #expect(defaults.persistentDomain(forName: suite)?["AppleLanguages"] == nil)
    #expect(defaults.bool(forKey: "silentLaunch"))
  }

  @Test func menuNamesUseNativePrefixAndCurrentInterfaceTranslation() throws {
    let appBundle = AppArtifact.bundle
    let english = try #require(
      Bundle(url: appBundle.bundleURL.appendingPathComponent("Contents/Resources/en.lproj")))
    let chinese = try #require(
      Bundle(url: appBundle.bundleURL.appendingPathComponent("Contents/Resources/zh-Hans.lproj")))

    #expect(AppLanguage.automatic.menuTitle(in: english) == "Auto Detect · Auto Detect")
    #expect(AppLanguage.simplifiedChinese.menuTitle(in: english) == "简体中文 · Simplified Chinese")
    #expect(AppLanguage.english.menuTitle(in: english) == "English · English")
    #expect(AppLanguage.automatic.menuTitle(in: chinese) == "Auto Detect · 自动检测")
    #expect(AppLanguage.simplifiedChinese.menuTitle(in: chinese) == "简体中文 · 简体中文")
    #expect(AppLanguage.english.menuTitle(in: chinese) == "English · 英文")
    #expect(AppLanguage.automatic.currentValueTitle(in: english) == "Auto Detect")
    #expect(AppLanguage.simplifiedChinese.currentValueTitle(in: english) == "简体中文")
    #expect(AppLanguage.english.currentValueTitle(in: chinese) == "English")
  }
}
