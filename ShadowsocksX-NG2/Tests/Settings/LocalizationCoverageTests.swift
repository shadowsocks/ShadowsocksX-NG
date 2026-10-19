import Foundation
import Testing

@testable import ShadowsocksX_NG2

struct LocalizationCoverageTests {
  @Test func interfaceAndErrorResourcesResolveInBothLanguages() throws {
    let resources = AppArtifact.bundle.bundleURL.appendingPathComponent("Contents/Resources")
    let english = try #require(Bundle(url: resources.appendingPathComponent("en.lproj")))
    let chinese = try #require(Bundle(url: resources.appendingPathComponent("zh-Hans.lproj")))
    #expect(
      String(localized: "后台代理客户端", bundle: english, locale: Locale(identifier: "en"))
        == "Background proxy client")
    #expect(String(localized: "后台代理客户端", bundle: chinese) == "后台代理客户端")
    #expect(
      String(localized: "目标分组不存在", bundle: english, locale: Locale(identifier: "en"))
        == "The destination group does not exist")
    #expect(String(localized: "目标分组不存在", bundle: chinese) == "目标分组不存在")
    let field = "server address"
    let index = 3
    #expect(
      String(
        localized: "订阅第 \(index) 条服务器记录的\(field)无效", bundle: english,
        locale: Locale(identifier: "en"))
        == "Invalid server address in subscription server record 3")
    let singleCount = 1
    let multipleCount = 2
    let group = "My Group"
    #expect(
      String(
        localized: "已导入 \(singleCount) 台服务器到「\(group)」", bundle: english,
        locale: Locale(identifier: "en"))
        == "Imported 1 server into “My Group”")
    #expect(
      String(
        localized: "已导入 \(multipleCount) 台服务器到「\(group)」", bundle: english,
        locale: Locale(identifier: "en"))
        == "Imported 2 servers into “My Group”")
    let socks = "1080"
    let http = "8080"
    #expect(
      String(
        localized: "SOCKS \(socks)，HTTP 代理 \(http)", bundle: english,
        locale: Locale(identifier: "en"))
        == "SOCKS 1080, HTTP proxy 8080")
  }

  @Test func allCatalogEntriesHaveBundledTranslations() throws {
    let directory = TestSourceTree.ng2Root().appendingPathComponent("App/Resources")
    let catalogs = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil
    ).filter { $0.pathExtension == "xcstrings" }
    #expect(!catalogs.isEmpty)
    for language in ["en", "zh-Hans"] {
      let resources = AppArtifact.bundle.bundleURL.appendingPathComponent("Contents/Resources")
      let bundle = try #require(Bundle(url: resources.appendingPathComponent("\(language).lproj")))
      for catalog in catalogs {
        let document = try JSONSerialization.jsonObject(with: Data(contentsOf: catalog))
        let object = try #require(document as? [String: Any])
        let sourceLanguage = try #require(object["sourceLanguage"] as? String)
        let entries = try #require(object["strings"] as? [String: [String: Any]])
        for (key, entry) in entries {
          let localizations = try #require(entry["localizations"] as? [String: Any])
          #expect(
            language == sourceLanguage || localizations[language] != nil,
            "\(catalog.lastPathComponent): \(key), \(language)")
          let translated = bundle.localizedString(
            forKey: key, value: "__missing_translation__",
            table: catalog.deletingPathExtension().lastPathComponent)
          #expect(translated != "__missing_translation__", "\(key), \(language)")
          #expect(!translated.isEmpty, "\(key), \(language)")
          if language == "en" {
            #expect(
              translated.range(of: "\\p{Han}", options: .regularExpression) == nil,
              "Untranslated English: \(key)")
          }
        }
      }
    }
  }

  @Test func credentialFailurePreservesExternalDetail() {
    let detail = "OSStatus -25293: external detail 保留原文"
    let message = AppPresentation.message(
      for: ProxyListeningStoreError.credentialFailure(detail: detail))
    #expect(message.hasSuffix(detail))
    #expect(message != detail)
  }
}
