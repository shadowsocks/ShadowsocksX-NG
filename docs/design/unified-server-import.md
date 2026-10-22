# 统一服务器导入入口

日期：2026-10-04。
状态：设计已确认（grill-with-docs 会话）；覆盖「SIP-008 文件导入」新增需求与既有三个导入入口的重构。

## 需求与范围

新增从 SIP-008 JSON 文件导入服务器配置，并把既有导入入口（ss:// 文本、二维码图片、旧版 Legacy 导入）收敛为一个统一导入面板。工具栏「导入」由三项 Menu 收敛为单个 Button（「导入服务器配置」，无省略号），直开统一面板。共通部分（来源分派、解码器复用、事务提交、结果聚合）构成一个共用深模块；成功与错误反馈统一。

退役项：`ImportURLSheet`（含 TextEditor）、`QRImportSheet`（含识别列表确认态）、`LegacyImportSheet`、应用首次打开时主动弹出 Legacy 导入的特性（`WorkspaceHomeView` 的 onAppear 门控与 `LegacyImportAvailability.shouldOffer`）。

## 统一导入面板（UI 规格）

面板结构对齐草图：标题「导入Shadowsocks服务器配置」、右上角关闭（X）、拖放区、底部两个按钮。

- **拖放区**：虚线圆角区域，图标 +「拖动文件到这里」+ 类型提示（二维码图片 / SIP008 JSON 文件 / 包含 ss:// 链接的 txt 文件）。支持多文件拖入；点击区域弹 `.fileImporter`（`.image`、`.json`、`.plainText`，允许多选）。
- **落点提示**：拖放区上方显示「将导入到：{目录根 / 分组路径}」，随侧栏选中实时变化。
- **按钮一「从剪贴板中导入 ss:// 链接」**：一键读取剪贴板文本、按行解析导入；不做 JSON 嗅探（按钮语义即 ss:// 链接）。
- **按钮二「从旧版本 ShadowsocksX-NG 导入」**：按 `legacyImportState.completed` 显示为「再次导入旧版本服务器」；`snapshotFound == false` 时隐藏。点击直接执行 `workflow.importLegacy(reimport:)`（原 LegacyImportSheet「导入/再次导入」按钮行为），不再有中转确认表单。
- **结果区**：面板下方，每次导入动作追加逐来源结果行：来源名（文件名/剪贴板/Legacy）+ 结构化结果。面板不自动关闭，成功与失败同位呈现。

## 深模块接缝

`CatalogWorkflow` 单一入口（UI 只认识这一个方法与结果类型）：

```
func importServers(from sources: [ImportSource], into parent: NodeID?) async -> ImportRunOutcome
```

- `ImportSource` = `.clipboardText(String)` | `.file(name: String, data: Data)`。
- 来源分派按内容优先：可解码位图（ImageIO 事实，`CGImageSource`）→ 二维码；内容为 JSON 对象 → SIP-008；其余按文本逐行提取 `ss://`。JSON 判定为否后不再降级回 SIP-008 语义（版本不支持等按整份失败报出，不当作文本行）。
- 解码器全部复用 Domain 既有实现：`SubscriptionDocumentParser`（SIP-008，传一次性导入会话 UUID 作作用域）、`QrCodeCodec`（二维码）、`SsUri`（文本行）。文本行的空白行跳过不报；失败行以原始切分下标点名。
- 提交：每来源独立事务，凭据统一经 `CredentialWriteJournal`，目录提交失败整体回滚并报 `CommitError.credentialRollback` 语义。
- 结果：`ImportRunOutcome` 逐来源携带成功（导入数、落点/新建根分组身份）/ 部分成功（添加数 + 逐行失败，沿用行号点名风格）/ 整体失败（typed 原因）。失败来源不产生任何目录变更。
- Legacy 入口沿用 `importLegacy` seam，返回值由报告扩展为含新建分组身份的 `LegacyImportOutcome`（供成功后选中）；报告发布缝（`legacyImportReport`）随之移除。

现有 `createServers(fromURIs:into:)` seam 被本入口吸收并删除，其凭据写入方式从「先写后删」改为 journal；对应测试迁移到新入口。

## SIP-008 文件导入语义（ADR-0027）

- 复用 `SubscriptionDocumentParser` 整份校验：任一记录无效整份拒绝，复用 `SubscriptionParseError` 文案。
- 文档 ID（`servers[].id` 供应商 UUID、扩展分组 UUIDv5 ID）只作装配键解析树结构，目录身份全部 `.fresh()`；重复导入产生独立副本，不合并去重。
- 文件根分组整棵挂入选中落点（`importTargetParent`：选中手动组→组内；选中服务器→其手动父组；无选中/订阅子树→目录根），来源为 `.manual`。
- 根组名：扩展根组名 → 文件名去扩展名兜底 → 重名加「 2」「 3」后缀（沿用 Legacy 导入 `nextGroupName` 风格）；扁平回退（无扩展或扩展无效）时根组内容为全部服务器按文档顺序平铺。嵌套分组名为空时以「未命名分组」兜底。
- 插件参数保真：`plugin_opts` 非空即建凭据引用并存入，即使 `plugin` 为空（激活语义按 `pluginNotProvided` 点名，用户可修复）。

## 统一反馈

- 成功：「已导入 N 台服务器到『{分组名}』」（Legacy 来源映射 `LegacyImportReport`：导入数、跳过记录、身份重生成统计）。
- 部分成功：「已添加 N 台服务器」+ 失败明细逐条点名（文本来源按行号；二维码来源按图片点名「未识别到 ss:// 二维码」）。
- 整体失败：typed 原因文案（SIP-008 解析错误复用订阅解析文案族；文件不可读、剪贴板无可识别内容等新增原因）。
- 任一来源成功后，侧栏选中切换到该来源新建的根分组（多来源全成功时选最后一个成功的分组）。
- Legacy 反馈走同一结果区，但 seam 不变（直连 `importLegacy`），其报告语义与统计口径保持原有定义。

## 测试边界

- 深模块接口测试：三种来源的解码分派、SIP-008 整树导入（嵌套分组、顺序、命名兜底与后缀）、整份拒绝、部分成功的行级点名、来源间独立性（一个失败不影响其他来源提交）、凭据 journal 回滚、落点规则。
- 迁移：原 `createServers(fromURIs:)` 测试改走 `importServers` 的文本来源路径。
- 退役路径删除测试随实现一并移除（deletion check）；Legacy 工作流测试（`importLegacy` 语义）不变。
