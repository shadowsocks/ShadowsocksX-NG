import Foundation

/// 诊断事实缝：目录只向诊断提供 domain-neutral 的
/// 聚合事实（数量与已知无效数）。诊断报告模型（DiagnosticSnapshot）不经
/// 本类型，原始目录与凭据不出 module。
extension CatalogWorkflow {
  /// 当前目录的聚合诊断事实（服务器/分组/来源/插件计数与已知无效数）。
  var diagnosticCatalogFacts: DiagnosticCatalogFacts {
    DiagnosticCatalogFacts(
      counts: DiagnosticReportBuilder.counts(in: dependencies.coordinator.committedCatalog),
      knownInvalidServerCount: tree.invalidServerCount)
  }
}
