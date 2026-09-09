#!/usr/bin/env python3
"""Require a complete, mutually resolvable set of N# release packages."""
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
import zipfile

expected = {
    'NSharpLang.Sdk', 'NSharpLang.Runtime', 'NSharpLang.Templates',
    'NSharpLang.Compiler', 'NSharpLang.Compiler.Core',
}
packages = {}
for path in Path(sys.argv[1]).glob('*.nupkg'):
    with zipfile.ZipFile(path) as archive:
        spec = ET.fromstring(archive.read(next(n for n in archive.namelist() if n.endswith('.nuspec'))))
        for element in spec.iter():
            element.tag = element.tag.split('}')[-1]
        metadata = spec.find('metadata')
        package_id = metadata.findtext('id')
        if package_id == 'NSharpLang.Sdk' and 'tools/System.Reflection.MetadataLoadContext.dll' not in archive.namelist():
            raise SystemExit('SDK package is missing System.Reflection.MetadataLoadContext.dll')
        if package_id in packages:
            raise SystemExit(f'Duplicate package in release: {package_id}')
        packages[package_id] = (metadata.findtext('version'), metadata.findall('.//dependency'))
if set(packages) != expected:
    raise SystemExit(f'Release package set mismatch: missing {expected - set(packages)}, unexpected {set(packages) - expected}')
for package_id, (_, dependencies) in packages.items():
    for dependency in dependencies:
        target, version = dependency.get('id'), dependency.get('version')
        if target.startswith('NSharpLang.'):
            if target not in packages or packages[target][0] != version:
                raise SystemExit(f'{package_id} requires {target} {version}, which this release does not contain')
print(f'Validated {len(packages)} packages and all internal package dependencies.')
