# Run unit tests without launching the app (hostless tests)

**Status**: accepted

## Context

The unit test bundle is a macOS unit-test bundle whose target depends on the application target, so xcodegen sets `TEST_HOST` and every `task test` run boots the full app executable as the test host before any test executes. The host process carries the production bundle identifier `com.qiuyuzhou.ShadowsocksX-NG2`. When the installed release app is running, a test run therefore creates a second same-identifier process: SwiftUI presents the 960×640 workspace window at launch (the silent-launch preference defaults to off), a second identical status item appears in the menu bar, and LaunchServices registers the DerivedData build path under the production identifier. A hermetic-composition guard (`ApplicationDependencies.isUnitTesting`) swapped in ephemeral stores and suppressed side effects at app startup, but it could not suppress the process itself, its scenes, or the LaunchServices registration, and it kept roughly 140 lines of test-only scaffolding inside the composition root.

Three production code paths resolved packaged resources through `Bundle.main` or the host process identity and therefore depended on the app being the test host: the built-in rule snapshots (`BuiltinRuleCatalog`, default `Bundle.main`), the LaunchDaemon plist fingerprint baseline (`SystemProxyHelperIdentity.launchDaemonPlistData`), and the XPC listener's expected client code-signing identifier (matching because the connecting process was the app itself). Tests that located embedded binaries used `Bundle.main.bundleURL`.

## Decision

Unit tests run hostless. A `ShadowsocksX-NG2Core` static-library target compiles the same sources as the application target (`App/` except the `@main` composition root `MainApp.swift`, plus `Domain/`) and keeps the module name `ShadowsocksX_NG2`, so every test file's `@testable import` is unchanged. Both test bundles depend on the Core target instead of the application target; xcodegen no longer emits `TEST_HOST`, and `xcodebuild test` builds the app but never launches it. The application target keeps compiling everything itself and renames its module to `ShadowsocksX_NG2App` so the two targets' swiftmodules do not collide in the shared products directory. Duplicated compilation follows the existing pattern in which the Agent and SystemProxyHelper targets compile shared `Domain/` files by path; Core is linked only by test targets and is never built by the release chain.

With the host gone, the composition-root test scaffolding is deleted outright rather than guarded: `isUnitTesting`, the testing dependency composition, the noop services, and the ephemeral stores. The app process can no longer run under XCTest, so the guards have no trigger condition.

Packaged-resource lookups become explicit seams instead of `Bundle.main` reads. The controller gains an `appBundle` dependency (production default `Bundle.main`) that both the rule-snapshot loader and the LaunchDaemon plist fingerprint use; the plist reader becomes `launchDaemonPlistData(in:)`. The XPC listener delegate takes its expected client identifier as an injected value (production default remains the 2.0 bundle identifier), and the round-trip test supplies its own process identifier obtained through the same SecCode query the validator uses. Tests locate the built app product through a shared `AppArtifact` helper that walks upward from the test bundle's on-disk location looking for `ShadowsocksX-NG2.app`; this works both while a host embeds the test bundle in `Contents/PlugIns/` and after, when the test bundle and the app sit as siblings in `Build/Products/<config>/`. Bundle-identity assertions in `SkeletonTests` read the located product's `Info.plist` instead of `Bundle.main`.

## Consequences

A test run no longer creates any process with the production bundle identifier, so it cannot collide with a running installed app: no window, no status item, no LaunchServices registration, no focus stealing. Test failures caused by host side effects are structurally impossible rather than guarded against, and the composition root no longer carries test-only branches.

The cost is one extra compile of the shared sources whenever tests are built, and a convention to maintain: production code must not read `Bundle.main` for packaged resources that tests exercise — such lookups go through the `appBundle` seam (or another explicit injection), with `Bundle.main` only as the production default. Tests that need app-bundle content must use `AppArtifact`, never `Bundle.main`, which is the xctest runner's bundle. The XPC listener's injected expected identifier is a test-only relaxation; the production default still accepts only the 2.0 bundle identifier.

This decision supersedes the hermetic test-host convention recorded during ADR-0017's implementation (the `isUnitTesting` startup guard), which existed only because the app was the test host.
