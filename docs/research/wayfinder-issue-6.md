# Wayfinder Issue 6：XcodeGen、SwiftPM 与外部二进制打包发布

- 票据：[研究：XcodeGen、SwiftPM 与外部二进制打包发布](https://github.com/qiuyuzhou/ShadowsocksX-NG/issues/6)
- 父地图：[Wayfinder: ShadowsocksX-NG 2.0 现代化重实现](https://github.com/qiuyuzhou/ShadowsocksX-NG/issues/1)
- 研究日期：2026-09-20
- 适用范围：macOS 15+、arm64、ShadowsocksX-NG 2.0、外部 `shadowsocks-rust` 可执行文件

## 决策摘要

1. **不在本仓库构建 `shadowsocks-rust` 源码，也不把它作为 SwiftPM 源码依赖。** 采用 `shadowsocks-rust` 官方 GitHub Release 的 `aarch64-apple-darwin` 归档；仓库只保存版本、下载地址、归档 SHA-256 和要提取的二进制名称，构建/CI 在 XcodeGen 生成前下载并校验归档。
2. **在 XcodeGen 中把 `sslocal` 表示为一个待复制的文件，而不是 SwiftPM target。** 将它放入 app bundle 的 `Contents/Helpers/sslocal`，使用 XcodeGen 的 `sources` 文件项和 `copyFiles` build phase；不要把 Mach-O 可执行文件放进 `Contents/Resources`。
3. **先签内部 helper，再由 Xcode 签外层 app。** 在 Xcode 的最后一个构建脚本阶段调用 `codesign` 为 `sslocal` 使用 Developer ID Application、secure timestamp、Hardened Runtime 和独立的 code-signing identifier；随后让 Xcode 完成 app 签名。不要用 `codesign --deep` 作为签名方案，`--deep` 只用于递归验证。
4. **校验对象是官方归档，而不是签名后的 `sslocal` 文件。** 先验证官方 `.tar.xz` 的 SHA-256，再解压并检查目标文件是 arm64、版本符合预期。重新签名会改变文件内容，因此不能在签名后继续拿官方归档哈希比较。
5. **CI 分两层验证：** 普通 CI 做下载、哈希、归档内容、架构、版本、XcodeGen 和未/开发签名构建检查；受保护的 macOS arm64 发布任务做 Developer ID 签名、archive、Gatekeeper 风格验证、公证、staple 和最终包验证。

## 1. 官方发布物事实

### 1.1 选择的官方资产

`shadowsocks-rust` README 将 GitHub Releases 作为静态链接构建的下载位置，并明确列出 macOS 目标 `aarch64-apple-darwin`。来源：

- [shadowsocks-rust README：Download release](https://github.com/shadowsocks/shadowsocks-rust/blob/master/README.md#download-release)
- [shadowsocks-rust 官方 Releases](https://github.com/shadowsocks/shadowsocks-rust/releases)
- [v1.25.0 官方 Release](https://github.com/shadowsocks/shadowsocks-rust/releases/tag/v1.25.0)
- [v1.25.0 官方 Release API](https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/tags/v1.25.0)

截至本研究日，适用于本项目的资产是：

```text
release:       v1.25.0
asset:         shadowsocks-v1.25.0.aarch64-apple-darwin.tar.xz
target:        aarch64-apple-darwin
archive sha256:58e0caf0cc9266c4ea226f38aa20fb28c1be12efc87a73cf5903197867555208
asset URL:     https://github.com/shadowsocks/shadowsocks-rust/releases/download/v1.25.0/shadowsocks-v1.25.0.aarch64-apple-darwin.tar.xz
checksum URL:  https://github.com/shadowsocks/shadowsocks-rust/releases/download/v1.25.0/shadowsocks-v1.25.0.aarch64-apple-darwin.tar.xz.sha256
```

官方配套 checksum 文件的内容是：

```text
58e0caf0cc9266c4ea226f38aa20fb28c1be12efc87a73cf5903197867555208  shadowsocks-v1.25.0.aarch64-apple-darwin.tar.xz
```

本地对该 Release 归档做了独立核验，结果如下：

```text
归档内容：sslocal、ssserver、ssurl、ssmanager、ssservice
sslocal：Mach-O 64-bit executable arm64
lipo -archs：arm64
sslocal --version：shadowsocks 1.25.0
归档 SHA-256：58e0caf0cc9266c4ea226f38aa20fb28c1be12efc87a73cf5903197867555208
```

这些结果是对当前 Release 的构建输入核验，不应把 `v1.25.0` 永久写死为“最新版本”。升级时必须通过一次显式依赖更新，连同新的 Release URL、归档哈希和验证结果一起变更。

### 1.2 官方归档签名不是本项目发布签名

当前 `v1.25.0` 归档中的 `sslocal` 可执行文件可以看到 ad-hoc/linker-signed 的 Mach-O 签名，没有 Developer ID team identity。它不能直接作为 ShadowsocksX-NG 的最终发布签名。发布流程必须在归档哈希校验之后、app 外层签名之前重新签署该 helper。

这也解释了为什么“下载官方构建文件”和“由 ShadowsocksX-NG 对最终产品负责签名”是两个独立步骤：前者验证来源物的字节完整性，后者让 macOS Gatekeeper 和 Apple notarization 识别最终分发者。

## 2. XcodeGen 工程落点

### 2.1 推荐的目录和生成顺序

建议把外部构建输入与应用源代码分开：

```text
ShadowsocksX-NG2/
  project.yml
  Sources/
  Scripts/
    fetch-shadowsocks-rust.sh
    sign-embedded-helpers.sh
  Vendor/
    shadowsocks-rust/
      manifest.json       # 版本、target、URL、归档 SHA-256、binary 名称
      sslocal             # 下载/解压后生成；是否提交二进制由后续发布策略决定
```

更推荐将 `sslocal` 放到明确的构建产物目录，例如 `BuildArtifacts/shadowsocks-rust/sslocal`，而不是把一个未校验的二进制直接提交到源码树。关键约束是：

- `fetch-shadowsocks-rust.sh` 只下载 Release 资产，不 checkout 或编译 `shadowsocks-rust` 源码。
- 下载后先校验归档 SHA-256，再在隔离临时目录解压，只复制预期的 `sslocal`。
- `xcodegen generate` 在依赖获取/校验成功后执行；不要让 XcodeGen 在没有输入时静默生成一个缺少代理核心的 app。
- `manifest.json` 是变更审查入口；不能使用 `latest` URL，也不能根据运行时网络内容替换 app bundle 中的 helper。

### 2.2 XcodeGen 表达方式

XcodeGen 官方 `ProjectSpec` 将文件项的 `buildPhase` 支持为 `sources`、`resources`、`copyFiles` 或 `none`，而 `copyFiles` 支持 `wrapper` 目标和 `subpath`。因此可以用类似下面的工程描述表达外部 helper：

```yaml
targets:
  ShadowsocksX-NG:
    type: application
    platform: macOS
    sources:
      - path: Sources
      - path: BuildArtifacts/shadowsocks-rust/sslocal
        type: file
        buildPhase:
          copyFiles:
            destination: wrapper
            subpath: Helpers
    postBuildScripts:
      - path: Scripts/sign-embedded-helpers.sh
        name: Sign embedded shadowsocks-rust helper
        inputFiles:
          - $(BUILT_PRODUCTS_DIR)/$(CONTENTS_FOLDER_PATH)/Helpers/sslocal
```

这会把文件复制到 app bundle 的 `Contents/Helpers/sslocal`。`type: file` 是必要的意图声明：该路径是一个文件，不是 Swift 源目录或 folder reference。实际 `project.yml` 仍需按新工程的 target 名称、构建配置和签名设置调整。

来源：[XcodeGen Project Specification：Sources / buildPhase / Copy Files](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md#sources)。XcodeGen 项目本身说明，YAML/JSON project spec 是生成 Xcode project 的单一描述来源：[XcodeGen README](https://github.com/yonaskolb/XcodeGen)。

### 2.3 为什么选择 `Contents/Helpers`

Apple TN2206 将 `Contents/Helpers` 和 `Contents/MacOS` 列为 bundle 中 helper apps/tools 的标准 code 位置，并提醒代码和普通资源必须放在正确的位置。它还特别建议把脚本和其他非 Mach-O 可执行文件放进 `Contents/Resources`，原因是非 Mach-O 签名可能依赖 extended attributes；当前 `sslocal` 是 Mach-O，因此应按嵌套代码放在 `Contents/Helpers`，而不是当作普通资源处理。

来源：[TN2206：Nested Code](https://developer.apple.com/library/archive/technotes/tn2206/_index.html#//apple_ref/doc/uid/DTS10003709-CH1-SUBSECTION13)。

这个位置也让 Swift 端的运行时路径明确：通过 app bundle 的 `Contents/Helpers/sslocal` 定位 helper，并且在启动服务前对该固定路径做存在性、架构和签名检查。不要在首次运行时下载或替换 bundle 内的可执行文件；Apple 明确要求签名后的 bundle 按只读内容处理。

## 3. SwiftPM 的边界

SwiftPM 确实支持：

```swift
.binaryTarget(
    name: "SomeBinary",
    url: "https://example.com/SomeBinary.zip",
    checksum: "..."
)
```

并要求使用 `swift package compute-checksum` 计算远程二进制归档的 SHA-256。来源：

- [Apple PackageDescription `Target`](https://developer.apple.com/documentation/packagedescription/target)
- [Apple PackageDescription `Target.checksum`](https://developer.apple.com/documentation/packagedescription/target/checksum)
- [Swift Package Manager：Adding Dependencies / Precompiled Binary Targets](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageManagerDocs/Documentation.docc/Dependencies/AddingDependencies.md#precompiled-binary-targets-for-apple-platforms)
- [SE-0272：Package Manager Binary Dependencies](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0272-swiftpm-binary-dependencies.md)

但本项目的 `sslocal` 是由 GUI 作为独立进程启动的命令行工具，不是被 Swift 编译器链接或 `import` 的 framework/module。官方 Release 是包含多个独立可执行文件的 `.tar.xz`，而不是供 SwiftPM 直接链接的 Swift binary target。将它包装成 SwiftPM binary target 会引入一个与进程生命周期无关的额外包层，并不能替代 app bundle 的嵌套代码签名。

因此本票据的决定是：

- SwiftPM 只管理真正被 Swift/Xcode 使用的库依赖。
- `sslocal` 走“固定 Release 资产 + SHA-256 校验 + XcodeGen Copy Files + 自定义签名脚本”路径。
- 如果未来要以 SwiftPM 分发某个可链接二进制，才使用 `.binaryTarget` 和 SwiftPM checksum；不要为了形式上的“二进制依赖”把 `sslocal` 塞入 SwiftPM。

## 4. 签名顺序和命令约束

### 4.1 签名顺序

推荐顺序如下：

```text
官方归档
  -> 校验 archive SHA-256
  -> 解压并检查 sslocal
  -> 复制到 Contents/Helpers/sslocal
  -> 签名 sslocal（最内层）
  -> Xcode 签名 ShadowsocksX-NG.app（外层）
  -> 打包 DMG/ZIP
  -> 公证并 staple 分发物
```

Apple 说明，嵌套代码在外层签名时已经必须正确签名；Xcode 的正常流程是从最内层向外层签名。Apple 也明确说，`codesign --deep` 适合验证嵌套代码，不推荐用它代替逐层签名。

来源：

- [TN2206：Nested Code](https://developer.apple.com/library/archive/technotes/tn2206/_index.html#//apple_ref/doc/uid/DTS10003709-CH1-SUBSECTION13)
- [TN2206：Using the `codesign` Tool’s `--deep` Option Correctly](https://developer.apple.com/library/archive/technotes/tn2206/_index.html#//apple_ref/doc/uid/DTS10003709-CH1-SUBSECTION21)
- [Apple：Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)

### 4.2 helper 的签名参数

发布配置的签名脚本应等价于下面的意图：

```sh
codesign \
  --force \
  --sign "$EXPANDED_CODE_SIGN_IDENTITY" \
  --timestamp \
  --options runtime \
  --identifier "${PRODUCT_BUNDLE_IDENTIFIER}.sslocal" \
  "$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Helpers/sslocal"
```

注意事项：

- 使用 `Developer ID Application` 身份，而不是开发证书、ad-hoc 或 Mac App Store 的其他分发身份。
- `--timestamp` 添加 secure timestamp；Apple 的自定义签名示例也使用该选项。
- `--options runtime` 为命令行 helper 启用 Hardened Runtime；如果将来需要例外能力，必须逐项评估并加入最小 entitlement。
- `--identifier` 为无 bundle 的 helper 提供稳定的 code-signing identifier，例如 `com.qiuyuzhou.ShadowsocksX-NG.sslocal`。
- 不使用 `sudo codesign`；Apple 文档指出签名过程依赖当前用户的 Keychain 和签名环境。
- 该脚本只能签内部 helper，不应在它之后修改 app bundle；外层 app 由 Xcode 在所有构建阶段完成后签名。

来源：[Apple：Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/)、[Apple：Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime)、[Apple：Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

## 5. 版本和 SHA-256 策略

### 5.1 版本清单

建议提交一个可审查的清单，例如：

```json
{
  "project": "shadowsocks-rust",
  "release": "v1.25.0",
  "target": "aarch64-apple-darwin",
  "asset": "shadowsocks-v1.25.0.aarch64-apple-darwin.tar.xz",
  "url": "https://github.com/shadowsocks/shadowsocks-rust/releases/download/v1.25.0/shadowsocks-v1.25.0.aarch64-apple-darwin.tar.xz",
  "archiveSHA256": "58e0caf0cc9266c4ea226f38aa20fb28c1be12efc87a73cf5903197867555208",
  "binary": "sslocal"
}
```

这个版本号与 ShadowsocksX-NG 自己的 `2.0` app 版本分开：

- `CFBundleShortVersionString` / `CFBundleVersion` 表示 ShadowsocksX-NG 产品版本。
- 清单中的 `release` 表示代理核心的上游版本。
- 可以把上游版本写入 About/diagnostics 或只作为构建元数据，但不能让 app 的产品版本随着上游版本隐式变化。

### 5.2 校验时机

构建脚本应在解压前做归档校验，概念上等价于：

```sh
curl --fail --location --output "$archive" "$url"
printf '%s  %s\n' "$archive_sha256" "$archive" | shasum --algorithm 256 --check -
tar --list --xz --file "$archive"
```

同时下载并核对官方 `.sha256` companion asset 是有益的审计步骤，但构建本身仍应以版本控制中的期望哈希为准；否则“下载 checksum 文件后信任它”会把版本更新和校验值更新绑定在同一次网络请求中。升级 PR 应同时改变 release、asset、URL 和 `archiveSHA256`，并重新执行架构/版本测试。

归档哈希与提取后的 `sslocal` 哈希有不同用途：

- 归档哈希验证官方发布物整体没有被替换。
- 提取后的二进制可额外记录 SHA-256 供诊断，但它在 `codesign` 重新签名后会改变，不能作为最终 app 内 helper 的发布校验值。
- 重新签名后验证的是 Apple code signature、Team ID、Hardened Runtime、secure timestamp 以及外层 bundle 的资源封印。

## 6. CI 与发布验证门槛

### 6.1 普通 CI（不需要发布证书）

每次修改清单、XcodeGen 配置或依赖获取脚本时至少执行：

1. 确认 URL 是精确的 `shadowsocks/shadowsocks-rust` Release 资产，拒绝 `latest`、未经固定的 branch 或用户可编辑下载地址。
2. 下载归档并用清单中的 SHA-256 校验；再用官方 `.sha256` 文件做独立报告。
3. 在干净临时目录解压，只接受预期的 `sslocal` 文件；拒绝路径穿越和意外文件覆盖。
4. 用 `file`/`lipo -archs` 确认结果是单一 `arm64`，不要把 `x86_64` 或 universal 资产混入仅 arm64 产品。
5. 执行 `sslocal --version`，确认输出的上游版本与清单一致；检查 `otool -L`，确保没有缺失的第三方动态库。
6. 运行 `xcodegen generate`，再用 `xcodebuild` 构建测试配置；检查生成的 app 中存在 `Contents/Helpers/sslocal`，并检查 app bundle identifier 仍为 `com.qiuyuzhou.ShadowsocksX-NG`。
7. 对 CI 构建的 helper/app 做递归签名验证；如果是无证书的 PR 构建，至少验证 bundle 结构和脚本顺序，Developer ID 相关断言放到发布任务。

### 6.2 Release job

发布任务必须使用 macOS arm64 runner，并在受保护环境中提供签名与公证凭据：

1. 重复执行清单、SHA-256、归档内容、架构和版本检查，不复用未验证的普通 CI workspace。
2. 通过 Xcode archive 生成 Release app；在 archive 的签名步骤中确认 helper 先签、app 后签。
3. 使用 Apple 建议的递归检查：

   ```sh
   codesign --verify --deep --strict --verbose=2 ShadowsocksX-NG.app
   spctl --assess --type exec --verbose=4 ShadowsocksX-NG.app
   ```

4. 用 `codesign --display --verbose=4` 检查 helper 和 app 的签名身份、Team ID、runtime option 和 secure timestamp；用 `lipo -archs` 再次确认最终 helper 仍是 arm64。
5. 将 app 放进最终分发形态（通常是 DMG 或 ZIP）后，使用 `xcrun notarytool submit ... --wait` 提交；无论提交成功与否都读取 `notarytool log`，对错误失败，对 warning 做人工审查。
6. 对可 staple 的 app/DMG 使用 `xcrun stapler staple` 和 `xcrun stapler validate`。Apple 明确说明不能直接对 ZIP staple；应先 staple ZIP 中的 app，再重新创建 ZIP。
7. 最后对重新生成的分发物做哈希、签名、Gatekeeper 和启动冒烟测试；签名或 staple 之后不得再修改 app bundle。

来源：

- [Apple：Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple：Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Apple：Resolving common notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)
- [TN2206：Checking Gatekeeper conformance](https://developer.apple.com/library/archive/technotes/tn2206/_index.html#//apple_ref/doc/uid/DTS10003709-CH1-SUBSECTION18)

### 6.3 “不构建上游源代码”的 CI 证据

CI 日志和脚本应能明确显示：

- 输入是一个固定 Release URL 和固定 SHA-256；
- 脚本执行的是下载、哈希校验、解压、架构/版本检查；
- 没有 `cargo build`、上游源码 checkout 或本仓库内的 Rust 构建步骤；
- 最终的本地构建只编译 SwiftUI GUI，并对下载的官方可执行文件执行复制和签名。

这样既满足“使用源项目直接提供的构建好的文件”，又使依赖升级、供应链完整性和最终 Apple 发布签名分别可审查。

## 7. 尚需后续票据决定的事项

本票据只决定外部二进制的取得、表示、签名和发布验证，不决定以下内容：

- `shadowsocks-rust` 配置文件中密码的生命周期和权限策略；
- per-user `launchd` plist 的具体 label、重启策略和 GUI 退出语义；
- 运行时是否为每次启动生成临时配置，以及配置文件删除时机；
- 是否提交/缓存解压后的官方二进制，还是每次在构建前下载；
- app 的 DMG/ZIP 制作工具和更新渠道。

这些事项应由后续票据分别决定；它们不改变本票据关于“官方 Release 资产、固定 SHA-256、`Contents/Helpers`、内向外签名和 CI/公证门槛”的结论。

