#!/usr/bin/env python3
"""Convert Loyalsoldier/domain-list-custom geosite.dat geolocation-cn into an
NG2 rule snapshot.

Parses the geosite protobuf typed entries (Plain/Regex/Domain/Full), applies
`.cn` suffix absorption, and writes a normalized RuleSnapshot JSON plus loss
report. Failure leaves any previous snapshot untouched.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import struct
import sys
from pathlib import Path

CONVERTER_VERSION = "2.0.0"
SCHEMA_VERSION = 2

# v2ray geosite Domain.Type
TYPE_PLAIN = 0
TYPE_REGEX = 1
TYPE_DOMAIN = 2
TYPE_FULL = 3

TYPE_NAMES = {
    TYPE_PLAIN: "plain",
    TYPE_REGEX: "regex",
    TYPE_DOMAIN: "domain",
    TYPE_FULL: "full",
}


def read_varint(data: bytes, offset: int) -> tuple[int, int]:
    result = 0
    shift = 0
    while offset < len(data):
        byte = data[offset]
        offset += 1
        result |= (byte & 0x7F) << shift
        if byte < 0x80:
            return result, offset
        shift += 7
        if shift > 63:
            raise ValueError("varint too long")
    raise ValueError("truncated varint")


def parse_key(data: bytes, offset: int) -> tuple[int, int, int]:
    key, offset = read_varint(data, offset)
    field = key >> 3
    wire = key & 0x07
    return field, wire, offset


def skip_field(data: bytes, offset: int, wire: int) -> int:
    if wire == 0:
        _, offset = read_varint(data, offset)
        return offset
    if wire == 1:
        return offset + 8
    if wire == 2:
        length, offset = read_varint(data, offset)
        return offset + length
    if wire == 5:
        return offset + 4
    raise ValueError(f"unsupported wire type {wire}")


def parse_domain(data: bytes) -> dict:
    """GeoSite.Domain: type=1 (varint), value=2 (string), attribute=3 (message)."""
    entry = {"type": TYPE_DOMAIN, "value": "", "attributes": []}
    offset = 0
    while offset < len(data):
        field, wire, offset = parse_key(data, offset)
        if field == 1 and wire == 0:
            entry["type"], offset = read_varint(data, offset)
        elif field == 2 and wire == 2:
            length, offset = read_varint(data, offset)
            entry["value"] = data[offset : offset + length].decode("utf-8", "replace")
            offset += length
        elif field == 3 and wire == 2:
            length, offset = read_varint(data, offset)
            attr = parse_attribute(data[offset : offset + length])
            offset += length
            if attr:
                entry["attributes"].append(attr)
        else:
            offset = skip_field(data, offset, wire)
    return entry


def parse_attribute(data: bytes) -> str:
    """GeoSite.Domain.Attribute: key=1 (string)."""
    key = ""
    offset = 0
    while offset < len(data):
        field, wire, offset = parse_key(data, offset)
        if field == 1 and wire == 2:
            length, offset = read_varint(data, offset)
            key = data[offset : offset + length].decode("utf-8", "replace")
            offset += length
        else:
            offset = skip_field(data, offset, wire)
    return key


def parse_geosite(data: bytes) -> list[dict]:
    """GeoSiteList: entry=1 (GeoSite message)."""
    sites: list[dict] = []
    offset = 0
    while offset < len(data):
        field, wire, offset = parse_key(data, offset)
        if field == 1 and wire == 2:
            length, offset = read_varint(data, offset)
            sites.append(parse_geo_site(data[offset : offset + length]))
            offset += length
        else:
            offset = skip_field(data, offset, wire)
    return sites


def parse_geo_site(data: bytes) -> dict:
    """GeoSite: country_code=1 (string), domain=2 (Domain message)."""
    site = {"code": "", "domains": []}
    offset = 0
    while offset < len(data):
        field, wire, offset = parse_key(data, offset)
        if field == 1 and wire == 2:
            length, offset = read_varint(data, offset)
            site["code"] = data[offset : offset + length].decode("utf-8", "replace")
            offset += length
        elif field == 2 and wire == 2:
            length, offset = read_varint(data, offset)
            site["domains"].append(parse_domain(data[offset : offset + length]))
            offset += length
        else:
            offset = skip_field(data, offset, wire)
    return site


def normalize_ipv4_cidr(value: str) -> str | None:
    if "/" in value:
        addr, prefix_s = value.split("/", 1)
        try:
            prefix = int(prefix_s)
        except ValueError:
            return None
        if not 0 <= prefix <= 32:
            return None
    else:
        addr, prefix = value, 32
    parts = addr.split(".")
    if len(parts) != 4:
        return None
    try:
        octets = [int(p) for p in parts]
    except ValueError:
        return None
    if any(o < 0 or o > 255 for o in octets):
        return None
    host = (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3]
    mask = 0 if prefix == 0 else (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF
    network = host & mask
    dotted = ".".join(str((network >> shift) & 0xFF) for shift in (24, 16, 8, 0))
    return f"{dotted}/{prefix}"


def domain_suffix(value: str) -> str | None:
    v = value.strip().lower().lstrip(".")
    if not v or "*" in v or v.endswith("."):
        return None
    if not all(c.isalnum() or c in "-." for c in v):
        return None
    labels = v.split(".")
    if v != "cn" and len(labels) < 2:
        return None
    return v


def domain_exact(value: str) -> str | None:
    v = value.strip().lower()
    if not v or "*" in v or v.startswith(".") or v.endswith("."):
        return None
    if not all(c.isalnum() or c in "-." for c in v):
        return None
    return v


def convert(entries: list[dict]) -> dict:
    report = {
        "convertedCount": 0,
        "absorbedCount": 0,
        "skipped": {},
        "rejected": {},
    }
    rules: list[dict] = []
    originals: dict[tuple[str, str], str] = {}

    def bump(bucket: str, key: str, n: int = 1) -> None:
        target = report[bucket]
        target[key] = target.get(key, 0) + n

    for entry in entries:
        etype = entry["type"]
        value = entry["value"]
        if etype == TYPE_PLAIN:
            print(f"keyword: {value}")
            bump("skipped", "keyword")
            continue
        if etype == TYPE_REGEX:
            print(f"regexp: {value}")
            bump("skipped", "regexp")
            continue
        if etype == TYPE_DOMAIN:
            normalized = domain_suffix(value)
            kind = "domainSuffix"
            original = f"domain:{value}"
        elif etype == TYPE_FULL:
            normalized = domain_exact(value)
            kind = "domainExact"
            original = f"full:{value}"
        else:
            bump("skipped", "unknownType")
            continue
        if normalized is None:
            print(f"invalidDomain: {value}")
            bump("rejected", "invalidDomain")
            continue
        originals.setdefault((kind, normalized), original)
        rules.append(
            {
                "action": "direct",
                "match": {"kind": kind, "value": normalized},
            }
        )

    # Deduplicate by (action, match).
    seen: set[tuple[str, str, str]] = set()
    deduped: list[dict] = []
    for rule in rules:
        key = (rule["action"], rule["match"]["kind"], rule["match"]["value"])
        if key in seen:
            continue
        seen.add(key)
        deduped.append(rule)
    rules = deduped

    # Synthesize `.cn` suffix when absent, then absorb same-action .cn domains.
    cn_key = ("domainSuffix", "cn")
    has_cn = any((r["match"]["kind"], r["match"]["value"]) == cn_key for r in rules)
    if not has_cn:
        rules.insert(
            0,
            {
                "action": "direct",
                "match": {"kind": "domainSuffix", "value": "cn"},
            },
        )
        print("synthesized-cn-suffix")

    absorbed_count = 0
    kept: list[dict] = []
    for rule in rules:
        kind = rule["match"]["kind"]
        value = rule["match"]["value"]
        if (kind, value) == cn_key:
            kept.append(rule)
            continue
        covered = (kind == "domainSuffix" and value.endswith(".cn") and value != "cn") or (
            kind == "domainExact" and value.endswith(".cn")
        )
        if covered and rule["action"] == "direct":
            print(f"absorbed-by-cn-suffix: {originals[(kind, value)]}")
            absorbed_count += 1
        else:
            kept.append(rule)

    report["convertedCount"] = len(kept)
    report["absorbedCount"] = absorbed_count
    return {
        "schemaVersion": SCHEMA_VERSION,
        "rules": kept,
        "lossReport": report,
    }


def build_snapshot(
    geosite_path: Path,
    category: str,
    upstream_reference: str,
    license_name: str,
    attribution: str,
) -> dict:
    raw = geosite_path.read_bytes()
    input_digest = hashlib.sha256(raw).hexdigest()
    sites = parse_geosite(raw)
    match = next((s for s in sites if s["code"].lower() == category.lower()), None)
    if match is None:
        raise SystemExit(f"category {category!r} not found in {geosite_path}")

    source = {
        "kind": "geolocation-cn",
        "upstreamVersion": upstream_reference,
        "label": "geolocation-cn",
    }
    metadata = {
        "source": source,
        "upstreamReference": upstream_reference,
        "inputDigest": input_digest,
        "fetchedAt": dt.datetime.now(dt.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "converterVersion": CONVERTER_VERSION,
        "license": license_name,
        "attribution": attribution,
    }
    snapshot = convert(match["domains"])
    snapshot["metadata"] = metadata
    return snapshot


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("geosite", type=Path, help="path to geosite.dat")
    parser.add_argument("--category", default="GEOLOCATION-CN")
    parser.add_argument("--upstream", required=True, help="pinned upstream reference")
    parser.add_argument("--license", required=True)
    parser.add_argument("--attribution", required=True)
    parser.add_argument("--out", type=Path, required=True, help="output snapshot.json")
    args = parser.parse_args()

    snapshot = build_snapshot(
        args.geosite,
        args.category,
        args.upstream,
        args.license,
        args.attribution,
    )
    rules = snapshot["rules"]
    if len(rules) < 100:
        print(f"error: abnormal rule count {len(rules)} (min 100)", file=sys.stderr)
        return 1
    if len(rules) > 200_000:
        print(f"error: abnormal rule count {len(rules)} (max 200000)", file=sys.stderr)
        return 1

    args.out.parent.mkdir(parents=True, exist_ok=True)
    tmp = args.out.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(snapshot, separators=(",", ":"), sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(args.out)
    loss = snapshot["lossReport"]
    print(
        f"wrote {args.out}: {loss['convertedCount']} rules, "
        f"{loss['absorbedCount']} absorbed, skipped={loss['skipped']}, "
        f"rejected={loss['rejected']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
