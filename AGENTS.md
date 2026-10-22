# ShadowsocksX-NG

macOS Shadowsocks 客户端。旧版实现已从本仓库移除,归档在 [shadowsocks/ShadowsocksX-NG](https://github.com/shadowsocks/ShadowsocksX-NG) 的 [`legacy-v1`](https://github.com/shadowsocks/ShadowsocksX-NG/tree/legacy-v1) 分支,仅作只读参考;新实现位于 `ShadowsocksX-NG2/`。文档与注释中引用旧版源码的链接都指向该分支。

## Agent skills

### Local validation

验证 ShadowsocksX-NG2 变更或诊断本地验证产物时，读取 [本地验证技能](.agents/skills/shadowsocksx-ng2-local-validation/SKILL.md)。仓库内版本为维护入口；memory 中的同名技能仅为历史快照。

### Git commits

Git 提交消息使用英文 Conventional Commits 格式。

### Issue tracker

Issue 跟踪在本仓库的 GitHub Issues,统一用 `gh` CLI 操作,并在每条命令上显式指定本仓库。见 `docs/agents/issue-tracker.md`。

### Code comments

编写或修改代码注释时，禁止引用 fork 仓库的 Issue 编号（包括 `#123`、`owner/repo#123` 或 Issue 链接），因为合并到上游后无法依靠上游 Issue 跟踪这些引用。注释应直接说明行为、约束或设计原因，使其无需查阅 fork Issue 也能理解。

### Triage labels

triage 标签使用五个默认角色名作为标签字符串(needs-triage / needs-info / ready-for-agent / ready-for-human / wontfix)。见 `docs/agents/triage-labels.md`。

### Domain docs

single-context:根目录一个 `GLOSSARY.md` + `docs/adr/`,按需惰性创建。见 `docs/agents/domain.md`。

`GLOSSARY.md` 和新建 ADR 的正文使用简体中文，代码标识符与必要的英文术语保留原文。已有 ADR 保留原文，不作语言迁移。

现状与已定设计以当前代码、`GLOSSARY.md` 和 `docs/adr/` 为准。仅 `GLOSSARY.md` 和 `docs/adr/` 持续维护为最新状态；判断当前实现时，以当前代码为事实依据。将设计文档或研究报告作为实现依据前，应先在代码中核实相关描述。

`docs/design/` 记录对应任务执行时的需求、设计与规格，仅作为历史参考，不代表最新代码现状。

`docs/research/` 收录研究报告。各文档记录写作时点对上游能力、候选方案与结论的调研，不描述项目当前状态，也不代表相关设计已经被采纳。
