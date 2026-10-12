#!/bin/sh
# Packaging gate for ShadowsocksX-NG2.
#
# Standalone assertion over a built app bundle; exits nonzero on any failure:
#   1. Nested code signatures pass strict verification (incl. every helper).
#   2. The main app is Developer ID signed with Hardened Runtime and carries
#      NO App Sandbox entitlement (and no network.server entitlement).
#   3. Every Vendor manifest binary is embedded at Contents/<bundleSubpath>,
#      is arm64-only, and is re-signed by our Developer ID with Hardened
#      Runtime, a secure timestamp and the pinned code-signing identifier
#      (<bundle-id>[.plugin].<name>).
#   4. The manifest set exactly covers every Mach-O under Contents/Helpers.
#
# Usage: Scripts/packaging-gate.sh path/to/ShadowsocksX-NG2.app
#        EXPECTED_TEAM_ID overrides the Team ID read from the local signing config.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib-manifests.sh"

NG2_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
VENDOR_DIR="$NG2_ROOT/Vendor"

# Expected Team ID is injected, not pinned in the repo (open source). The same
# file the build reads supplies it here: Configs/Signing.local.xcconfig
# (gitignored). An explicit EXPECTED_TEAM_ID wins. Knowing no expected team is a
# hard failure: an unsigned or wrong-team bundle must not pass just because
# there is nothing to compare against.
LOCAL_SIGNING_CONFIG="$NG2_ROOT/Configs/Signing.local.xcconfig"
EXPECTED_TEAM_ID=${EXPECTED_TEAM_ID:-}
if [ -z "$EXPECTED_TEAM_ID" ] && [ -f "$LOCAL_SIGNING_CONFIG" ]; then
    EXPECTED_TEAM_ID=$(
        sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*\([^[:space:]]*\).*/\1/p' \
            "$LOCAL_SIGNING_CONFIG" | tail -1
    )
fi

APP=${1:-}
[ -n "$APP" ] || {
    echo "usage: $0 <path/to/App.app>" >&2
    exit 2
}
[ -d "$APP/Contents" ] || {
    echo "gate: FAIL  not an app bundle: $APP"
    exit 1
}
CONTENTS="$APP/Contents"

FAILS=0
pass() { printf 'gate: PASS  %s\n' "$1"; }
fail() { printf 'gate: FAIL  %s\n' "$1"; FAILS=$((FAILS + 1)); }

dv_of() { codesign -dv --verbose=4 "$1" 2>&1; }
dv_value() {
    # $1 = dv output, $2 = key. Handles both "Key=value" lines and fields
    # embedded in the CodeDirectory line ("... flags=0x10000(runtime) ...").
    printf '%s\n' "$1" |
        sed -n -e "s/^$2=//p" -e "s/^CodeDirectory .* $2=\([^ )]*\).*/\1/p" |
        head -1
}

check_devid_and_runtime() {
    # $1 = label, $2 = dv output
    authority=$(dv_value "$2" Authority)
    case "$authority" in
        "Developer ID Application:"*) pass "$1: Developer ID Application signed" ;;
        *) fail "$1: Developer ID Application signed (got: ${authority:-none})" ;;
    esac
    flags=$(dv_value "$2" flags)
    case "$flags" in
        *runtime*) pass "$1: Hardened Runtime" ;;
        *) fail "$1: Hardened Runtime (flags: ${flags:-none})" ;;
    esac
}

# --- 1. strict nested signature verification -------------------------------
if err=$(codesign --verify --strict --deep "$APP" 2>&1); then
    pass "nested code signatures verify strictly"
else
    fail "nested code signatures verify strictly: $err"
fi

# --- 2. main app identity, runtime, entitlements ----------------------------
bundle_id=$("$PLIST_BUDDY" -c 'Print :CFBundleIdentifier' "$CONTENTS/Info.plist" 2>/dev/null) || {
    fail "read CFBundleIdentifier from Info.plist"
    bundle_id=""
}
[ -n "$bundle_id" ] && pass "bundle identifier: $bundle_id"

app_dv=$(dv_of "$APP")
app_team=$(dv_value "$app_dv" TeamIdentifier)
app_authority=$(dv_value "$app_dv" Authority)
app_flags=$(dv_value "$app_dv" flags)

if [ -z "$EXPECTED_TEAM_ID" ]; then
    fail "expected Team ID is known (set EXPECTED_TEAM_ID or write DEVELOPMENT_TEAM in Configs/Signing.local.xcconfig)"
else
    [ "$app_team" = "$EXPECTED_TEAM_ID" ] ||
        fail "main app TeamIdentifier is $EXPECTED_TEAM_ID (got: ${app_team:-none})"
fi
check_devid_and_runtime "main app" "$app_dv"
case "$app_authority" in
    "Developer ID Application:"*) ;;
    *)
        echo "gate: hint  ad-hoc / non-Developer-ID artifacts come from the certificate-less Debug baseline; only a Developer ID signed release artifact can pass"
        ;;
esac

app_entitlements=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)
for forbidden in com.apple.security.app-sandbox com.apple.security.network.server; do
    case "$app_entitlements" in
        *"$forbidden"*) fail "main app has no $forbidden entitlement" ;;
        *) pass "main app has no $forbidden entitlement" ;;
    esac
done

# --- 3+4. per-binary manifest coverage --------------------------------------
if [ ! -d "$CONTENTS/Helpers" ]; then
    fail "Contents/Helpers exists"
fi

tmproot=$(mktemp -d "${TMPDIR:-/tmp}/ng2-gate.XXXXXX")
trap 'rm -rf "$tmproot"' EXIT INT TERM
expected_list="$tmproot/expected.txt"
actual_list="$tmproot/actual.txt"
: > "$expected_list"

manifests=$(vendor_manifests) || { fail "read manifests"; manifests=""; }
for manifest in $manifests; do
    name=$(basename "$(dirname "$manifest")")
    plist="$tmproot/$name.plist"
    manifest_to_plist "$manifest" "$plist" || { fail "read manifest $name"; continue; }
    binary=$(manifest_field "$plist" binary "$manifest") || { fail "read manifest $name"; continue; }
    subpath=$(manifest_field "$plist" bundleSubpath "$manifest") || { fail "read manifest $name"; continue; }
    identifier=$(manifest_field "$plist" signIdentifier "$manifest") || { fail "read manifest $name"; continue; }

    subpath_ok=1
    case "$subpath" in
        Helpers|Helpers/*) ;;
        *) subpath_ok=0 ;;
    esac
    case "$subpath" in
        ""|/*|*..*) subpath_ok=0 ;;
    esac
    if [ "$subpath_ok" -eq 1 ]; then
        pass "$name: bundleSubpath is under Helpers ($subpath)"
    else
        fail "$name: bundleSubpath must be Helpers or Helpers/... without '..' (got: '$subpath')"
    fi

    target="$CONTENTS/$subpath/$binary"
    rel="${subpath#Contents/}/$binary"
    printf '%s\n' "$rel" >> "$expected_list"

    if [ ! -f "$target" ]; then
        fail "$name: embedded at Contents/$rel"
        continue
    fi
    [ -x "$target" ] || fail "$name: embedded binary is executable"

    if err=$(codesign --verify --strict "$target" 2>&1); then
        :
    else
        fail "$name: signature verifies strictly: $err"
    fi

    lipo -archs "$target" >/dev/null 2>&1 || { fail "$name: is an arm64 Mach-O binary"; continue; }
    archs=$(lipo -archs "$target" | xargs)
    [ "$archs" = "arm64" ] || fail "$name: is arm64-only (got: $archs)"

    dv=$(dv_of "$target")
    team=$(dv_value "$dv" TeamIdentifier)
    actual_identifier=$(dv_value "$dv" Identifier)
    timestamp=$(dv_value "$dv" Timestamp)

    check_devid_and_runtime "$name" "$dv"
    [ -n "$timestamp" ] || fail "$name: secure timestamp present"
    [ "$team" = "$app_team" ] ||
        fail "$name: TeamIdentifier matches the app (got: ${team:-none})"
    [ "$actual_identifier" = "$identifier" ] ||
        fail "$name: code-signing identifier is $identifier (got: ${actual_identifier:-none})"
    case "$identifier" in
        "$bundle_id".*) pass "$name: identifier is prefixed by the bundle id" ;;
        *) fail "$name: identifier is prefixed by the bundle id ($identifier)" ;;
    esac
done

# Every code file under Contents/Helpers must be manifest-covered, and vice
# versa; symlinks anywhere under Helpers are anomalous and fail outright.
if [ -d "$CONTENTS/Helpers" ]; then
    if find "$CONTENTS/Helpers" -type l | grep -q .; then
        fail "Contents/Helpers contains no symlinks"
    fi
    : > "$actual_list"
    find "$CONTENTS/Helpers" -type f |
        awk -v prefix="$CONTENTS/" '{print substr($0, length(prefix) + 1)}' |
        sort > "$actual_list"
    sort -o "$expected_list" "$expected_list"
    if diff -u "$expected_list" "$actual_list" > "$tmproot/cover.diff" 2>&1; then
        pass "manifest set covers every file under Contents/Helpers"
    else
        fail "manifest set covers every file under Contents/Helpers:
$(sed 's/^/        /' "$tmproot/cover.diff")"
    fi
fi

# --- summary -----------------------------------------------------------------
if [ "$FAILS" -eq 0 ]; then
    echo "gate: ALL CHECKS PASSED ($APP)"
    exit 0
fi
echo "gate: $FAILS CHECK(S) FAILED ($APP)" >&2
exit 1
