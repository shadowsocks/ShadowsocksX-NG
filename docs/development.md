# Development, Build, and Testing

[Project home](../ShadowsocksX-NG2/README.md) | [简体中文](development.zh.md)

Unless noted otherwise, run commands from `ShadowsocksX-NG2/`; paths in this document are relative to that directory.

## Unified validation

Run the unified validation workflow from the repository root:

```bash
task --exit-code --taskfile ShadowsocksX-NG2/Taskfile.dist.yml validate
# Run only the requested stages, in the specified order:
task --exit-code --taskfile ShadowsocksX-NG2/Taskfile.dist.yml validate -- format:check lint test
```

From the project directory, use `task --exit-code validate`. From any directory, use `task --exit-code --taskfile /path/to/ShadowsocksX-NG/ShadowsocksX-NG2/Taskfile.dist.yml validate`. The entry point locates the project directory relative to the Taskfile and invokes individual tasks from the distribution Taskfile.

By default, stages run in this order: `lint → test → build`. Real-process smoke tests remain available as the explicit `test:smoke` stage. Formatting is not part of the default validation loop; pre-commit controls local formatting, and CI invokes `task format:check` separately on the Xcode 27 arm64 runner to match the Swift 6.4 formatter baseline. You can select a subset in a specified order; each stage can appear at most once. Execution stops on the first failure, marks later stages `not_run`, and exits nonzero. `--exit-code` makes Task pass through the stage's exit code. Without it, Task still exits nonzero but may use its own error code. The entry point does not retry automatically, change test parallelism, or run formatters that modify source files.

### Validation artifacts and evidence

Each local `validate` run creates a separate `.build/validation/<UTC time>-<random suffix>/` directory and prints its absolute path at the start and end. `summary.txt` records each stage's status, exit code, and evidence status. For every executed stage, the corresponding subdirectory contains a combined stdout/stderr `raw.log` and a `status.txt` (`test:smoke` uses `test-smoke/`); Xcode stages also save `result.xcresult`. The console shows progress and a summary. Read the corresponding logs for complete errors. All artifacts are inside existing ignored directories. `task clean` deletes them, so copy anything you need to keep.

CI runs two independent matrix jobs: `test` and `test:smoke`, with fail-fast disabled. Both run through `task --exit-code validate STRICT=true -- <gate>` and treat compiler warnings as errors. The `test` job also checks formatting, runs lint, and builds. Failed jobs upload retained validation logs, summaries, and result bundles for seven days. Read the uploaded `summary.txt` and `test-summary.json` first; test output is retained in `raw.log`.

For test stages, the workflow uses the local `xcrun xcresulttool get test-results summary` and system `plutil` to read test counts on a best-effort basis; it adds no scripts or tool dependencies. `test-summary.json` stores the raw summary, `test-summary.stderr.log` stores xcresulttool errors, and `count-reader.log` stores count-reading errors. The summary shows passed, failed, skipped, expected-failure, and total counts using Xcode's summary semantics; parameterized tests may have a different actual execution count. Stage and overall exit codes come from the original command, and a failed command always remains a failure. A missing result bundle or unreadable summary is marked `evidence incomplete`, with counts shown as unknown. This does not change the command result, and missing counts are never reported as zero. Build stages do not read test counts; a stage that did not run is not the same as a skipped test.

A successful unified run means the selected stage commands passed; still check that the evidence is complete. Acceptance boundaries remain separate for hostless tests, real-process smoke tests, native UI, and the real system proxy. See [Signing and distribution](distribution.md#release-gate) for release packaging requirements.

`task test` and `task test:smoke` explicitly enable the Xcode per-test timeout: 120 seconds by default, with a 300-second maximum. This is a runner fallback. It does not guarantee normal test-task cleanup and is not a performance threshold. If a rule-stage wait fails, the test body throws and exits. Protected test tasks release their fixtures before cancellation and wait for task completion. Rule-delay gates and synchronous blocking fixtures have a default wait limit of 10 seconds and must report a failure on timeout. The shared `AsyncGate` preserves cancellation semantics controlled by each test. Swift Testing detached-worker timeout reports retain the creating test's name and source location. Check both the command exit code and test counts; a passing count for one test alone does not establish success.

## Common tasks

For routine formatting, static checks, project generation, builds, and tests, prefer the tasks defined in `Taskfile.dist.yml` and run them from the project directory:

```bash
task format
task format:check  # Check formatting without modifying source files.
task lint
task lint:fix  # Use for automatic SwiftLint fixes; run task lint afterward.
task gen:prj   # Generate the Xcode project.
task build     # Build the Debug app.
task test      # Run unit tests (without real-process smoke tests).
task test STRICT=true   # Treat Swift and Clang compiler warnings as errors.
task build STRICT=true  # Build the Debug app with the same strict policy.
task test:smoke  # Run real-process smoke tests (launches real sslocal; see the release gate in the signing and distribution guide).
```

`STRICT=true` enables `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` and `GCC_TREAT_WARNINGS_AS_ERRORS=YES` for `test` and `build`. It also sets `SWIFT_SUPPRESS_WARNINGS=NO` to avoid conflicting Swift compiler options in package dependencies, whose warnings are checked too. It is opt-in; omitted or `STRICT=false` preserves the project's warning policy. The validation wrapper forwards this option: `task --exit-code validate STRICT=true -- test build`. Diagnostics explicitly suppressed with `@diagnose` remain suppressed. Xcode tool messages, such as AppIntents metadata warnings, are outside this compiler policy.

`task format` formats Swift files under `App/`, `Tests/`, `Domain/`, and `Agent/`. `task format:check` runs the same configuration in strict, read-only mode. `task lint:fix` modifies source files; inspect and review the diff afterward.

## First-time setup and test scope

After a fresh clone or a manifest change, fetch the external binaries before generating the project. Run these commands from the project directory, in this order:

```bash
Scripts/fetch-external-binaries.sh
task gen:prj
```

Swift Package Manager resolves the pinned release of AgeSwift from `project.yml` and verifies its release XCFramework. Network access is needed for the first resolution; consumers do not need to install Rust. `Vendor/AgeSwift/LICENSE-MIT` comes from the pinned release and is bundled in the app at `Resources/ThirdParty/AgeSwift/`. Encryption-storage interoperability tests also require `brew install age` and an accessible login keychain. Tests use a UUID-isolated service and clean it up without changing real app configuration. See the [encryption format guide](server-library-encryption-format.md) for command-line debugging.

You can build and run unit tests without a certificate: the Debug baseline uses ad-hoc signing and does not require `Configs/Signing.local.xcconfig`. Create that file only when signing with Developer ID, either for release or to make a local Debug build pass the packaging gate. See [Signing and runtime baseline](distribution.md#signing-and-runtime-baseline) for its contents.

`Tests/Smoke/` contains real-process smoke tests. A wrapper launches real `sslocal` to verify startup, handshake, ACL routing, and plugin supervision. Agent lifecycle tests use the packaged Agent with shell stubs to verify signals, restart ordering, startup deadlines, and persisted failures. Connectivity runtime cleanup tests also run here. These tests are not part of the default `task test`; run them locally with their separate scheme. CI runs them as an independent job. Pending reload-signal accumulation is tested without child processes in `RuntimeReloadStateTests`; real signal delivery and combined server/ACL routing remain covered by `RuntimePublicationSmokeTests`.

## Writing and optimizing tests

### Hostless tests and packaged resources

Unit tests run without the app as a host ([ADR-0021](adr/0021-hostless-unit-tests.md)):

- Tests that need the app product, such as embedded binaries or packaged `Info.plist` assertions, locate it through `Tests/Support/AppArtifact.swift`.
- Production code reads packaged resources, such as rule snapshots and LaunchDaemon manifests, through explicit dependency injection. Controllers use an `appBundle` parameter with `Bundle.main` as the production default; test fixtures inject `AppArtifact.bundle`.

See ADR-0021 for the background and the three resource seams.

### Test framework and isolation

- Use Swift Testing (`import Testing`) for new tests by default. UI and performance tests continue to use XCTest for its exclusive APIs (`XCUIApplication` and `measure`). Existing XCTest cases stay in XCTest.
- Unit tests run in parallel across multiple runners. New fixtures use process-private resources: dynamically allocated ports, temporary directories, and UUID-suffixed namespaces instead of shared paths or fixed names.

### Fixtures and execution cost

- Choose input size from the assertion's purpose. Behavior integration tests for starting, stopping, saving, deploying, rolling back, and state projection use small deterministic inputs while retaining the real workflow and compilation path. Prefer `ProxyRuntimeFixture.controlFlowRuleSnapshot` for rule behavior fixtures.
- Dedicated tests for packaged resources, complete rule semantics, large-data boundaries, or performance explicitly inject complete data. Behavior tests reduce inputs through rule-data injection; retain `AppArtifact.bundle` when packaged resources such as manifests are still needed.
- Small fixtures preserve scenario relationships, including overrides, shadowing, disabled entries, and orphaned records. Keep unrelated domains in shared fixtures outside the test's own rules, so accidental absorption or duplication does not turn an expected deployment into a no-op. Test doubles implement lifecycle behavior required by the tested workflow, including registration, exit, and receipts.
- Observe asynchronous interleaving with expectations, gates, or controllable clocks. Shorten production delays unrelated to assertions through injection. Preserve timeouts, health windows, process-supervision waits, and data boundaries that a case deliberately tests.
- Split existing XCTest cases by behavior into concrete classes that can be scheduled independently. Shared fixture base classes contain only state and factories; keep `test*` methods in concrete classes to avoid inherited cases running more than once. After splitting classes or changing fixtures, compare test inventories for omissions, duplicates, and newly skipped cases.
- Before optimizing duration, record the full-suite wall time and the slowest classes and cases under the same configuration. Then measure individual segments to distinguish computation from waiting. First remove repeated computation outside the test's purpose; then assess parallel scheduling through class splits or separate production performance changes. Summed case durations divided by wall time measure execution overlap, not CPU utilization.

## Code style tools

- `swift format` is included with the Xcode/Swift toolchain and does not need a separate installation (baseline: Apple Swift 6.4). Install SwiftLint with `brew install swiftlint` (baseline: 0.65.0), and install the hook manager with `brew install pre-commit`. If a required tool is missing, pre-commit rejects a commit that contains NG2 Swift files.
- `.swift-format` is a snapshot of the Swift 6.4 toolchain's default rules, checked in so the rules do not drift on toolchain upgrades. `.swiftlint.yml` starts with the default rules and declares only exclusions and individual opt-outs that conflict with the format baseline; comments in the file show triggering examples.
- The repository-level hook configuration is `.pre-commit-config.yaml`. See [Development hooks](#development-hooks) for how to install it and what it checks.
- Adjust rules only to address concrete problems. A PR that changes `.swift-format` or `.swiftlint.yml` must include a triggering example and update the baseline versions in this section.

## Development hooks

After cloning, install the hooks from the repository root:

```bash
brew install pre-commit  # Skip if already installed.
pre-commit install
```

If you previously enabled the old `.githooks` setup, remove its local Git setting before installing the new hook:

```bash
git config --local --unset core.hooksPath
pre-commit install
```

The hooks run when a commit stages `.swift` files under `ShadowsocksX-NG2/`; other files are skipped. `swift format` formats those staged files in the working tree, and pre-commit stops that commit when formatting changes them. Review and stage the formatting changes, then commit again. The read-only `task format:check` hook then checks all NG2 Swift source directories, including lint-only rules the formatter cannot fix automatically. SwiftLint checks the staged files; errors reject the commit and warnings do not. If no NG2 Swift files are staged, these hooks are skipped. If NG2 Swift files are staged and a required tool is missing, the corresponding hook fails. See [Code style tools](#code-style-tools) for tool installation and versions.

## Language of domain documents

The project's [glossary](../GLOSSARY.md) and new [architecture decision records (ADRs)](adr/) are written in Simplified Chinese, while code identifiers and necessary English technical terms remain in English. Existing ADRs retain their original language and are not translated.

As AI generates more documents, communication between people and machines can become a collaboration bottleneck: people's reading, comprehension, and review speed determines whether documentation can support development effectively. Simplified Chinese reduces the cognitive load for maintainers and makes communication and review more efficient.
