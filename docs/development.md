# Development, Build, and Testing

[Project home](../ShadowsocksX-NG2/README.md) | [简体中文](development.zh-CN.md)

Unless noted otherwise, run commands from `ShadowsocksX-NG2/`; paths in this document are relative to that directory.

## Unified validation

Run the unified validation workflow from the repository root:

```bash
task --exit-code --taskfile ShadowsocksX-NG2/Taskfile.dist.yml validate
# Run only the requested stages, in the specified order:
task --exit-code --taskfile ShadowsocksX-NG2/Taskfile.dist.yml validate -- lint test
```

From the project directory, use `task --exit-code validate`. From any directory, use `task --exit-code --taskfile /path/to/ShadowsocksX-NG/ShadowsocksX-NG2/Taskfile.dist.yml validate`. The entry point locates the project directory relative to the Taskfile and invokes individual tasks from the distribution Taskfile.

By default, stages run in this order: `lint → test → test:smoke → build`. You can select a subset in a specified order; each stage can appear at most once. Execution stops on the first failure, marks later stages `not_run`, and exits nonzero. `--exit-code` makes Task pass through the stage's exit code. Without it, Task still exits nonzero but may use its own error code. The entry point does not retry automatically, change test parallelism, or run formatters that modify source files.

### Validation artifacts and evidence

Each run creates a separate `.build/validation/<UTC time>-<random suffix>/` directory and prints its absolute path at the start and end. `summary.txt` records each stage's status, exit code, and evidence status. For every executed stage, the corresponding subdirectory contains a combined stdout/stderr `raw.log` and a `status.txt` (`test:smoke` uses `test-smoke/`); Xcode stages also save `result.xcresult`. The console shows progress and a summary. Read the corresponding logs for complete errors. All artifacts are inside existing ignored directories. `task clean` deletes them, so copy anything you need to keep.

For test stages, the workflow uses the local `xcrun xcresulttool get test-results summary` and system `plutil` to read test counts on a best-effort basis; it adds no scripts or tool dependencies. `test-summary.json` stores the raw summary, `test-summary.stderr.log` stores xcresulttool errors, and `count-reader.log` stores count-reading errors. The summary shows passed, failed, skipped, expected-failure, and total counts using Xcode's summary semantics; parameterized tests may have a different actual execution count. Stage and overall exit codes come from the original command, and a failed command always remains a failure. A missing result bundle or unreadable summary is marked `evidence incomplete`, with counts shown as unknown. This does not change the command result, and missing counts are never reported as zero. Build stages do not read test counts; a stage that did not run is not the same as a skipped test.

A successful unified run means the selected stage commands passed; still check that the evidence is complete. Acceptance boundaries remain separate for hostless tests, real-process smoke tests, native UI, and the real system proxy. See [Signing and distribution](distribution.md#release-gate) for release packaging requirements.

`task test` and `task test:smoke` explicitly enable the Xcode per-test timeout: 120 seconds by default, with a 300-second maximum. This is a runner fallback. It does not guarantee normal test-task cleanup and is not a performance threshold. If a rule-stage wait fails, the test body throws and exits. Protected test tasks release their fixtures before cancellation and wait for task completion. Rule-delay gates and synchronous blocking fixtures have a default wait limit of 10 seconds and must report a failure on timeout. The shared `AsyncGate` preserves cancellation semantics controlled by each test. Swift Testing detached-worker timeout reports retain the creating test's name and source location. Check both the command exit code and test counts; a passing count for one test alone does not establish success.

## Common tasks

For routine formatting, static checks, project generation, builds, and tests, prefer the tasks defined in `Taskfile.dist.yml` and run them from the project directory:

```bash
task format
task lint
task lint:fix  # Use for automatic SwiftLint fixes; run task lint afterward.
task gen:prj   # Generate the Xcode project.
task build     # Build the Debug app.
task test      # Run unit tests (without real-process smoke tests).
task test:smoke  # Run real-process smoke tests (launches real sslocal; see the release gate in the signing and distribution guide).
```

`task format` formats Swift files under `App/`, `Tests/`, `Domain/`, and `Agent/`. `task lint:fix` modifies source files; inspect and review the diff afterward.

## First-time setup and test scope

After a fresh clone or a manifest change, fetch the external binaries before generating the project. Run these commands from the project directory, in this order:

```bash
Scripts/fetch-external-binaries.sh
task gen:prj
```

Swift Package Manager resolves the pinned release of AgeSwift from `project.yml` and verifies its release XCFramework. Network access is needed for the first resolution; consumers do not need to install Rust. `Vendor/AgeSwift/LICENSE-MIT` comes from the pinned release and is bundled in the app at `Resources/ThirdParty/AgeSwift/`. Encryption-storage interoperability tests also require `brew install age` and an accessible login keychain. Tests use a UUID-isolated service and clean it up without changing real app configuration. See the [encryption format guide](server-library-encryption-format.md) for command-line debugging.

You can build and run unit tests without a certificate: the Debug baseline uses ad-hoc signing and does not require `Configs/Signing.local.xcconfig`. Create that file only when signing with Developer ID, either for release or to make a local Debug build pass the packaging gate. See [Signing and runtime baseline](distribution.md#signing-and-runtime-baseline) for its contents.

`Tests/Smoke/` contains real-process smoke tests. A wrapper launches real `sslocal` to verify startup, handshake, ACL routing, and plugin supervision. These tests are not part of the default `task test`; run them on demand with their separate scheme.

## Code style tools

- `swift format` is included with the Xcode/Swift toolchain and does not need a separate installation (baseline: Apple Swift 6.4). Install SwiftLint with `brew install swiftlint` (baseline: 0.65.0). If either tool is missing, the pre-commit hook rejects a commit that contains Swift files under the project directory instead of allowing it.
- `.swift-format` is a snapshot of the Swift 6.4 toolchain's default rules, checked in so the rules do not drift on toolchain upgrades. `.swiftlint.yml` starts with the default rules and declares only exclusions and individual opt-outs that conflict with the format baseline; comments in the file show triggering examples.
- See [Development hooks](#development-hooks) for how to enable the repository-level `pre-commit` hook and what it checks.
- Adjust rules only to address concrete problems. A PR that changes `.swift-format` or `.swiftlint.yml` must include a triggering example and update the baseline versions in this section.

## Development hooks

After cloning, enable Git hooks from the repository root:

```bash
git config core.hooksPath .githooks
```

Once enabled, `pre-commit` checks only staged `.swift` files under `ShadowsocksX-NG2/`. `swift format` writes its result back to the index without changing the working tree. SwiftLint errors reject the commit; warnings are informational. Other files are skipped. If there are no NG2 Swift files, the hook passes. If NG2 Swift files are present and a required tool is missing, the check fails. Both checks distinguish “tool execution failed” from “issues found”: when you see “execution failed,” investigate the tool or configuration environment instead of changing code. See [Code style tools](#code-style-tools) for installation and versions.

## Language of domain documents

The project's [glossary](../GLOSSARY.md) and new [architecture decision records (ADRs)](adr/) are written in Simplified Chinese, while code identifiers and necessary English technical terms remain in English. Existing ADRs retain their original language and are not translated.

As AI generates more documents, communication between people and machines can become a collaboration bottleneck: people's reading, comprehension, and review speed determines whether documentation can support development effectively. Simplified Chinese reduces the cognitive load for maintainers and makes communication and review more efficient.
