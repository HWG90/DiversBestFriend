"""Build a separate Shared Loader addon without replacing the exporter."""
from pathlib import Path
import importlib.util
import json
import struct
import zipfile

ROOT = Path(__file__).resolve().parent
RESOURCE = 'mods/EquippedStratagems/NativeStratagemRadial'
ARCHIVE = '9ba626afa44a3aa3.patch_0'
REVISION = 34
DISPLAY_NAME = "Diver's Best Friend Canary - Automated Stratagem System (ASS)"
GUID = 'e42c1e5b-0828-4c54-a05e-4c9866b3ca72'
RECENT_FEATURE = 'PageCue'
OUTPUT = ROOT / f'DiversBestFriendCanary-R{REVISION}-{RECENT_FEATURE}.zip'


def build():
    spec = importlib.util.spec_from_file_location('exporter_packager', ROOT.parent / 'build.py')
    packager = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(packager)
    source = ('-- HD2-Addon: ' + RESOURCE + '\n'
              "if rawget(_G,'NativeStratagemRadial') then return end\n")
    source += '\n'.join((ROOT / name).read_text(encoding='utf-8')
                        for name in ('layout.lua', 'guards.lua', 'native.lua', 'menu_latch.lua', 'input.lua', 'pointing.lua', 'camera.lua', 'icon_colors.lua', 'duplicate.lua', 'emote.lua', 'expanded.lua', 'selection.lua', 'release.lua', 'settings.lua', 'feedback.lua', 'entry.lua'))
    body = source.encode('utf-8')
    assert f'revision={REVISION},' in source, 'Runtime revision must match release metadata'
    # The runtime log headers are the first thing a CTD report shows; they must
    # name the packaged revision, not the one the source was last edited for.
    assert source.count(f'Canary R{REVISION} - {RECENT_FEATURE}') == 2, \
        'Runtime log headers must match release metadata'
    install_text = (ROOT / 'INSTALL.txt').read_text(encoding='utf-8')
    assert install_text.splitlines()[0] == DISPLAY_NAME, 'Install title must match release metadata'
    assert f'Canary Revision {REVISION} - {RECENT_FEATURE}' in install_text, \
        'Install revision line must match release metadata'
    (ROOT / 'NativeStratagemRadial.lua').write_bytes(body)
    archive = packager.make_archive({packager.resource_hash(RESOURCE): struct.pack('<II', len(body), 2) + body})
    description = (f"Revision {REVISION}: CANARY: Adds a sound cue when the native wheel changes pages. Retains native selection sounds, size presets and independent icon/label sizing, native background opacity, grouped settings and an illustrated guide. Optional Select on Release remains off by default. "
                   'Input interval applies to both Confirm and release sequences (0-250 ms, default 70). '
                   'Native and expanded wheels gray and dim icons during cooldown or delivery. '
                   'The selected stratagem shows its native remaining time below the name, restoring colors at expiry. '
                   'Uses the original HUD timer state, including native special cases. Retains all layouts, wedge appearance controls and centering. '
                   'Requires Mod Options Menu, Mod Bindings Menu v2 and Bingus Shared Loader API 1.')
    assert description.startswith(f'Revision {REVISION}: CANARY:'), \
        'Manifest description must match release metadata'
    # Version is Arsenal's schema version, NOT the release revision. Keep the
    # same GUID for every radial release so imports retain the mod identity.
    manifest = {'Version': 1, 'Guid': GUID,
                'Name': DISPLAY_NAME, 'Description': description,
                'Options': [{'Name': 'Stratagem menu selection modes', 'Description': description, 'Include': ['Addon']}]}
    (ROOT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    files = {'manifest.json': (json.dumps(manifest, indent=2) + '\n').encode(),
             'INSTALL.txt': (ROOT / 'INSTALL.txt').read_bytes(),
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
