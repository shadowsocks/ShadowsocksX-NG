#!/usr/bin/env python3
"""Generate and verify offline bundle resources. No network or executable probes."""
import argparse
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlparse


def required(value, label):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f'{label}: required nonempty string')
    return value


def web_url(value, label):
    value = required(value, label)
    if urlparse(value).scheme != 'https' or not urlparse(value).netloc:
        raise ValueError(f'{label}: invalid HTTPS URL')
    return value


def local_path(root, reference):
    required(reference, 'text reference')
    if Path(reference).is_absolute():
        raise ValueError(f'invalid reference: {reference}')
    path = (root / reference).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError(f'invalid reference: {reference}')
    return path


def generate(root):
    vendor = root / 'Vendor'
    specs = json.loads((vendor / 'dependency-metadata.json').read_text())
    expected_manifests = {str(p.relative_to(vendor)) for p in vendor.glob('*/manifest.json')}
    expected_manifests |= {str(p.relative_to(vendor)) for p in vendor.glob('rules/*/manifest.json')}
    declared = [s['manifest'] for s in specs.values() if 'manifest' in s]
    if set(declared) != expected_manifests or len(declared) != len(set(declared)):
        raise ValueError(f'dependency manifest coverage mismatch: expected {sorted(expected_manifests)}, declared {declared}')
    resources, entries, plugins, aliases = {}, [], [], set()
    for identity, spec in specs.items():
        try:
            if 'package' in spec:
                name = required(spec.get('name', spec['package']), 'name')
                # shortcut: reads the current exact-pin block; use a YAML parser if its shape expands.
                package = re.search(r'^  ' + re.escape(spec['package']) + r':\n((?:    .*\n)+)',
                                    (root / 'project.yml').read_text(), re.MULTILINE)
                if not package:
                    raise ValueError('missing XcodeGen package')
                fields = dict(re.findall(r'^    (url|exactVersion): ([^\n]+)$', package[1], re.MULTILINE))
                version = required(fields.get('exactVersion'), 'exactVersion')
                project = source = web_url(fields.get('url'), 'package URL')
                distribution = f'{source}/releases/tag/{version}'
            else:
                manifest = json.loads(local_path(vendor, spec['manifest']).read_text())
                name = required(spec.get('name', manifest.get('project')), 'name')
                version = required(manifest.get('release', manifest.get('upstreamVersion')), 'version')
                project = web_url(spec.get('projectURL'), 'projectURL')
                source = web_url(spec.get('sourceURL', project), 'sourceURL')
                distribution = web_url(manifest.get('url', manifest.get('upstreamURL')), 'distributionURL')
                if manifest.get('bundleSubpath') == 'Helpers/Plugins':
                    names = manifest.get('pluginNames')
                    arguments = manifest.get('defaultArguments')
                    if not isinstance(names, list) or not names or not isinstance(arguments, list):
                        raise ValueError('missing pluginNames/defaultArguments')
                    for alias in names:
                        required(alias, 'plugin alias')
                        if alias in aliases:
                            raise ValueError(f'duplicate plugin alias: {alias}')
                        aliases.add(alias)
                    for argument in arguments:
                        required(argument, 'plugin argument')
                    plugins.append(dict(program=identity, names=names,
                                        executableName=required(manifest.get('binary'), 'binary'),
                                        signIdentifier=required(manifest.get('signIdentifier'), 'signIdentifier'),
                                        defaultArguments=arguments))
            licenses, notices = spec.get('licenses'), spec.get('notices')
            if not isinstance(licenses, list) or not licenses or not isinstance(notices, list) or not notices:
                raise ValueError('licenses/notices must be text reference lists')
            references = list(licenses) + list(notices)
            for reference in references:
                path = local_path(vendor, reference)
                content = path.read_bytes()
                if not content.decode('utf-8').strip():
                    raise ValueError(f'empty text: {reference}')
                if reference.endswith(('/THIRD-PARTY-NOTICES', '/NOTICE')) and version not in content.decode():
                    raise ValueError(f'notice does not match selected version {version}: {reference}')
                resources[reference] = content
                # Existing aggregate notices reference shared full texts and extra notices.
                for link in re.findall(r'`(\.\./third-party-licenses/[^`]+\.(?:txt))`', content.decode()):
                    target = local_path(vendor, str(Path(reference).parent / link))
                    normalized = str(target.relative_to(vendor.resolve()))
                    if normalized not in references:
                        references.append(normalized)
                        notices = [*notices, normalized]
            entries.append(dict(id=identity, name=name, projectURL=project, sourceURL=source,
                                distributionURL=distribution, version=version,
                                licenses=licenses, notices=notices))
        except (ValueError, OSError, KeyError, TypeError) as error:
            raise ValueError(f'{identity}: {error}') from error
    resources['catalog.json'] = (json.dumps(dict(schemaVersion=1, dependencies=entries), indent=2) + '\n').encode()
    lines = ['// Generated by Scripts/dependency-metadata.py. Do not edit.', 'import Foundation', '',
             'extension ManagedPluginCatalog {', '  static let definitions: [ManagedPluginInfo] = [']
    for plugin in plugins:
        lines.append('    ManagedPluginInfo(')
        pairs = list(plugin.items())
        for index, (key, value) in enumerate(pairs):
            suffix = '),' if index == len(pairs) - 1 else ','
            lines.append(f'      {key}: {json.dumps(value, ensure_ascii=False)}{suffix}')
    lines += ['  ]', '}', '']
    return resources, '\n'.join(lines).encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--bundle', type=Path, help='verify actual Contents/Resources/ThirdParty')
    args = parser.parse_args()
    root = args.root.resolve()
    resources, swift = generate(root)
    if args.bundle:
        resolved = root / 'ShadowsocksX-NG2.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
        pins = json.loads(resolved.read_text())['pins']
        package = next(entry for entry in json.loads(resources['catalog.json'])['dependencies']
                       if entry['id'] == 'AgeSwift')
        if not any(pin.get('location') == package['sourceURL'] and
                   pin.get('state', {}).get('version') == package['version'] for pin in pins):
            raise ValueError('AgeSwift: resolved package disagrees with selected source/version')
    output = args.bundle or root / '.build/dependency-metadata/ThirdParty'
    files = {output / path: data for path, data in resources.items()}
    if not args.bundle:
        files[root / 'Domain/Plugin/ManagedPluginDefinitions.generated.swift'] = swift
    for path, data in files.items():
        if args.check or args.bundle:
            if not path.is_file() or path.read_bytes() != data:
                raise ValueError(f'{"bundle" if args.bundle else "stale generated metadata"}: {path}')
        elif not path.is_file() or path.read_bytes() != data:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
    print(f'Dependency metadata: {len(resources)} resources verified' if args.check or args.bundle
          else f'Dependency metadata: {len(resources)} resources generated')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError) as error:
        sys.exit(f'error: dependency metadata: {error}')
