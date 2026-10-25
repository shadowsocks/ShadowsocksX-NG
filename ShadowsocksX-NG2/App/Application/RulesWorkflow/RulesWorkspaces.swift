import Combine
import Foundation

/// Each preset owns an unchanged workflow, including its in-flight operations.
@MainActor
final class RulesWorkspaces: ObservableObject {
  @Published var selectedPreset: RulePreset = .gfwlist
  @Published private(set) var reportSource: RulesSourceSnapshot?
  private let workflows: [RulePreset: RulesWorkflow]
  private var reports: Set<AnyCancellable> = []

  init(makeWorkflow: (RulePreset) -> RulesWorkflow) {
    workflows = Dictionary(uniqueKeysWithValues: RulePreset.allCases.map { ($0, makeWorkflow($0)) })
    for workflow in workflows.values {
      workflow.$reportSource.compactMap { $0 }.sink { [weak self] in
        self?.reportSource = $0
      }.store(in: &reports)
    }
  }

  var current: RulesWorkflow { workflows[selectedPreset]! }
}
