# Shared manifest reading for the Vendor supply chain scripts
# (fetch-external-binaries.sh / sign-embedded-helpers.sh / packaging-gate.sh).
# Sourced by those scripts; not runnable on its own.
#
# A manifest is Vendor/<name>/manifest.json with the fields fixed by
# project, release, target, asset, url, archiveSHA256,
# binary, bundleSubpath, signIdentifier. assetFormat defaults to tar; tar
# requires archiveMember, while binary uses the downloaded asset directly.
# JSON is parsed with
# plutil + PlistBuddy so the scripts depend only on base macOS tooling.

PLIST_BUDDY=${PLIST_BUDDY:-/usr/libexec/PlistBuddy}

vendor_manifests() {
    # Echo the path of every Vendor/*/manifest.json; fail if there are none.
    local found=""
    for manifest in "${VENDOR_DIR:?VENDOR_DIR not set}"/*/manifest.json; do
        [ -f "$manifest" ] || continue
        found=1
        printf '%s\n' "$manifest"
    done
    [ -n "$found" ] || {
        echo "error: no manifests found under $VENDOR_DIR" >&2
        return 1
    }
}

manifest_to_plist() {
    # $1 = manifest.json path, $2 = destination .plist path
    plutil -convert xml1 -o "$2" "$1" || {
        echo "error: cannot parse manifest: $1" >&2
        return 1
    }
}

manifest_field() {
    # $1 = converted .plist, $2 = key, $3 = original manifest path (for errors)
    "$PLIST_BUDDY" -c "Print :$2" "$1" 2>/dev/null || {
        echo "error: manifest $3: missing required field '$2'" >&2
        return 1
    }
}
