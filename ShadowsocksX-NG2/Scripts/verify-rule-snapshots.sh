#!/usr/bin/env bash
# Build-time offline verification of pinned rule snapshots.
# Ordinary builds never fetch or convert; they only verify the local snapshots
# are present, intact, and match their manifests. Missing, corrupt, or
# version-mismatched snapshots fail the build.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() {
  echo "error: $*" >&2
  echo "  (run the matching Scripts/update-*.sh after reviewing upstream changes)" >&2
  exit 1
}

verify_one() {
  local name="$1"
  local min_count="$2"
  local max_count="$3"
  local rules_dir="${ROOT}/Vendor/rules/${name}"
  local snapshot="${rules_dir}/snapshot.json"
  local manifest="${rules_dir}/manifest.json"
  local notice="${rules_dir}/NOTICE"

  [[ -f "${snapshot}" ]] || fail "missing ${snapshot}"
  [[ -f "${manifest}" ]] || fail "missing ${manifest}"
  [[ -f "${notice}" ]] || fail "missing ${notice} (license/attribution must ship with the snapshot)"

  python3 - "${snapshot}" "${manifest}" "${min_count}" "${max_count}" "${name}" <<'PY' || fail "${name} rule snapshot verification failed"
import hashlib, json, sys
from pathlib import Path

snapshot_path, manifest_path, min_count, max_count, name = sys.argv[1:6]
min_count, max_count = int(min_count), int(max_count)
snapshot_bytes = Path(snapshot_path).read_bytes()
try:
    snapshot = json.loads(snapshot_bytes)
except Exception as exc:  # noqa: BLE001
    raise SystemExit(f"snapshot is not valid JSON: {exc}")

if snapshot.get("schemaVersion") != 2:
    raise SystemExit(f"schemaVersion mismatch: {snapshot.get('schemaVersion')!r} != 2")

meta = snapshot.get("metadata") or {}
for key in ("source", "upstreamReference", "inputDigest", "fetchedAt", "converterVersion", "license", "attribution"):
    if key not in meta:
        raise SystemExit(f"snapshot metadata missing {key!r}")

if meta.get("converterVersion") != "2.0.0":
    raise SystemExit(
        f"converterVersion mismatch: {meta.get('converterVersion')!r} != '2.0.0' "
        "(re-run the explicit update or bump both sides together)"
    )

rules = snapshot.get("rules")
if not isinstance(rules, list) or not rules:
    raise SystemExit("snapshot has no rules")
if len(rules) < min_count or len(rules) > max_count:
    raise SystemExit(f"abnormal rule count {len(rules)} (allowed {min_count}..{max_count})")

try:
    manifest = json.loads(Path(manifest_path).read_text(encoding="utf-8"))
except Exception as exc:  # noqa: BLE001
    raise SystemExit(f"manifest is not valid JSON: {exc}")

for key in ("upstreamVersion", "snapshotSHA256", "converterVersion"):
    if key not in manifest:
        raise SystemExit(f"manifest missing {key!r}")

if manifest.get("converterVersion") != meta.get("converterVersion"):
    raise SystemExit("manifest converterVersion does not match snapshot metadata")

digest = hashlib.sha256(snapshot_bytes).hexdigest()
if digest != manifest.get("snapshotSHA256"):
    raise SystemExit(
        "snapshot SHA-256 does not match manifest "
        f"({digest} != {manifest.get('snapshotSHA256')})"
    )

if manifest.get("upstreamVersion") != meta.get("source", {}).get("upstreamVersion"):
    raise SystemExit("manifest upstreamVersion does not match snapshot metadata")

print(f"{name} snapshot ok: {len(rules)} rules, upstream {meta.get('source', {}).get('upstreamVersion')}")
PY
}

# geolocation-cn: domain rules.
verify_one "geolocation-cn" 100 200000
# china-ipv4: China mainland IPv4 CIDR.
verify_one "china-ipv4" 100 50000
# gfwlist: GFWList AutoProxy proxy candidates.
verify_one "gfwlist" 100 50000

echo "verify-rule-snapshots: ok"
