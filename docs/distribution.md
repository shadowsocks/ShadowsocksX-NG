# External Binaries, Signing, and Distribution

[Project home](../ShadowsocksX-NG2/README.md) | [简体中文](distribution.zh-CN.md)

Unless noted otherwise, run commands from `ShadowsocksX-NG2/`; paths in this document are relative to that directory.

## External binary supply chain

External binaries come only from fixed-version upstream releases: the [`sslocal` manifest](../ShadowsocksX-NG2/Vendor/sslocal/manifest.json) (installed in `Contents/Helpers/`), the [`v2ray-plugin` manifest](../ShadowsocksX-NG2/Vendor/v2ray-plugin/manifest.json), and the [`ck-client` manifest](../ShadowsocksX-NG2/Vendor/ck-client/manifest.json) (both plugins are installed in `Contents/Helpers/Plugins/`). The manifests record each release and hash. The build pipeline is as follows (spec #21 D6/D10):

1. **fetch** — `Scripts/fetch-external-binaries.sh` downloads the asset from the URL pinned in its manifest, verifies `archiveSHA256` byte for byte, processes tar archives according to `assetFormat` (the default; extracts `archiveMember`) or copies a raw binary (`binary`), verifies arm64, places the result in `Vendor/<name>/`, and writes a stamp. A hash mismatch fails immediately. A changed local cache or manifest triggers an automatic download and re-verification.
2. **generate** — `xcodegen generate` adds each manifest binary as a Copy Files item under `Contents/Helpers[/Plugins]`. Order matters: **fetch before generate**. The files must exist when the project is generated; otherwise, the Copy Files phase may be silently omitted (or generation may report the missing file).
3. **verify on every build** — a pre-build script runs the fetch script again. On a cache hit, it quickly rechecks the local stamp. A hash or manifest change fails the build.
4. **sign** — in the post-build phase, `Scripts/sign-embedded-helpers.sh` re-signs every binary with Developer ID using `--options runtime --timestamp --identifier <manifest signIdentifier>` (plugin identifiers use the form `<bundle-id>.plugin.<name>`). Xcode then signs the outer app and seals the re-signed nested code.
5. **gate** — the built app must pass `Scripts/packaging-gate.sh <App.app>`. It strictly verifies nested-code signatures, requires Developer ID and Hardened Runtime on the main app with no App Sandbox entitlement, and checks manifest coverage for each binary (every Mach-O under Helpers must be in a manifest and pass Developer ID re-signing). Tampering with any binary is detected because its signature is invalid.

## Signing and runtime baseline

- Bundle ID: `com.qiuyuzhou.ShadowsocksX-NG2`, distinct from Legacy (`com.qiuyuzhou.ShadowsocksX-NG`). Runtime data is stored in `~/Library/Application Support/ShadowsocksX-NG2/`. The app targets macOS 15+ / arm64.
- Hardened Runtime is required for the Developer ID release path; ad-hoc Debug builds are exempt because they need no certificate (see the configuration below). App Sandbox is disabled, entitlements are an empty dictionary, and the signing style is fixed to `Manual`.
- **Certificates and Team IDs are not checked in** (this is an open-source repository). `project.yml` does not set `CODE_SIGN_IDENTITY` or `DEVELOPMENT_TEAM`; the project xcconfig injects both settings at build time according to the configuration:
  - The checked-in `Configs/Signing-Debug.xcconfig` baseline is **ad-hoc (`-`)**. A fresh clone and CI need no certificate to run `task build` or `task test`. On arm64, code must have at least an ad-hoc signature to load, so “no certificate” does not mean “unsigned.” Ad-hoc builds do not use Hardened Runtime (Xcode does not pass `-o runtime` for ad-hoc signing, as verified; the ad-hoc branch of `Scripts/sign-embedded-helpers.sh` does the same). Hardened Runtime is enforced by the Developer ID release path and packaging gate.
  - The checked-in `Configs/Signing-Release.xcconfig` baseline is **Developer ID Application**. Release artifacts must be signed; there is no certificate-free path.
  - Both configurations may optionally include `Configs/Signing.local.xcconfig` (gitignored). Developers with a certificate, including maintainers, can use it to set a local identity, for example to use Developer ID for Debug builds:

    ```bash
    cat > Configs/Signing.local.xcconfig <<'EOF'
    DEVELOPMENT_TEAM = YOUR_TEAM_ID
    CODE_SIGN_IDENTITY = Developer ID Application
    EOF
    ```

  - If this file is absent, Debug builds use ad-hoc signing and can run unit tests. Release builds fail explicitly in Xcode with “Signing for … requires selecting either a development team or a provisioning profile”; they do not silently fall back.
  - Test targets (unit and smoke tests) use the same baseline. After tests became hostless (ADR-0021), the xctest bundle no longer injects the host app and can load and run with ad-hoc signing (verified), so tests need no certificate.
  - If these two settings are added back to `project.yml`, the generated pbxproj build settings override the xcconfig. `Tests/Architecture/SigningConfigurationTests.swift` guards this constraint.
- The Release configuration disables `CODE_SIGN_INJECT_BASE_ENTITLEMENTS` so release entitlements come only from project files.
- The Release configuration passes `OTHER_CODE_SIGN_FLAGS = $(inherited) --timestamp` so Xcode requests secure timestamps for the main app and two native tools it signs. The packaging gate checks these timestamps before notarization upload; a timestamp on the DMG cannot replace timestamps on the executables inside it.

## Release gate

### Signed and notarized DMG

Run these commands from `ShadowsocksX-NG2/`. See above for initial external-binary setup and Developer ID signing configuration. The keychain must contain the matching certificate and private key.

First, use Apple's tool to save notarization credentials. This command interactively requests the app-specific password and stores the credentials in the keychain, not in the repository or Taskfile:

```bash
xcrun notarytool store-credentials shadowsocks-release \
  --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
```

Full release entry point:

```bash
task package NOTARY_PROFILE=shadowsocks-release \
  MARKETING_VERSION=2.1.0 CURRENT_PROJECT_VERSION=21
```

`task package`, `task build:release`, and `task i:release` require non-empty `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`; they do not use the project defaults. Supply parameters on the command line, through environment variables, or in a local `.env` file. They override only the current Release build and do not rewrite `project.yml`. `MARKETING_VERSION` accepts three dot-separated numbers, an optional `v` prefix, and an optional prerelease suffix beginning with `-`. Identifiers in the suffix use ASCII letters, digits, or hyphens and are separated by dots; examples include `v2.0.0-alpha-1`, `2.0.0-beta.2`, and `v2.0.0-rc.1`. `CURRENT_PROJECT_VERSION` accepts one to three dot-separated numbers. `package:notarize` reuses an existing DMG and does not require the version parameters again.

Example prerelease build:

```bash
task package NOTARY_PROFILE=shadowsocks-release \
  MARKETING_VERSION=v2.0.0-alpha-1 CURRENT_PROJECT_VERSION=22
```

The DMG filename retains the complete release version: `ShadowsocksX-NG2-v2.0.0-alpha-1-22-arm64.dmg`. Task extracts `2.0.0` and passes it to Xcode, so the app's `CFBundleShortVersionString` remains in Apple's three-number format. The prerelease suffix is not written to this field; prerelease builds inside the app are distinguished by the increasing `CURRENT_PROJECT_VERSION`. Continue incrementing the build number for every alpha, beta, rc, and final build.

`Taskfile.package.yml` orchestrates the flow: check notarization credentials → fetch external binaries → real-process smoke test → Release build → app packaging gate → create a compressed DMG → sign the DMG → notarize with Apple → staple the ticket → check signature, ticket, and Gatekeeper → publish to `dist/`. Builds support arm64 only. The DMG contains only the app and a shortcut to `/Applications`; it does not add a background image or depend on Finder automation.

The DMG is signed using the SHA-1 fingerprint of the certificate that actually signed the app, with a secure timestamp. Notarization uses only the keychain profile named by `NOTARY_PROFILE`. An example release artifact is `dist/ShadowsocksX-NG2-2.1.0-21-arm64.dmg`. The filename retains the supplied full release version. The build number is always read from the app's Info.plist. Before packaging, the numeric part of the release version is checked against the app version to prevent a mismatch between the filename and the version inside the app. If an artifact with the same name already exists, the process fails explicitly and does not overwrite it.

Before tool checks, notarization-credential checks, smoke tests, or builds, `package` checks for an existing artifact with the required versioned filename. Overwrite protection also remains in place when creating the disk image, notarizing, and publishing, to prevent concurrent packaging runs from overwriting one another.

Each build uses a separate `.build/packaging/run-*/` directory that retains the signed DMG, build artifacts, and smoke-test results. Each notarization uses `.build/notarization/run-*/` to retain the submission response, submission ID, wait results, and Apple's diagnostic logs. The console prints both directories. Submission and waiting are separate operations, so the submission ID remains available if waiting is interrupted. Notarization waits for up to 30 minutes; Apple may continue processing after the local wait ends.

After notarization fails, you can retry the retained signed DMG without rebuilding:

```bash
task package:notarize \
  DMG_PATH=/absolute/path/to/ShadowsocksX-NG2-2.1.0-21-arm64.dmg \
  NOTARY_PROFILE=shadowsocks-release
```

This entry point submits the DMG to Apple again. If only the wait timed out, query Apple with the retained submission ID first to avoid a duplicate submission:

```bash
xcrun notarytool info SUBMISSION_ID --keychain-profile shadowsocks-release
```

`package:notarize` staples the DMG ticket only after Apple returns `Accepted`. The complete file is published to `dist/` only after signature, ticket, and Gatekeeper checks pass. A failure does not publish a new file. This workflow staples a ticket to the DMG; it does not distribute a separate app. The retry entry point does not replace the smoke test or app packaging gate from the full release entry point; it accepts a signed DMG produced by that full flow.

`task clean` deletes intermediate artifacts and logs under `.build/` but preserves `dist/`. Both output locations are ignored by Git. This workflow does not upload a GitHub Release.

See Apple's [notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) and [software packaging for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution) for tool usage.

### Check an app separately

When a build artifact already exists, run the release gate separately:

```bash
# Release gate (both stages must pass): real-process smoke test and packaging gate.
task test:smoke
task build:release MARKETING_VERSION=2.1.0 CURRENT_PROJECT_VERSION=21
Scripts/packaging-gate.sh \
  .build/derivedData/Build/Products/Release/ShadowsocksX-NG2.app
```

The packaging gate accepts only Developer ID-signed artifacts. It gets the expected Team ID from `Configs/Signing.local.xcconfig` (or an explicit `EXPECTED_TEAM_ID=<Team ID>` override). If neither is available, the assertion fails; it is not silently skipped. An ad-hoc Debug artifact without a certificate fails here explicitly (`gate: hint` explains why), as expected.

## Dependency upgrades

Upgrading an external binary is an explicit supply-chain action: manually re-verify the new release (download the archive and inspect its hash, architecture, and signature without executing it), then update the manifest's release, asset, URL, and `archiveSHA256` and the corresponding test anchors in the same PR. Do not use `latest`, build the binary in this repository, or add an in-app update channel; upgrades ship only with an app release.
