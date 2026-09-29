"""Build the DBF Floaty HUD addon zip (consumer of the HD2UI framework addon).

The product of concepts/floaty-hud: ONE graphical station, one grammar.

Contents:
  CORE/<archive>.patch_0          -> lua resource 'mods/dbf/floaty/hud'
                                     (product modules + entry, ONE chunk)
  ANCHOR/<key>/<archive>.patch_0  -> tiny preset lua 'mods/dbf/floaty/preset_anchor'
  SIZE/<n>/<archive>.patch_0      -> tiny preset lua 'mods/dbf/floaty/preset_size'
The manifest declares SubOptions so the Mod Options menu shows them; the
manager deploys the chosen folder's patch files, and the addon reads the
presets at install (game require of the deployed lua resource).

The framework itself (core + backend + solid material) is NOT in this zip --
it is the separate 'HD2UI' addon so any mod can reuse it.
"""
from __future__ import annotations

import importlib.util
import json
import re
import struct
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REVISION = 8
# Resource name is 'hud', NOT 'entry': BSL appears to special-case a lua
# resource named .../entry and the game AVs in .boot at boot when ours mounts
# (crash bisection 2026-09-29: R4 entry-named crashed, R5 hud-named stub booted).
LUA_RESOURCE = 'mods/dbf/floaty/hud'
ARCHIVE = '9ba626afa44a3aa3'   # the standard loader-scanned archive name
# GUID is PERMANENT for this mod (user rule 2026-09-29: never rotate it).
# New product line, distinct from the archived DBF Ammo HUD GUID.
GUID = '4be31d6a-8f52-4b3c-9a27-e01d5c7f4b82'
DISPLAY_NAME = "Diver's Best Friend - Floaty HUD"
OUTPUT = HERE / f'DBF-floaty-R{REVISION}.zip'
ASSEMBLED = HERE / 'hd2ui_floaty.lua'

MODULES = [
    ('hd2ui.memreader', 'memreader.lua'),
    ('hd2ui.live_scan', 'live_scan.lua'),
    ('hd2ui.ammo_reader', 'ammo_reader.lua'),
    ('hd2ui.ammo_cache', 'ammo_cache.lua'),
    ('hd2ui.ammo_chain', 'ammo_chain.lua'),
    ('hd2ui.station_bars', 'station_bars.lua'),
    ('hd2ui.station_holo', 'station_holo.lua'),
]
ENTRY = 'station_entry.lua'

ANCHORS = [
    ('gunside', 'Gun-side (default)',
     'The station docks right-below center, beside the first-person weapon. The Division look.'),
    ('crosshair', 'Right of crosshair',
     'The station parks beside the reticle.'),
]
SIZES = ['50', '75', '100', '125', '150', '200']


def _demo():
    spec = importlib.util.spec_from_file_location('hd2ui_build_demo', HERE / 'build_demo.py')
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


DEMO = _demo()
resource_hash = DEMO.resource_hash
TYPE_LUA = DEMO.TYPE_LUA
make_archive_multi = DEMO.make_archive_multi
parse_archive = DEMO.parse_archive
REGISTRY = DEMO.REGISTRY


def assemble_lua() -> bytes:
    parts = [f'-- HD2-Addon: {LUA_RESOURCE}\n',
             f'-- dbf floaty hud r{REVISION}; assembled by hd2ui/build_station.py; do not edit.\n',
             REGISTRY]
    for name, rel in MODULES:
        src = (HERE / rel).read_text(encoding='utf-8').replace('require(', '__hd2ui_require(')
        parts.append(f"__hd2ui_modules['{name}'] = function()\n{src}\nend\n")
    entry = (HERE / ENTRY).read_text(encoding='utf-8').replace('require(', '__hd2ui_require(')
    parts.append('do\n' + entry + '\nend\n')
    return ''.join(parts).encode('utf-8')


MIN_ARCHIVE = 512   # bytes; third-party floor is 464 on current builds. The
                    # game's DirectStorage queue errors on smaller archives on
                    # the 2026-09-24 build (every boot that deployed 240/256B
                    # preset archives crashed ~3s later at a fixed launcher
                    # offset; NxStorage names exactly that file every time).
                    # Pad tiny lua sources with comment lines before packing.

def pad_lua(data: bytes, res_len_floor: int) -> bytes:
    while struct.calcsize('<II') + len(data) < res_len_floor:
        data += b'-- pad for minimum archive size (DirectStorage floor)\n'
    return data

def preset_archive(res_name: str, lua_src: str) -> bytes:
    data = pad_lua(lua_src.encode('utf-8'), MIN_ARCHIVE - 192)
    patch, gpu = make_archive_multi([
        {'name': resource_hash(res_name), 'type': TYPE_LUA,
         'data': struct.pack('<II', len(data), 2) + data},
    ])
    assert not gpu
    assert len(patch) >= MIN_ARCHIVE, f'preset archive too small: {len(patch)}'
    return patch


def build(lua_only: bool = False) -> Path:
    lua = assemble_lua()
    ASSEMBLED.write_bytes(lua)
    if lua_only:
        return ASSEMBLED

    patch0, gpu0 = make_archive_multi([
        {'name': resource_hash(LUA_RESOURCE), 'type': TYPE_LUA,
         'data': struct.pack('<II', len(lua), 2) + lua},
    ])
    assert not gpu0
    assert len(patch0) >= MIN_ARCHIVE, 'core archive below DirectStorage floor'
    p0 = parse_archive(patch0)
    assert p0[0]['data'][8:] == lua

    description = (
        f'DBF Floaty HUD r{REVISION}: one Division-style weapon station — ammo, magazines '
        '(or heatsinks / fuel / charge), drawn with the game\'s own screen GUI. Instant reads '
        '(no scan delay). REQUIRES the separate "HD2UI - Stingray HUD Framework" addon (install '
        'both; the framework is a standalone library any mod can use). Anchor and size come from '
        'the Mod Options menu. Display-only: reads own process, no writes, no game calls. Log: '
        '%APPDATA%/Arrowhead/Helldivers2/hd2ui_floaty.log')

    options = [
        {'Name': 'Station anchor', 'Description': 'Where the station docks.',
         'SubOptions': [
             dict({'Name': name, 'Description': desc,
                   'Include': ['CORE', f'ANCHOR/{key}']},
                  **({'Selected': True} if key == 'gunside' else {}))
             for key, name, desc in ANCHORS]},
        {'Name': 'Station size', 'Description': 'Station scale, in 25%-steps.',
         'SubOptions': [
             dict({'Name': f'{s}%' + (' (default)' if s == '100' else ''),
                   'Description': f'Station at {s}% size.',
                   'Include': [f'SIZE/{s}']},
                  **({'Selected': True} if s == '100' else {}))
             for s in SIZES]},
    ]
    manifest = {'Version': 1, 'Guid': GUID, 'Name': DISPLAY_NAME,
                'Description': description, 'Options': options}

    files = {
        'manifest.json': (json.dumps(manifest, indent=2) + '\n').encode(),
        'README.txt': description.encode(),
        f'CORE/{ARCHIVE}.patch_0': patch0,
        f'CORE/{ARCHIVE}.patch_0.stream': b'',
        f'CORE/{ARCHIVE}.patch_0.gpu_resources': b'',
    }
    # Every deployed archive MUST ship the full triad (archive + empty
    # .stream + .gpu_resources companions) -- the game's DirectStorage mount
    # AVs on option archives deployed without them (crash root cause 2026-09-29).
    for key, _, _ in ANCHORS:
        base = f'ANCHOR/{key}/{ARCHIVE}.patch_0'
        files[base] = preset_archive(
            'mods/dbf/floaty/preset_anchor',
            f"-- DBF Floaty HUD anchor preset\nreturn '{key}'\n")
        files[base + '.stream'] = b''
        files[base + '.gpu_resources'] = b''
    for s in SIZES:
        base = f'SIZE/{s}/{ARCHIVE}.patch_0'
        files[base] = preset_archive(
            'mods/dbf/floaty/preset_size',
            f"-- DBF Floaty HUD size preset\nreturn '{s}'\n")
        files[base + '.stream'] = b''
        files[base + '.gpu_resources'] = b''

    # Guard: every deployed archive must ship its .stream/.gpu_resources
    # companions (mount-time AV otherwise -- proven crash 2026-09-29).
    for nm in list(files):
        if nm.endswith('.patch_0'):
            assert nm + '.stream' in files and nm + '.gpu_resources' in files, \
                f'deployed archive {nm} missing companion files'
            assert len(files[nm]) >= MIN_ARCHIVE, f'deployed archive {nm} below size floor'

    with zipfile.ZipFile(OUTPUT, 'w', compression=zipfile.ZIP_DEFLATED) as z:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            z.writestr(info, data)
    return OUTPUT


if __name__ == '__main__':
    print(build(lua_only='--lua-only' in sys.argv))
