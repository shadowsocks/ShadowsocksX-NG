# 服务器分享 sheet（2026-10-05）

本文件记录本轮已确认规格（按用户提供的草图方向实现），现状以代码为准。

## 需求

服务器分区的「分享」由工具栏 popover（220×220 二维码 + 复制 ss:// 链接）升级为窗口 sheet，按草图布局：顶部说明文字、大幅二维码、三个纵向按钮（复制二维码图片 / 保存二维码图片 / 复制 ss:// 链接）。入口与可用性判据不变：仅服务器分区工具栏「分享」按钮，作用于选中的服务器叶子，无有效载荷即禁用。

## 已确认决策

- 呈现：popover 整体替换为 `.sheet(item:)`；打开时冻结分享载荷与建议文件名（`ShareContext`），sheet 生命周期内不随选择漂移；选中项变化时立即收起。Esc 与「完成」按钮均可关闭。
- 二维码：显示 280×280，白底圆角衬底保证深色外观下的扫码对比度；后台线程生成，就绪前呈进度，图片动作禁用。生成参数不变（`QrCodeCodec.generatePNG`，CIQRCodeGenerator，纠错级 M，scale 8）。
- 复制二维码图片：同一 pasteboard 写 PNG（规范类型）+ TIFF（兼容类型，附加失败不影响 PNG 已写入）；不附带 ss:// 文本。
- 保存二维码图片：只提供 PNG，走 NSSavePanel；默认文件名取服务器显示名，路径非法字符（/ 与 :)替换为空格并去首尾空白，清洗后为空回退 `ss-qrcode`，统一追加 `.png`。
- 复制反馈：两个复制动作成功后按钮文案短暂变为「✓ 已复制」约 2 秒，重复点击重置计时；保存由系统面板反馈，不做额外提示。
- 按钮：四枚按钮（三个动作 + 完成）标签统一最小宽 260pt（略窄于二维码块，最长标签与反馈态均小于该值），居中排布，宽度不随文案切换跳变。
- 术语：保存二维码图片文件属于「分享」，不叫导出（GLOSSARY.md 的导出保留给配置组/诊断报告文件快照）；新 seam 命名用 saver。GLOSSARY「服务器分享」条目已更新。

## 设计

- 新增平台 seam（与既有 TextClipboard / ConfigurationGroupFileExporter 同法，协议 + InMemory + AppKit adapter，`NSPasteboard`/`NSSavePanel`/文件写入仍集中在聚焦 adapter，守卫见 `PlatformEffectsArchitectureTests`）：
  - `ImageClipboard` / `InMemoryImageClipboard` / `AppKitImageClipboard`：图片剪贴板写入。
  - `QrImageSaver` / `InMemoryQrImageSaver` / `AppKitQrImageSaver`（含 `QrImageSaveDraft.suggestedFileName(from:)` 命名清洗）：二维码图片保存面板与原子写入。
- `ShareServerSheet`（`ServersView+Share.swift`）自持二维码与反馈状态；错误沿用共享 `ErrorAlertPresenter` 呈现边缘（与 NewGroupSheet 同法）。
- 注入链：组合根 `ApplicationDependencies` → `MainWindowView` → `ServersView` → sheet。
- typed failure 在 `AppPresentation.message(for:)` 白名单登记：图片剪贴板写入失败、二维码图片写入失败。
