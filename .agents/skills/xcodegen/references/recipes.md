# project.yml Recipes

Complete, copy-pasteable specs. Combine the parts you need; trim what you don't. Each recipe is self-contained except where noted.

## 1. iOS app + unit tests + UI tests

```yaml
name: MyApp
options:
  bundleIdPrefix: com.example
  deploymentTarget:
    iOS: "16.0"
targets:
  MyApp:
    type: application
    platform: iOS
    sources: [MyApp]
    info:
      path: MyApp/Info.plist
      properties:
        UILaunchScreen: {}              # modern no-storyboard launch
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
    scheme:
      testTargets: [MyAppTests, MyAppUITests]
  MyAppTests:
    type: bundle.unit-test
    platform: iOS
    sources: [MyAppTests]
    dependencies:
      - target: MyApp                   # TEST_HOST set automatically
  MyAppUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [MyAppUITests]
    dependencies:
      - target: MyApp                   # TEST_TARGET_NAME set automatically
```

## 2. macOS app with an embedded extension (network extension, share extension, …)

Extensions need three things: the right `type`, an `NSExtension` (or `NSSystemExtension`) dict in Info.plist properties, and usually entitlements. The app embeds them automatically — no copy phase needed.

```yaml
name: MyProxy
options:
  bundleIdPrefix: com.example
  deploymentTarget:
    macOS: "13.0"
targets:
  MyProxy:
    type: application
    platform: macOS
    sources:
      - path: MyProxy
    info:
      path: MyProxy/Info.plist
      properties:
        LSMinimumSystemVersion: "13.0"
    entitlements:
      path: MyProxy/MyProxy.entitlements
      properties:
        com.apple.security.app-sandbox: true
        com.apple.security.network.client: true
        com.apple.security.network.server: true
    dependencies:
      - target: Tunnel                  # embedded into Contents/PlugIns automatically
    scheme:
      testTargets: [MyProxyTests]
  Tunnel:
    type: app-extension                 # Network Extension packet-tunnel providers use this type;
                                        # use system-extension for DriverKit/transparent-proxy style
    platform: macOS
    sources: [Tunnel]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.example.MyProxy.Tunnel   # must be prefixed by the app's
                                        # bundle ID; bundleIdPrefix auto-derivation (com.example.Tunnel)
                                        # fails at build validation, not compile
    info:
      path: Tunnel/Info.plist
      properties:
        CFBundleDisplayName: Tunnel
        NSExtension:
          NSExtensionPointIdentifier: com.apple.networkextension.packet-tunnel
    entitlements:
      path: Tunnel/Tunnel.entitlements
      properties:
        com.apple.security.app-sandbox: true
        com.apple.security.network.client: true
  MyProxyTests:
    type: bundle.unit-test
    platform: macOS
    sources: [MyProxyTests]
    dependencies:
      - target: MyProxy
```

Note: Network Extension entitlements (`com.apple.developer.networking.networkextension`) require a provisioning profile from Apple; generation and local builds succeed without it, distribution signing does not. Don't "fix" a signing failure by inventing entitlement values.

## 3. SPM dependencies (remote and local)

```yaml
name: MyApp
options:
  bundleIdPrefix: com.example
packages:
  SnapshotTesting:
    url: https://github.com/pointfreeco/swift-snapshot-testing
    from: 1.17.0
  Alamofire:
    github: Alamofire/Alamofire         # shorthand
    exactVersion: 5.8.0
  FeatureKit:
    path: Packages/FeatureKit           # local package (dir with Package.swift)
targets:
  MyApp:
    type: application
    platform: iOS
    sources: [MyApp]
    dependencies:
      - package: Alamofire
      - package: FeatureKit
        product: FeatureKitDomain       # only when product ≠ package name
  MyAppTests:
    type: bundle.unit-test
    platform: iOS
    sources: [MyAppTests]
    dependencies:
      - target: MyApp
      - package: SnapshotTesting
        products: [SnapshotTesting]     # or use `product:` for one
```

## 4. Custom configs + xcconfig files

```yaml
name: MyApp
options:
  bundleIdPrefix: com.example
configs:
  Debug: debug
  Beta: release                          # maps to release-type defaults
  AppStore: release
configFiles:                             # project level
  Debug: Configs/project-debug.xcconfig
targets:
  MyApp:
    type: application
    platform: iOS
    sources: [MyApp]
    configFiles:                         # target level overrides
      Debug: Configs/app-debug.xcconfig
      Beta: Configs/app-beta.xcconfig
      AppStore: Configs/app-appstore.xcconfig
    settings:
      base:
        XCConfigOnlyWhenNotInFile: value # xcconfig wins for keys it defines
schemes:
  MyApp-Beta:
    build:
      targets: {MyApp: all}
    run:
      config: Beta
    archive:
      config: AppStore
```

## 5. Vendored pre-built binaries and frameworks

Pre-built CLI tools and xcframeworks checked into the repo (not built from source):

```yaml
targets:
  MyApp:
    type: application
    platform: macOS
    sources:
      - path: MyApp
      - path: Vendor/Tools/ss-local          # a single pre-built executable
        buildPhase:
          copyFiles:
            destination: wrapper
            subpath: Contents/Tools          # ends up at MyApp.app/Contents/Tools/ss-local
      - path: Vendor/Tools/privoxy
        buildPhase:
          copyFiles:
            destination: wrapper
            subpath: Contents/Tools
    dependencies:
      - framework: Vendor/Frameworks/SwiftZip.xcframework
```

Keep vendored binaries out of any target's plain `sources:` glob (or exclude them), otherwise XcodeGen guesses a build phase from the extension. Executables without extension are left alone, but being explicit with `buildPhase: copyFiles` documents intent.

## 6. Build script phases with proper inputs/outputs

Scripts without declared inputs/outputs re-run every build and break incremental builds — declare them:

```yaml
targets:
  MyApp:
    type: application
    platform: iOS
    sources: [MyApp]
    preBuildScripts:
      - name: Generate Protos
        script: |
          ./scripts/generate-protos.sh
        inputFiles:
          - $(SRCROOT)/Protos/messages.proto
        outputFiles:
          - $(DERIVED_FILE_DIR)/Messages.pb.swift
        basedOnDependencyAnalysis: true
    postBuildScripts:
      - name: SwiftLint
        script: swiftlint
        showEnvVars: false
      - name: Crash Reporter Upload
        script: ./scripts/upload-dsyms.sh
        runOnlyWhenInstalling: true
```

## 7. Splitting a big spec across files

`include` merges additively (dicts merge, arrays append); add `:REPLACE` to overwrite a list instead of appending to it.

```yaml
# project.yml
name: MyApp
include:
  - project/targets.yml
  - project/schemes.yml
options:
  bundleIdPrefix: com.example
```

```yaml
# project/targets.yml
targets:
  MyApp:
    type: application
    platform: iOS
    sources: [MyApp]
  MyAppTests:
    type: bundle.unit-test
    platform: iOS
    sources: [MyAppTests]
    dependencies:
      - target: MyApp
```

Use `xcodegen dump --spec project.yml` to inspect the merged result when an override doesn't behave.
