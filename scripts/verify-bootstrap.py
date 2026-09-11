#!/usr/bin/env python3
"""Fail before executing the pinned compiler seed if its bytes or version drift."""
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile

root = Path(__file__).resolve().parents[1]
version = json.loads((root / 'src/NSharpLang.Compiler.Core/global.json').read_text())['msbuild-sdks']['NSharpLang.Sdk']
expected = {f'NSharpLang.Sdk.{version}.nupkg', 'NSharpLang.Runtime.0.1.0.nupkg'}
entries = {}
for line in (root / 'bootstrap/SHA256SUMS').read_text().splitlines():
    digest, name = line.split()
    if name not in expected or name in entries:
        raise SystemExit(f'Unexpected bootstrap manifest entry: {name}')
    entries[name] = digest
if set(entries) != expected:
    raise SystemExit('Bootstrap manifest does not match compiler SDK/runtime pins')
for name, digest in entries.items():
    path = root / 'bootstrap' / name
    if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        raise SystemExit(f'Bootstrap checksum mismatch: {name}')
    with zipfile.ZipFile(path) as package:
        if name.startswith("NSharpLang.Sdk.") and "tools/System.Reflection.MetadataLoadContext.dll" not in package.namelist():
            raise SystemExit("Bootstrap SDK is missing its metadata-loading dependency")
        spec = ET.fromstring(package.read(next(n for n in package.namelist() if n.endswith('.nuspec'))))
        metadata = next(e for e in spec if e.tag.endswith('metadata'))
        fields = {e.tag.split('}')[-1]: e.text for e in metadata}
        if f"{fields['id']}.{fields['version']}.nupkg" != name:
            raise SystemExit(f'Bootstrap package identity mismatch: {name}')
print('Pinned bootstrap SDK and runtime verified.')
