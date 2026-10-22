#!/bin/sh
# Re-sign every embedded helper binary with the Developer ID identity before
# Xcode signs the app itself.
#
# Upstream ships these binaries ad-hoc signed; they must carry a signature with
# Hardened Runtime and a stable code-signing identifier so the outer app seal,
# notarization and Gatekeeper cover them. Xcode runs this as a post-build script
# phase and applies the app's own signature afterwards, so the outer signature
# embeds the re-signed nested code.
#
# The identity comes from the build configuration: Developer ID on a release
# build, ad-hoc ("-") on the certificate-less Debug baseline. Ad-hoc mirrors
# Xcode's own ad-hoc signing: no secure timestamp and no Hardened Runtime (Xcode
# omits -o runtime for ad-hoc; hardened runtime with an untrusted identity would
# only get in the way of local debugging). The release path is unchanged.
#
# The identifier scheme is pinned in the manifests: <bundle-id>.<name> for
# sslocal, <bundle-id>.plugin.<name> for SIP003 plugins.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib-manifests.sh"

SRCROOT=${SRCROOT:?SRCROOT not set}
BUILT_PRODUCTS_DIR=${BUILT_PRODUCTS_DIR:?BUILT_PRODUCTS_DIR not set}
CONTENTS_FOLDER_PATH=${CONTENTS_FOLDER_PATH:?CONTENTS_FOLDER_PATH not set}
PRODUCT_BUNDLE_IDENTIFIER=${PRODUCT_BUNDLE_IDENTIFIER:?PRODUCT_BUNDLE_IDENTIFIER not set}

IDENTITY=${EXPANDED_CODE_SIGN_IDENTITY:-${EXPANDED_CODE_SIGN_IDENTITY_NAME:-${CODE_SIGN_IDENTITY:-}}}
[ -n "$IDENTITY" ] || {
    echo "error: no code signing identity (EXPANDED_CODE_SIGN_IDENTITY empty)" >&2
    exit 1
}

CONTENTS="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH"
tmproot=$(mktemp -d "${TMPDIR:-/tmp}/ng2-sign.XXXXXX")
trap 'rm -rf "$tmproot"' EXIT INT TERM

manifests=$(VENDOR_DIR="$SRCROOT/Vendor" vendor_manifests) || exit 1
for manifest in $manifests; do
    plist="$tmproot/manifest.plist"
    manifest_to_plist "$manifest" "$plist"
    binary=$(manifest_field "$plist" binary "$manifest")
    subpath=$(manifest_field "$plist" bundleSubpath "$manifest")
    identifier=$(manifest_field "$plist" signIdentifier "$manifest")

    target="$CONTENTS/$subpath/$binary"
    [ -f "$target" ] || {
        echo "error: embedded helper missing: $target (check the Copy Files phase in project.yml)" >&2
        exit 1
    }

    if [ "$IDENTITY" = "-" ]; then
        codesign --force --sign - --identifier "$identifier" "$target"
    else
        codesign --force --sign "$IDENTITY" --timestamp --options runtime \
            --identifier "$identifier" "$target"
    fi
    echo "sign($binary): $identifier"
done
