"""Build the in-game offset-derivation addon (derive_entry) as a BSL zip.

Reuses hd2ui/build_demo.py's archive machinery (same packager hashes, same
multi-type container writer). Unlike the demo, this addon is LOGIC ONLY: one
lua resource, no texture/material patches (it never renders).

Usage:  python hd2ui/build_derive.py            -> DBF-derive-R1.zip
        python hd2ui/build_derive.py --lua-only -> assembled .lua only
"""
from __future__ import annotations

import importlib.util
import json
import struct
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
REVISION = 11
LUA_RESOURCE = 'mods/dbf/hd2ui/derive'
# The Shared Loader scans this standard mod-archive name (proven: demo, Aggro,
# Driver HUD all load from 9ba626afa44a3aa3.patch_*). A unique name does NOT
# get enumerated by BSL.
ARCHIVE = '9ba626afa44a3aa3'
GUID = 'b7e248f3-91ac-4d37-b546-1f8c30ad7c62'  # PERMANENT (user rule: GUID never rotates)
DISPLAY_NAME = "Diver's Best Friend - Derive (offset discovery, no render)"
OUTPUT = HERE / f'DBF-derive-R{REVISION}.zip'
ASSEMBLED = HERE / 'hd2ui_derive.lua'

MODULES = [
    ('hd2ui.memreader', 'memreader.lua'),
    ('hd2ui.live_scan', 'live_scan.lua'),
]
ENTRY = 'derive_entry.lua'


def _demo_mod():
    spec = importlib.util.spec_from_file_location('hd2ui_build_demo', HERE / 'build_demo.py')
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


DEMO = _demo_mod()
resource_hash = DEMO.resource_hash
TYPE_LUA = DEMO.TYPE_LUA
make_archive_multi = DEMO.make_archive_multi
parse_archive = DEMO.parse_archive

REGISTRY = DEMO.REGISTRY


def assemble_lua() -> bytes:
    parts = [f'-- HD2-Addon: {LUA_RESOURCE}\n',
             f'-- hd2ui derive r{REVISION}; assembled by hd2ui/build_derive.py; do not edit.\n',
             REGISTRY]
    for name, rel in MODULES:
        src = (HERE / rel).read_text(encoding='utf-8').replace('require(', '__hd2ui_require(')
        parts.append(f"__hd2ui_modules['{name}'] = function()\n{src}\nend\n")
    entry = (HERE / ENTRY).read_text(encoding='utf-8').replace('require(', '__hd2ui_require(')
    parts.append('do\n' + entry + '\nend\n')
    return ''.join(parts).encode('utf-8')


def build(lua_only: bool = False) -> Path:
    lua = assemble_lua()
    ASSEMBLED.write_bytes(lua)
    if lua_only:
        return ASSEMBLED

    lua_name = resource_hash(LUA_RESOURCE)
    patch0, gpu0 = make_archive_multi([
        {'name': lua_name, 'type': TYPE_LUA, 'data': struct.pack('<II', len(lua), 2) + lua},
    ])
    assert not gpu0
    p0 = parse_archive(patch0)
    assert [e['type'] for e in p0] == [TYPE_LUA] and p0[0]['data'][8:] == lua

    description = (f'hd2ui derive r{REVISION}: in-process memory scanner for ammo-offset '
                   'derivation. File-RPC under %APPDATA%/Arrowhead/Helldivers2/derive_*.{txt,log}. '
                   'Display-only (ReadProcessMemory on its own process); no rendering, no writes.')
    manifest = {'Version': 1, 'Guid': GUID, 'Name': DISPLAY_NAME, 'Description': description,
                'Options': [{'Name': 'Core', 'Description': 'Derivation scanner logic.', 'Include': ['Addon']}]}
    files = {
        'manifest.json': (json.dumps(manifest, indent=2) + '\n').encode(),
        'README.txt': description.encode(),
        f'Addon/{ARCHIVE}.patch_0': patch0,
        f'Addon/{ARCHIVE}.patch_0.stream': b'',
        f'Addon/{ARCHIVE}.patch_0.gpu_resources': b'',
    }
    with zipfile.ZipFile(OUTPUT, 'w', compression=zipfile.ZIP_DEFLATED) as z:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            z.writestr(info, data)
    return OUTPUT


if __name__ == '__main__':
    print(build(lua_only='--lua-only' in sys.argv))
