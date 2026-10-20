"""Build a separate Shared Loader addon without replacing the exporter."""
from pathlib import Path
import importlib.util
import json
import struct
import zipfile

ROOT = Path(__file__).resolve().parent
RESOURCE = 'mods/EquippedStratagems/NativeStratagemRadial'
ARCHIVE = '9ba626afa44a3aa3.patch_0'
REVISION = 46
DISPLAY_NAME = "Diver's Best Friend - Automated Stratagem System (ASS)"
GUID = 'e42c1e5b-0828-4c54-a05e-4c9866b3ca72'
RECENT_FEATURE = 'Homecoming Update'
OUTPUT = ROOT.parent / 'dist' / 'releases' / 'r46' / 'DiversBestFriend-R46-BSL.zip'


def lua_literal(text):
    delimiter='='
    while ']'+delimiter+']' in text:delimiter+='='
    return '['+delimiter+'['+text+']'+delimiter+']'

def bootstrap(sources,order):
    template=(ROOT/'bsl_startup.lua').read_text(encoding='utf-8')
    embedded='\n'.join('['+json.dumps(name)+']='+lua_literal(sources[name].decode())+',' for name in order)
    return template.replace('-- __MODULES__',embedded).replace('-- __ORDER__',','.join(json.dumps(name) for name in order))


def build():
    spec = importlib.util.spec_from_file_location('exporter_packager', ROOT.parent / 'build.py')
    packager = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(packager)
    module_spec=importlib.util.spec_from_file_location('ass_modules', ROOT.parent/'tools/release_package.py')
    modules=importlib.util.module_from_spec(module_spec);module_spec.loader.exec_module(modules)
    sources=modules.sources('BSL')
    entry=sources['src/entry.lua'].decode()
    assert f'revision={REVISION},' in entry, 'Runtime revision must match release metadata'
    assert entry.count(f'R{REVISION} - {RECENT_FEATURE}') == 2, 'Runtime log headers must match release metadata'
    source=bootstrap(sources,['src/'+name+'.lua' for name in modules.ORDER])
    body=source.encode('utf-8')
    install_text = (ROOT / 'INSTALL.txt').read_text(encoding='utf-8')
    assert install_text.splitlines()[0] == DISPLAY_NAME, 'Install title must match release metadata'
    assert f'Revision {REVISION} - {RECENT_FEATURE}' in install_text, \
        'Install revision line must match release metadata'
    (ROOT / 'NativeStratagemRadial.lua').write_bytes(body)
    archive = packager.make_archive({packager.resource_hash(RESOURCE): struct.pack('<II', len(body), 2) + body})
    description = (f"Revision {REVISION}: HUD Plus 0.2.8 / 0.2.9 list/picker compatibility; Custom Stratagem Compendium 0.4.1 / HD2Runtime 0.40.0 code ownership support; exhausted stratagem state and Foliage Pass-Through 1.0 donor compatibility. All compatibility mods are optional. Retains bounded UI recovery, native guards, streamlined options, blacklist settings and existing bindings. Requires Mod Options Menu, Mod Bindings Menu v2 or newer (API 1) and a compatible shared loader. Install one ASS loader variant and restart after updates.")
    assert description.startswith(f'Revision {REVISION}:'), \
        'Manifest description must match release metadata'
    # Version is Arsenal's schema version, NOT the release revision. Keep the
    # same GUID for every radial release so imports retain the mod identity.
    manifest = {'Version': 1, 'Guid': GUID,
                'Name': DISPLAY_NAME, 'Description': description,
                'Options': [{'Name': 'Stratagem menu selection modes', 'Description': description, 'Include': ['Addon']}]}
    (ROOT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    files = {'Source/bsl_startup.lua':(ROOT/'bsl_startup.lua').read_bytes(),
             **{'Source/'+name:body for name,body in sources.items()},
             'manifest.json': (json.dumps(manifest, indent=2) + '\n').encode(),
             'INSTALL.txt': (ROOT / 'INSTALL.txt').read_bytes(),
             'HUD-PLUS-COMPATIBILITY.md': (ROOT / 'HUD-PLUS-COMPATIBILITY.md').read_bytes(),
             'CUSTOM-STRATAGEM-COMPATIBILITY.md': (ROOT / 'CUSTOM-STRATAGEM-COMPATIBILITY.md').read_bytes(),
             'RELEASE-r46.md': (ROOT.parent / 'docs/RELEASE-r46.md').read_bytes(),
             'LICENSE': (ROOT.parent / 'LICENSE').read_bytes(),
             'docs/BLACKLIST.md': (ROOT.parent / 'docs/BLACKLIST.md').read_bytes(),
             'Addon/' + ARCHIVE: archive, 'Addon/' + ARCHIVE + '.stream': b'',
             'Addon/' + ARCHIVE + '.gpu_resources': b''}
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(OUTPUT, 'w', compression=zipfile.ZIP_DEFLATED) as package:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            package.writestr(info, data)
    return OUTPUT


if __name__ == '__main__':
    print(build())
