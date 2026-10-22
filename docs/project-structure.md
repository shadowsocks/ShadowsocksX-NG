# Project Structure and Source Search

[Project home](../ShadowsocksX-NG2/README.md) | [简体中文](project-structure.zh.md)

Unless noted otherwise, run commands from `ShadowsocksX-NG2/`; paths in this document are relative to that directory.

## Project structure

- `project.yml` — XcodeGen project definition and single source of truth. `.xcodeproj`, `App/Resources/Info.plist`, `*.entitlements`, and `Tests/Info.plist` are generated and gitignored. Change the project structure in `project.yml`, then regenerate the project.
- `App/` — app target source code (a SwiftUI menu bar app with `LSUIElement`). Directories define layers; files within each layer are grouped by feature:
  - `Composition/` — composition root and process lifecycle: `@main`, dependency assembly, app form, and window activation strategy.
  - `Application/` — application layer without SwiftUI views: `*Workflow/` workflow modules (UI-facing interfaces and implementation collaborators), the `ProxyRuntime/` runtime-controller family and fact projections, and `Services/` for LaunchAgent, login item, helper, and firewall.
  - `Presentation/` — cross-feature presentation: error presentation and state models shared by multiple views.
  - `UI/` — view layer, organized by subview (`Workspace/`, `Home/`, `Servers/`, `Subscriptions/`, `Rules/`, `Settings/`, `Diagnostics/`, and `StatusMenu/`); `Servers/Plugin/` contains plugin-management views.
  - `PlatformEffects/` — platform-effect seams (protocols and AppKit adapters; test doubles are in `Tests/Support/`); access to system frameworks is centralized here.
  - `Resources/` — generated `Info.plist` and entitlements, plus checked-in `Assets.xcassets` and `*.xcstrings`.

  `Tests/Architecture/SkeletonTests.swift` enforces layer boundaries with an allowlist guard that scans only `App/UI/`. The view layer must not reference runtime controllers, workflow implementation collaborators, or raw directory/credential storage types. New runtime adapters belong in `Application/`, which is outside the scan scope and needs no exemption. Note that XcodeGen includes any non-source file under `App/` in the Resources build phase and signs it into the bundle, so do not put documents there (`project.yml` excludes `**/*.md`). See [ADR-0029](adr/0029-source-layout-declares-layer-and-theme.md) for the layer and theme organization, why the guard uses an allowlist, and the XcodeGen constraint.
- `Agent/` — standalone background-supervision executable, installed in `Contents/MacOS/` and kept running by a LaunchAgent. It reads only non-secret `agent-supervision.json`, switches stable configuration and ACL links, and launches and supervises `sslocal`; it does not parse sslocal configuration or LAN credentials. See ADR-0037 and ADR-0038 for release and failure handling, and ADR-0043 for one-way configuration output from the GUI.
- `LaunchAgent/` — registration manifest for `SMAppService.agent(plistName:)`, installed in `Contents/Library/LaunchAgents/`. `ProgramArguments` uses bundle-relative paths, which launchd resolves from the registered app's bundle location.
- `Domain/` — domain core for the configuration catalog tree, credential references, and persistence (spec #21 D3/D5), independent of the UI. Directories define topics; there are no flat files at the root. Child-directory boundaries follow the sections in the [glossary](../GLOSSARY.md):
  - `Catalog/` — configuration catalog tree, structural invariant errors, catalog file storage, node and credential identities, and `SsUri` for `ss://` encoding and decoding.
  - `Subscription/` — subscription document parsing, fetching, subscription records, and refresh failures.
  - `Rules/` — proxy modes, rule identity and matching, bundled rule snapshots, rule collections/browsing/analysis, and offline rule tests; `Rules/Custom/` contains edit drafts, validation, and storage for user-defined rules.
  - `Runtime/` — proxy runtime services: runtime documents and listener settings, ACLs and deployment receipts, paths, atomic writes, file storage, logs and events (`SystemLog` unified-log emitter, `LogLine` unified-log line, and sslocal-output intake), plus endpoint/port/socket probes.
  - `Activation/` — activation-candidate validation, activation state machine, and `RuntimeConfiguration`.
  - `Settings/` — proxy-listening configuration file, independent proxy-control preferences, in-memory snapshots of runtime calculations, and silent-launch preference.
  - `SystemProxy/` — typed system-proxy configuration, property-list mapping, planner, privileged-helper XPC contract/request engine, and helper-side log events.
  - `Plugin/` — managed plugins, user-plugin mappings, and plugin security inspection.
  - `Credentials/`, `LegacyImport/`, and `Diagnostics/` — master-key storage and encrypted-file commits, legacy import, and diagnostic reports.

  Cross-process contracts are compiled into other targets file by file: nine files from `Runtime/` and `Settings/ApplicationSupportPaths.swift` are also compiled into the wrapper (`RuntimePaths`, `RuntimeSupervision`, `RuntimeLog`, `SystemLog`, `LogLine`, `SslocalOutputIntake`, and others); all seven files from `SystemProxy/`, together with `Runtime/SystemLog.swift`, are compiled into the privileged helper (helper logs go only to the unified log; see ADR-0047). These 18 entries are explicit paths in `project.yml`. Moving a file under `Domain/` requires updating the project definition too; otherwise, `xcodegen generate` fails immediately because a file is missing. The layout guard (`DomainLayoutTests` in `Tests/Architecture/SkeletonTests.swift`) asserts that there are no flat `.swift` files at the root and that the tree contains only `.swift` files. XcodeGen would otherwise include non-source files in the Resources build phase and sign them into the bundle.
- `Tests/` — unit-test target, run with the `ShadowsocksX-NG2` scheme. Directories define topics; there are no flat test files at the root:
  - `Architecture/` — guards for cross-cutting project constraints (layers and layout, platform-effect seams, window entry points, and manifest completeness). They scan source or build artifacts without driving behavior.
  - `TestSupport/` — regression tests for test-wait and cleanup helpers.
  - `Support/` — fixtures, doubles, and helpers, with no test cases (`CatalogFixtures`, `ProxyRuntimeFixture`, `SystemProxyFakes`, `AppArtifact`, `TestSourceTree`, and others).
  - `Agent/`, `Activation/`, `Catalog/` (workflow tests are in `Catalog/Workflow/`), `Subscription/`, `Rules/` (custom rules are in `Rules/Custom/`), `ProxyRuntime/`, `ProxyControl/`, `Runtime/`, `Settings/`, `SystemProxy/`, `Plugin/`, `Diagnostics/`, `Credentials/`, `Workspace/`, and `Servers/` — feature-domain tests aligned with production domain topics and `*Workflow` boundaries.
  - `Smoke/` — real-process smoke tests in a separate target and scheme (`task test:smoke`).
  - `Fixtures/RuleSnapshots/` — generated fixtures for bundled rule snapshots, distributed as folder resources in the test bundle and read by `GeneratedRuleSnapshotTests` with `subdirectory:`.

  When an assertion needs to read the source tree (`Vendor/` manifests, `App/`, or `Domain/`), use `Support/TestSourceTree.swift` to locate `ShadowsocksX-NG2/` by walking up from `#filePath`. Do not hard-code the number of parent directories: test files are at different depths, and a move could make the path silently point elsewhere. `TestsLayoutTests` only asserts that there are no flat `.swift` files at the root. This is weaker than the `Domain/` guard because the root `Info.plist` and JSON under `Fixtures/` are required. `Tests/Support/AppArtifact.swift` is also compiled into the Smoke target and is an explicit file path in `project.yml`; update it when moving the file.
- `Vendor/<name>/manifest.json` — pinned supply-chain manifest for an external binary (tag, asset URL, asset SHA-256, location inside the bundle, and signing identifier). The binary itself and `.fetched.sha256` stamp are build cache and are not checked in.
- `Vendor/rules/geolocation-cn/` — bundled snapshot of Chinese domain rules (issue #63): `snapshot.json` (normalized rules, metadata, and loss report), `manifest.json` (upstream version and snapshot SHA-256), and `NOTICE` (license and attribution). Normal builds read only the local snapshot; they never fetch or convert rules.
- `Vendor/rules/china-ipv4/` — bundled snapshot of Chinese IPv4 CIDRs considered for direct routing (issue #64): the same three files, sourced from a pinned commit of `china.txt` in [gaoyifan/china-operator-ip](https://github.com/gaoyifan/china-operator-ip). The rule-mode `proxy_all` ACL includes both Chinese-domain and IPv4-CIDR direct-routing candidates.
- `Vendor/rules/gfwlist/` — bundled snapshot of GFWList proxy candidates (issue #65): the same three files, sourced from the official Base64 AutoProxy `gfwlist.txt` in [gfwlist/gfwlist](https://github.com/gfwlist/gfwlist) at a pinned commit. Domain anchors are converted to suffix matching. Eligible URL prefixes with an empty or root path are converted to exact-domain matching. The `bypass_all` ACL for “direct when unmatched” includes these proxy candidates.
- `Scripts/` — supply-chain scripts (see [External binary supply chain](distribution.md#external-binary-supply-chain)) and packaging-gate assertions. `update-geolocation-cn.sh`, `update-china-ipv4.sh`, and `update-gfwlist.sh` are explicit maintenance actions that fetch pinned upstream versions and convert them. `verify-rule-snapshots.sh` checks snapshot integrity offline before a build.

## Source search

First use `rg --files` to locate files based on the directory layers above, then search content in the relevant directory or file type. If there are no matches, expand the search gradually. Run these commands from `ShadowsocksX-NG2/`:

```sh
# Find the external-binary version and source by locating its manifest first.
rg --files Vendor/sslocal -g 'manifest.json'
# Search relevant Swift source for runtime responsibilities.
rg -n -g '*.swift' 'sslocal|reload' Agent Domain/Runtime App/Application/ProxyRuntime
# List files matching a rule term before displaying matches.
rg -l 'keyword' Vendor/rules Tests/Fixtures/RuleSnapshots
# Display matching lines while limiting long lines and retaining match context.
rg -n -M 300 'keyword' Vendor/rules
```

`Vendor/rules/*/snapshot.json` and `Tests/Fixtures/RuleSnapshots/*.json` are generated, single-line JSON files. `-M 300` limits the displayed length of a line in bytes; it does not limit total output. `-m` and `head -n` limit line counts but do not prevent one long line from producing too much output. To inspect complete rules, locate the specific snapshot and read the relevant JSON fields. Manifests and `NOTICE` files remain in their respective `Vendor` directories and can be searched separately as needed.
