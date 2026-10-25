import Combine
import SwiftUI

/// 表单字段标识：字段级校验错误的挂靠位与首错定位序（表单栅格顺序）。
enum ServerFormField: Hashable {
  case name
  case address
  case port
  case password
  case pluginOptions

  static let focusOrder: [ServerFormField] = [.name, .address, .port, .password, .pluginOptions]
}

/// 字段级校验错误：只携带字段、原因与上限，不回显字段内容；
/// 文案归呈现层（`ServerFormFieldsGrid`）。
enum ServerFormFieldError: Equatable {
  /// 名称必填（原有规则并入统一校验入口）。
  case missingName
  /// 用户可见字符（Swift `Character`）超上限。
  case tooManyCharacters(limit: Int)
  /// UTF-8 字节超上限（插件参数按最终字符串的字节数计量）。
  case tooManyBytes(limit: Int)
  /// 端口草稿为空、含非十进制数字、超过五位或落在 1–65535 之外。
  case invalidPort
  /// 参数列表存在未完成行（有值或开关形态却没有参数名）。
  case unfinishedPluginOptionRow
}

/// 服务器表单草稿（UI 持有）：连接字段草稿状态与「字段 ↔ ServerEditForm/
/// ServerEditDraft 命令」的映射只在此写一次；新建与编辑两个表单面各自
/// `@StateObject` 持有一份，经 `load(from:)` 装载、`draft` 提交，第三个表单
/// 面接入只需学这一对方法。栅格渲染见 `ServerFormFieldsGrid`；编辑资格
/// 与插件区 facts 由 caller 注入。
@MainActor
final class ServerFormFields: ObservableObject {
  /// 手动表单的产品输入上限：不宣称是 DNS、Shadowsocks 或
  /// SIP003 协议的最大长度；导入、订阅刷新与既有保存数据不执行这些上限。
  static let nameCharacterLimit = 128
  static let addressCharacterLimit = 255
  static let portDigitLimit = 5
  static let passwordCharacterLimit = 1_024
  static let pluginOptionsUTF8Limit = 65_536

  @Published var address = "" { didSet { clearError(.address) } }
  /// 端口十进制编辑草稿：提交前经 `validateForSubmit` 验证，不用数值绑定
  /// 以免转换失败时悄悄提交旧绑定值。
  @Published var portText = "" { didSet { clearError(.port) } }
  @Published var encryptionMethod = ""
  @Published var password = "" { didSet { clearError(.password) } }
  @Published var remark = "" {
    didSet {
      if !nameIsEmpty { clearError(.name) }
    }
  }
  @Published var pluginChoice: PluginSelection = .none
  /// 插件参数会话草稿：行/模式/原文收在模块内，提交串取
  /// `composedString`；编辑参数即清除参数字段错误，变更通知转发给本类
  /// 观察者（视图只观察 ServerFormFields）。
  let pluginOptions = PluginOptionsDraft()
  private var pluginOptionsChanges: AnyCancellable?
  @Published var showPassword = false
  @Published private(set) var fieldErrors: [ServerFormField: ServerFormFieldError] = [:]
  @Published private var savedDraft: ServerEditDraft?

  @Published private(set) var serverID: NodeID?
  @Published private(set) var presentation: ServerFormPresentation?
  @Published private(set) var loadFailure: ServerFormLoadError?
  @Published private(set) var hasLoadedServer = false

  var canSaveServer: Bool {
    hasLoadedServer && loadFailure == nil && presentation?.isEditable == true
  }

  init() {
    pluginOptionsChanges = pluginOptions.objectWillChange.sink { [weak self] _ in
      guard let self else { return }
      self.clearError(.pluginOptions)
      self.objectWillChange.send()
    }
  }

  /// 变更检测按提交草稿比较；端口在草稿可解析时按数值比较（如前导零改写
  /// 不算变更），不可解析视为已变更，保证非法输入后保存入口仍可点击并在
  /// 提交时得到行内错误，而不是按钮死锁。
  var hasChanges: Bool {
    draft != savedDraft
  }

  private var nameIsEmpty: Bool {
    remark.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// 提交前的全量校验：名称必填与五字段输入上限；与装载基线
  /// 逐字相同的超限字段放行（未修改的历史超长值不阻塞其他变更保存）。
  /// 错误逐字段发布，重新编辑对应字段即清除；首次装载不显示。
  @discardableResult
  func validateForSubmit() -> Bool {
    var errors: [ServerFormField: ServerFormFieldError] = [:]
    if nameIsEmpty {
      errors[.name] = .missingName
    } else {
      errors[.name] = characterLimitError(
        raw: remark, measured: remark.trimmingCharacters(in: .whitespacesAndNewlines),
        baseline: savedDraft?.remark, limit: Self.nameCharacterLimit)
    }
    errors[.address] = characterLimitError(
      raw: address, measured: address.trimmingCharacters(in: .whitespaces),
      baseline: savedDraft?.address, limit: Self.addressCharacterLimit)
    if submittablePort == nil {
      errors[.port] = .invalidPort
    }
    errors[.password] = characterLimitError(
      raw: password, measured: password,
      baseline: savedDraft?.password, limit: Self.passwordCharacterLimit)
    if pluginChoice != .none {
      if pluginOptions.hasUnfinishedRows {
        errors[.pluginOptions] = .unfinishedPluginOptionRow
      } else if let options = pluginOptions.composedString {
        errors[.pluginOptions] = utf8LimitError(
          raw: options, baseline: savedDraft?.pluginOptions,
          limit: Self.pluginOptionsUTF8Limit)
      }
    }
    fieldErrors = errors
    return errors.isEmpty
  }

  /// 首个待修正字段（首错定位用）；无错误时为 nil。
  var firstErrorField: ServerFormField? {
    ServerFormField.focusOrder.first { fieldErrors[$0] != nil }
  }

  /// 新建表单的默认字段：端口 8388、加密 aes-256-gcm、插件「无」。
  static func newForm() -> ServerFormFields {
    let fields = ServerFormFields()
    fields.portText = "8388"
    fields.encryptionMethod = "aes-256-gcm"
    fields.savedDraft = fields.draft
    return fields
  }

  /// 当前 sslocal 能力目录；目录中既有的未知方法原样追加显示，便于用户修复。
  /// 新建面初值恒在集内，追加分支不会触发，与仅列集内值行为一致。
  var methodChoices: [String] {
    var choices = EncryptionMethodCatalog.supported.sorted()
    if !encryptionMethod.isEmpty && !choices.contains(encryptionMethod) {
      choices.append(encryptionMethod)
    }
    return choices
  }

  /// 从编辑面状态装载（凭据明文只在编辑命令中出现）；重置密码
  /// 明文显示。
  func load(from state: ServerEditForm) {
    address = state.address
    portText = String(state.port)
    encryptionMethod = state.encryptionMethod
    password = state.password
    remark = state.remark
    pluginChoice = state.plugin.selection
    pluginOptions.load(state.plugin.options)
    showPassword = false
    fieldErrors = [:]
    savedDraft = draft
  }

  /// 提交载荷：配置与凭据字段作为一个逻辑变更。端口取自十进制
  /// 草稿、插件参数取自会话草稿拼装串；任一不能作为提交值（无效端口或
  /// 未完成参数行）时为 nil——本 getter 仅在 `validateForSubmit` 通过后
  /// 消费，无效输入不得悄悄回落到旧值。
  var draft: ServerEditDraft? {
    guard let port = submittablePort, let options = pluginOptions.composedString else { return nil }
    return ServerEditDraft(
      address: address,
      port: port,
      encryptionMethod: encryptionMethod,
      password: password,
      remark: remark,
      plugin: pluginChoice,
      pluginOptions: options)
  }

  // MARK: - Explicit server loading

  /// Reappearing with the same selection preserves the loaded draft, including failures.
  func showServer(_ id: NodeID, load: (NodeID) throws -> ServerEditForm?) {
    guard serverID != id else { return }
    serverID = id
    clearLoadedServer()
    reloadServer(load: load)
  }

  func updatePresentation(
    _ facts: ServerFormPresentation?,
    preservingDraft: Bool = false,
    load: ((NodeID) throws -> ServerEditForm?)? = nil
  ) {
    if preservingDraft {
      updatePresentationFacts(facts)
      return
    }
    updatePluginSelection(from: facts, load: load)
    updatePresentationFacts(facts)
  }

  private func updatePresentationFacts(_ facts: ServerFormPresentation?) {
    if presentation != facts { presentation = facts }
  }

  private func updatePluginSelection(
    from facts: ServerFormPresentation?, load: ((NodeID) throws -> ServerEditForm?)?
  ) {
    guard let selection = facts?.plugin.selection,
      presentation?.plugin.selection != selection,
      pluginProgram(pluginChoice) != nil,
      pluginProgram(pluginChoice) == pluginProgram(selection),
      savedDraft?.plugin == pluginChoice
    else { return }
    refreshUnknownPluginOptions(for: selection, load: load)
    pluginChoice = selection
    savedDraft?.plugin = selection
  }

  private func refreshUnknownPluginOptions(
    for selection: PluginSelection, load: ((NodeID) throws -> ServerEditForm?)?
  ) {
    guard case .unknown = pluginChoice, case .named = selection,
      let serverID, let load,
      pluginOptions.composedString == savedDraft?.pluginOptions
    else { return }
    do {
      if let form = try load(serverID) {
        pluginOptions.load(form.plugin.options)
        savedDraft?.pluginOptions = pluginOptions.composedString
      }
    } catch {
      loadFailure = .credentialsUnavailable
    }
  }

  private func pluginProgram(_ selection: PluginSelection) -> String? {
    switch selection {
    case .named(let program), .unknown(let program): return program
    case .none: return nil
    }
  }

  /// Only a manual reset failure may retain a successfully loaded draft.
  func reloadServer(load: (NodeID) throws -> ServerEditForm?) {
    guard let serverID else { return }
    let preserveDraft = hasLoadedServer && presentation?.isEditable == true
    do {
      guard let form = try load(serverID) else { throw ServerFormLoadError.notFound }
      self.load(from: form)
      presentation = ServerFormPresentation(isEditable: form.isEditable, plugin: form.plugin)
      hasLoadedServer = true
      loadFailure = nil
    } catch {
      if !preserveDraft { clearLoadedServer() }
      loadFailure = (error as? ServerFormLoadError) ?? .credentialsUnavailable
    }
  }

  /// A late save completion must not reset a different server's draft.
  func didSaveServer(_ id: NodeID, load: (NodeID) throws -> ServerEditForm?) {
    guard serverID == id else { return }
    reloadServer(load: load)
  }

  /// Only successful refreshes of the displayed read-only server trigger a reload.
  func subscriptionDidRefresh(
    affectedServers: Set<NodeID>, load: (NodeID) throws -> ServerEditForm?
  ) {
    guard let serverID, affectedServers.contains(serverID),
      presentation?.isEditable == false
    else { return }
    reloadServer(load: load)
  }

  private func clearLoadedServer() {
    address = ""
    portText = ""
    encryptionMethod = ""
    password = ""
    remark = ""
    pluginChoice = .none
    pluginOptions.load("")
    showPassword = false
    fieldErrors = [:]
    savedDraft = nil
    presentation = nil
    hasLoadedServer = false
    loadFailure = nil
  }

  // MARK: - 校验实现

  /// 端口草稿可否作为提交端口：非空、纯 ASCII 十进制数字、不超过五位且
  /// 落在 1–65535。
  private var submittablePort: Int? {
    guard !portText.isEmpty, portText.count <= Self.portDigitLimit,
      portText.allSatisfy({ ("0"..."9").contains($0) }),
      let port = Int(portText)
    else { return nil }
    return (1...65_535).contains(port) ? port : nil
  }

  /// 字符上限：与基线逐字相同（未修改）的历史超长值放行；名称与地址按
  /// 提交值（现行首尾空白处理后）计量，密码不 trim、不 Unicode 归一化。
  private func characterLimitError(
    raw: String, measured: String, baseline: String?, limit: Int
  ) -> ServerFormFieldError? {
    guard baseline == nil || raw != baseline else { return nil }
    return measured.count > limit ? .tooManyCharacters(limit: limit) : nil
  }

  /// 插件参数字节上限：按最终参数字符串的 UTF-8 字节数计量（含分隔符与
  /// 转义），与基线逐字相同的未修改值放行。
  private func utf8LimitError(
    raw: String, baseline: String?, limit: Int
  ) -> ServerFormFieldError? {
    guard baseline == nil || raw != baseline else { return nil }
    return raw.utf8.count > limit ? .tooManyBytes(limit: limit) : nil
  }

  private func clearError(_ field: ServerFormField) {
    guard fieldErrors[field] != nil else { return }
    fieldErrors[field] = nil
  }
}

/// 新建与编辑共享的名称优先表单；焦点由提交入口持有，校验失败时定位首个
/// 待修正字段。
