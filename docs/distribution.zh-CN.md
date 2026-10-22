# 外部二进制、签名与分发

[English](distribution.md) | [返回工程首页](../ShadowsocksX-NG2/README.zh-CN.md)

除特别说明外，命令从 `ShadowsocksX-NG2/` 执行，文中工程路径也相对于该目录。

## 外部二进制供应链

外部二进制只用固定版本的上游 release 构建产物：[`sslocal` 清单](../ShadowsocksX-NG2/Vendor/sslocal/manifest.json)（装于 `Contents/Helpers/`）、[`v2ray-plugin` 清单](../ShadowsocksX-NG2/Vendor/v2ray-plugin/manifest.json) 与 [`ck-client` 清单](../ShadowsocksX-NG2/Vendor/ck-client/manifest.json)（两个插件均装于 `Contents/Helpers/Plugins/`）。清单记录各 release 与哈希；构建链如下（spec #21 D6/D10）：

1. **fetch** — `Scripts/fetch-external-binaries.sh` 下载清单固定 URL 的资产、逐字节校验 `archiveSHA256`，按 `assetFormat` 处理 tar 归档（默认，提取 `archiveMember`）或直接二进制（`binary`），并确认 arm64，落盘 `Vendor/<name>/` 并记录戳。资产哈希不符 → 立即失败；本地缓存漂移或清单变更 → 自动重新下载复验。
2. **generate** — `xcodegen generate` 把清单对应二进制作为 Copy Files 项装入 `Contents/Helpers[/Plugins]`。注意顺序：**先 fetch 再 generate**，文件在生成时必须已存在，否则 Copy Files 阶段会被静默丢弃（generate 也会直接报缺文件）。
3. **verify on every build** — 预构建脚本阶段重跑 fetch 脚本（缓存命中时只对本地戳快速复验），哈希或清单漂移使构建即失败。
4. **sign** — `Scripts/sign-embedded-helpers.sh`（post-build 阶段）对每个二进制 Developer ID 重签：`--options runtime --timestamp --identifier <清单 signIdentifier>`（插件形如 `<bundle-id>.plugin.<name>`）；随后 Xcode 完成 app 外层签名，封存重签后的嵌套代码。
5. **gate** — 构建产物必须过 `Scripts/packaging-gate.sh <App.app>`：嵌套代码签名严格校验、主应用 DevID + Hardened Runtime 且无 App Sandbox entitlement、逐二进制清单覆盖（Helpers 下每个 Mach-O 都在清单内且 DevID 重签通过）。篡改任一二进制会因签名失效被断言发现。

## 签名与运行形态基线

- bundle id `com.qiuyuzhou.ShadowsocksX-NG2`，与 Legacy（`com.qiuyuzhou.ShadowsocksX-NG`）区分；运行时数据落 `~/Library/Application Support/ShadowsocksX-NG2/`。macOS 15+ / arm64。
- Hardened Runtime（DevID 发布路径；免证书的 ad-hoc Debug 例外，详见下面的配置说明）；不启用 App Sandbox，entitlements 为空 dict；签名样式固定 `Manual`。
- **证书与 Team 都不入库**（开源仓库）：`project.yml` 不含 `CODE_SIGN_IDENTITY` / `DEVELOPMENT_TEAM`，两个键由 project xcconfig 按 config 在构建期注入：
  - `Configs/Signing-Debug.xcconfig`（入库）基线是 **ad-hoc（`-`）**：新 clone 与 CI 不需要任何证书就能 `task build` / `task test`。arm64 要求代码至少有 ad-hoc 签名才会被加载，所以「免证书」不是「不签名」。ad-hoc 产物不带 Hardened Runtime（Xcode 对 ad-hoc 签名不传 `-o runtime`，实测；`Scripts/sign-embedded-helpers.sh` 的 ad-hoc 分支同样不加），Hardened Runtime 由 DevID 发布路径与打包门槛断言。
  - `Configs/Signing-Release.xcconfig`（入库）基线是 **Developer ID Application**：发布产物必须真签名，这里不给免证书路径。
  - 两者都可选包含 `Configs/Signing.local.xcconfig`（gitignore）。有证书的人（含维护者）用它升级本机身份，例如让 Debug 也走 Developer ID：

    ```bash
    cat > Configs/Signing.local.xcconfig <<'EOF'
    DEVELOPMENT_TEAM = YOUR_TEAM_ID
    CODE_SIGN_IDENTITY = Developer ID Application
    EOF
    ```

  - 该文件缺失时 Debug 构建为 ad-hoc（可跑单测），Release 构建以 Xcode 的「Signing for … requires selecting either a development team or a provisioning profile」明确失败，不静默降级。
  - 测试 target（单测与冒烟）身份随同一基线：去宿主化（ADR-0021）后 xctest 包不再注入宿主 app，ad-hoc 也能加载执行（实测），因此测试无需证书。
  - 注意 `project.yml` 一旦重新设置这两个键，pbxproj 构建设置会盖掉 xcconfig（`Tests/Architecture/SigningConfigurationTests.swift` 守卫该约束）。
- Release 配置关闭 `CODE_SIGN_INJECT_BASE_ENTITLEMENTS`，保证发布产物 entitlements 只来自项目文件。
- Release 配置通过 `OTHER_CODE_SIGN_FLAGS = $(inherited) --timestamp` 为 Xcode 签名的主程序和两个原生工具请求安全时间戳。打包门槛在上传公证前检查这些时间戳；DMG 的时间戳不能替代包内可执行文件的时间戳。

## 发布门槛

### 签名并公证的 DMG

从 `ShadowsocksX-NG2/` 执行。首次准备外部二进制及 Developer ID 签名配置的方法见上文。钥匙串中必须有对应证书及私钥。

先用 Apple 的工具保存公证凭据。此命令交互输入 App 专用密码；凭据保存在钥匙串中，不写入仓库或 Taskfile：

```bash
xcrun notarytool store-credentials shadowsocks-release \
  --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
```

完整发布入口：

```bash
task package NOTARY_PROFILE=shadowsocks-release \
  MARKETING_VERSION=2.1.0 CURRENT_PROJECT_VERSION=21
```

`task package`、`task build:release` 和 `task i:release` 必须提供非空的 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`，不使用工程默认版本。参数可以通过命令行、环境变量或本机 `.env` 提供，只覆盖本次 Release 构建，不改写 `project.yml`。`MARKETING_VERSION` 接受三个以点分隔的数字、可选的 `v` 前缀和以 `-` 开头的预发布后缀。后缀中的标识符使用 ASCII 字母、数字或连字符，以点分隔，例如 `v2.0.0-alpha-1`、`2.0.0-beta.2` 和 `v2.0.0-rc.1`。`CURRENT_PROJECT_VERSION` 接受一至三个以点分隔的数字。`package:notarize` 复用已有 DMG，不要求重新提供版本参数。

预发布构建示例：

```bash
task package NOTARY_PROFILE=shadowsocks-release \
  MARKETING_VERSION=v2.0.0-alpha-1 CURRENT_PROJECT_VERSION=22
```

DMG 文件名保留完整发布版本：`ShadowsocksX-NG2-v2.0.0-alpha-1-22-arm64.dmg`。Task 用计算变量提取 `2.0.0` 传给 Xcode，因此 App 的 `CFBundleShortVersionString` 仍符合 Apple 的三段数字格式。预发布后缀不写入这个字段；App 内的预发布构建用递增的 `CURRENT_PROJECT_VERSION` 区分。不同 alpha、beta、rc 和正式构建都应继续递增构建号。

流程由 `Taskfile.package.yml` 编排：检查公证凭据 → 获取外部二进制 → 真实进程冒烟 → Release 构建 → App 打包门槛 → 制作压缩 DMG → DMG 签名 → Apple 公证 → 装订票据 → 签名、票据及 Gatekeeper 检查 → 发布到 `dist/`。构建只支持 arm64。DMG 只包含 App 和指向 `/Applications` 的快捷方式，不增加背景图或 Finder 自动化依赖。

DMG 复用 App 实际签名证书的 SHA-1 指纹选择签名身份，使用安全时间戳。公证仅接收 `NOTARY_PROFILE` 指定的钥匙串配置名称。发布产物示例为 `dist/ShadowsocksX-NG2-2.1.0-21-arm64.dmg`。名称保留传入的完整发布版本。构建号始终从 App 的 Info.plist 读取。打包前校验发布版本的数字部分与 App 版本一致，防止文件名与包内版本不符。已有同名发布产物时明确失败，不覆盖文件。

`package` 根据必填版本参数，在工具检查、公证凭据检查、冒烟和构建之前检查同名产物。制盘、公证和最终发布时仍保留覆盖保护，防止并发打包产生覆盖。

每次构建使用独立的 `.build/packaging/run-*/`，其中保留签名 DMG、构建产物与冒烟结果。每次公证在 `.build/notarization/run-*/` 保存提交响应、提交编号、等待结果与 Apple 诊断日志。控制台打印这两个目录。提交和等待分别执行，等待中断时仍保留提交编号。公证等待上限为 30 分钟；本地等待结束后 Apple 仍可能继续处理。

公证失败后，可以直接重跑保留的签名 DMG，无须重新构建：

```bash
task package:notarize \
  DMG_PATH=/absolute/path/to/ShadowsocksX-NG2-2.1.0-21-arm64.dmg \
  NOTARY_PROFILE=shadowsocks-release
```

此入口会重新提交公证。若此前仅等待超时，可以先用保留的提交编号查询 Apple 状态，避免重复提交：

```bash
xcrun notarytool info SUBMISSION_ID --keychain-profile shadowsocks-release
```

`package:notarize` 仅在 Apple 返回 `Accepted` 后装订 DMG 票据。签名、票据和 Gatekeeper 检查全部通过后，才发布完整文件到 `dist/`。失败时不发布新文件。此流程只装订 DMG 票据，不另外分发独立 App。公证重跑入口不代替完整入口中的冒烟和 App 打包门槛；它接收此前完整入口生成的签名 DMG。

`task clean` 删除 `.build/` 中间产物及日志，保留 `dist/`。仓库忽略这两类产物。此流程不上传 GitHub Release。

工具用法见 Apple 的[公证流程](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)与[分发打包说明](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)。

### 单独检查 App

已有构建产物时，可以单独运行发布门槛检查：

```bash
# 发布门槛（必须全绿）：真实进程冒烟 + 打包门槛
task test:smoke
task build:release MARKETING_VERSION=2.1.0 CURRENT_PROJECT_VERSION=21
Scripts/packaging-gate.sh \
  .build/derivedData/Build/Products/Release/ShadowsocksX-NG2.app
```

打包门槛只接受 Developer ID 签名的产物：Team 期望值取自 `Configs/Signing.local.xcconfig`（可用 `EXPECTED_TEAM_ID=<Team ID>` 显式覆盖），两者都没有时该断言直接失败，不静默跳过。无证书的 ad-hoc Debug 产物会在此明确失败（`gate: hint` 会说明原因），这是预期行为。

## 依赖升级

升级任一外部二进制是显式供应链动作：人工复验新 release（下载归档、静态观测哈希/架构/签名，不执行），随后在一次 PR 中同时改 `Vendor/<name>/manifest.json` 的 release/asset/url/archiveSHA256 与对应测试锚点。不接受 `latest`，不在仓库内构建，不做应用内更新通道（升级仅随 app 发版）。
