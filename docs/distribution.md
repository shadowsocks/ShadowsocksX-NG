# 外部二进制、签名与分发

[返回工程首页](../ShadowsocksX-NG2/README.md)

除特别说明外，命令从 `ShadowsocksX-NG2/` 执行，文中工程路径也相对于该目录。

## 外部二进制供应链

外部二进制只用固定版本的上游 release 构建产物：`sslocal`（[qiuyuzhou/shadowsocks-rust v1.26.0](https://github.com/qiuyuzhou/shadowsocks-rust/releases/tag/v1.26.0)，装于 `Contents/Helpers/`）、`v2ray-plugin`（v1.3.2）与 Cloak `ck-client`（v2.12.0，两个插件均装于 `Contents/Helpers/Plugins/`）。信任根是提交在库里的清单哈希；构建链如下（spec #21 D6/D10）：

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

## 发布门槛

发布前运行发布门槛检查：

```bash
# 发布门槛（必须全绿）：真实进程冒烟 + 打包门槛
task test:smoke
Scripts/packaging-gate.sh \
  .build/derivedData/Build/Products/Debug/ShadowsocksX-NG2.app
```

打包门槛只接受 Developer ID 签名的产物：Team 期望值取自 `Configs/Signing.local.xcconfig`（可用 `EXPECTED_TEAM_ID=<Team ID>` 显式覆盖），两者都没有时该断言直接失败，不静默跳过。无证书的 ad-hoc Debug 产物会在此明确失败（`gate: hint` 会说明原因），这是预期行为。

## 依赖升级

升级任一外部二进制是显式供应链动作：人工复验新 release（下载归档、静态观测哈希/架构/签名，不执行），随后在一次 PR 中同时改 `Vendor/<name>/manifest.json` 的 release/asset/url/archiveSHA256 与对应测试锚点。不接受 `latest`，不在仓库内构建，不做应用内更新通道（升级仅随 app 发版）。
