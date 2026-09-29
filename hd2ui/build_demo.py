"""Build the hd2ui demo as a Bingus Shared Loader addon zip for Arsenal.

Produces two patch archives (same container family as build.py::make_archive):
  patch_0  -> one `lua` resource: the assembled demo chunk
  patch_1  -> a `texture` + `material` pair sharing one name (our solid material)
              with the texture pixels in the `.gpu_resources` sidecar

Everything in patch_1 is generated here from format knowledge (see
hd2ui/STINGRAY_NOTES.md); no third-party bytes are copied.

Usage:  python hd2ui/build_demo.py            (from repo root)
        python hd2ui/build_demo.py --lua-only  (write assembled .lua, no zip)
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
REVISION = 1
LUA_RESOURCE = 'mods/dbf/hd2ui/demo'
MATERIAL_RESOURCE = 'mods/dbf/hd2ui/solid'
ARCHIVE = '9ba626afa44a3aa3'
GUID = '6f1a2c0e-7d4b-4b7e-9c31-2e8a5d0f4a11'  # hd2ui demo (distinct from ASS)
DISPLAY_NAME = "Diver's Best Friend - hd2ui Demo Counter"
OUTPUT = HERE / f'DBF-hd2ui-demo-R{REVISION}.zip'
ASSEMBLED = HERE / 'hd2ui_demo.lua'

# Module order matters only for readability; the registry resolves lazily.
MODULES = [
    ('hd2ui.core.colors', 'core/colors.lua'),
    ('hd2ui.core.geometry', 'core/geometry.lua'),
    ('hd2ui.core.layout', 'core/layout.lua'),
    ('hd2ui.scene', 'scene.lua'),
    ('hd2ui.backend_stingray', 'backend_stingray.lua'),
    ('hd2ui.demo_counter', 'demo_counter.lua'),
]
ENTRY = 'demo_entry.lua'

# --------------------------------------------------------------------------
# Hashing: reuse the repo packager (MurmurHash64A, seed 0) so names match
# what the game / Shared Loader compute.
# --------------------------------------------------------------------------
def _packager():
    spec = importlib.util.spec_from_file_location('exporter_packager', ROOT / 'build.py')
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

PK = _packager()
resource_hash = PK.resource_hash
TYPE_LUA = resource_hash('lua')
TYPE_TEXTURE = resource_hash('texture')
TYPE_MATERIAL = resource_hash('material')
assert TYPE_LUA == 0xA14E8DFA2CD117E2
assert TYPE_TEXTURE == 0xCD4238C6A0C69E32
assert TYPE_MATERIAL == 0xEAC0B497876ADEDF

GUI_SHADER_TEMPLATE = 0x5F8113D2          # game GUI shader template id
DIFFUSE_MAP_SLOT = resource_hash('diffuse_map') >> 32
assert DIFFUSE_MAP_SLOT == 0x3AA8B87E


# --------------------------------------------------------------------------
# Lua assembly
# --------------------------------------------------------------------------
REGISTRY = """\
local __hd2ui_modules, __hd2ui_loaded = {}, {}
local __hd2ui_real = require
local function __hd2ui_require(name)
  local m = __hd2ui_loaded[name]
  if m ~= nil then return m end
  local f = __hd2ui_modules[name]
  if not f then
    -- Not ours: defer to the game's require (Arsenal/BSL preset lua resources
    -- arrive as mods/<mod>/preset_* lookups the manager deployed).
    local ok, v = pcall(__hd2ui_real, name)
    if ok then
      __hd2ui_loaded[name] = v
      return v
    end
    error('hd2ui: missing module ' .. tostring(name))
  end
  m = f()
  if m == nil then m = true end
  __hd2ui_loaded[name] = m
  return m
end
"""


def assemble_lua() -> bytes:
    parts = [f'-- HD2-Addon: {LUA_RESOURCE}\n',
             f'-- hd2ui demo counter r{REVISION}. Assembled by hd2ui/build_demo.py; do not edit.\n',
             REGISTRY]
    for name, rel in MODULES:
        src = (HERE / rel).read_text(encoding='utf-8').replace('require(', '__hd2ui_require(')
        parts.append(f"__hd2ui_modules['{name}'] = function()\n{src}\nend\n")
    entry = (HERE / ENTRY).read_text(encoding='utf-8').replace('require(', '__hd2ui_require(')
    parts.append('do\n' + entry + '\nend\n')
    return ''.join(parts).encode('utf-8')


# --------------------------------------------------------------------------
# Solid material: texture (DDS BC3, solid white) + material referencing it.
# --------------------------------------------------------------------------
def bc3_solid_white_block() -> bytes:
    # BC3 block = 8 bytes alpha (a0, a1, 6 index bytes) + 8 bytes BC1 color
    # (c0, c1 as RGB565, 4 index bytes). a0=a1=0xFF and c0=c1=0xFFFF with all
    # indices 0 decodes to opaque white everywhere.
    return bytes([0xFF, 0xFF, 0, 0, 0, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0])


def mip_chain_blocks(w: int, h: int, mips: int) -> int:
    total = 0
    for _ in range(mips):
        total += max(1, (w + 3) // 4) * max(1, (h + 3) // 4)
        w, h = max(1, w // 2), max(1, h // 2)
    return total


TEX_W, TEX_H, TEX_MIPS = 8, 16, 5
DXGI_BC3_UNORM = 77


def dds_header() -> bytes:
    # Standard DDS_HEADER (124 bytes) + DDS_HEADER_DXT10 (20 bytes), preceded by 'DDS '.
    DDSD = 0x1 | 0x2 | 0x4 | 0x1000 | 0x20000 | 0x80000  # CAPS|HEIGHT|WIDTH|PIXELFORMAT|MIPMAPCOUNT|LINEARSIZE
    linear = max(1, TEX_W // 4) * max(1, TEX_H // 4) * 16
    hdr = struct.pack('<7I', 124, DDSD, TEX_H, TEX_W, linear, 1, TEX_MIPS)
    hdr += b'\0' * 44                                        # reserved1[11]
    hdr += struct.pack('<II4s5I', 32, 0x4, b'DX10', 0, 0, 0, 0, 0)  # DDS_PIXELFORMAT
    DDSCAPS = 0x8 | 0x400000 | 0x1000                       # COMPLEX|MIPMAP|TEXTURE
    hdr += struct.pack('<5I', DDSCAPS, 0, 0, 0, 0)          # caps..reserved2
    assert len(hdr) == 124
    dx10 = struct.pack('<5I', DXGI_BC3_UNORM, 3, 0, 1, 0)   # format, TEXTURE2D, misc, arraySize, misc2
    return b'DDS ' + hdr + dx10


def texture_resource() -> tuple[bytes, bytes]:
    """Returns (main data blob, gpu_resources payload)."""
    hd2 = bytearray(192)
    struct.pack_into('<I', hd2, 8, 0xFFFFFFFF)
    data = bytes(hd2) + dds_header()
    gpu = bc3_solid_white_block() * mip_chain_blocks(TEX_W, TEX_H, TEX_MIPS)
    return data, gpu


def material_resource(texture_name: int) -> bytes:
    # VERIFIED-IN-GAME solid GUI material (byte layout captured from a working
    # mod's archive; earlier hand-packed framing was wrong: the shader param
    # name is a full u64 at 0x88 and the diffuse texture is an engine id32
    # (0xE6AB3CEC) at 0x90, not our mounted texture at all). Shipped verbatim.
    import os
    asset = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'assets', 'solid.material')
    with open(asset, 'rb') as f:
        blob = f.read()
    assert len(blob) == 160, 'solid.material must be the exact 160B verified blob'
    return blob


# --------------------------------------------------------------------------
# Multi-type archive (superset of build.py::make_archive)
# --------------------------------------------------------------------------
def make_archive_multi(entries: list[dict]) -> tuple[bytes, bytes]:
    """entries: [{name, type, data, gpu?}] -> (archive bytes, gpu_resources bytes)."""
    types: list[int] = []
    for e in entries:
        if e['type'] not in types:
            types.append(e['type'])
    entries = sorted(entries, key=lambda e: (types.index(e['type']), e['name']))
    count = len(entries)
    header_len = 72 + 32 * len(types) + 80 * count
    offset = (header_len + 15) & ~15
    body = bytearray(offset)
    gpu = bytearray()
    records = bytearray()
    for index, e in enumerate(entries, start=1):
        data = e['data']
        gpu_blob = e.get('gpu', b'')
        gpu_off = 0
        if gpu_blob:
            gpu += b'\0' * (-len(gpu) % 64)
            gpu_off = len(gpu)
            gpu += gpu_blob
        records += struct.pack('<7Q6I', e['name'], e['type'], offset, 0, gpu_off,
                               0xB000, 0x7C100, len(data), 0, len(gpu_blob), 16, 64, index)
        body += data
        body += b'\0' * (-len(body) % 16)
        offset = len(body)
    header = struct.pack('<III20sQQ24s', 0xF0000011, len(types), count, b'', offset, 0, b'')
    type_recs = b''.join(
        struct.pack('<IIQIIII', 0, 0, t, sum(1 for e in entries if e['type'] == t), 0, 16, 64)
        for t in types)
    body[:header_len] = header + type_recs + records
    return bytes(body), bytes(gpu)


def parse_archive(blob: bytes) -> list[dict]:
    """Read back an archive (used for self-check)."""
    magic, ntypes, count = struct.unpack_from('<III', blob, 0)
    assert magic == 0xF0000011, hex(magic)
    off = 72 + 32 * ntypes
    out = []
    for _ in range(count):
        name, typ, doff, soff, goff, u1, u2, dsz, ssz, gsz, a1, a2, idx = struct.unpack_from('<7Q6I', blob, off)
        off += 80
        out.append(dict(name=name, type=typ, data=blob[doff:doff + dsz], gpu_off=goff, gpu_size=gsz, index=idx))
    return out


# --------------------------------------------------------------------------
def build(lua_only: bool = False) -> Path:
    lua = assemble_lua()
    ASSEMBLED.write_bytes(lua)
    if lua_only:
        return ASSEMBLED

    lua_name = resource_hash(LUA_RESOURCE)
    mat_name = resource_hash(MATERIAL_RESOURCE)
    patch0, gpu0 = make_archive_multi([
        {'name': lua_name, 'type': TYPE_LUA, 'data': struct.pack('<II', len(lua), 2) + lua},
    ])
    tex_data, tex_gpu = texture_resource()
    patch1, gpu1 = make_archive_multi([
        {'name': mat_name, 'type': TYPE_TEXTURE, 'data': tex_data, 'gpu': tex_gpu},
        {'name': mat_name, 'type': TYPE_MATERIAL, 'data': material_resource(mat_name)},
    ])
    assert not gpu0
    assert len(gpu1) == 16 * mip_chain_blocks(TEX_W, TEX_H, TEX_MIPS) == 208

    # Self-check: archives parse back to what we put in.
    p0 = parse_archive(patch0)
    assert [e['type'] for e in p0] == [TYPE_LUA] and p0[0]['data'][8:] == lua
    p1 = parse_archive(patch1)
    assert [e['type'] for e in p1] == [TYPE_TEXTURE, TYPE_MATERIAL]
    assert all(e['name'] == mat_name for e in p1)
    assert p1[0]['gpu_size'] == 208 and p1[0]['data'][192:196] == b'DDS '
    # The material is the byte-verified in-game blob (see material_resource):
    # shader param name u64 @0x88, engine diffuse id32 @0x90 -- NOT our mounted
    # texture hash. Pin the verified values so the blob cannot drift silently.
    assert struct.unpack_from('<II', p1[1]['data'], 0x80) == (1602294738, 0)
    assert struct.unpack_from('<Q', p1[1]['data'], 0x88) == (0x70C202B23AA8B87E,)
    assert struct.unpack_from('<I', p1[1]['data'], 0x90) == (0xE6AB3CEC,)

    description = (f'hd2ui demo r{REVISION}: a custom counter drawn with the engine screen GUI '
                   '(stingray Gui.triangle/Gui.text) to the right of the crosshair. Display only; '
                   'the number is a synthetic demo value, not weapon ammo. '
                   'Requires Bingus Shared Loader API 1 (v15+). Writes %APPDATA%/Arrowhead/Helldivers2/hd2ui_demo.log.')
    manifest = {'Version': 1, 'Guid': GUID, 'Name': DISPLAY_NAME, 'Description': description,
                'Options': [{'Name': 'Core', 'Description': 'Demo counter + solid GUI material.', 'Include': ['Addon']}]}
    files = {
        'manifest.json': (json.dumps(manifest, indent=2) + '\n').encode(),
        'README.txt': (HERE / 'DEMO_README.txt').read_bytes() if (HERE / 'DEMO_README.txt').exists() else description.encode(),
        f'Addon/{ARCHIVE}.patch_0': patch0,
        f'Addon/{ARCHIVE}.patch_0.stream': b'',
        f'Addon/{ARCHIVE}.patch_0.gpu_resources': b'',
        f'Addon/{ARCHIVE}.patch_1': patch1,
        f'Addon/{ARCHIVE}.patch_1.stream': b'',
        f'Addon/{ARCHIVE}.patch_1.gpu_resources': gpu1,
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
