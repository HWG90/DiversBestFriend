"""Build a separate Shared Loader addon without replacing the exporter."""
from pathlib import Path
import importlib.util
import json
import struct
import zipfile

ROOT = Path(__file__).resolve().parent
RESOURCE = 'mods/EquippedStratagems/NativeStratagemRadial'
ARCHIVE = '9ba626afa44a3aa3.patch_0'
REVISION = 41
DISPLAY_NAME = "Diver's Best Friend - Automated Stratagem System (ASS)"
GUID = 'e42c1e5b-0828-4c54-a05e-4c9866b3ca72'
RECENT_FEATURE = 'MissionBlacklist'
OUTPUT = ROOT / f'DiversBestFriend-R{REVISION}-{RECENT_FEATURE}.zip'


def build():
    spec = importlib.util.spec_from_file_location('exporter_packager', ROOT.parent / 'build.py')
    packager = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(packager)
    source = ('-- HD2-Addon: ' + RESOURCE + '\n'
              "if rawget(_G,'NativeStratagemRadial') then return end\n")
    source += '\n'.join((ROOT / name).read_text(encoding='utf-8')
                        for name in ('layout.lua', 'guards.lua', 'native.lua', 'menu_latch.lua', 'mission_blacklist.lua', 'input.lua', 'pointing.lua', 'camera.lua', 'icon_colors.lua', 'duplicate.lua', 'emote.lua', 'expanded.lua', 'selection.lua', 'release.lua', 'blacklist.lua', 'settings.lua', 'feedback.lua', 'entry.lua'))
    body = source.encode('utf-8')
    assert f'revision={REVISION},' in source, 'Runtime revision must match release metadata'
    # The runtime log headers are the first thing a CTD report shows; they must
    # name the packaged revision, not the one the source was last edited for.
    assert source.count(f'R{REVISION} - {RECENT_FEATURE}') == 2, \
        'Runtime log headers must match release metadata'
    install_text = (ROOT / 'INSTALL.txt').read_text(encoding='utf-8')
    assert install_text.splitlines()[0] == DISPLAY_NAME, 'Install title must match release metadata'
    assert f'Revision {REVISION} - {RECENT_FEATURE}' in install_text, \
        'Install revision line must match release metadata'
    (ROOT / 'NativeStratagemRadial.lua').write_bytes(body)
    archive = packager.make_archive({packager.resource_hash(RESOURCE): struct.pack('<II', len(body), 2) + body})
    description = (f"Revision {REVISION}: streamlined options leave Enable Mod, Mode, Sound feedback, Experimental layout, Preset, Controller Select on Release and Input interval, plus three mission blacklist entries. Suppresses appearance size, icon, label, opacity and color controls without changing saved values. Vertical offset is disabled at zero. Retains R40 native selection fixes, stable-ID blacklist persistence and equipped-stratagem protection. Requires Mod Options Menu, Mod Bindings Menu v2 or newer (API 1) and Shared Loader API 1.")
    assert description.startswith(f'Revision {REVISION}:'), \
        'Manifest description must match release metadata'
    # Version is Arsenal's schema version, NOT the release revision. Keep the
    # same GUID for every radial release so imports retain the mod identity.
    manifest = {'Version': 1, 'Guid': GUID,
                'Name': DISPLAY_NAME, 'Description': description,
                'Options': [{'Name': 'Stratagem menu selection modes', 'Description': description, 'Include': ['Addon']}]}
    (ROOT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    files = {'manifest.json': (json.dumps(manifest, indent=2) + '\n').encode(),
             'INSTALL.txt': (ROOT / 'INSTALL.txt').read_bytes(),
             'docs/BLACKLIST.md': (ROOT.parent / 'docs/BLACKLIST.md').read_bytes(),
             'Addon/' + ARCHIVE: archive, 'Addon/' + ARCHIVE + '.stream': b'',
             'Addon/' + ARCHIVE + '.gpu_resources': b''}
    with zipfile.ZipFile(OUTPUT, 'w', compression=zipfile.ZIP_DEFLATED) as package:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            package.writestr(info, data)
    return OUTPUT


if __name__ == '__main__':
    print(build())
