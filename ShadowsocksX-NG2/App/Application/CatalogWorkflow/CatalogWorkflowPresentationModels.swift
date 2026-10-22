import Foundation

/// Non-secret facts for rendering; options is always empty in this projection.
struct ServerFormPresentation: Equatable {
  let isEditable: Bool
  let plugin: PluginSectionState

  init(isEditable: Bool, plugin: PluginSectionState) {
    self.isEditable = isEditable
    var facts = plugin
    facts.options = ""
    self.plugin = facts
  }
}

/// 详情的已保存展示事实，参数明文通过独立读取 interface 装载。
struct ServerDetailPresentation {
  let name: String
  let address: String
  let port: Int
  let encryptionMethod: String
  let plugin: PluginSectionState
}
