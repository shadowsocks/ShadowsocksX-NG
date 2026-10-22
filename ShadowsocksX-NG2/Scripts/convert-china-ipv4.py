#!/usr/bin/env python3
"""Convert gaoyifan/china-operator-ip china.txt into an NG2 rule snapshot.

Parses one IPv4 CIDR per line, normalizes (masks host bits), deduplicates, and
writes a normalized RuleSnapshot JSON plus loss report. Failure leaves any
previous snapshot untouched.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import ipaddress
import json
import sys
from pathlib import Path

CONVERTER_VERSION = "2.0.0"
SCHEMA_VERSION = 2

MINIMUM_RULE_COUNT = 100
MAXIMUM_RULE_COUNT = 50_000
MINIMUM_SCALE_RATIO = 0.5
MAXIMUM_SCALE_RATIO = 2.0
MAXIMUM_REJECTION_PERCENT = 5


def parse_lines(text: str) -> tuple[list[dict], int, int]:
    """Return (rules, duplicate_count, rejected_count)."""
    rules: list[dict] = []
    seen: set[str] = set()
    duplicates = 0
    rejected = 0
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            network = ipaddress.IPv4Network(line, strict=False)
        except ValueError:
            print(f"invalidCIDR: {line}")
            rejected += 1
            continue
        normalized = f"{network.network_address}/{network.prefixlen}"
        if normalized in seen:
            duplicates += 1
            continue
        seen.add(normalized)
        rules.append(
            {
                "action": "direct",
                "match": {"kind": "ipv4CIDR", "value": normalized},
            }
        )
    return rules, duplicates, rejected


def build_snapshot(
    document: str,
    source: dict,
    upstream_reference: str,
    license_name: str,
    attribution: str,
    previous_rule_count: int | None,
) -> dict:
    rules, duplicates, rejected = parse_lines(document)
    if not any(line.strip() and not line.strip().startswith("#") for line in document.splitlines()):
        raise SystemExit("empty input")
    if not rules and rejected:
        raise SystemExit("all entries invalid")
    code_lines = len(rules) + duplicates + rejected
    if code_lines and rejected * 100 > code_lines * MAXIMUM_REJECTION_PERCENT:
        raise SystemExit(f"abnormal format: {rejected}/{code_lines} lines rejected")
    rule_count = len(rules)
    if rule_count < MINIMUM_RULE_COUNT:
        raise SystemExit(f"abnormal rule count {rule_count} (min {MINIMUM_RULE_COUNT})")
    if rule_count > MAXIMUM_RULE_COUNT:
        raise SystemExit(f"abnormal rule count {rule_count} (max {MAXIMUM_RULE_COUNT})")
    if previous_rule_count is not None and previous_rule_count > 0:
        lower = int(previous_rule_count * MINIMUM_SCALE_RATIO)
        upper = int(previous_rule_count * MAXIMUM_SCALE_RATIO)
        if not (lower <= rule_count <= upper):
            raise SystemExit(
                f"abnormal scale change: {rule_count} vs previous {previous_rule_count} "
                f"(allowed {lower}..{upper})"
            )

    report = {
        "convertedCount": rule_count,
        "absorbedCount": 0,
        "skipped": {"duplicate": duplicates} if duplicates else {},
        "rejected": {"invalidCIDR": rejected} if rejected else {},
    }
    return {
        "schemaVersion": SCHEMA_VERSION,
        "metadata": {
            "source": source,
            "upstreamReference": upstream_reference,
            "inputDigest": hashlib.sha256(document.encode("utf-8")).hexdigest(),
            "fetchedAt": dt.datetime.now(dt.timezone.utc)
            .replace(microsecond=0)
            .isoformat()
            .replace("+00:00", "Z"),
            "converterVersion": CONVERTER_VERSION,
            "license": license_name,
            "attribution": attribution,
        },
        "rules": rules,
        "lossReport": report,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="path to china.txt")
    parser.add_argument("--upstream", required=True, help="pinned upstream version (commit)")
    parser.add_argument(
        "--upstream-reference",
        required=True,
        help="upstream repo/product identifier including the pinned commit or URL",
    )
    parser.add_argument("--license", required=True)
    parser.add_argument("--attribution", required=True)
    parser.add_argument("--out", type=Path, required=True, help="output snapshot.json")
    parser.add_argument(
        "--previous-count",
        type=int,
        default=None,
        help="previous snapshot rule count for scale-change detection",
    )
    args = parser.parse_args()

    document = args.input.read_text(encoding="utf-8")
    source = {
        "kind": "china-ipv4",
        "upstreamVersion": args.upstream,
        "label": "china-operator-ip",
    }
    snapshot = build_snapshot(
        document,
        source,
        args.upstream_reference,
        args.license,
        args.attribution,
        args.previous_count,
    )

    args.out.parent.mkdir(parents=True, exist_ok=True)
    tmp = args.out.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(snapshot, separators=(",", ":"), sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(args.out)
    loss = snapshot["lossReport"]
    print(
        f"wrote {args.out}: {loss['convertedCount']} rules, "
        f"skipped={loss['skipped']}, rejected={loss['rejected']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
