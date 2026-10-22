#!/bin/sh
# Fetch and hash-verify the external binaries pinned under Vendor/.
#
# For every Vendor/<name>/manifest.json (see lib-manifests.sh for the schema):
#   1. If the extracted binary is present and its recorded SHA-256 stamp still
#      matches, nothing is downloaded (build cache hit).
#   2. Otherwise the pinned release asset is downloaded and its asset
#      SHA-256 must equal manifest archiveSHA256 — a mismatch fails the build.
#   3. A tar member or direct binary must be an arm64-only Mach-O,
#      and is installed as Vendor/<name>/<binary> with a fresh stamp.
#
# Trust root is the committed manifest (tag + asset URL + archive SHA-256);
# local artifacts are a cache and are silently refetched when they drift.
# Usage: Scripts/fetch-external-binaries.sh   (run from anywhere)

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib-manifests.sh"

NG2_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
VENDOR_DIR="$NG2_ROOT/Vendor"

fetch_one() {
    manifest=$1
    name=$(basename "$(dirname "$manifest")")

    tmproot=$(mktemp -d "${TMPDIR:-/tmp}/ng2-fetch.XXXXXX")
    trap 'rm -rf "$tmproot"' EXIT INT TERM

    plist="$tmproot/manifest.plist"
    manifest_to_plist "$manifest" "$plist"
    binary=$(manifest_field "$plist" binary "$manifest")
    format=$("$PLIST_BUDDY" -c "Print :assetFormat" "$plist" 2>/dev/null || printf 'tar')
    case "$format" in
        tar) member=$(manifest_field "$plist" archiveMember "$manifest") ;;
        binary) ;;
        *) echo "error: $manifest: unsupported assetFormat '$format'" >&2; return 1 ;;
    esac
    asset=$(manifest_field "$plist" asset "$manifest")
    url=$(manifest_field "$plist" url "$manifest")
    expected=$(manifest_field "$plist" archiveSHA256 "$manifest")

    dir="$VENDOR_DIR/$name"
    artifact="$dir/$binary"
    stamp="$dir/.fetched.sha256"

    printf '%s' "$expected" | grep -Eq '^[0-9a-f]{64}$' || {
        echo "error: $manifest: archiveSHA256 must be 64 lowercase hex chars" >&2
        return 1
    }

    if [ -f "$artifact" ] && [ -f "$stamp" ]; then
        stamp_archive=$(awk '$1 == "archive" {print $2}' "$stamp")
        stamp_binary=$(awk '$1 == "binary" {print $2}' "$stamp")
        actual_binary=$(shasum -a 256 "$artifact" | awk '{print $1}')
        if [ "$stamp_archive" = "$expected" ] && [ "$stamp_binary" = "$actual_binary" ]; then
            echo "fetch($name): $binary up to date"
            rm -rf "$tmproot"
            trap - EXIT INT TERM
            return 0
        fi
        echo "fetch($name): pinned manifest or local artifact changed; refetching release"
    fi

    echo "fetch($name): $url"
    archive="$tmproot/$asset"
    curl --fail --location --silent --show-error --retry 3 \
        --connect-timeout 15 --output "$archive" "$url" || {
        echo "error: $name: download failed: $url" >&2
        return 1
    }

    actual=$(shasum -a 256 "$archive" | awk '{print $1}')
    [ "$actual" = "$expected" ] || {
        echo "error: $name: archive SHA-256 mismatch (expected $expected, got $actual)
error: $name: the pinned release asset changed; redo the static manifest before upgrading" >&2
        return 1
    }

    case "$format" in
        binary) extracted="$archive" ;;
        tar)
            if tar -tf "$archive" | grep -Eq '(^|/)\.\.(/|$)|^/'; then
                echo "error: $name: archive contains unsafe member paths" >&2
                return 1
            fi
            if ! tar -tf "$archive" | grep -Fqx "$member"; then
                echo "error: $name: archive has no member '$member'" >&2
                return 1
            fi

            xdir="$tmproot/extracted"
            mkdir -p "$xdir"
            tar -xf "$archive" -C "$xdir" "$member"
            extracted="$xdir/$member"
            ;;
    esac
    [ -f "$extracted" ] && [ ! -L "$extracted" ] || {
        echo "error: $name: selected binary is not a regular file: $extracted" >&2
        return 1
    }

    lipo -archs "$extracted" >/dev/null 2>&1 || {
        echo "error: $name: selected binary is not a Mach-O binary: $extracted" >&2
        return 1
    }
    archs=$(lipo -archs "$extracted" | xargs)
    [ "$archs" = "arm64" ] || {
        echo "error: $name: expected arm64-only binary, got: $archs" >&2
        return 1
    }

    mkdir -p "$dir"
    cp "$extracted" "$artifact"
    chmod 755 "$artifact"

    actual_binary=$(shasum -a 256 "$artifact" | awk '{print $1}')
    {
        printf 'archive\t%s\n' "$expected"
        printf 'binary\t%s\n' "$actual_binary"
    } > "$stamp.tmp"
    mv "$stamp.tmp" "$stamp"
    echo "fetch($name): verified and installed $binary ($actual_binary)"

    rm -rf "$tmproot"
    trap - EXIT INT TERM
}

manifests=$(vendor_manifests) || exit 1
for manifest in $manifests; do
    fetch_one "$manifest"
done
