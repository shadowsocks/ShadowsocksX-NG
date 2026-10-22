extension PluginSectionState {
  /// 详情和编辑表单共用可用性解释；未知引用的操作建议由各视图呈现。
  func availabilityWarning(for program: String) -> String? {
    if mappingsUnreadable {
      return String(localized: "无法读取用户插件映射，插件暂不可用。请修复映射后重试。")
    }
    guard let facts = programs.first(where: { $0.program == program }) else { return nil }
    switch facts.availability {
    case .available: return nil
    case .missing: return String(localized: "插件文件不存在，请检查用户插件路径或应用安装。")
    case .notExecutable: return String(localized: "插件文件不可执行，请检查文件类型和执行权限。")
    case .unreadable: return String(localized: "无法读取插件文件信息，请检查路径和访问权限。")
    }
  }
}
