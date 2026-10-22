#!/usr/bin/env python3
"""Exercise the sole generation path and its committed Swift consumer fixtures.

Run with --write-fixtures after reviewing an intentional conversion change.
Normal execution verifies the fixtures byte for byte; no network is used.
"""
import base64
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / 'Tests/Fixtures/RuleSnapshots'


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / f'Scripts/convert-{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


GEO = load('geolocation-cn')
GFW = load('gfwlist')
CHINA = load('china-ipv4')


def varint(value):
    result = bytearray()
    while value > 127:
        result.append((value & 127) | 128)
        value >>= 7
    return bytes(result + bytes([value]))


def field(number, data):
    return varint(number * 8 + 2) + varint(len(data)) + data


def geosite(entries, category='GEOLOCATION-CN'):
    domains = b''.join(field(2, b'\x08' + varint(kind) + field(2, value.encode())) for kind, value in entries)
    return field(1, field(1, category.encode()) + domains)


def inputs():
    return {
        'geolocation-cn': geosite([(2, 'foo.cn'), (2, 'example.com'), (3, 'api.example.org')]
                                 + [(2, f'geo{i}.example.net') for i in range(100)]),
        'china-ipv4': ('\n'.join(f'1.0.{i}.7/24' for i in range(100)) + '\n').encode(),
        'gfwlist': base64.b64encode(('||example.com\n@@||safe.example.com\n@@||other.example\n'
                                    '|https://exact.example.net\n@@|https://direct.example.net\n'
                                    '|https://root.example.net/\n|https://path.example.net/a\n'
                                    + '\n'.join(f'||gfw{i}.example.net' for i in range(100))).encode()),
    }


def generate(name, raw):
    source = {'kind': name, 'upstreamVersion': 'fixture-v1', 'label': name}
    with contextlib.redirect_stdout(io.StringIO()):
        if name == 'geolocation-cn':
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / 'geosite.dat'
                path.write_bytes(raw)
                snapshot = GEO.build_snapshot(path, 'GEOLOCATION-CN', 'fixture-v1', 'MIT', 'test fixture')
        else:
            module = CHINA if name == 'china-ipv4' else GFW
            document = raw.decode() if module is CHINA else GFW.decode_autoproxy(raw.decode())
            snapshot = module.build_snapshot(document, source, 'fixture-v1', 'MIT', 'test fixture', None)
    snapshot['metadata']['fetchedAt'] = '2026-10-03T00:00:00Z'
    return (json.dumps(snapshot, separators=(',', ':'), sort_keys=True) + '\n').encode()


class ConversionBehaviorTests(unittest.TestCase):
    def setUp(self):
        self.output = contextlib.redirect_stdout(io.StringIO())
        self.output.__enter__()
        self.addCleanup(self.output.__exit__, None, None, None)

    def test_generated_fixtures_are_current_and_reproducible(self):
        for name, raw in inputs().items():
            with self.subTest(source=name):
                self.assertEqual((FIXTURES / f'{name}.json').read_bytes(), generate(name, raw))
                snapshot = json.loads(generate(name, raw))
                digest_input = GFW.decode_autoproxy(raw.decode()).encode() if name == 'gfwlist' else raw
                self.assertEqual(snapshot['metadata']['inputDigest'], hashlib.sha256(digest_input).hexdigest())
                self.assertEqual(snapshot['lossReport']['convertedCount'], len(snapshot['rules']))
                if name == 'gfwlist':
                    for action, host in [('proxy', 'exact.example.net'), ('direct', 'direct.example.net'), ('proxy', 'root.example.net')]:
                        self.assertIn({'action': action, 'match': {'kind': 'domainExact', 'value': host}}, snapshot['rules'])

    def test_geosite_reads_published_typed_protobuf_and_selects_category(self):
        raw = geosite([(2, 'IGNORE.example')], 'OTHER') + geosite([(2, 'Example.COM'), (3, 'api.example.org'), (0, 'keyword'), (1, '^regexp')])
        sites = GEO.parse_geosite(raw)
        self.assertEqual([site['code'] for site in sites], ['OTHER', 'GEOLOCATION-CN'])
        snapshot = GEO.convert(sites[1]['domains'])
        self.assertEqual([r['match']['kind'] for r in snapshot['rules']], ['domainSuffix', 'domainSuffix', 'domainExact'])
        self.assertEqual(snapshot['rules'][1]['match']['value'], 'example.com')
        self.assertEqual(snapshot['lossReport']['skipped'], {'keyword': 1, 'regexp': 1})

    def test_geosite_invalid_varint_and_missing_category_fail(self):
        with self.assertRaises(ValueError):
            GEO.parse_geosite(b'\x80')
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'input.dat'
            path.write_bytes(geosite([], 'OTHER'))
            with self.assertRaisesRegex(SystemExit, 'not found'):
                GEO.build_snapshot(path, 'GEOLOCATION-CN', 'v', 'MIT', 'test')

    def test_geo_dedup_absorption_and_invalid_domains(self):
        snapshot = GEO.convert([{'type': kind, 'value': value} for kind, value in
                                [(2, 'cn'), (2, 'foo.cn'), (3, 'exact.cn'), (2, 'example.com'),
                                 (2, 'Example.COM'), (2, '*.bad.com'), (3, '.bad.com')]])
        self.assertEqual([r['match']['value'] for r in snapshot['rules']], ['cn', 'example.com'])
        self.assertEqual(snapshot['lossReport']['absorbedCount'], 2)
        self.assertEqual(snapshot['lossReport']['rejected'], {'invalidDomain': 2})

    def test_gfw_classifies_all_unsupported_forms_without_expanding(self):
        forms = {'urlPrefix': '|https://example.com/a', 'urlPath': '||example.com/a',
                 'filterOption': '||example.com$third-party', 'wildcard': '||*.example.com',
                 'regexp': '/regex/', 'plainText': 'example.com', 'singleLabelPrefix': '||google',
                 'ipLiteral': '||1.2.3.4'}
        for category, line in forms.items():
            for prefix in ['', '@@']:
                with self.subTest(line=prefix + line):
                    rules, report = GFW.convert_document(prefix + line + '\n||keep.example\n')
                    self.assertEqual([r['match']['value'] for r in rules], ['keep.example'])
                    self.assertEqual(report['skipped'], {category: 1})

    def test_gfw_normalizes_deduplicates_and_keeps_broader_exception(self):
        rules, report = GFW.convert_document('[AutoProxy 0.2.9]\n! comment\n\n||Sub.Example.COM^\n||sub.example.com\n@@||example.com\n@@||else.example\n')
        self.assertEqual([(r['action'], r['match']['value']) for r in rules],
                         [('proxy', 'sub.example.com'), ('direct', 'example.com'), ('direct', 'else.example')])
        self.assertEqual(report['absorbedCount'], 0)
        self.assertEqual(report['skipped'], {'header': 1, 'comment': 1, 'blank': 1})

    def test_gfw_url_prefix_without_path_converts_to_exact_domain(self):
        rules, report = GFW.convert_document(
            '|https://Example.COM\n|http://example.com\n||example.com\n'
            '@@|https://Safe.Example.ORG\n|https://port.example:8443\n')
        self.assertEqual([(r['action'], r['match']) for r in rules], [
            ('proxy', {'kind': 'domainExact', 'value': 'example.com'}),
            ('proxy', {'kind': 'domainSuffix', 'value': 'example.com'}),
            ('proxy', {'kind': 'domainExact', 'value': 'port.example'}),
            ('direct', {'kind': 'domainExact', 'value': 'safe.example.org'}),
        ])
        self.assertEqual(report['convertedCount'], 4)
        self.assertEqual(report['skipped'], {})

    def test_gfw_url_prefix_with_conditions_or_invalid_host_stays_skipped(self):
        patterns = [
            'https://example.com/path', 'https://example.com//',
            'https://*.example.com', 'https://exam*ple.com',
            'https://1.2.3.4', 'https://999.2.3.4', 'https://[2001:db8::1]',
            'https://localhost', 'https://bad..example', 'https://-bad.example',
            'https://bad-.example', 'https://example.com?query',
            'https://example.com#fragment', 'https://user@example.com',
            'https://example.com:invalid', 'https://example.com:65536',
            'https://example.com:', 'https://example.com$third-party',
            'https://example.com|', 'https://', 'example.com',
            'https://exa\tmple.com',
        ]
        for pattern in patterns:
            for prefix in ['|', '@@|']:
                with self.subTest(line=prefix + pattern):
                    rules, report = GFW.convert_document(prefix + pattern + '\n||keep.example')
                    self.assertEqual([r['match']['value'] for r in rules], ['keep.example'])
                    self.assertEqual(report['skipped'], {'urlPrefix': 1})

    def test_gfw_url_prefix_root_path_converts_and_deduplicates(self):
        rules, report = GFW.convert_document(
            '|https://Example.COM/\n|http://example.com\n'
            '@@|https://safe.example.org/\n@@|http://safe.example.org\n')
        self.assertEqual(rules, [
            {'action': 'proxy', 'match': {'kind': 'domainExact', 'value': 'example.com'}},
            {'action': 'direct', 'match': {'kind': 'domainExact', 'value': 'safe.example.org'}},
        ])
        self.assertEqual(report['convertedCount'], 2)
        self.assertEqual(report['skipped'], {})

    def test_gfw_exact_proxy_only_shadows_same_exact_exception(self):
        lines = ['|https://example.com', '@@|http://example.com',
                 '@@|https://sub.example.com', '@@||example.com', '@@||sub.example.com']
        for document in ['\n'.join(lines), '\n'.join(reversed(lines))]:
            rules, report = GFW.convert_document(document)
            self.assertEqual(report['absorbedCount'], 1)
            self.assertEqual(len(rules), 4)
            self.assertNotIn({'action': 'direct', 'match': {'kind': 'domainExact', 'value': 'example.com'}}, rules)

    def test_gfw_suffix_proxy_shadows_exact_exception_and_reports_original(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            rules, report = GFW.convert_document(
                '@@|https://safe.example.com\n||example.com\n|https://example.com')
        self.assertEqual(report['absorbedCount'], 1)
        self.assertEqual(len(rules), 2)
        self.assertIn('@@|https://safe.example.com shadowed-by ||example.com', output.getvalue())

    def test_gfw_equal_and_broader_proxy_shadow_exception_in_any_order(self):
        for document in ['||example.com\n@@||example.com\n@@||safe.example.com',
                         '@@||safe.example.com\n@@||example.com\n||example.com']:
            rules, report = GFW.convert_document(document)
            self.assertEqual(len(rules), 1)
            self.assertEqual(report['absorbedCount'], 2)
            self.assertNotIn('shadowedException', report['skipped'])

    def test_gfw_empty_unknown_and_corrupt_payload_fail(self):
        with self.assertRaises(SystemExit):
            GFW.convert_document('! comments only\n')
        for line in ['???bogus???', '||bad^host.example^']:
            with self.assertRaises(GFW.UnknownSyntax):
                GFW.convert_document(line)
        document = '[AutoProxy 0.2.9]\n||example.com\n'
        self.assertEqual(GFW.decode_autoproxy(base64.b64encode(document.encode()).decode()), document)
        for encoded in ['not!!!valid@@@base64', base64.b64encode(b'\xff').decode()]:
            with self.assertRaises(SystemExit):
                GFW.decode_autoproxy(encoded)

    def test_china_normalizes_addresses_and_rejects_invalid_entries(self):
        rules, duplicates, rejected = CHINA.parse_lines('# comment\n203.0.113.7/24\n203.0.113.8/24\n8.8.8.8\n::1/128\n1.2.3.4/33\ninvalid\n')
        self.assertEqual([r['match']['value'] for r in rules], ['203.0.113.0/24', '8.8.8.8/32'])
        self.assertEqual((duplicates, rejected), (1, 3))

    def test_china_empty_invalid_and_rejection_rate_guards(self):
        for document, reason in [('# comment\n', 'empty input'), ('invalid\n', 'all entries invalid'),
                                 ('1.2.3.4/24\ninvalid\n', 'abnormal format')]:
            with self.assertRaisesRegex(SystemExit, reason):
                CHINA.build_snapshot(document, {}, 'v', 'MIT', 'test', None)
        document = inputs()['china-ipv4'].decode() + 'invalid\n'
        snapshot = CHINA.build_snapshot(document, {}, 'v', 'MIT', 'test', None)
        self.assertEqual(snapshot['lossReport']['rejected'], {'invalidCIDR': 1})

    def test_count_and_scale_guards_on_actual_generators(self):
        for module, document in [(CHINA, inputs()['china-ipv4'].decode()),
                                 (GFW, GFW.decode_autoproxy(inputs()['gfwlist'].decode()))]:
            count = len(module.build_snapshot(document, {}, 'v', 'MIT', 'test', None)['rules'])
            for setting, value in [('MINIMUM_RULE_COUNT', count + 1), ('MAXIMUM_RULE_COUNT', count - 1)]:
                with patch.object(module, setting, value):
                    with self.assertRaisesRegex(SystemExit, 'abnormal rule count'):
                        module.build_snapshot(document, {}, 'v', 'MIT', 'test', None)
            for previous in [count * 3, count // 3]:
                with self.assertRaisesRegex(SystemExit, 'abnormal scale change'):
                    module.build_snapshot(document, {}, 'v', 'MIT', 'test', previous)
            module.build_snapshot(document, {}, 'v', 'MIT', 'test', count)

    def test_failed_cli_keeps_previous_snapshot(self):
        for name, raw in [('geolocation-cn', geosite([(2, 'small.example')])),
                          ('china-ipv4', b'invalid'), ('gfwlist', base64.b64encode(b'???bogus???'))]:
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory)
                (path / 'input').write_bytes(raw)
                output = path / 'snapshot.json'
                output.write_bytes(b'previous snapshot')
                command = [sys.executable, str(ROOT / f'Scripts/convert-{name}.py'), str(path / 'input'),
                           '--upstream', 'v', '--license', 'MIT', '--attribution', 'test', '--out', str(output)]
                if name != 'geolocation-cn':
                    command += ['--upstream-reference', 'v']
                result = subprocess.run(command, capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(output.read_bytes(), b'previous snapshot')


if __name__ == '__main__':
    if sys.argv[1:] == ['--write-fixtures']:
        FIXTURES.mkdir(parents=True, exist_ok=True)
        for name, raw in inputs().items():
            (FIXTURES / f'{name}.json').write_bytes(generate(name, raw))
    else:
        unittest.main()
