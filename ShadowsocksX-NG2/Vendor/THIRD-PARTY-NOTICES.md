# 已分发组件的传递依赖许可材料

`sslocal/THIRD-PARTY-NOTICES`、`v2ray-plugin/THIRD-PARTY-NOTICES`、`ck-client/THIRD-PARTY-NOTICES` 和 `AgeSwift/THIRD-PARTY-NOTICES` 按实际分发组件列出传递依赖。完整许可文本按 SPDX 标识集中保存在 `third-party-licenses/<SPDX-ID>.txt`；各组件声明只保留依赖分组、版权/归属信息和必须单独保留的 NOTICE 或例外条款。因此，同一种许可文本只维护一份，不按 crate/module 重复复制。

## 覆盖基线

- 组件版本的唯一依据是同目录的 `manifest.json`，或 Xcode 工程共享的 SwiftPM `Package.resolved`。每份组件声明同时记录对应上游源码修订；不要在此目录另建传递依赖版本表。
- `sslocal` 按其发布工作流的 `full` 特性和已分发的 `aarch64-apple-darwin` 目标检查。Cargo build/dev-only 和仅用于生成代码的 proc-macro 依赖不计入。
- AgeSwift 按锁定的 `Rust/age-swift-ffi` 依赖图和 XCFramework 的 arm64、x86_64 macOS 目标检查；AgeSwift 本身及其 FFI crate 是直接组件，不列入传递依赖组。
- Go 组件按实际二进制入口运行 `go-licenses`，并用 `go version -m` 核对二进制记录的 Go 版本、目标、模块图和源码修订。Go 标准库许可不由 `go-licenses` 输出，所以另按二进制所用的 Go 版本加入共享 BSD-3-Clause 文本及 Go Authors 归属。
- Go YAML 的独立 NOTICE、Go 标准库和其他同 SPDX 标识但措辞不同的条件、Cloak `juju/ratelimit` 的 LGPL-3.0 链接例外、Rust/AWS-LC 组件的额外 NOTICE/COPYRIGHT，以及 Cloak 内嵌 ecdh 归属均单独保留；不能用共享 SPDX 文本替代这些材料。
- 系统框架/系统库、开发与测试工具、用户自行安装的插件，以及没有随应用分发的规则数据不在此传递代码依赖清单内。规则数据的直接声明仍由其自身 NOTICE 管理。

以上是基于当前二进制和锁定源码图的覆盖说明，不构成完整法律审计，也不能证明没有遗漏。`go-licenses` 对非 Go 文件及无法解析的来源 URL 会发出警告；更新时须检查相应源码目录及 LICENSE/NOTICE 文件，不能把工具输出视为完整性证明。

## 更新流程

更新只在维护者工作站执行；正常应用构建不得联网下载许可材料。

1. 从已有 manifest 或 `Package.resolved` 解析已分发组件的版本和来源。取对应标签/修订的源码，并用 `go version -m`、发布工作流及构建目标确认源码图和二进制一致。
2. 使用固定版本的 `cargo-about`（0.9.2）和本目录的 `cargo-about.toml` 生成 Rust 原始报告。示例：

   ```sh
   cargo about generate --format json --config ShadowsocksX-NG2/Vendor/cargo-about.toml \
     --manifest-path /path/to/shadowsocks-rust/Cargo.toml \
     --target aarch64-apple-darwin --features full --locked --fail \
     > /tmp/sslocal-about.json

   cargo about generate --format json --config ShadowsocksX-NG2/Vendor/cargo-about.toml \
     --manifest-path /path/to/AgeSwift/Rust/age-swift-ffi/Cargo.toml \
     --target aarch64-apple-darwin x86_64-apple-darwin --locked --fail \
     > /tmp/ageswift-about.json
   ```

   Cargo-about 用于生成许可候选报告；组件范围以对应 Cargo 目标图为准。再用 `cargo tree --edges normal,no-proc-macro` 排除 build/dev-only 和仅由 proc-macro 使用的包，并从候选报告排除直接组件、workspace crate 和不在该图中的 crate。示例：

   ```sh
   cargo tree --manifest-path /path/to/shadowsocks-rust/Cargo.toml \
     --features full --target aarch64-apple-darwin --edges normal,no-proc-macro
   cargo tree --manifest-path /path/to/AgeSwift/Rust/age-swift-ffi/Cargo.toml \
     --target aarch64-apple-darwin --edges normal,no-proc-macro
   cargo tree --manifest-path /path/to/AgeSwift/Rust/age-swift-ffi/Cargo.toml \
     --target x86_64-apple-darwin --edges normal,no-proc-macro
   ```

   对每个 SPDX 标识复用一份完整文本；保留每个已纳入组件的版权行和额外 NOTICE/COPYRIGHT。
3. 使用固定版本的 `go-licenses`（`github.com/google/go-licenses/v2@v2.0.1`），分别从 v2ray-plugin 根包及 Cloak `./cmd/ck-client` 生成 `report` 和 `save` 输出。例：

   ```sh
   cd /path/to/v2ray-plugin
   GOPROXY=off go-licenses report . > /tmp/v2ray-plugin.csv
   GOPROXY=off go-licenses save . --save_path /tmp/v2ray-plugin-notices

   cd /path/to/Cloak
   GOPROXY=off go-licenses report ./cmd/ck-client > /tmp/ck-client.csv
   GOPROXY=off go-licenses save ./cmd/ck-client --save_path /tmp/ck-client-notices
   ```

   按 `report` 中的 SPDX 类型归组；从实际二进制 Go 版本对应的 Go 源码 `LICENSE` 核对 Go 标准库文本和归属。不要把直接产品本身的许可混进传递依赖组。
4. 比较报告中的许可类型及组件名与现有分组。只有在类型尚未出现时才新增共享文本；相同 SPDX 标识不得复制完整正文。检查所有额外 NOTICE、COPYRIGHT、许可选择分支、自定义例外（包括同 SPDX 标识下不同的条件/免责声明措辞）和非 Go 源码；把新增材料放入 `third-party-licenses/additional-notices/` 并在对应组件声明中引用。
5. 更新之后核对组件 pin、源码 revision、目标/feature、二进制构建信息及系统依赖边界；检查每个相对链接均指向离线存在的文件，再运行 `git diff --check`。只更新审阅后的本地静态材料，不能把扫描工具或网络下载加入正常构建步骤。上层 bundle 资源配置须同时复制这些声明和其引用的共享文本，并保留相对目录关系。生成与打包流程见 `DEPENDENCY-METADATA.md`。

工具文档：[`cargo-about`](https://github.com/EmbarkStudios/cargo-about)、[`go-licenses`](https://github.com/google/go-licenses)。二进制所用 Go 工具链的源许可可从对应 Go 标签的 [`LICENSE`](https://go.googlesource.com/go/+/refs/tags/go1.27.3/LICENSE) 核对；Cloak 当前二进制对应的 [Go 1.24.5 LICENSE](https://go.googlesource.com/go/+/refs/tags/go1.24.5/LICENSE) 也按同一方式核对。
