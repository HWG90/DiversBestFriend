# Development

## Repository contents

- `native-selection-poc/`: modular Lua implementation, assembled addon, package metadata, and tests. The directory name is retained from the working prototype.
- `native-selection-poc/RESEARCH.md`: implementation history and native ownership/input notes.
- `native-selection-poc/EMOTE-WHEEL.md`: native-wheel and expanded-layout investigation notes.
- `build.py`: minimal archive/hash helpers for the Shared Loader package format.
- `scripts/build.py`: builds the current manager ZIP.
- `scripts/test.py`: package validation and optional native-LuaJIT fixtures.
- `run_lua.py`: isolated Lua fixture runner, with `HD2_LUA51_DLL` override.
- `assets/`: banner PNG, editable SVG, and reproducible artwork script.

Research notes describe earlier iterations as well as the current implementation. Captured game binaries, raw memory/probe logs, dependencies, the external helper executable, and broken historical release ZIPs are not included. Some historical evidence paths in those notes refer to private local development captures, not downloadable repository files.

## Build

Python 3.10+ is sufficient for packaging; no third-party Python modules are needed:

```sh
python scripts/build.py
python scripts/test.py --package-only
```

The ZIP is written under `native-selection-poc/`. The builder combines the Lua modules, creates the plaintext addon resource, and emits the Arsenal manifest plus patch/stream/gpu_resources files. Generated ZIPs are distributed as GitHub Release assets rather than committed.

Runtime/log revision, package filename, display name, manifest description, and install title must be updated together for a new release. Keep the manager GUID `e42c1e5b-0828-4c54-a05e-4c9866b3ca72`, resource name, and setting/binding IDs stable so upgrades preserve identity. Arsenal manifest `Version: 1` is its schema version, not the addon revision.

## Tests

For the Lua fixtures, use Windows and your own installed game's `lua51.dll`. The runner loads that DLL into a separate test process; it does not attach to the game.

```powershell
$env:HD2_LUA51_DLL = 'D:/SteamLibrary/steamapps/common/Helldivers 2/bin/lua51.dll'
python scripts/test.py
```

With the default Steam path on C:, no environment override is needed. The full suite covers native matrix extraction and both-axis centering, layout bounds, native context ownership, widget allocation, mode switching, list order, paging, pointer selection, icon materials, live descriptors including Maelstrom, input cancellation, and package reproducibility. GitHub Actions performs package-only checks because the game DLL is not redistributed.

Mocks validate our logic and expected native call arguments; they cannot prove renderer stability or successful deployment in the live game. Test a new native change in-game before declaring it confirmed.

## How it works

The addon runs through the shared in-game Lua update chain. It reads the local mission HUD and current definitions, validates owners and signatures, and constructs separate native UI widgets. Radial modes reuse the native wheel's mouse/stick cursor integration. Experimental wedges use owned native sprites; copied cards preserve original rows.

On Confirm, a bounded controller feeds the live definition's direction code into the native stratagem input handler, with short synchronous action-byte pulses and restoration. It does not send OS keypresses, directly set a selected stratagem ID, auto-throw, or spawn anything. The native matcher decides availability. Closing the menu, changing ownership/membership, manual input, or focus loss cancels input as appropriate.

The r22 centering correction projects the native 4x4 GUI matrix onto its X/Z screen plane, then maps the viewport midpoint into list-local coordinates. It accounts for inherited scale and translation rather than using a fixed 575-unit correction.

## Contributing

Small, focused changes and reproducible bug reports are welcome. Keep native calls guarded, preserve ownership/cleanup behavior, and separate isolated-test claims from in-game evidence. Don't commit game captures, game DLLs, access tokens, personal logs, or dependency packages. Project code is MIT licensed; game assets and third-party projects are not covered by that license.
