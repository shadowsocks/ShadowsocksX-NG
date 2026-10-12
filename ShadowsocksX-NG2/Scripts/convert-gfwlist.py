#!/usr/bin/env python3
"""Convert the official Base64 GFWList AutoProxy list into an NG2 rule snapshot.

Domain anchors become suffix matches. URL prefixes with an empty or root path and a
literal domain host become exact matches, discarding the scheme and port.
Other URL conditions are reported as losses rather than expanded to domains.
`@@` exceptions shadowed by a broader proxy rule are kept out of the ACL and
reported item by item; the broader proxy rules stay. Unknown syntax, corrupt
input, or abnormal shrinkage block the update and leave the previous snapshot.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import datetime as dt
import hashlib
import ipaddress
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlsplit

CONVERTER_VERSION = "2.0.0"
SCHEMA_VERSION = 2

MINIMUM_RULE_COUNT = 100
MAXIMUM_RULE_COUNT = 50_000
MINIMUM_SCALE_RATIO = 0.5
MAXIMUM_SCALE_RATIO = 2.0

DOMAIN_HOST_RE = re.compile(r"^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$")


class UnknownSyntax(Exception):
    def __init__(self, line: str) -> None:
        super().__init__(f"unknown AutoProxy syntax: {line}")
        self.line = line


def looks_like_ip(text: str) -> bool:
    try:
        ipaddress.ip_address(text)
        return True
    except ValueError:
        pass
    parts = text.split(".")
    return len(parts) == 4 and all(p.isdigit() for p in parts)


def is_valid_domain_host(host: str) -> bool:
    return bool(host) and "." in host and DOMAIN_HOST_RE.fullmatch(host) is not None


def parse_line(raw_line: str) -> dict:
    """Classify one AutoProxy line. Raises UnknownSyntax on unrecognized forms."""
    line = raw_line.strip()
    if not line:
        return {"kind": "blank"}
    if line.startswith("!"):
        return {"kind": "comment"}
    if line.startswith("[") and line.endswith("]"):
        return {"kind": "header"}

    is_exception = line.startswith("@@")
    pattern = line[2:] if is_exception else line

    if pattern.startswith("||"):
        return parse_domain_pattern(pattern[2:], line, is_exception)
    if pattern.startswith("|"):
        return parse_url_prefix(pattern[1:], line, is_exception)
    if len(pattern) >= 3 and pattern.startswith("/") and pattern.endswith("/"):
        return {"kind": "regexp", "original": line, "isException": is_exception}
    if "*" in pattern:
        return {"kind": "wildcard", "original": line, "isException": is_exception}
    if looks_like_ip(pattern):
        return {"kind": "ipLiteral", "original": line, "isException": is_exception}
    if "." in pattern and DOMAIN_HOST_RE.fullmatch(pattern):
        return {"kind": "plainText", "original": line, "isException": is_exception}
    raise UnknownSyntax(line)


def parse_url_prefix(url: str, original: str, is_exception: bool) -> dict:
    skipped = {"kind": "urlPrefix", "original": original, "isException": is_exception}
    # urlsplit tolerates whitespace and bare hosts; neither is a literal URL rule.
    if any(char.isspace() for char in url) or not re.match(
        r"^[A-Za-z][A-Za-z0-9+.-]*://", url
    ):
        return skipped
    try:
        parsed = urlsplit(url)
        host = parsed.hostname or ""
        _ = parsed.port  # Validate numeric syntax and range before dropping it.
    except ValueError:
        return skipped
    if parsed.path not in {"", "/"} or "?" in url or "#" in url or parsed.username is not None:
        return skipped
    if (
        parsed.netloc.endswith(":")
        or not is_valid_domain_host(host)
        or looks_like_ip(host)
    ):
        return skipped
    labels = host.split(".")
    if (
        len(host) > 253
        or not all(
            re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", label)
            for label in labels
        )
        or not any(char.isalpha() for char in labels[-1])
    ):
        return skipped
    kind = "exactDomainException" if is_exception else "exactDomainProxy"
    return {"kind": kind, "host": host.lower(), "original": original}


def parse_domain_pattern(host_part: str, original: str, is_exception: bool) -> dict:
    if "/" in host_part:
        return {"kind": "urlPath", "original": original, "isException": is_exception}
    if "*" in host_part:
        return {"kind": "wildcard", "original": original, "isException": is_exception}
    if "$" in host_part:
        return {"kind": "filterOption", "original": original, "isException": is_exception}

    host = host_part
    if host.endswith("^"):
        host = host[:-1]
        if "^" in host:
            raise UnknownSyntax(original)
    if looks_like_ip(host):
        return {"kind": "ipLiteral", "original": original, "isException": is_exception}
    if "." not in host:
        return {
            "kind": "singleLabelPrefix",
            "original": original,
            "isException": is_exception,
        }
    if not is_valid_domain_host(host):
        raise UnknownSyntax(original)
    kind = "domainException" if is_exception else "domainProxy"
    return {"kind": kind, "host": host.lower(), "original": original}


def domain_suffix_covers(broad: str, narrow: str) -> bool:
    broad_host = broad.lower()
    narrow_host = narrow.lower()
    return narrow_host == broad_host or narrow_host.endswith("." + broad_host)


def split_shadowed(
    proxy_rules: list[dict], exception_rules: list[dict]
) -> tuple[list[dict], list[dict], list[tuple[dict, dict]]]:
    """Return (kept_proxy, kept_exceptions, shadowed_pairs).

    A suffix proxy covers exact or suffix exceptions on that domain or subdomains.
    An exact proxy only covers an exact exception on the same domain.
    sslocal matches domain proxy_list before bypass_list, so a covered exception
    would be an ineffective ACL entry.
    """
    kept_exceptions: list[dict] = []
    shadowed: list[tuple[dict, dict]] = []
    for exception in exception_rules:
        blocker = None
        for proxy in proxy_rules:
            broad, narrow = proxy["match"], exception["match"]
            if (
                broad["kind"] == "domainSuffix"
                and domain_suffix_covers(broad["value"], narrow["value"])
            ) or (broad == narrow):
                blocker = proxy
                break
        if blocker is None:
            kept_exceptions.append(exception)
        else:
            shadowed.append((exception, blocker))
    return proxy_rules, kept_exceptions, shadowed


def make_rule(action: str, match: dict) -> dict:
    return {
        "action": action,
        "match": match,
    }


def convert_document(document: str) -> tuple[list[dict], dict]:
    """Return (rules, lossReport)."""
    skipped: dict[str, int] = {}
    proxy_rules: list[dict] = []
    exception_rules: list[dict] = []
    saw_code_line = False
    originals: dict[tuple[str, str, str], str] = {}

    def rule_key(rule: dict) -> tuple[str, str, str]:
        return (rule["action"], rule["match"]["kind"], rule["match"]["value"])

    def bump(category: str) -> None:
        skipped[category] = skipped.get(category, 0) + 1

    for raw_line in document.splitlines():
        entry = parse_line(raw_line)
        kind = entry["kind"]
        if kind == "blank":
            bump("blank")
        elif kind == "comment":
            bump("comment")
        elif kind == "header":
            bump("header")
        elif kind in {"domainProxy", "domainException", "exactDomainProxy", "exactDomainException"}:
            saw_code_line = True
            action = "direct" if kind.endswith("Exception") else "proxy"
            match_kind = "domainExact" if kind.startswith("exact") else "domainSuffix"
            rule = make_rule(
                action, {"kind": match_kind, "value": entry["host"]}
            )
            originals.setdefault(rule_key(rule), entry["original"])
            (exception_rules if action == "direct" else proxy_rules).append(rule)
        elif kind in {
            "urlPrefix",
            "urlPath",
            "filterOption",
            "wildcard",
            "regexp",
            "plainText",
            "singleLabelPrefix",
            "ipLiteral",
        }:
            saw_code_line = True
            bump(kind)
            print(f"unexpressible-{kind}: {entry['original']}")
        else:
            raise UnknownSyntax(entry.get("original", raw_line))

    if not saw_code_line:
        raise SystemExit("empty input")

    kept_proxy, kept_exceptions, shadowed = split_shadowed(proxy_rules, exception_rules)
    if shadowed:
        for exception, blocker in shadowed:
            print(
                "shadowed-exception: "
                f"{originals[rule_key(exception)]} "
                f"shadowed-by {originals[rule_key(blocker)]}"
            )

    rules = kept_proxy + kept_exceptions
    # Deduplicate by (action, match.kind, match.value), keeping first.
    seen: set[tuple[str, str, str]] = set()
    deduped: list[dict] = []
    for rule in rules:
        key = (rule["action"], rule["match"]["kind"], rule["match"]["value"])
        if key in seen:
            continue
        seen.add(key)
        deduped.append(rule)
    rules = deduped

    report = {
        "convertedCount": len(rules),
        "absorbedCount": len(shadowed),
        "skipped": skipped,
        "rejected": {},
    }
    return rules, report


def build_snapshot(
    document: str,
    source: dict,
    upstream_reference: str,
    license_name: str,
    attribution: str,
    previous_rule_count: int | None,
) -> dict:
    rules, report = convert_document(document)
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


def decode_autoproxy(text: str) -> str:
    compact = "".join(text.split())
    try:
        raw = base64.b64decode(compact, validate=False)
    except (binascii.Error, ValueError) as exc:
        raise SystemExit(f"corrupt Base64 input: {exc}") from exc
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise SystemExit(f"corrupt AutoProxy payload: {exc}") from exc


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="path to official Base64 gfwlist.txt")
    parser.add_argument("--upstream", required=True, help="pinned upstream commit")
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

    base64_text = args.input.read_text(encoding="utf-8")
    document = decode_autoproxy(base64_text)
    source = {
        "kind": "gfwlist",
        "upstreamVersion": args.upstream,
        "label": "GFWList",
    }
    try:
        snapshot = build_snapshot(
            document,
            source,
            args.upstream_reference,
            args.license,
            args.attribution,
            args.previous_count,
        )
    except UnknownSyntax as exc:
        raise SystemExit(str(exc)) from exc

    args.out.parent.mkdir(parents=True, exist_ok=True)
    tmp = args.out.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(snapshot, separators=(",", ":"), sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(args.out)
    loss = snapshot["lossReport"]
    print(
        f"wrote {args.out}: {loss['convertedCount']} rules, "
        f"skipped={loss['skipped']}, "
        f"shadowed={loss['absorbedCount']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
