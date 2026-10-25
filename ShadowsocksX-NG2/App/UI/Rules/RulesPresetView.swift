import SwiftUI

struct RulesPresetView: View {
  @ObservedObject var workspaces: RulesWorkspaces

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Picker("规则预设", selection: $workspaces.selectedPreset) {
        ForEach(RulePreset.allCases, id: \.self) { preset in
          Text(preset.label).tag(preset)
        }
      }
      .pickerStyle(.segmented)
      .padding(.top)
      .padding(.horizontal)
      RulesView(workflow: workspaces.current).id(workspaces.selectedPreset)
    }
  }
}
