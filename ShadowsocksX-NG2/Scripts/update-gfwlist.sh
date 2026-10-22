#!/usr/bin/env bash
# Explicit maintainer update for the built-in GFWList AutoProxy rule snapshot
# Normal builds never run this script — they only read the local
# pinned snapshot. On any failure the previous valid snapshot is kept.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RULES_DIR="${ROOT}/Vendor/rules/gfwlist"
SNAPSHOT="${RULES_DIR}/snapshot.json"
MANIFEST="${RULES_DIR}/manifest.json"
NOTICE="${RULES_DIR}/NOTICE"

# Pinned upstream: gfwlist/gfwlist master commit. Bump these together after
# human review of the new commit.
UPSTREAM_VERSION="c19292511da4c5af8f6193fd32d666eaaa0312f9"
UPSTREAM_URL="https://raw.githubusercontent.com/gfwlist/gfwlist/${UPSTREAM_VERSION}/gfwlist.txt"
UPSTREAM_MIRROR_URL="https://cdn.jsdelivr.net/gh/gfwlist/gfwlist@${UPSTREAM_VERSION}/gfwlist.txt"
UPSTREAM_SHA256="750d34564363075fafa12d8ab9739f269e2fbd2bf3c5f4ab8cfd859bfd3441df"
LICENSE="LGPL-2.1"
ATTRIBUTION="GFWList AutoProxy rules derived from gfwlist/gfwlist gfwlist.txt at commit ${UPSTREAM_VERSION}. Official Base64 AutoProxy 0.2.9 list. Domain anchors become suffix matches. URL prefixes with an empty or root path, no query, fragment or user information, and a literal domain host become exact matches, discarding scheme and any valid port. Other URL conditions, wildcard hosts, IP literals and regex rules are reported as losses. List is candidate routing data, not a guarantee of reachability or completeness."

usage() {
  cat <<'EOF'
Usage: Scripts/update-gfwlist.sh [--fetch-only]

Explicitly refresh Vendor/rules/gfwlist/snapshot.json from the pinned
gfwlist/gfwlist commit. This is a maintainer action; ordinary builds are
offline and only read the local snapshot.

  --fetch-only   Download and verify gfwlist.txt without converting.
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

echo "Fetching gfwlist.txt ${UPSTREAM_VERSION} …"
fetch_ok=0
if command -v curl >/dev/null 2>&1; then
  if curl -fsSL --retry 1 --max-time 20 -o "${TMP}/gfwlist.txt" "${UPSTREAM_URL}"; then
    fetch_ok=1
    echo "Fetched from ${UPSTREAM_URL}"
  elif curl -fsSL --retry 2 --max-time 45 -o "${TMP}/gfwlist.txt" "${UPSTREAM_MIRROR_URL}"; then
    fetch_ok=1
    echo "Fetched from mirror ${UPSTREAM_MIRROR_URL}"
  fi
fi
if [[ "${fetch_ok}" -ne 1 ]]; then
  echo "error: failed to fetch gfwlist.txt from pinned upstream or mirror" >&2
  echo "previous snapshot kept"
  exit 1
fi

ACTUAL="$(shasum -a 256 "${TMP}/gfwlist.txt" | awk '{print $1}')"
if [[ "${ACTUAL}" != "${UPSTREAM_SHA256}" ]]; then
  echo "error: gfwlist.txt sha256 mismatch" >&2
  echo "  expected ${UPSTREAM_SHA256}" >&2
  echo "  actual   ${ACTUAL}" >&2
  echo "previous snapshot kept"
  exit 1
fi
echo "Verified gfwlist.txt sha256"

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
  "${TMP}/gfwlist.txt"
  --upstream "${UPSTREAM_VERSION}"
  --upstream-reference "gfwlist/gfwlist gfwlist.txt @ ${UPSTREAM_VERSION}"
  --license "${LICENSE}"
  --attribution "${ATTRIBUTION}"
  --out "${TMP}/snapshot.json"
)
if [[ -n "${PREVIOUS_COUNT}" ]]; then
  CONVERT_ARGS+=(--previous-count "${PREVIOUS_COUNT}")
fi

# Convert into a temporary snapshot first; only replace on success.
if ! python3 "${ROOT}/Scripts/convert-gfwlist.py" "${CONVERT_ARGS[@]}"; then
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
print(f"snapshot ok: {len(data['rules'])} rules, "
      f"shadowed={data.get('lossReport', {}).get('absorbedCount', 0)}")
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
    "name": "gfwlist",
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
gfwlist rule snapshot
=====================

Upstream: gfwlist/gfwlist gfwlist.txt
Upstream commit: ${UPSTREAM_VERSION}
Upstream URL: ${UPSTREAM_URL}
Upstream archive SHA-256: ${UPSTREAM_SHA256}

License: ${LICENSE}

${ATTRIBUTION}

This list is candidate routing data. It is not a guarantee of network
reachability, geographic ownership, or privacy. Domain anchors become suffix
matches. Eligible URL prefixes become exact
domain matches, discarding scheme and any valid port. Other URL conditions,
wildcard hosts, IP literals and regex rules are counted as conversion losses.
\`@@\` exceptions fully covered by a proxy rule are
reported item by item and omitted from the generated ACL because sslocal would
ignore them.
EOF

echo "Updated ${SNAPSHOT}"
echo "Remember to review the diff and commit the snapshot together with its NOTICE and manifest."
