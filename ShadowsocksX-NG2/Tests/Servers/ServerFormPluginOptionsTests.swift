import Foundation
import Testing

@testable import ShadowsocksX_NG2

/// 插件参数无损编辑会话：全部经表单草稿模块公开面观察
/// （装载、行编辑、模式切换、拼装串、校验与变更检测），不为内部扫描器
/// 单独建立测试边界。
@MainActor
struct ServerFormPluginOptionsTests {
  private static let certRaw = String(repeating: "A", count: 5_000)

  private static func editForm(pluginOptions: String) -> ServerEditForm {
    ServerEditForm(
      address: "203.0.113.7",
      port: 8388,
      encryptionMethod: "aes-256-gcm",
      password: "password",
      remark: "服务器",
      plugin: PluginSectionState(
        selection: .named(program: "v2ray-plugin"),
        programs: [.init(program: "v2ray-plugin", source: .managed, availability: .available)],
        mappingsUnreadable: false,
        optionsPresent: !pluginOptions.isEmpty,
        options: pluginOptions),
      isEditable: true)
  }

  private static func loadedFields(_ options: String) -> ServerFormFields {
    let fields = ServerFormFields()
    fields.load(from: editForm(pluginOptions: options))
    return fields
  }

  private static func formalRows(_ fields: ServerFormFields) -> [PluginOptionsDraft.Row] {
    fields.pluginOptions.rows.filter { !$0.isBlank }
  }

  // MARK: - 无编辑往返逐字保留

  @Test(
    arguments: [
      "", "tls", "key=",
      "mode=websocket;host=example.com;path=/ws",
      "k=1;k=2",
      "path=/a\\;b",
      "k=a\\=b",
      "k=a\\\\b",
      "a=1;",
      " host = x ",
      "未知参数=yes",
      "港=值",
      "certRaw=" + String(repeating: "A", count: 5_000),
    ])
  func noEditSessionsReturnTheOriginalStringVerbatim(_ original: String) {
    let fields = Self.loadedFields(original)
    #expect(fields.pluginOptions.mode == .table, "可解析内容默认进入参数列表")
    #expect(fields.pluginOptions.composedString == original)
    #expect(!fields.hasChanges, "仅查看不改写参数")
    #expect(fields.validateForSubmit())
    #expect(fields.draft?.pluginOptions == original)
  }

  @Test
  func modeSwitchingAloneReturnsTheOriginalAndDoesNotMarkChanges() {
    let fields = Self.loadedFields("a=1;")
    #expect(fields.pluginOptions.switchToRawText())
    #expect(fields.pluginOptions.mode == .rawText)
    #expect(fields.pluginOptions.rawText == "a=1;")
    #expect(!fields.hasChanges, "切换模式不触发表单变更")
    #expect(fields.pluginOptions.switchToTable())
    #expect(fields.pluginOptions.mode == .table)
    #expect(fields.pluginOptions.composedString == "a=1;")
    #expect(!fields.hasChanges)
  }

  @Test(arguments: ["a=1;;b=2", "=x", "a=1\\", ";a=1"])
  func unparseableOptionsDefaultToRawModeAndStillSubmit(_ original: String) {
    let fields = Self.loadedFields(original)
    #expect(fields.pluginOptions.mode == .rawText, "不可可靠解析时默认原始文本")
    #expect(fields.pluginOptions.composedString == original)
    #expect(!fields.hasChanges)
    #expect(fields.validateForSubmit(), "解析失败不是提交的新增阻塞原因")
    #expect(fields.draft?.pluginOptions == original)
  }

  // MARK: - 行编辑的局部保留

  @Test
  func editingOneRowEncodesOnlyThatRow() throws {
    let fields = Self.loadedFields("tls;host=a;path=/p")
    let rows = Self.formalRows(fields)
    let host = try #require(rows.first { $0.keyText == "host" })

    // 只改值：该行重新转义编码，其他行原文照抄。
    fields.pluginOptions.updateValue("b;c", of: host.id)
    #expect(fields.pluginOptions.composedString == "tls;host=b\\;c;path=/p")

    // 只改参数名。
    fields.pluginOptions.updateKey("topic", of: host.id)
    #expect(fields.pluginOptions.composedString == "tls;topic=b\\;c;path=/p")

    // 编辑后改回原值：该行回到原文写法。
    fields.pluginOptions.updateKey("host", of: host.id)
    fields.pluginOptions.updateValue("a", of: host.id)
    #expect(fields.pluginOptions.composedString == "tls;host=a;path=/p")
  }

  @Test
  func addingARowAppendsWithMinimalSeparatorAdjustment() {
    let fields = Self.loadedFields("a=1")
    // 在空行开始输入后行身份保持（焦点稳定），新的空行补到末尾。
    let added = fields.pluginOptions.quickAddRowID
    fields.pluginOptions.updateKey("b", of: added)
    fields.pluginOptions.updateValue("2", of: added)
    #expect(fields.pluginOptions.rows.count == 3)
    #expect(fields.pluginOptions.composedString == "a=1;b=2")
  }

  @Test
  func trailingSeparatorSurvivesContentEditsAndDropsOnlyOnStructuralChange() {
    let fields = Self.loadedFields("a=1;")
    let row = Self.formalRows(fields)[0]
    fields.pluginOptions.updateValue("2", of: row.id)
    #expect(fields.pluginOptions.composedString == "a=2;", "内容修改保留既有末尾分号")
    fields.pluginOptions.deleteRow(row.id)
    #expect(fields.pluginOptions.composedString == "", "删除行后不再保留悬空分隔符")
  }

  @Test
  func deletingARowKeepsOtherRowsVerbatim() throws {
    let fields = Self.loadedFields("tls;host=a;path=/p")
    let host = try #require(Self.formalRows(fields).first { $0.keyText == "host" })
    fields.pluginOptions.deleteRow(host.id)
    #expect(fields.pluginOptions.composedString == "tls;path=/p")
  }

  // MARK: - 无值开关与空字符串值

  @Test
  func flagAndEmptyValueAreDistinctAndReversible() {
    let fields = Self.loadedFields("tls")
    let row = Self.formalRows(fields)[0]
    #expect(row.kind == .flag)

    // 无值开关 → 键值：没有会话值草稿则序列化为 key=，不得自动相互推断。
    fields.pluginOptions.setKind(.keyValue, of: row.id)
    #expect(fields.pluginOptions.composedString == "tls=")
    fields.pluginOptions.setKind(.flag, of: row.id)
    #expect(fields.pluginOptions.composedString == "tls")

    // 键值 → 开关 → 键值：恢复本会话保留的值草稿。
    let other = Self.loadedFields("host=a")
    let hostRow = Self.formalRows(other)[0]
    other.pluginOptions.setKind(.flag, of: hostRow.id)
    #expect(other.pluginOptions.composedString == "host")
    other.pluginOptions.setKind(.keyValue, of: hostRow.id)
    #expect(other.pluginOptions.composedString == "host=a")
  }

  // MARK: - 行顺序调整

  @Test
  func movingARowReordersVerbatimSlicesOnly() throws {
    let fields = Self.loadedFields("tls;host=a;path=/p")
    let host = try #require(Self.formalRows(fields).first { $0.keyText == "host" })
    fields.pluginOptions.moveRow(host.id, by: 1)
    #expect(fields.pluginOptions.composedString == "tls;path=/p;host=a")
    #expect(fields.hasChanges, "重排改变拼装串顺序")
  }

  @Test
  func editedRowCarriesItsEncodingWhenMoved() throws {
    let fields = Self.loadedFields("tls;host=a;path=/p")
    let path = try #require(Self.formalRows(fields).first { $0.keyText == "path" })
    fields.pluginOptions.updateValue("x;y", of: path.id)
    fields.pluginOptions.moveRow(path.id, by: -1)
    #expect(fields.pluginOptions.composedString == "tls;path=x\\;y;host=a")
  }

  @Test
  func trailingSeparatorSurvivesRowMoves() throws {
    let fields = Self.loadedFields("a=1;b=2;")
    let first = try #require(Self.formalRows(fields).first)
    fields.pluginOptions.moveRow(first.id, by: 1)
    #expect(fields.pluginOptions.composedString == "b=2;a=1;", "移动不算结构修改，末尾分号保留")
  }

  @Test
  func movesAreBoundedByFormalRowsAndTheQuickAddRowStaysLast() throws {
    let fields = Self.loadedFields("a=1;b=2")
    let rows = Self.formalRows(fields)
    let firstRow = try #require(rows.first { $0.keyText == "a" })
    let secondRow = try #require(rows.first { $0.keyText == "b" })
    let blank = fields.pluginOptions.quickAddRowID

    // 空行不可移动；末尾正式行不可再下移（不得越过空行）。
    fields.pluginOptions.moveRow(blank, by: -1)
    fields.pluginOptions.moveRow(secondRow.id, by: 1)
    #expect(fields.pluginOptions.composedString == "a=1;b=2")
    #expect(fields.pluginOptions.rows.last?.id == blank)

    // 首行不可上移。
    fields.pluginOptions.moveRow(firstRow.id, by: -1)
    #expect(fields.pluginOptions.composedString == "a=1;b=2")

    // 有效下移仍可用。
    fields.pluginOptions.moveRow(firstRow.id, by: 1)
    #expect(fields.pluginOptions.composedString == "b=2;a=1")
    #expect(fields.pluginOptions.rows.last?.id == blank)
  }

  // MARK: - 底部空行与未完成草稿

  @Test
  func blankQuickAddRowIsPromotedOnInputAndNeverSerialized() {
    let fields = Self.loadedFields("a=1")
    #expect(fields.pluginOptions.rows.count == 2, "一条正式行 + 底部空行")
    #expect(fields.pluginOptions.composedString == "a=1")

    // 只输入参数名：提升为正式行并补上新的空行。
    fields.pluginOptions.updateKey("b", of: fields.pluginOptions.quickAddRowID)
    #expect(fields.pluginOptions.rows.count == 3)
    #expect(fields.pluginOptions.composedString == "a=1;b=")

    // 清回完全空白：回到占位状态，不进入参数串。
    fields.pluginOptions.updateKey("", of: fields.pluginOptions.rows[1].id)
    #expect(fields.pluginOptions.composedString == "a=1")
  }

  @Test
  func unfinishedRowsBlockAssemblySaveAndModeSwitch() throws {
    let fields = Self.loadedFields("a=1")
    fields.pluginOptions.updateValue("x", of: fields.pluginOptions.quickAddRowID)
    #expect(fields.pluginOptions.hasUnfinishedRows)
    #expect(fields.pluginOptions.composedString == nil)
    #expect(fields.draft == nil)
    #expect(fields.hasChanges, "未完成输入仍是变更，保存入口不得死锁")
    #expect(!fields.validateForSubmit())
    #expect(fields.fieldErrors[.pluginOptions] == .unfinishedPluginOptionRow)
    #expect(!fields.pluginOptions.switchToRawText(), "未完成行阻止切换到原始文本")
    #expect(fields.pluginOptions.mode == .table)

    // 重新编辑该行即清除字段错误。
    let unfinished = try #require(fields.pluginOptions.rows.first { $0.isUnfinished })
    fields.pluginOptions.updateKey("b", of: unfinished.id)
    #expect(fields.fieldErrors[.pluginOptions] == nil)
    #expect(fields.pluginOptions.composedString == "a=1;b=x")
    #expect(fields.pluginOptions.switchToRawText())
  }

  @Test
  func clearedKeyWithKeptValueIsUnfinishedAndNotAutoDeleted() {
    let fields = Self.loadedFields("a=1")
    let row = Self.formalRows(fields)[0]
    fields.pluginOptions.updateKey("", of: row.id)
    #expect(fields.pluginOptions.rows.contains { $0.id == row.id }, "清空参数名不得自动删除行")
    #expect(fields.pluginOptions.hasUnfinishedRows)
    fields.pluginOptions.deleteRow(row.id)
    #expect(fields.pluginOptions.composedString == "")
  }

  // MARK: - 原始文本编辑

  @Test
  func rawTextEditsReparseOnSwitchBackOrStayRawOnFailure() {
    let fields = Self.loadedFields("a=1")
    #expect(fields.pluginOptions.switchToRawText())
    fields.pluginOptions.rawText = "x=1;y"
    #expect(fields.pluginOptions.switchToTable())
    #expect(fields.pluginOptions.composedString == "x=1;y")

    // 解析不可靠：留在原始模式并保留原文，不丢弃草稿。
    fields.pluginOptions.switchToRawText()
    fields.pluginOptions.rawText = "bad;;"
    #expect(!fields.pluginOptions.switchToTable())
    #expect(fields.pluginOptions.mode == .rawText)
    #expect(fields.pluginOptions.rawText == "bad;;")
    #expect(fields.pluginOptions.composedString == "bad;;")
  }

  // MARK: - 装载/重置与提交边界

  @Test
  func reloadRestoresRowsModeAndRawStateTogether() {
    let fields = Self.loadedFields("a=1")
    fields.pluginOptions.updateKey("b", of: fields.pluginOptions.quickAddRowID)
    fields.pluginOptions.switchToRawText()
    #expect(fields.hasChanges)

    fields.load(from: Self.editForm(pluginOptions: "a=1"))
    #expect(fields.pluginOptions.mode == .table)
    #expect(fields.pluginOptions.composedString == "a=1")
    #expect(!fields.hasChanges)
    #expect(fields.fieldErrors.isEmpty)

    fields.load(from: Self.editForm(pluginOptions: "bad;;"))
    #expect(fields.pluginOptions.mode == .rawText)
    #expect(fields.pluginOptions.composedString == "bad;;")
  }

  @Test
  func composedStringFeedsTheByteLimitAtTheFormBoundary() {
    let fields = Self.loadedFields("a=1")
    #expect(fields.pluginOptions.switchToRawText())
    // 14 × 5,000 字符 + 前缀 > 65,536 字节上限。
    fields.pluginOptions.rawText = "certRaw=" + String(repeating: Self.certRaw, count: 14)
    #expect(!fields.validateForSubmit())
    #expect(
      fields.fieldErrors[.pluginOptions]
        == .tooManyBytes(limit: ServerFormFields.pluginOptionsUTF8Limit))
    #expect(fields.hasChanges)
  }

  @Test
  func hiddenPluginSelectionDoesNotBlockOnOptionsDraft() {
    let fields = Self.loadedFields("a=1")
    fields.pluginChoice = .none
    fields.pluginOptions.updateValue("x", of: fields.pluginOptions.quickAddRowID)
    #expect(fields.validateForSubmit(), "插件「无」时隐藏参数草稿不阻塞保存")
  }
}

extension ServerFormPluginOptionsTests {
  // 移动可行性与执行共用草稿 interface。
  @Test(arguments: [false, true])
  func movementEligibilityMatchesActionsAndTracksReordering(rawMode: Bool) throws {
    let fields = Self.loadedFields("a=1;b=2;")
    let draft = fields.pluginOptions
    let rows = Self.formalRows(fields)
    let first = try #require(rows.first)
    let last = try #require(rows.last)
    let blank = draft.quickAddRowID
    let unknown = UUID()
    if rawMode { #expect(draft.switchToRawText()) }

    let denied = [
      (first.id, -1), (last.id, 1), (blank, -1), (blank, 1),
      (unknown, -1), (unknown, 1), (first.id, 0), (first.id, 2),
      (first.id, Int.min), (first.id, Int.max),
    ]
    for (id, offset) in denied {
      #expect(!draft.canMoveRow(id, by: offset))
      draft.moveRow(id, by: offset)
      #expect(draft.rows.map(\.id) == rows.map(\.id) + [blank])
      #expect(draft.composedString == "a=1;b=2;")
      #expect(!fields.hasChanges)
    }

    #expect(draft.canMoveRow(first.id, by: 1) == !rawMode)
    #expect(draft.canMoveRow(last.id, by: -1) == !rawMode)
    draft.moveRow(first.id, by: 1)
    if rawMode {
      #expect(draft.composedString == "a=1;b=2;")
      #expect(!fields.hasChanges)
    } else {
      #expect(draft.rows.map(\.id) == [last.id, first.id, blank])
      #expect(draft.composedString == "b=2;a=1;")
      #expect(fields.hasChanges)
      #expect(!draft.canMoveRow(first.id, by: 1))
      #expect(!draft.canMoveRow(last.id, by: -1))
      #expect(draft.canMoveRow(first.id, by: -1))
      draft.moveRow(first.id, by: -1)
      #expect(draft.composedString == "a=1;b=2;")
      #expect(!fields.hasChanges)
    }
  }
}
