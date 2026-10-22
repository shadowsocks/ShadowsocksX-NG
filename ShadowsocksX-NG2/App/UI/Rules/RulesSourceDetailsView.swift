import SwiftUI

struct RulesSourceSummaryView: View {
  let source: RulesSourceSnapshot
  let openReport: () -> Void

  var body: some View {
    if let metadata = source.metadata {
      VStack(alignment: .leading, spacing: 6) {
        Text(verbatim: String(metadata.source.upstreamVersion.prefix(12)))
          .help(metadata.source.upstreamVersion)
        Text(verbatim: metadata.license)
        if source.conversionReport != nil {
          Button(RulesCopy.text("快照制作时的转换报告"), action: openReport)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .font(.caption)
      .frame(maxWidth: .infinity, alignment: .leading)
      .textSelection(.enabled)
    }
  }
}

struct RulesReportView: View {
  static let sceneID = "rules-conversion-report"
  @ObservedObject var workflow: RulesWorkflow

  var body: some View {
    ScrollView {
      if let source = workflow.reportSource, let metadata = source.metadata {
        VStack(alignment: .leading, spacing: 12) {
          Text(verbatim: "\(source.id.label) · \(metadata.source.upstreamVersion)")
          Text(verbatim: metadata.upstreamReference)
          Text(verbatim: "\(metadata.license) · \(metadata.attribution)")
          if let report = source.conversionReport {
            Divider()
            Text(verbatim: "\(RulesCopy.text("已转换")): \(report.convertedCount)")
            Text(verbatim: "\(RulesCopy.text("已吸收")): \(report.absorbedCount)")
            counts(report.skipped, label: RulesCopy.text("已跳过"))
            counts(report.rejected, label: RulesCopy.text("已拒绝"))
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .textSelection(.enabled)
      }
    }
    .navigationTitle(
      (workflow.reportSource?.id.label ?? "") + " · " + RulesCopy.text("快照制作时的转换报告")
    )
    .frame(minWidth: 480, minHeight: 320)
  }

  private func counts(_ values: [String: Int], label: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(verbatim: label)
      ForEach(values.keys.sorted(), id: \.self) { key in
        Text(verbatim: "\(key): \(values[key, default: 0])")
      }
      if values.isEmpty { Text(verbatim: "0") }
    }
  }
}
