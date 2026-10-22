#!/usr/bin/env bash
# Explicit maintainer update for the built-in china-operator-ip IPv4 CIDR rule
# snapshot. Normal builds never run this script — they only read the
# local pinned snapshot. On any failure the previous valid snapshot is kept.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RULES_DIR="${ROOT}/Vendor/rules/china-ipv4"
SNAPSHOT="${RULES_DIR}/snapshot.json"
MANIFEST="${RULES_DIR}/manifest.json"
NOTICE="${RULES_DIR}/NOTICE"

# Pinned upstream: gaoyifan/china-operator-ip ip-lists branch commit.
# Bump these together after human review of the new commit.
UPSTREAM_VERSION="75f2eb035cb53a7a4af3437e2c2110d0f73cf14a"
UPSTREAM_URL="https://raw.githubusercontent.com/gaoyifan/china-operator-ip/${UPSTREAM_VERSION}/china.txt"
UPSTREAM_SHA256="98493d3ec7f2c77b9f191600dc741df731cfbaef775201594d0bda66b0181479"
LICENSE="MIT"
ATTRIBUTION="China mainland IPv4 CIDR derived from gaoyifan/china-operator-ip china.txt (ip-lists branch) at commit ${UPSTREAM_VERSION}. BGP/ASN-derived candidate routing data; not a guarantee of geographic ownership or reachability."

usage() {
  cat <<'EOF'
Usage: Scripts/update-china-ipv4.sh [--fetch-only]

Explicitly refresh Vendor/rules/china-ipv4/snapshot.json from the pinned
china-operator-ip china.txt commit. This is a maintainer action; ordinary
builds are offline and only read the local snapshot.

  --fetch-only   Download and verify china.txt without converting.
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

echo "Fetching china.txt ${UPSTREAM_VERSION} …"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL --retry 3 -o "${TMP}/china.txt" "${UPSTREAM_URL}"
else
  echo "error: curl is required" >&2
  exit 1
fi

ACTUAL="$(shasum -a 256 "${TMP}/china.txt" | awk '{print $1}')"
if [[ "${ACTUAL}" != "${UPSTREAM_SHA256}" ]]; then
  echo "error: china.txt sha256 mismatch" >&2
  echo "  expected ${UPSTREAM_SHA256}" >&2
  echo "  actual   ${ACTUAL}" >&2
  echo "previous snapshot kept"
  exit 1
fi
echo "Verified china.txt sha256"

if [[ "${FETCH_ONLY}" -eq 1 ]]; then
  echo "fetch-only: leaving snapshot untouched"
  exit 0
fi

mkdir -p "${RULES_DIR}"

# Previous rule count feeds scale-change detection; missing snapshot is first run.
PREVIOUS_COUNT=""
if [[ -f "${SNAPSHOT}" ]]; then
  PREVIOUS_COUNT="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["rules"]))' "${SNAPSHOT}")"
fi

CONVERT_ARGS=(
  "${TMP}/china.txt"
  --upstream "${UPSTREAM_VERSION}"
  --upstream-reference "${UPSTREAM_URL} @ ${UPSTREAM_VERSION}"
  --license "${LICENSE}"
  --attribution "${ATTRIBUTION}"
  --out "${TMP}/snapshot.json"
)
if [[ -n "${PREVIOUS_COUNT}" ]]; then
  CONVERT_ARGS+=(--previous-count "${PREVIOUS_COUNT}")
fi

# Convert into a temporary snapshot first; only replace on success.
if ! python3 "${ROOT}/Scripts/convert-china-ipv4.py" "${CONVERT_ARGS[@]}"; then
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
    "name": "china-ipv4",
    "upstreamVersion": version,
    "upstreamURL": url,
    "upstreamArchiveSHA256": sha256,
    "snapshotSHA256": digest,
    "converterVersion": json.loads(data)["metadata"]["converterVersion"],
}
Path(manifest_path).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"wrote {manifest_path}")
PY

# NOTICE: license and attribution accompany the distributed snapshot.
cat > "${NOTICE}" <<EOF
china-ipv4 rule snapshot
========================

Upstream: gaoyifan/china-operator-ip china.txt (ip-lists branch)
Upstream commit: ${UPSTREAM_VERSION}
Upstream URL: ${UPSTREAM_URL}
Upstream archive SHA-256: ${UPSTREAM_SHA256}

License: ${LICENSE}

${ATTRIBUTION}

This list is candidate routing data. It is not a guarantee of network
reachability, geographic ownership, or privacy. IP-CIDR matching may cause
sslocal to issue local DNS queries for unmatched hostnames; the product does
not promise that all DNS queries travel through the remote Shadowsocks server.
EOF

echo "Updated ${SNAPSHOT}"
echo "Remember to review the diff and commit the snapshot together with its NOTICE and manifest."
