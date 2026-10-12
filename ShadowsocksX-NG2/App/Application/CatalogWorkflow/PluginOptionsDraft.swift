import Combine
import Foundation

/// 插件参数会话草稿（见 GLOSSARY.md「Plugin parameter draft」）：
/// 带稳定行身份的有序参数行 + 原始文本双模式。解析与拼装遵循受管
/// v2ray-plugin v1.3.2 的 SIP003 转义语义（未转义 `;` 分隔项目、第一个
/// 未转义 `=` 分隔参数名与值、反斜杠转义后续字符）；原始参数字符串仍是
/// 持久化、凭据与运行时边界的唯一载荷，本模块状态不进入配置目录。
@MainActor
final class PluginOptionsDraft: ObservableObject {
  enum Mode: Hashable {
    case table
    case rawText
  }

  /// 行的值形态：无等号的无值开关与带等号的键值（含空串值）。
  enum Kind: Hashable {
    case keyValue
    case flag
  }

  /// 一行参数草稿：`original` 持有装载时的解析结果与原文片段，未修改的行
  /// 拼装时逐字回写。
  struct Row: Identifiable {
    let id: UUID
    var keyText: String
    var valueText: String
    var kind: Kind
    let original: ParsedItem?

    /// 完全空白的快速添加占位行：不计入参数项、不触发变更、不序列化。
    var isBlank: Bool {
      kind == .keyValue && keyText.isEmpty && valueText.isEmpty
    }

    /// 有值或开关形态却没有参数名的未完成草稿：阻止拼装与模式切换。
    var isUnfinished: Bool {
      keyText.isEmpty && !isBlank
    }

    /// 与装载解析结果逐字一致（编辑后改回也算），拼装时回写原文片段。
    var isUnmodified: Bool {
      guard let original else { return false }
      guard keyText == original.key else { return false }
      switch kind {
      case .flag: return !original.hasValue
      case .keyValue: return original.hasValue && valueText == original.value
      }
    }
  }

  struct ParsedItem {
    let key: String
    let hasValue: Bool
    let value: String
    let slice: String
  }

  struct ParseOutcome {
    let items: [ParsedItem]
    let trailingSeparator: Bool
  }

  @Published private(set) var mode: Mode = .table
  @Published private(set) var rows: [Row] = [PluginOptionsDraft.blankRow()]
  @Published var rawText = ""
  @Published private(set) var hadTrailingSeparator = false
  private var structureChanged = false

  // MARK: - 装载与会话串

  /// 装载（或重置）：按可解析性决定初始模式，行、原文与结构标记全部重建。
  func load(_ raw: String) {
    if let outcome = Self.parse(raw) {
      mode = .table
      rows = outcome.items.map(Self.row(from:)) + [Self.blankRow()]
      hadTrailingSeparator = outcome.trailingSeparator
    } else {
      mode = .rawText
      rows = [Self.blankRow()]
      hadTrailingSeparator = false
    }
    rawText = raw
    structureChanged = false
  }

  /// 当前会话的参数字符串：原始文本模式即其文本，列表模式拼装各行（未修改
  /// 行逐字回写）。存在未完成行（有值或开关形态却无参数名）时为 nil。
  var composedString: String? {
    switch mode {
    case .rawText: return rawText
    case .table: return assembledFromRows()
    }
  }

  var hasUnfinishedRows: Bool {
    mode == .table && rows.contains { $0.isUnfinished }
  }

  // MARK: - 模式切换

  /// 切到原始文本：先验证并拼装当前行草稿；有未完成行则留在列表模式。
  @discardableResult
  func switchToRawText() -> Bool {
    guard mode == .table else { return true }
    guard let assembled = assembledFromRows() else { return false }
    rawText = assembled
    mode = .rawText
    return true
  }

  /// 切回参数列表：重新解析当前原始文本；不可可靠解析则留在原始模式并
  /// 保留原文，不丢弃草稿。
  @discardableResult
  func switchToTable() -> Bool {
    guard mode == .rawText else { return true }
    guard let outcome = Self.parse(rawText) else { return false }
    rows = outcome.items.map(Self.row(from:)) + [Self.blankRow()]
    hadTrailingSeparator = outcome.trailingSeparator
    structureChanged = false
    mode = .table
    return true
  }

  // MARK: - 行编辑

  func updateKey(_ text: String, of id: UUID) {
    mutateRow(id) { $0.keyText = text }
  }

  func updateValue(_ text: String, of id: UUID) {
    mutateRow(id) { $0.valueText = text }
  }

  /// 键值 ⇄ 无值开关：切到开关不序列化等号；切回键值恢复本会话保留的值
  /// 草稿（无则空串）。
  func setKind(_ kind: Kind, of id: UUID) {
    mutateRow(id) { $0.kind = kind }
  }

  func deleteRow(_ id: UUID) {
    rows.removeAll { $0.id == id }
    structureChanged = true
    normalize()
  }

  /// 单行上移/下移一格（评审追加）：只换行序不改行内容——未修改行仍逐字
  /// 回写原文片段，故移动不算结构修改、既有末尾分号保留。末尾快速添加行
  /// 不可移动，也不得把行移到它之后；越界目标是无操作。
  func moveRow(_ id: UUID, by offset: Int) {
    guard let move = rowMove(id, by: offset) else { return }
    rows.swapAt(move.source, move.target)
  }

  /// 按钮与移动动作共用同一判定，视图不再维护空行和目标位置约束。
  func canMoveRow(_ id: UUID, by offset: Int) -> Bool {
    rowMove(id, by: offset) != nil
  }

  private func rowMove(_ id: UUID, by offset: Int) -> (source: Int, target: Int)? {
    guard mode == .table, offset == -1 || offset == 1 else { return nil }
    guard let index = rows.firstIndex(where: { $0.id == id }), !rows[index].isBlank else {
      return nil
    }
    var target = index + offset
    if rows.last?.isBlank ?? false {
      target = min(target, rows.count - 2)
    }
    guard target >= 0, target != index else { return nil }
    return (index, target)
  }

  /// 「添加参数」入口语义：末尾空行即快速添加行，返回其身份供聚焦。
  var quickAddRowID: UUID {
    rows[rows.count - 1].id
  }

  // MARK: - 行状态实现

  private func mutateRow(_ id: UUID, _ mutate: (inout Row) -> Void) {
    guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
    mutate(&rows[index])
    normalize()
  }

  /// 末尾始终保持一条完全空白的快速添加行；在空行开始输入（参数名、值或
  /// 类型）后该行保持身份获得正式草稿地位（焦点稳定），同时补上新的空行。
  private func normalize() {
    if !(rows.last?.isBlank ?? true) {
      rows.append(Self.blankRow())
    }
  }

  private static func blankRow() -> Row {
    Row(id: UUID(), keyText: "", valueText: "", kind: .keyValue, original: nil)
  }

  private static func row(from item: ParsedItem) -> Row {
    Row(
      id: UUID(),
      keyText: item.key,
      valueText: item.hasValue ? item.value : "",
      kind: item.hasValue ? .keyValue : .flag,
      original: item)
  }

  private func assembledFromRows() -> String? {
    var slices: [String] = []
    for row in rows where !row.isBlank {
      guard !row.keyText.isEmpty else { return nil }
      slices.append(encodedSlice(of: row))
    }
    var assembled = slices.joined(separator: ";")
    // 既有合法的末尾分号等非内容分隔表现，在没有对应结构修改时保留。
    if hadTrailingSeparator && !structureChanged && !slices.isEmpty {
      assembled += ";"
    }
    return assembled
  }

  private func encodedSlice(of row: Row) -> String {
    if row.isUnmodified, let original = row.original {
      return original.slice
    }
    switch row.kind {
    case .flag:
      return Self.escaped(row.keyText, escapingEquals: false)
    case .keyValue:
      return
        Self.escaped(row.keyText, escapingEquals: true) + "="
        + Self.escaped(row.valueText, escapingEquals: false)
    }
  }
}

// MARK: - SIP003 解析与编码（v2ray-plugin v1.3.2 args.go 语义）

extension PluginOptionsDraft {
  /// 解析：未转义 `;` 分隔项目，第一个未转义 `=` 分隔参数名与值，反斜杠
  /// 转义后续字符；空参数名或结尾悬空转义返回 nil——完整原文走原始文本
  /// 模式，不强行转换。
  static func parse(_ raw: String) -> ParseOutcome? {
    var items: [ParsedItem] = []
    var trailingSeparator = false
    var index = raw.startIndex

    while index < raw.endIndex {
      let itemStart = index
      var key = ""
      var value = ""
      var hasValue = false
      var terminatedBySeparator = false

      scan: while index < raw.endIndex {
        let character = raw[index]
        if character == "\\" {
          let escapedIndex = raw.index(after: index)
          guard escapedIndex < raw.endIndex else { return nil }
          if hasValue {
            value.append(raw[escapedIndex])
          } else {
            key.append(raw[escapedIndex])
          }
          index = raw.index(after: escapedIndex)
          continue
        }
        if character == ";" {
          terminatedBySeparator = true
          index = raw.index(after: index)
          break scan
        }
        if character == "=" && !hasValue {
          hasValue = true
          index = raw.index(after: index)
          continue
        }
        if hasValue {
          value.append(character)
        } else {
          key.append(character)
        }
        index = raw.index(after: index)
      }

      guard !key.isEmpty else { return nil }
      let itemEnd = terminatedBySeparator ? raw.index(before: index) : index
      items.append(
        ParsedItem(
          key: key, hasValue: hasValue, value: value, slice: String(raw[itemStart..<itemEnd])))
      trailingSeparator = terminatedBySeparator && index == raw.endIndex
    }

    return ParseOutcome(items: items, trailingSeparator: trailingSeparator)
  }

  /// 反向编码：反斜杠、分号（及参数名中的等号）以反斜杠转义，与
  /// v2ray-plugin 的编码方向一致；其余字符（含换行、Unicode）原样保留。
  private static func escaped(_ text: String, escapingEquals: Bool) -> String {
    var result = ""
    for character in text {
      if character == "\\" || character == ";" || (escapingEquals && character == "=") {
        result.append("\\")
      }
      result.append(character)
    }
    return result
  }
}
