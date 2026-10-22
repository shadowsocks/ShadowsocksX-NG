---
name: xcodegen
description: Generate and manage Xcode projects with XcodeGen — write project.yml as the source of truth and produce .xcodeproj from it instead of hand-editing pbxproj files. Use this skill whenever creating or modifying an Xcode project's structure (targets, schemes, build settings, Info.plist, entitlements, dependencies like SPM packages or frameworks), when the user mentions xcodegen / project.yml / regenerating or fixing a .xcodeproj, or when asked to add files or targets to an Xcode project — even if they don't name XcodeGen explicitly. Also applies to CI project generation and migrating a repo to a generated-project workflow.
---

# XcodeGen

XcodeGen generates `.xcodeproj` files from a declarative `project.yml` spec.

**Core mental model: `project.yml` is the source of truth; `.xcodeproj` is a disposable build artifact.** Never hand-edit the `.xcodeproj` and never tell the user to add files through Xcode's UI — every structural change (new target, new source directory, new dependency) goes through `project.yml` + regeneration. That is the entire point of the tool: no pbxproj merge conflicts, and the project structure becomes reviewable YAML in git.

## The workflow

1. Check the tool exists: `which xcodegen` (install with `brew install xcodegen`). If the spec uses newer features, note them in `options.minimumXcodeGenVersion`.
2. Write or edit `project.yml` at the repo/project root.
3. Generate: `xcodegen generate` (add `--use-cache` in scripts/CI so unchanged specs skip regeneration).
4. Verify the result — a generated project that doesn't build is not done:
   - `xcodebuild -list -project <Name>.xcodeproj` — schemes and configurations are as expected.
   - `xcodebuild -project <Name>.xcodeproj -scheme <Scheme> build` — the real gate.
   - `xcodegen dump --spec project.yml` prints the fully-resolved spec; use it to debug `include:` merges or surprising settings presets.

## Minimal working example

macOS app + unit tests + scheme — the shape most projects need; adapt platform, paths, and deployment target:

```yaml
name: MyApp
options:
  bundleIdPrefix: com.example        # targets without PRODUCT_BUNDLE_IDENTIFIER get com.example.<TargetName>
  deploymentTarget:
    macOS: "13.0"
  createIntermediateGroups: true
targets:
  MyApp:
    type: application
    platform: macOS
    sources:
      - path: MyApp                  # a directory: everything under it is picked up
    info:
      path: MyApp/Info.plist         # generated and written to disk; CFBundle* keys auto-filled
      properties:
        LSMinimumSystemVersion: "13.0"
    scheme:
      testTargets:
        - MyAppTests                 # scheme "MyApp" builds app + runs tests
  MyAppTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: MyAppTests
    dependencies:
      - target: MyApp                # TEST_HOST is set automatically for unit tests
```

```bash
xcodegen generate
xcodebuild -project MyApp.xcodeproj -scheme MyApp build
```

## Rules that prevent most mistakes

- **Regenerate after adding/removing source files.** Source globs are resolved when `xcodegen generate` runs, not live by Xcode — a new `.swift` file on disk is invisible to the project until then. "My file isn't in the target" almost always means: run `xcodegen generate`. (Xcode auto-reloads a regenerated project that's already open.)
- **Never mix settings styles.** In a `settings:` block, if you use `base:`, `configs:`, or `groups:`, a sibling plain map (e.g. `MARKETING_VERSION: 1.0` at the same level) is *silently ignored*. Pick one style per block; the plain-map style only works alone.
- **Quote deployment targets**: `deploymentTarget: "14.0"`, not `14.0` (YAML parses the latter as a float and trailing zeros vanish).
- **Prefer `info:` / `entitlements:` blocks** over committing static plists: XcodeGen writes the files and sets `INFOPLIST_FILE` / `CODE_SIGN_ENTITLEMENTS` for you, and fills `CFBundleIdentifier`, `CFBundleExecutable`, `CFBundleShortVersionString` etc. automatically. Anything you put in `properties:` wins. Info.plist files found in sources are never added to build phases.
- **Mark generated/optional paths** with `optional: true` on a source, or generation fails when the directory doesn't exist yet.
- **Test targets**: declare the app as a `dependencies: - target:` of the test target — that alone wires up `TEST_HOST` (unit tests) or `TEST_TARGET_NAME` (UI tests, type `bundle.ui-testing`).
- **Extensions embed themselves**: a dependency of an `application` target defaults to `embed: true`, so `- target: MyExtension` is usually all an app needs — no copy-files phase to write.
- **Extension bundle IDs must live under the app's bundle ID.** macOS/iOS validate that an embedded extension's bundle ID starts with the parent app's — `com.example.MyProxy.Tunnel`, not `com.example.Tunnel`. Since `bundleIdPrefix` auto-derivation gives every target `prefix.TargetName`, extensions fail a *build-validation* step (not compilation) with "Embedded binary's bundle identifier is not prefixed with the parent app's bundle identifier". Always set `PRODUCT_BUNDLE_IDENTIFIER` explicitly on extension targets (see recipes.md #2).
- **`.gitignore` the generated project** (`*.xcodeproj`) so no one edits it by accident. If the repo currently tracks one, flag the migration step (remove from index, regenerate locally) rather than doing it silently.
- **`xcodegen generate` is idempotent.** When in doubt, re-run it; there is no state to corrupt.

## Choosing between the reference files

- `references/project-spec.md` — syntax cheat sheet: every section of `project.yml` with exact key names. Read when you need a field you don't remember precisely (source exclude patterns, dependency options, scheme fields, SPM version constraints).
- `references/recipes.md` — complete copy-pasteable `project.yml` examples: app + unit/UI tests, app extension (e.g. network extension) with entitlements, SPM remote/local packages, per-config xcconfig, vendored pre-built binaries/frameworks, build-script phases, splitting a spec with `include:`. Read before writing any non-trivial spec — reuse a recipe rather than assembling from memory.
