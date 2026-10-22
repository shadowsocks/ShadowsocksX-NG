import SwiftUI

struct LanguageSettingsRow: View {
  @StateObject private var preferences = AppLanguagePreferences()

  var body: some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 2) {
        Text("语言")
        Text("下次启动生效")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 16)
      Picker(
        "语言",
        selection: Binding(
          get: { preferences.selection },
          set: { preferences.select($0) }),
        content: {
          ForEach(AppLanguage.allCases, id: \.self) { language in
            Text(verbatim: language.menuTitle()).tag(language)
          }
        },
        currentValueLabel: {
          Text(verbatim: preferences.selection.currentValueTitle())
        }
      )
      .pickerStyle(.menu)
      .labelsHidden()
      .fixedSize()
      .accessibilityIdentifier("appLanguagePicker")
    }
    .padding(.vertical, 4)
  }
}
