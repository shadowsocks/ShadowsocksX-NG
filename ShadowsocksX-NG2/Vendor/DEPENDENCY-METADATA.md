# Offline dependency metadata

`dependency-metadata.json` adds display names, project/source URLs and local text references to existing authoritative pins. It contains no version table. Binary versions and distribution URLs come from `*/manifest.json`; rule pins come from `rules/*/manifest.json`; AgeSwift's URL and exact version come from `project.yml`, which XcodeGen uses for SwiftPM resolution. Plugin aliases and default arguments live in their binary manifests. Rule update scripts also read their manifests rather than maintaining separate pins.

`xcodegen generate` (including `task gen:prj`) runs `Scripts/dependency-metadata.py` before collecting resources. It generates `.build/dependency-metadata/ThirdParty/` and `Domain/Plugin/ManagedPluginDefinitions.generated.swift`. Do not edit these outputs. The generated Swift contains only executable contracts, not display facts. Build phases reject stale outputs and verify the actual app's catalog and every referenced text before signing. Normal generation and checks use only local files.

`BundledDependencyCatalog` enumerates direct dependencies and reads their associated texts. Inject an app bundle URL in hostless tests. Relative references from aggregate notices to shared license texts retain the Vendor directory layout. Plugin display metadata can fail independently of executable lookup.

## Updating dependencies

1. Update the authoritative pin and fetch/resolve the selected artifact. For rule snapshots, edit the manifest's `upstreamVersion`, `upstreamURL` and `upstreamArchiveSHA256`, then run its update script to regenerate the snapshot and integrity hash.
2. Review the actual artifact and matching source graph; refresh direct licenses and aggregate notices using the process in `THIRD-PARTY-NOTICES.md`. Keep original copyright lines and additional notices. Full texts are pinned locally, not fetched by the build. Update supplemental project facts only when they change.
3. Run `task gen:prj`, `task test:metadata`, and the applicable validation gates. A future viewer can reuse the catalog and text reader; this change adds no About viewer.

The direct license files were collected from the selected manifest release/commit (`LICENSE`, or GFWList's `COPYING.txt`). AgeSwift's MIT and Apache texts come from its resolved package checkout. The `domain-list-custom` data license includes its own MIT text and the inherited v2fly/domain-list-community MIT text at the matching `20260925234224` release tag; the selected build workflow consumes that community data. The existing rule NOTICE files retain conversion attribution. The sslocal record distinguishes the original Shadowsocks project from the actual qiuyuzhou fork source and release asset.

Existence and consistency validation is not a legal compliance audit. Aggregate notice coverage still requires artifact/source review when a dependency changes; the catalog does not fulfill other distribution duties such as corresponding-source delivery.
