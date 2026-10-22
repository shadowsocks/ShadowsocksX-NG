# 源码目录即分层与主题，边界由守卫断言

Status: Accepted (2026-10-05)

`App/` 按分层组织（Composition / Application / Presentation / UI / PlatformEffects / Resources），`Domain/` 按主题组织，主题名取自 `GLOSSARY.md` 的章节划分（配置与订阅、代理规则、代理控制与网络、设置、凭据与诊断），避免同一概念在文档与目录里有两个名字。两个目录的根层只放子目录、不放平铺文件——目录本身就是架构声明。

边界由 `Tests/SkeletonTests.swift` 的守卫断言，且一律**正面圈定**而非禁令加豁免登记：视图层的守卫只扫 `App/UI/`（不得引用运行时控制器、工作流实现协作者、原始目录/凭据存储类型），`Domain/` 的守卫只断言根下无平铺 `.swift`、树下只有 `.swift`。把文件放进 `Application/`、`PlatformEffects/` 或某个主题目录，即自动落在扫描范围之外，无需登记豁免；新增主题目录也不需要改断言。

各目录的划分与各自职责由 [工程结构文档](../project-structure.zh-CN.md)维护——本 ADR 只固定组织原则，不维护清单。

## Considered options

- **平铺 + 禁令表 + 豁免登记**：守卫默认扫描整个目录，再逐个登记要放行的例外。每加一个运行时适配器都要改守卫，豁免清单本身成了需要维护的知识，而「这个文件属于哪一层／哪个主题」仍然无处声明。
- **feature-first（按功能纵向切分）**：把某个功能的领域类型、工作流与视图放进同一个目录。与既有分层冲突——工作流依赖的运行时控制器与目录存储会变成视图的同层邻居，边界退化成不可断言的约定。
- **`Domain/` 也照搬分层**：领域内部不存在 `App/` 那样的层间依赖方向（没有「领域视图」），照搬只会得到一个叫 Services 的杂物箱。
- **让守卫锁定主题目录集合**：即正向列举「允许的目录」。未采纳——断言应当固定「不留平铺文件」这条不变量，而不是把主题划分冻结成一份需要同步维护的清单；新增主题目录是正常演进。

## Consequences

XcodeGen 带来两条**在代码里不可见**的约束：

- 源路径的 `excludes` glob **不跨 `/`**：裸文件名只匹配被扫描目录的根层。Core 测试镜像因此必须用 `**/MainApp.swift` 这类递归形式；文件下移后旧写法会**静默**失效，把 `@main` 组合根编进测试镜像。
- `App/`、`Domain/` 整目录是 source path，其中任何非源码文件都会被 XcodeGen 收进 Resources 阶段并封进签名后的 app bundle。因此文档不放 `App/`（`project.yml` 排除 `**/*.md`），`Domain/` 则由守卫禁止出现非 `.swift` 文件。

跨进程契约按**文件**引用而非按目录：wrapper 与 system proxy helper 两个 target 各自显式列出所需的 `Domain/` 文件，因为它们只该拿到跨进程契约，而不是整个领域层。代价是目录内移动文件必须同步 `project.yml`；漏改时 xcodegen 以 `missing source directory` 直接失败，不静默。

在目录内移动文件因此是低代价操作：模块名、类型名与 import 均不变，`task format` 与 lint 基线不变，版本历史可继续追溯。这条约定分散记录在 `project.yml` 的分层注释、[工程结构文档](../project-structure.zh-CN.md)与本 ADR；新增主题目录时只需同步前两处（`DomainLayoutTests` 失败信息里列举的目录名会过期，断言本身不会失败）。
