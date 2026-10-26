#!/usr/bin/env python3
"""Offline acceptance checks for authoritative inputs -> packaged metadata."""
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'Scripts/dependency-metadata.py'


class DependencyMetadataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='ng2-metadata-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        shutil.copytree(ROOT / 'Vendor', self.root / 'Vendor',
                        ignore=lambda directory, names: [name for name in names
                            if name == '.fetched.sha256' or
                            (Path(directory).name == name and name in
                             ('sslocal', 'ck-client', 'v2ray-plugin'))])
        shutil.copy(ROOT / 'project.yml', self.root / 'project.yml')

    def run_generator(self, *args, success=True):
        result = subprocess.run(['python3', str(SCRIPT), '--root', str(self.root), *args],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def test_offline_generation_and_packaging(self):
        self.run_generator()
        self.run_generator('--check')
        output = self.root / '.build/dependency-metadata/ThirdParty'
        catalog = json.loads((output / 'catalog.json').read_text())
        self.assertEqual(len(catalog['dependencies']), 7)
        for entry in catalog['dependencies']:
            self.assertTrue(entry['version'])
            self.assertTrue(entry['licenses'])
            for reference in entry['licenses'] + entry['notices']:
                self.assertTrue((output / reference).read_text().strip())
        bundle = self.root / 'Test.app/Contents/Resources/ThirdParty'
        shutil.copytree(output, bundle)
        # Model SwiftPM's actual resolution in the isolated app-build fixture.
        package = next(entry for entry in catalog['dependencies'] if entry['id'] == 'AgeSwift')
        resolved = self.root / 'ShadowsocksX-NG2.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
        resolved.parent.mkdir(parents=True)
        resolution = {'pins': [{'location': package['sourceURL'], 'state': {'version': package['version']}}]}
        resolved.write_text(json.dumps(resolution))
        self.run_generator('--bundle', str(bundle))
        (bundle / catalog['dependencies'][0]['licenses'][0]).unlink()
        self.assertIn('bundle', self.run_generator('--bundle', str(bundle), success=False).stderr)
        shutil.copytree(output, bundle, dirs_exist_ok=True)
        resolution['pins'][0]['state']['version'] = 'incorrect'
        resolved.write_text(json.dumps(resolution))
        self.assertIn('AgeSwift', self.run_generator('--bundle', str(bundle), success=False).stderr)

    def test_one_authoritative_fact_changes_output_and_stale_output_is_rejected(self):
        self.run_generator()
        path = self.root / 'Vendor/dependency-metadata.json'
        data = json.loads(path.read_text())
        data['sslocal']['projectURL'] = 'https://example.org/project'
        path.write_text(json.dumps(data))
        self.assertIn('stale', self.run_generator('--check', success=False).stderr)
        self.run_generator()
        catalog = json.loads((self.root / '.build/dependency-metadata/ThirdParty/catalog.json').read_text())
        entry = next(item for item in catalog['dependencies'] if item['id'] == 'sslocal')
        self.assertEqual(entry['projectURL'], 'https://example.org/project')

    def test_invalid_inputs_are_named(self):
        path = self.root / 'Vendor/dependency-metadata.json'
        original = json.loads(path.read_text())
        for field, value in [('name', ''), ('licenses', ['../escape']),
                             ('licenses', ['missing.txt']), ('notices', []), ('projectURL', 'not a URL')]:
            with self.subTest(field=field, value=value):
                data = json.loads(json.dumps(original))
                data['sslocal'][field] = value
                path.write_text(json.dumps(data))
                self.assertIn('sslocal', self.run_generator(success=False).stderr)


if __name__ == '__main__':
    unittest.main()
