# project.yml Syntax Cheat Sheet

Condensed from the official ProjectSpec docs (XcodeGen 2.4x). When this file and the official docs disagree, trust the docs: https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md

## Top level

```yaml
name: MyProject              # required
include: [base.yml]          # merge other specs (see bottom of this file)
options: {...}               # project-wide behavior (below)
attributes: {...}            # raw PBXProject attributes (rarely needed)
configs: {...}               # build configurations (default: Debug/Release)
configFiles: {Debug: path.xcconfig}
settingGroups: {name: {settings}}   # reusable settings, referenced via settings.groups
settings: {...}              # project-level build settings
targets: {TargetName: {...}} # the targets
fileGroups: [dir-or-file]    # shown in project navigator, not in any target
schemes: {SchemeName: {...}}
schemeTemplates: {...}
targetTemplates: {...}
packages: {PackageName: {...}}      # Swift packages
projectReferences: {Name: {path: Other.xcodeproj}}
```

## Options (commonly used)

```yaml
options:
  bundleIdPrefix: com.example     # auto bundle IDs: prefix + target name
  deploymentTarget:               # project-wide defaults
    macOS: "13.0"
    iOS: "16.0"
  createIntermediateGroups: true  # groups for intermediate path components
  minimumXcodeGenVersion: "2.38.0"
  developmentLanguage: zh-Hans    # default "en"
  transitivelyLinkDependencies: false   # link deps-of-deps (default false)
  generateEmptyDirectories: false
  groupSortPosition: bottom       # top | bottom | none
  groupOrdering:                  # custom group order in navigator
    - order: [Sources, Resources, Tests]
  preGenCommand: make resources   # bash, skipped when cache skips generation
  postGenCommand: pod install
  defaultConfig: Debug
  defaultSourceDirectoryType: group   # group | folder | syncedFolder (xcode16_0+)
```

Environment variable expansion works in any string: `${SOME_VAR}` (disable with `xcodegen generate -n`).

## Configs

Each config maps to a build type; anything other than `debug`/`release` gets no default settings:

```yaml
configs:
  Debug: debug
  Beta: release
  AppStore: release
```

## Settings

Two forms — **never mix them in one block** (plain keys are silently dropped if `base`/`configs`/`groups` is present):

```yaml
settings:
  SWIFT_VERSION: "5.9"            # form 1: simple map

settings:                          # form 2: structured
  base:
    MARKETING_VERSION: "1.0"
  configs:                         # key matched case-insensitively/partially to config names
    debug:
      CODE_SIGN_IDENTITY: Apple Development
    release:
      CODE_SIGN_IDENTITY: Apple Distribution
  groups: [shared-settings]        # references to settingGroups
```

## Target

```yaml
targets:
  MyTarget:
    type: application              # required, see list below
    platform: macOS                # required: macOS | iOS | tvOS | watchOS | visionOS | auto
    supportedDestinations: [macOS, macCatalyst]   # alternative to platform (Xcode 14+)
    deploymentTarget: "13.0"       # or per-platform map for multi-platform targets
    sources: [...]
    dependencies: [...]
    settings: {...}
    configFiles: {Debug: path.xcconfig}
    info: {...}                    # generates Info.plist
    entitlements: {...}            # generates .entitlements
    templates: [Name]              # from targetTemplates; ${target_name} substitution
    templateAttributes: {attr: value}
    preBuildScripts: [...]         # also postCompileScripts, postBuildScripts
    buildRules: [...]
    buildToolPlugins: [{plugin: P, package: PKG}]
    scheme: {...}                  # per-target convenience scheme
    attributes: {...}
    transitivelyLinkDependencies: true
    requiresObjCLinking: true      # default true only for library.static
```

Product types (attribute to `type:`): `application`, `app-extension`, `extensionkit-extension`, `framework`, `framework.static`, `library.static`, `library.dynamic`, `bundle`, `bundle.unit-test`, `bundle.ui-testing`, `tool`, `xpc-service`, `system-extension`, `watchkit2-extension`, `application.messages`, `application.watchapp2`, and friends.

Settings set automatically for you (don't set by hand): `INFOPLIST_FILE` (if an Info.plist is found in sources or defined via `info:`), `TEST_HOST` (unit tests depending on an app), `TEST_TARGET_NAME` (UI tests depending on an app), `FRAMEWORK_SEARCH_PATHS` (Carthage), `OTHER_LDFLAGS` (ObjC linking).

Multi-platform: `platform: [iOS, tvOS]` generates one target per platform named `Name_iOS`, `Name_tvOS`; `${platform}` interpolates inside the target spec.

## Sources

A source is a path string or an object. Directories are expanded at **generation time** — new files require regeneration.

```yaml
sources:
  - Sources                       # whole directory
  - path: Sources
    excludes:                     # bash-4 globstar patterns, relative to `path`
      - "**/*.md"
      - "ios/*.[mh]"
      - "*-Private.h"
    includes: ["**/*.swift"]      # whitelist; excludes win on conflict
    compilerFlags: ["-Werror"]
    createIntermediateGroups: true
    optional: true                # don't fail if the path doesn't exist
    headerVisibility: public      # public | private | project
    type: group                   # group (default for dirs) | file | folder | syncedFolder
    buildPhase: sources           # sources | resources | headers | none, or copyFiles: {destination: …, subpath: …}
  - path: Vendor/Binaries
    buildPhase: none              # show in navigator only
  - path: MyFile.swift            # single file
    buildPhase:
      copyFiles:
        destination: wrapper      # absolutePath | productsDirectory | wrapper | executables |
        subpath: Contents/Tools   # resources | javaResources | frameworks | sharedFrameworks |
                                  # sharedSupport | plugins
```

## Dependencies

```yaml
dependencies:
  - target: OtherTarget              # links; embeds if this is an application (embed default true)
  - target: OtherProject/OtherTarget # via projectReferences
  - package: SomePackage             # name from top-level packages
    product: LibraryName             # only if product ≠ package name
    products: [A, B]                 # multiple products
  - framework: Vendor/Foo.xcframework
    embed: true                      # default true for apps
    codeSign: true
    weak: false
  - sdk: libc++.tbd                  # or Contacts.framework, libz.dylib
  - carthage: Alamofire              # linkType: static|dynamic, findFrameworks: bool
  - bundle: Prebuilt.bundle          # adds to Copy Resources
```

## Info.plist and entitlements (`info:` / `entitlements:`)

Files are written to disk on every generation. `info` auto-fills CFBundleIdentifier, CFBundleInfoDictionaryVersion, CFBundleExecutable, CFBundleName, CFBundleDevelopmentRegion, CFBundleShortVersionString, CFBundleVersion, CFBundlePackageType where appropriate; `entitlements` requires all properties explicitly.

```yaml
info:
  path: App/Info.plist
  properties:
    LSMinimumSystemVersion: "13.0"
entitlements:
  path: App/App.entitlements
  properties:
    com.apple.security.application-groups: [group.com.example.app]
```

## Build scripts

```yaml
preBuildScripts:                 # also postCompileScripts, postBuildScripts
  - name: SwiftLint
    script: swiftlint            # or path: scripts/lint.sh
    inputFiles: ["$(SRCROOT)/file1"]
    outputFileLists: ["$(SRCROOT)/outputs.xcfilelist"]
    showEnvVars: false
    basedOnDependencyAnalysis: true   # skip when inputs/outputs unchanged
    runOnlyWhenInstalling: false
```

## Schemes

Per-target convenience (preferred when one scheme ≈ one target):

```yaml
targets:
  App:
    scheme:
      testTargets: [AppTests]
      configVariants: [Staging, Production]   # generates one scheme per variant
      gatherCoverageData: true
      commandLineArguments: {"-MyArg": true}
      environmentVariables: {KEY: VALUE}
```

Top-level (full control; `build.targets` is required):

```yaml
schemes:
  MyApp:
    build:
      targets:
        MyApp: all                 # all | none | [run, test, profile, analyze, archive]
        MyAppTests: [test]
    run:
      config: Debug
      commandLineArguments: {"-InMemory": true}
      environmentVariables:
        - variable: API_ENV
          value: staging
          isEnabled: true
    test:
      gatherCoverageData: true
      targets:
        - AppTests
        - name: UITests
          parallelizable: true
          randomExecutionOrder: true
          skippedTests: [UITests/testFlaky()]
    archive:
      config: Release
      customArchiveName: MyApp
```

## Swift packages

```yaml
packages:
  Yams:
    url: https://github.com/jpsim/Yams
    from: 2.0.0                # or majorVersion / minorVersion / exactVersion / version,
                               # minVersion+maxVersion, branch, revision
  Alamofire:
    github: Alamofire/Alamofire   # shorthand for github URLs
    exactVersion: 5.8.0
  LocalLib:
    path: Packages/LocalLib     # directory containing Package.swift
    group: LocalPackages        # navigator group, default "Packages"
```

Link into targets with `dependencies: - package: Yams`.

## Splitting the spec (`include`)

Included files merge additively (dicts merge, arrays append); suffix a key with `:REPLACE` to override instead of append. Paths inside included files are relative to that file unless `relativePaths: false`.

```yaml
include:
  - base.yml
  - path: extra.yml
    relativePaths: false
    enable: ${INCLUDE_EXTRA}
targets:
  App:                # target defined in base.yml
    sources:REPLACE: [NewSources]
```
