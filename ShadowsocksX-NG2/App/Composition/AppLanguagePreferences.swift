import Combine
import Foundation

/// 应用语言覆盖使用 macOS 的应用级 AppleLanguages 偏好；不写全局偏好。
/// Bundle 在进程内缓存语言选择，因此保存后由下次启动统一应用。
@MainActor
final class AppLanguagePreferences: ObservableObject {
  @Published private(set) var selection: AppLanguage

  private let defaults: UserDefaults

  init(
    defaults: UserDefaults = .standard,
    applicationID: String = "com.qiuyuzhou.ShadowsocksX-NG2"
  ) {
    self.defaults = defaults
    let languages =
      defaults.persistentDomain(forName: applicationID)?["AppleLanguages"] as? [String]
    selection = languages?.first.flatMap(AppLanguage.init(rawValue:)) ?? .automatic
  }

  func select(_ language: AppLanguage) {
    if language == .automatic {
      defaults.removeObject(forKey: "AppleLanguages")
    } else {
      defaults.set([language.rawValue], forKey: "AppleLanguages")
    }
    selection = language
  }
}
