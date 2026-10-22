#!/usr/bin/env bash
# Explicit maintainer update for the built-in geolocation-cn rule snapshot
# Normal builds never run this script — they only read the local
# pinned snapshot. On any failure the previous valid snapshot is kept.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RULES_DIR="${ROOT}/Vendor/rules/geolocation-cn"
SNAPSHOT="${RULES_DIR}/snapshot.json"
MANIFEST="${RULES_DIR}/manifest.json"
NOTICE="${RULES_DIR}/NOTICE"

# Pinned upstream: Loyalsoldier/domain-list-custom release (geosite.dat).
# Bump these together after human review of the new release.
UPSTREAM_VERSION="20260925234224"
UPSTREAM_URL="https://github.com/Loyalsoldier/domain-list-custom/releases/download/${UPSTREAM_VERSION}/geosite.dat"
UPSTREAM_SHA256="db12e746ef387c34c9e1be8194d772a0606ef09c236815555af5ba2595f3741f"
LICENSE="MIT"
ATTRIBUTION="geolocation-cn derived from Loyalsoldier/domain-list-custom geosite.dat ${UPSTREAM_VERSION} (based on v2fly/domain-list-community). The upstream export applies domain-list-custom attribute filtering (@ads and @!cn omitted)."

usage() {
  cat <<'EOF'
Usage: Scripts/update-geolocation-cn.sh [--fetch-only]

Explicitly refresh Vendor/rules/geolocation-cn/snapshot.json from the pinned
domain-list-custom geosite.dat release. This is a maintainer action; ordinary
builds are offline and only read the local snapshot.

  --fetch-only   Download and verify geosite.dat without converting.
EOF
}

FETCH_ONLY=0
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
if [[ "${1:-}" == "--fetch-only" ]]; then
  FETCH_ONLY=1
elif [[ $# -gt 0 ]]; then
  usage >&2
  exit 2
fi

TMP="$(mktemp -d)"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

echo "Fetching geosite.dat ${UPSTREAM_VERSION} …"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL --retry 3 -o "${TMP}/geosite.dat" "${UPSTREAM_URL}"
else
  echo "error: curl is required" >&2
  exit 1
fi

ACTUAL="$(shasum -a 256 "${TMP}/geosite.dat" | awk '{print $1}')"
if [[ "${ACTUAL}" != "${UPSTREAM_SHA256}" ]]; then
  echo "error: geosite.dat sha256 mismatch" >&2
  echo "  expected ${UPSTREAM_SHA256}" >&2
  echo "  actual   ${ACTUAL}" >&2
  echo "previous snapshot kept"
  exit 1
fi
echo "Verified geosite.dat sha256"

if [[ "${FETCH_ONLY}" -eq 1 ]]; then
  echo "fetch-only: leaving snapshot untouched"
  exit 0
fi

mkdir -p "${RULES_DIR}"

# Convert into a temporary snapshot first; only replace on success.
if ! python3 "${ROOT}/Scripts/convert-geolocation-cn.py" \
  "${TMP}/geosite.dat" \
  --upstream "${UPSTREAM_VERSION}" \
  --license "${LICENSE}" \
  --attribution "${ATTRIBUTION}" \
  --out "${TMP}/snapshot.json"; then
  echo "error: conversion failed; previous snapshot kept"
  exit 1
fi

# Sanity: snapshot must load as JSON and carry required metadata keys.
python3 - "${TMP}/snapshot.json" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
meta = data.get("metadata") or {}
for key in ("source", "upstreamReference", "inputDigest", "fetchedAt", "converterVersion", "license", "attribution"):
    if key not in meta:
        raise SystemExit(f"snapshot metadata missing {key}")
if not data.get("rules"):
    raise SystemExit("snapshot has no rules")
print(f"snapshot ok: {len(data['rules'])} rules")
PY

cp "${TMP}/snapshot.json" "${SNAPSHOT}"

# Refresh manifest (build-time integrity anchor).
python3 - "${SNAPSHOT}" "${MANIFEST}" "${UPSTREAM_VERSION}" "${UPSTREAM_URL}" "${UPSTREAM_SHA256}" <<'PY'
import hashlib, json, sys
from pathlib import Path
snapshot_path, manifest_path, version, url, sha256 = sys.argv[1:6]
data = Path(snapshot_path).read_bytes()
digest = hashlib.sha256(data).hexdigest()
manifest = {
    "name": "geolocation-cn",
    "upstreamVersion": version,
    "upstreamURL": url,
    "upstreamArchiveSHA256": sha256,
    "snapshotSHA256": digest,
    "converterVersion": data and json.loads(data)["metadata"]["converterVersion"],
}
Path(manifest_path).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"wrote {manifest_path}")
PY

# NOTICE: license and attribution accompany the distributed snapshot.
cat > "${NOTICE}" <<EOF
geolocation-cn rule snapshot
============================

Upstream: Loyalsoldier/domain-list-custom geosite.dat ${UPSTREAM_VERSION}
Upstream URL: ${UPSTREAM_URL}
Upstream archive SHA-256: ${UPSTREAM_SHA256}

Based on v2fly/domain-list-community data. This distribution applies the same
attribute filtering as domain-list-custom (omits @ads and @!cn rules from
geolocation-cn).

License: ${LICENSE}

${ATTRIBUTION}

This list is candidate routing data. It is not a guarantee of network
reachability, geographic ownership, or privacy.
EOF

echo "Updated ${SNAPSHOT}"
echo "Remember to review the diff and commit the snapshot together with its NOTICE and manifest."
