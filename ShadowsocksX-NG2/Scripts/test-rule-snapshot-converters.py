#!/usr/bin/env python3
"""Behavior checks at the maintainer conversion boundary (no network)."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import unittest


def converter(name):
    path = Path(__file__).with_name(f"convert-{name}.py")
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SnapshotConverterTests(unittest.TestCase):
    def assert_slim(self, snapshot):
        self.assertEqual(snapshot["schemaVersion"], 2)
        self.assertNotIn("absorbed", snapshot)
        for rule in snapshot["rules"]:
            self.assertEqual(set(rule), {"action", "match"})
        report = snapshot["lossReport"]
        self.assertEqual(set(report), {"convertedCount", "absorbedCount", "skipped", "rejected"})
        self.assertEqual(report["convertedCount"], len(snapshot["rules"]))
        for category in ("skipped", "rejected"):
            self.assertTrue(all(type(count) is int and count >= 0 for count in report[category].values()))
        self.assertNotIn("shadowedException", report["skipped"])

    def test_cn_absorption_drops_narrow_entries_and_reports_only_totals(self):
        geo = converter("geolocation-cn")
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            snapshot = geo.convert([
                {"type": geo.TYPE_DOMAIN, "value": "foo.cn"},
                {"type": geo.TYPE_FULL, "value": "exact.cn"},
                {"type": geo.TYPE_DOMAIN, "value": "example.com"},
                {"type": geo.TYPE_REGEX, "value": "^example"},
            ])
        self.assert_slim(snapshot)
        self.assertEqual([rule["match"]["value"] for rule in snapshot["rules"]], ["cn", "example.com"])
        self.assertEqual(snapshot["lossReport"]["absorbedCount"], 2)
        self.assertEqual(snapshot["lossReport"]["skipped"], {"regexp": 1})
        self.assertIn("synthesized-cn-suffix", output.getvalue())
        self.assertIn("foo.cn", output.getvalue())
        self.assertNotIn("foo.cn", json.dumps(snapshot))

    def test_gfw_shadowed_exception_counts_once_and_keeps_raw_evidence_on_stdout(self):
        gfw = converter("gfwlist")
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            rules, report = gfw.convert_document(
                "||Example.COM^\n@@||Safe.Example.COM^\n@@||other.example\n|https://path.example/a\n")
        snapshot = {"schemaVersion": gfw.SCHEMA_VERSION, "rules": rules, "lossReport": report}
        self.assert_slim(snapshot)
        self.assertEqual(report["absorbedCount"], 1)
        self.assertEqual(report["skipped"], {"urlPrefix": 1})
        self.assertEqual([rule["match"]["value"] for rule in rules], ["example.com", "other.example"])
        self.assertIn("@@||Safe.Example.COM^ shadowed-by ||Example.COM^", output.getvalue())
        self.assertNotIn("Safe.Example.COM", json.dumps(snapshot))

    def test_china_ip_build_retains_metadata_normalization_and_duplicate_counts(self):
        china = converter("china-ipv4")
        document = "\n".join(f"1.0.{index}.1/24" for index in range(100)) + "\n1.0.0.2/24\n"
        source = {"kind": "china-ipv4", "upstreamVersion": "fixed", "label": "China"}
        snapshot = china.build_snapshot(document, source, "fixed", "MIT", "author", None)
        self.assert_slim(snapshot)
        self.assertEqual(snapshot["metadata"]["source"], source)
        self.assertEqual(snapshot["metadata"]["converterVersion"], "2.0.0")
        self.assertEqual(snapshot["rules"][0]["match"]["value"], "1.0.0.0/24")
        self.assertEqual(snapshot["lossReport"]["skipped"], {"duplicate": 1})

    def test_shipped_artifacts_use_compact_schema_and_preserve_pinned_rule_counts(self):
        for name, count, absorbed in [("geolocation-cn", 4241, 1138), ("china-ipv4", 6206, 0), ("gfwlist", 4046, 31)]:
            with self.subTest(source=name):
                data = (Path(__file__).parent.parent / "Vendor" / "rules" / name / "snapshot.json").read_bytes()
                self.assertEqual(data.count(b"\n"), 1)
                snapshot = json.loads(data)
                self.assert_slim(snapshot)
                self.assertEqual(len(snapshot["rules"]), count)
                self.assertEqual(snapshot["lossReport"]["absorbedCount"], absorbed)
                self.assertEqual(snapshot["metadata"]["source"]["kind"], name)
                self.assertEqual(snapshot["metadata"]["converterVersion"], "2.0.0")


if __name__ == "__main__":
    unittest.main()
