import Testing

@testable import ShadowsocksX_NG2

/// 服务器表单的手动输入上限与端口十进制草稿：全部经表单草稿
/// 模块的公开面观察（装载、校验、提交草稿、变更检测），不触碰内部实现。
@MainActor
struct ServerFormFieldLimitsTests {
  private static let overLongName = String(
    repeating: "港", count: ServerFormFields.nameCharacterLimit + 1)
  private static let overLongAddress = String(
    repeating: "a", count: ServerFormFields.addressCharacterLimit + 1)
  private static let overLongPassword = String(
    repeating: "p", count: ServerFormFields.passwordCharacterLimit + 1)
  private static let overLongOptions = String(
    repeating: "港", count: ServerFormFields.pluginOptionsUTF8Limit / 3 + 1)

  private static func editForm(
    name: String = "服务器",
    address: String = "203.0.113.7",
    port: Int = 8388,
    password: String = "password",
    pluginOptions: String = ""
  ) -> ServerEditForm {
    ServerEditForm(
      address: address,
      port: port,
      encryptionMethod: "aes-256-gcm",
      password: password,
      remark: name,
      plugin: PluginSectionState(
        selection: .named(program: "v2ray-plugin"),
        programs: [.init(program: "v2ray-plugin", source: .managed, availability: .available)],
        mappingsUnreadable: false,
        optionsPresent: !pluginOptions.isEmpty,
        options: pluginOptions),
      isEditable: true)
  }

  private static func loadedFields(_ form: ServerEditForm = editForm()) -> ServerFormFields {
    let fields = ServerFormFields()
    fields.load(from: form)
    return fields
  }

  // MARK: - 端口十进制草稿

  @Test(
    arguments: [
      ("", "空输入"), ("abc", "非数字"), ("12a4", "中途字母"), ("123456", "六位数字"),
      ("0", "零"), ("65536", "超范围"), ("-1", "负号"), (" 8388", "带空格"),
      ("８３８８", "全角数字"),
    ])
  func invalidPortDraftsBlockSubmissionAndNeverSubmitStaleValues(_ text: String, _ label: String) {
    let fields = Self.loadedFields()
    fields.portText = text
    #expect(!fields.validateForSubmit(), "\(label)")
    #expect(fields.fieldErrors[.port] == .invalidPort, "\(label)")
    #expect(fields.draft == nil, "无效端口不得回落到旧绑定值：\(label)")
    #expect(fields.hasChanges, "非法端口仍是变更，保存入口不得死锁：\(label)")
  }

  @Test(arguments: [("1", 1), ("65535", 65_535), ("8388", 8388), ("08388", 8388)])
  func validPortDraftsSubmitParsedValues(_ text: String, expected: Int) {
    let fields = Self.loadedFields()
    fields.portText = text
    #expect(fields.validateForSubmit())
    #expect(fields.draft?.port == expected)
  }

  @Test
  func numericallyEqualPortRewriteIsNotAChange() {
    let fields = Self.loadedFields()
    fields.portText = "08388"
    #expect(!fields.hasChanges)
    fields.portText = "8389"
    #expect(fields.hasChanges)
  }

  // MARK: - 字符上限（Swift Character 计量）

  @Test
  func nameLimitCountsCharactersIncludingComposedSequences() {
    let fields = Self.loadedFields()
    fields.remark = String(repeating: "港", count: ServerFormFields.nameCharacterLimit)
    #expect(fields.validateForSubmit())
    fields.remark = Self.overLongName
    #expect(!fields.validateForSubmit())
    #expect(
      fields.fieldErrors[.name] == .tooManyCharacters(limit: ServerFormFields.nameCharacterLimit))

    // 组合字符序列按用户可见字符计数：e + U+0301 是一个 Character。
    fields.remark = String(repeating: "e\u{301}", count: ServerFormFields.nameCharacterLimit)
    #expect(fields.validateForSubmit())
    fields.remark = String(repeating: "e\u{301}", count: ServerFormFields.nameCharacterLimit + 1)
    #expect(!fields.validateForSubmit())
  }

  @Test
  func nameAndAddressLimitsMeasurePreparedValuesAfterExistingTrimming() {
    let fields = Self.loadedFields()
    // 名称/地址沿用首尾空白处理后计量：首尾空白不计入上限。
    fields.remark = " " + String(repeating: "港", count: ServerFormFields.nameCharacterLimit) + " "
    #expect(fields.validateForSubmit())
    fields.address = " " + String(repeating: "a", count: ServerFormFields.addressCharacterLimit)
    #expect(fields.validateForSubmit())
    // 去掉空白后仍超一位才越界。
    fields.remark = " " + Self.overLongName
    #expect(!fields.validateForSubmit())
    fields.remark = "服务器"
    fields.address = Self.overLongAddress
    #expect(!fields.validateForSubmit())
    #expect(
      fields.fieldErrors[.address]
        == .tooManyCharacters(limit: ServerFormFields.addressCharacterLimit))
  }

  @Test
  func passwordLimitDoesNotTrimOrNormalize() {
    let fields = Self.loadedFields()
    fields.password = String(repeating: "p", count: ServerFormFields.passwordCharacterLimit)
    #expect(fields.validateForSubmit(), "恰好达标")
    // 密码不 trim、不归一化：尾随空格计入长度，1025 位即越界。
    fields.password = String(repeating: "p", count: ServerFormFields.passwordCharacterLimit) + " "
    #expect(!fields.validateForSubmit())
    fields.password = Self.overLongPassword
    #expect(!fields.validateForSubmit())
    #expect(
      fields.fieldErrors[.password]
        == .tooManyCharacters(limit: ServerFormFields.passwordCharacterLimit))
  }

  // MARK: - 插件参数字节上限（UTF-8 计量）

  @Test
  func pluginOptionsLimitCountsUTF8BytesOfTheWholeString() {
    let fields = Self.loadedFields()
    fields.pluginOptions.switchToRawText()
    fields.pluginOptions.rawText = String(
      repeating: "a", count: ServerFormFields.pluginOptionsUTF8Limit)
    #expect(fields.validateForSubmit(), "恰好 65,536 字节达标")
    fields.pluginOptions.rawText = String(
      repeating: "a", count: ServerFormFields.pluginOptionsUTF8Limit + 1)
    #expect(!fields.validateForSubmit())
    #expect(
      fields.fieldErrors[.pluginOptions]
        == .tooManyBytes(limit: ServerFormFields.pluginOptionsUTF8Limit))

    // 多字节字符按字节计：21846 个「港」= 65,538 字节越界。
    fields.pluginOptions.rawText = String(repeating: "港", count: 21_846)
    #expect(!fields.validateForSubmit())
  }

  @Test
  func hiddenOptionsDraftDoesNotBlockSaveWhenPluginIsNone() {
    let fields = Self.loadedFields()
    fields.pluginChoice = .none
    fields.pluginOptions.switchToRawText()
    fields.pluginOptions.rawText = Self.overLongOptions
    #expect(fields.validateForSubmit(), "插件「无」时隐藏参数草稿不阻塞保存")
  }

  // MARK: - 超长基线兼容

  @Test
  func unmodifiedOverLongBaselineFieldsDoNotBlockSavingOtherChanges() {
    let fields = Self.loadedFields(
      Self.editForm(
        name: Self.overLongName, address: Self.overLongAddress,
        password: Self.overLongPassword, pluginOptions: Self.overLongOptions))
    #expect(fields.validateForSubmit(), "未修改的历史超长字段放行")
    #expect(fields.draft != nil)

    // 只改名称（合规新值），其余超长基线字段继续放行。
    fields.remark = "新名称"
    #expect(fields.validateForSubmit())

    // 主动修改超限字段后必须满足上限。
    fields.address = Self.overLongAddress + "x"
    #expect(!fields.validateForSubmit())
    #expect(
      fields.fieldErrors[.address]
        == .tooManyCharacters(limit: ServerFormFields.addressCharacterLimit))
  }

  @Test
  func baselineExemptionUsesTheLoadedSnapshotNotLiveCatalogValues() {
    let fields = Self.loadedFields(Self.editForm(name: Self.overLongName))
    #expect(fields.validateForSubmit())
    // 再次成功装载后基线刷新。
    fields.remark = "正常名称"
    fields.load(from: Self.editForm(name: Self.overLongName))
    #expect(fields.validateForSubmit(), "重载后基线恢复为超长保存值，未修改即放行")
  }

  // MARK: - 错误呈现时机

  @Test
  func firstOpenShowsNoErrorsAndErrorsClearOnFieldEdit() {
    let fields = ServerFormFields.newForm()
    #expect(fields.fieldErrors.isEmpty, "首次打开不显示校验错误")
    #expect(!fields.validateForSubmit(), "新建面名称为空仍拒绝提交（原有必填规则）")
    #expect(fields.firstErrorField == .name)
    #expect(fields.fieldErrors[.name] == .missingName)

    fields.remark = "有名称"
    #expect(fields.fieldErrors[.name] == nil, "重新编辑对应字段即清除")

    fields.portText = "abc"
    #expect(!fields.validateForSubmit())
    fields.portText = "8388"
    #expect(fields.fieldErrors[.port] == nil)
  }

  @Test
  func firstErrorFieldFollowsGridOrder() {
    let fields = Self.loadedFields()
    fields.portText = "0"
    fields.remark = ""
    fields.password = Self.overLongPassword
    #expect(!fields.validateForSubmit())
    #expect(fields.firstErrorField == .name, "名称 → 地址 → 端口 → 密码 → 参数")
  }

  @Test
  func loadedEditFormShowsNoErrorsUntilValidated() {
    let fields = Self.loadedFields(Self.editForm(name: Self.overLongName))
    #expect(fields.fieldErrors.isEmpty)
    #expect(fields.validateForSubmit())
    #expect(fields.fieldErrors.isEmpty)
  }
}
