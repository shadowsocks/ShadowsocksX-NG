# ShadowsocksX-NG2

English | [简体中文](README.zh-CN.md)

ShadowsocksX-NG2 is a modern rewrite of ShadowsocksX-NG for macOS 15+ and Apple Silicon (arm64). Its source code and build configuration are in this directory. The archived legacy version is described on the [repository home page](../README.md#旧版归档).

The app uses upstream releases of `sslocal`, `v2ray-plugin`, and Cloak `ck-client`. HTTP inbound traffic is handled directly by shadowsocks-rust; Legacy Privoxy is no longer bundled.

## Development, build, and test

Install the Xcode/Swift toolchain, [Task](https://taskfile.dev/), [XcodeGen](https://github.com/yonaskolb/XcodeGen), and SwiftLint. See the [development guide](../docs/development.md#code-style-tools) for tool versions and installation instructions.

From this directory, fetch the external binaries before generating the Xcode project for the first build:

```bash
Scripts/fetch-external-binaries.sh
task gen:prj
task build
```

Debug builds use ad-hoc signing by default and do not require a certificate. See [Signing and distribution](../docs/distribution.md) for Developer ID configuration and release requirements. `project.yml` is the source of truth for project settings; the generated `.xcodeproj` is not checked in.

Run the unified validation workflow from the repository root:

```bash
task --exit-code --taskfile ShadowsocksX-NG2/Taskfile.dist.yml validate
# Run only the requested stages, in the specified order:
task --exit-code --taskfile ShadowsocksX-NG2/Taskfile.dist.yml validate -- lint test
```

The default order is `lint → test → test:smoke → build`; execution stops on the first failure. Logs and results are saved in `ShadowsocksX-NG2/.build/validation/`. From this directory, you can run `task --exit-code validate`. See the [development guide](../docs/development.md) for individual tasks, evidence, and test boundaries.

## Documentation

| Document | Contents |
| --- | --- |
| [Development, build, and test](../docs/development.md) | Validation entry points and artifacts, individual tasks, code style tools, Git hooks, and document language |
| [Project structure and source search](../docs/project-structure.md) | Source layers, test directories, cross-target file constraints, and search methods |
| [External binaries, signing, and distribution](../docs/distribution.md) | Supply-chain checks, Debug/Release signing, release requirements, and dependency updates |
| [Bundled rule snapshots](../docs/rule-snapshots.md) | Sources, conversion semantics, maintenance scripts, and offline checks |
| [Subscriptions, plugins, and listener configuration](../docs/configuration.md) | Subscription data, user plugins, Cloak, local and LAN listeners, and configuration recovery |
| [Server library encryption format](../docs/server-library-encryption-format.md) | Encrypted file format and external decryption contract |

The [glossary](../GLOSSARY.md) and [architecture decision records](../docs/adr/) are maintained in Simplified Chinese and describe domain terminology and accepted designs. `docs/design/` and `docs/research/` are historical design and research records. Use the current code as the source of truth for implementation behavior.
