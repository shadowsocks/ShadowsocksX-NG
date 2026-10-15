import Foundation

enum AppLanguage: String, CaseIterable {
  case automatic
  case simplifiedChinese = "zh-Hans"
  case english = "en"

  func currentValueTitle(in bundle: Bundle = .main) -> String {
    self == .automatic ? localizedName(in: bundle) : nativeName
  }

  func menuTitle(in bundle: Bundle = .main) -> String {
    "\(nativeName) · \(localizedName(in: bundle))"
  }

  private var nativeName: String {
    switch self {
    case .automatic: "Auto Detect"
    case .simplifiedChinese: "简体中文"
    case .english: "English"
    }
  }

  private func localizedName(in bundle: Bundle) -> String {
    switch self {
    case .automatic: String(localized: "自动检测", bundle: bundle)
    case .simplifiedChinese: String(localized: "简体中文", bundle: bundle)
    case .english: String(localized: "英文", bundle: bundle)
    }
  }
}
