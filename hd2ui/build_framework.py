"""Build the HD2UI framework addon as its own Arsenal zip.

This is the SHARED LIBRARY: other mods require('mods/dbf/hd2ui') and get the
module table (colors, geometry, layout, scene, backend_stingray, demo_counter).
It also ships the solid BC3 material 'mods/dbf/hd2ui/solid' that backends
need, so consumers never embed their own copy.

  patch_0 -> lua resource 'mods/dbf/hd2ui'      (assembled framework chunk)
  patch_1 -> texture+material 'mods/dbf/hd2ui/solid'
"""
from __future__ import annotations

import importlib.util
import json
import struct
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REVISION = 2
LUA_RESOURCE = 'mods/dbf/hd2ui'
MATERIAL_RESOURCE = 'mods/dbf/hd2ui/solid'
ARCHIVE = '9ba626afa44a3aa3'   # the standard loader-scanned archive name
GUID = 'f1a4c7b0-6d2e-4b8f-9c15-3a7e2d0f8b46'
DISPLAY_NAME = "HD2UI - Stingray HUD Framework (library)"
OUTPUT = HERE / f'DBF-hd2ui-R{REVISION}.zip'
ASSEMBLED = HERE / 'hd2ui_framework.lua'

MODULES = [
    ('hd2ui.core.colors', 'core/colors.lua'),
    ('hd2ui.core.geometry', 'core/geometry.lua'),
    ('hd2ui.core.layout', 'core/layout.lua'),
    ('hd2ui.scene', 'scene.lua'),
    ('hd2ui.backend_stingray', 'backend_stingray.lua'),
    ('hd2ui.demo_counter', 'demo_counter.lua'),
]

spec = importlib.util.spec_from_file_location('hd2ui_build_demo', HERE / 'build_demo.py')
DEMO = importlib.util.module_from_spec(spec)
spec.loader.exec_module(DEMO)
resource_hash = DEMO.resource_hash
TYPE_LUA, TYPE_TEXTURE, TYPE_MATERIAL = DEMO.TYPE_LUA, DEMO.TYPE_TEXTURE, DEMO.TYPE_MATERIAL
make_archive_multi = DEMO.make_archive_multi
parse_archive = DEMO.parse_archive
texture_resource = DEMO.texture_resource
material_resource = DEMO.material_resource
REGISTRY = DEMO.REGISTRY


def assemble_lua() -> bytes:
    parts = [f'-- HD2-Addon: {LUA_RESOURCE}\n',
             f'-- HD2UI framework r{REVISION}; assembled by hd2ui/build_framework.py; do not edit.\n',
             REGISTRY]
    for name, rel in MODULES:
        src = (HERE / rel).read_text(encoding='utf-8').replace('require(', '__hd2ui_require(')
        parts.append(f"__hd2ui_modules['{name}'] = function()\n{src}\nend\n")
    # Install surface: require('mods/dbf/hd2ui') -> api table; also set a
    # global so co-loaded addons are independent of resource exec order.
    exports = ', '.join(
        f"[{n.split('.')[-1]!r}] = __hd2ui_require({n!r})" for n, _ in MODULES)
    parts.append(f"""\
local api = {{ {exports} }}
api.version = 'r{REVISION}'
rawset(_G, '__DBF_HD2UI', api)
return api
""")
    return ''.join(parts).encode('utf-8')


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
    assert not gpu0 and len(gpu1) == 208
    p0 = parse_archive(patch0)
    assert p0[0]['data'][8:] == lua

    description = (
        f'HD2UI framework r{REVISION}: shared stingray HUD library for Lua mods '
        '(Bingus Shared Loader v15+). Display-list scene graph (rect/line/arc/ring/'
        'circle/text) with y-up geometry, 1080p reference layout, screen-GUI backend '
        'and a generated solid material. Other addons consume it with '
        "require('mods/dbf/hd2ui') -- no memory access of its own. Install alongside "
        'mods that declare it as a dependency.')
    manifest = {'Version': 1, 'Guid': GUID, 'Name': DISPLAY_NAME, 'Description': description,
                'Options': [{'Name': 'Core', 'Description': 'Framework modules + solid material.',
                             'Include': ['Addon']}]}
    files = {
        'manifest.json': (json.dumps(manifest, indent=2) + '\n').encode(),
        'README.txt': description.encode(),
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
