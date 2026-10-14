# 首页终端代理环境命令格式扩展

日期：2026-10-14。

本文记录本次设计访谈与实现验证，不作为持续更新的现状依据。当前地址、端口和身份验证规则以代码与 ADR-0034 为准。

## 需求

- 首页复制代理环境变量设置命令支持 Nushell。
- 局域网监听开启且选择局域网 IP 时，支持 Windows：CMD 和 Windows：PowerShell。

## 已确认的决策

用户在第一轮访谈中选择全部推荐项。

- Nushell 始终显示，支持本地地址与局域网地址。
- Windows 格式仅在局域网监听开启且选择局域网 IP 时显示；条件不满足时隐藏。
- 代理停止时仍允许复制，沿用已保存的监听设置。
- 命令供用户直接粘贴到当前终端会话执行；不增加持久化命令，不支持 CMD `.bat` 文件。
- 新格式沿用四个小写变量：`http_proxy`、`https_proxy`、`all_proxy`、`no_proxy`。
- `no_proxy` 沿用 `localhost,127.0.0.1,::1,.local`。
- 局域网命令沿用现有端口与凭据规则；IPv6 URL 使用方括号。
- 保留纵向复制按钮。顺序为 `zsh / bash`、`fish`、`Nushell`、`Windows：CMD`、`Windows：PowerShell`，最多五个按钮。
- 保留完整命令 tooltip 和按钮内“已复制”反馈。
- 第二轮用户指定：复制前刷新发现所选 IP 失效时，所有格式统一停止本次复制，保留剪贴板，并提示重新选择 IP。不得把回退后的本地地址静默写入剪贴板。地址候选刷新和 Windows 格式显隐仍按最新监听事实更新。
- 第二轮用户选择本地验证：执行本地测试与构建，覆盖格式生成、显示条件、凭据编码和地址失效。真实 Windows 执行与跨设备代理连接标为未验证，不列入本次完成条件。

## 验收条件

- 本地地址下提供 zsh/bash、fish、Nushell 三个按钮。
- 局域网监听开启且选择有效局域网 IP 时，额外提供两个 Windows 格式按钮；代理停止不影响这一条件。
- 新格式复制四个小写变量，HTTP/HTTPS 与 SOCKS 使用对应入口，`no_proxy` 内容不变。
- 启用局域网认证时，URL 保留完整且正确编码的凭据；读取失败停止复制。
- 所选 IP 在复制前失效时，每一种格式都停止本次复制，不改写剪贴板，不显示“已复制”，提示“命令地址已失效，请重新选择 IP。”。
- tooltip 与对应格式的复制内容一致。
- 本地测试与构建通过；终端执行与跨设备连接按实际证据分别汇报。

## 实现前代码事实

- `HomeView+Cards.swift` 提供 zsh/bash 和 fish 复制按钮；复制前刷新命令地址。
- `TerminalCommandAddress.swift` 在地址失效时回退 `127.0.0.1`。
- `ProxyControlAdapters.swift` 按命令地址选择本地或局域网端口；认证 URL 对凭据中的特殊字符作百分号编码。
- 凭据读取失败时，现有命令返回失败，界面禁用复制。
- ADR-0034 规定 tooltip 与复制内容均包含完整命令和真实密码。

## 实现约束与验证边界

- CMD 交互命令必须保留认证 URL 的百分号编码，不能让已有环境变量改变凭据。生成方式属于实现问题，不降低认证要求。
- Nushell 与 PowerShell 使用各自的环境变量赋值语法；CMD 使用其交互语法，不采用 `.bat` 百分号转义规则。
- 当前环境未找到 `nu` 和 `pwsh`。`wine --version` 执行失败，输出为 `zsh:1: bad CPU type in executable: wine`。这些事实不代表目标终端执行通过。
- CMD 对含百分号编码的 URL 使用交互 `for %P in ("%") do set "NAME=VALUE"`，以 `%~P` 插入百分号；各变量分行赋值，不写临时环境变量。普通 URL 使用四个 `set` 以 ` & ` 连接。分行方案限制最长允许凭据下的单行长度。
- 上述 CMD 输出通过命令字符串测试与静态审查；官方文档说明 `%~P` 移除外围引号、环境变量展开不递归。原生 Windows 的完整解析行为与同名变量干扰仍未验证，不把字符串断言视为终端执行证据。
- 用户调用 `implement` 技能，授权按本文实现、审查并提交到当前分支。

## 测试边界

本地验证沿用第一轮与第二轮确认的格式、显示条件、凭据编码和地址失效范围：

- `TerminalProxyEnvironmentCommands` 投影：精确命令、监听端口、IPv6 与凭据编码。
- `ProxyControlWorkflow` 的 snapshot 与复制前准备：格式显隐、代理关闭、网络/监听变化及旧 IP 失效。
- 测试通过公开投影与工作流动作观察结果，不调用私有生成器或 SwiftUI 私有方法。

## 文档来源

- [Nushell 环境变量](https://www.nushell.sh/book/environment.html)：`$env.NAME = 'value'`。
- [PowerShell 环境变量](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_environment_variables)：`$env:NAME = 'value'`。
- [CMD set](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/set_1)：当前命令解释器的环境变量赋值。
- [CMD](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/cmd)：命令连接与变量展开。
- [CMD for](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/for)：交互循环变量与引号移除修饰符。
- [CMD 命令行长度限制](https://learn.microsoft.com/en-us/troubleshoot/windows-client/shell-experience/command-line-string-limitation)：单行最大长度为 8191 个字符。

本变更为可逆的命令格式与界面扩展，不新建 ADR。

## 本次实现与验证

- 实现五种命令格式、按地址条件显示 Windows 按钮，以及所有格式共用的复制前地址身份检查。
- Standards 与 Spec 两项只读代码审查均未发现问题。
- 使用 `CODE_SIGN_IDENTITY=-` 执行 macOS arm64 全量 hostless 测试：1,059 个测试、1,162 次执行，0 失败、0 跳过。
- 同配置 Debug 构建通过。
- 外部二进制离线检查 5 个测试、规则快照检查 4 个测试、规则转换行为检查 17 个测试通过。
- 修改的 Swift 文件通过严格格式检查；仓库 SwiftLint 返回 31 条警告、0 条严重问题。
- 真实 Nushell、Windows CMD、Windows PowerShell、跨设备代理连接与原生界面交互未验证。剪贴板保留和失败反馈路径经静态审查，不将其描述为原生交互测试。
