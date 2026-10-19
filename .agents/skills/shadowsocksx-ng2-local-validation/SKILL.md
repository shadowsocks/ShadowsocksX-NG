---
name: shadowsocksx-ng2-local-validation
description: Validate ShadowsocksX-NG2 changes and diagnose retained local validation results.
---

# ShadowsocksX-NG2 local validation

This repository copy is the maintained skill. Copies under `~/.codex/memories/skills/` are historical snapshots. Paths below are relative to the repository root unless stated otherwise.

## Select the evidence

1. Inspect the request, staged and unstaged diffs, `ShadowsocksX-NG2/AGENTS.md`, and relevant ADRs. Read `ShadowsocksX-NG2/README.md` for build/signing conventions and `ShadowsocksX-NG2/Taskfile.dist.yml` for current gate definitions.
2. Identify the requested level: focused tests, full hostless suite, real-process smoke, Debug/Release build, native/manual UI, or real system-proxy behavior. Retain that scope; documentation-only changes do not require repeating full suites.
3. For structural/resource changes, update authoritative `project.yml` and run `task gen:prj` from `ShadowsocksX-NG2/`; never hand-edit the generated project.

## Run the selected checks

- Work from `ShadowsocksX-NG2/`. For combined validation use `task --exit-code validate`. From another directory use `task --exit-code --taskfile /absolute/path/to/ShadowsocksX-NG2/Taskfile.dist.yml validate`.
- Default gates are `lint test test:smoke build`, executed in order with fail-fast behavior. To select a non-duplicated subset, append e.g. `-- lint test`. Diagnose the first failure; later selected gates are `not_run`, not skipped tests.
- `test` runs offline binary/rule checks before the hostless arm64 Xcode suite. Its Xcode test counts do not count those earlier checks. `test:smoke` uses the separate `ShadowsocksX-NG2Smoke` scheme and real processes. `build` is Debug; Release is a separate `task build:release` and is outside `validate`.
- Run focused tests when appropriate using the existing Xcode scheme and test selection; a focused Xcode run does not cover the preceding Taskfile checks. Use isolated derived data when needed. Follow the repository Debug ad-hoc signing baseline; Release requires Developer ID signing and has no unsigned fallback.
- `task format` and `task lint:fix` mutate source; use when requested or needed for the change, then inspect the diff. Current commands and options belong in Taskfile, not this skill.

## Read retained evidence

`validate` prints its run directory, `ShadowsocksX-NG2/.build/validation/<UTC>-<random>/`. Gate directories use the gate name with `:` replaced by `-` (`test:smoke` → `test-smoke/`). `task clean` removes these artifacts; copy them elsewhere if long-term retention is needed.

1. Read the run's `summary.txt` first. It records the overall exit code, selected gates, gate status/exit codes, test counts and evidence warnings. Per-gate `status.txt` supplies the same gate summary.
2. For failed Xcode tests, read that gate's `test-summary.json`, especially `testFailures`. Report each failing case using `testIdentifierString` (or `testName`) and its `failureText`. For example, `plutil -extract testFailures json -o - <gate-dir>/test-summary.json` reads the retained failures without reopening the result bundle.
3. If the summary is absent, unreadable, or insufficient, read the relevant diagnostics: `test-summary.stderr.log` for extraction failure, `count-reader.log` for invalid counts, and `raw.log` for gate output, pre-Xcode failures, build/lint errors, or missing context. Query `result.xcresult` only for unresolved detail. When retained summaries answer the question, do not repeat `xcresulttool` extraction.
4. Keep command outcome and evidence completeness separate. `validate:result` writes the original gate exit code; summary extraction does not replace it. A missing result bundle or unreadable/invalid test summary means `evidence incomplete` and unknown counts, never zero counts or an inferred pass. `validate:summary` preserves the overall exit code and marks unexecuted selected gates `not_run`. Build has no test-count summary; lint has no xcresult requirement.

## Diagnose within the evidence boundary

- If XcodeGen reports `No project spec found`, check cwd. Permission failures in Xcode, macros, signing or Git may be environment boundaries: retry the unchanged command through authorized macOS execution before changing source. Distinguish missing Release signing configuration from source failure.
- Preserve assertions and default parallel execution when investigating flakes. Prefer deterministic readiness and explicit fixture release, cancellation and drainage over extra sleeps or increased timeouts. For parallelism claims, inspect runner evidence; configuration alone does not prove concurrent execution.
- For connectivity/latency smoke, verify listener ownership by the spawned process (`RuntimeSocketOwnershipProbe` or its current equivalent), response-header deadlines, and process-group/temp-environment cleanup. Use local DNS/loopback fixtures and proxy-egress observations where routing assertions require them.
- Keep inherited XCTest `test*` methods out of shared fixture bases to avoid duplicate execution. Measure slow rule/runtime segments before adding delay injection.
- Hostless tests, real-process smoke, native/manual UI, and real system-proxy acceptance are separate evidence levels. Hostless/smoke success does not establish SystemConfiguration writes, helper approval, notification behavior, or visual acceptance.

## Finish

Inspect staged and unstaged diffs and run `git diff --check`. Report the actual commands, run directory, exit codes, counts in Xcode's summary convention (parameterized executions may differ), warnings, evidence gaps, and omitted acceptance levels. Commit locally only when requested; push only with explicit authorization.
