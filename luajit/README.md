# Diver's Best Friend R50, LuaJIT (game build 26251122)

R50 is R46 as a plain LuaJIT folder mod for Live Lua Loader R38 on HELLDIVERS 2 build 26251122. Every module uses LuaJIT's own `ffi` and `bit`. There is no Lua 5.1/cffi adapter and no `hd2_nativeinfo` DLL. Tested on Linux under Proton.

The `main` branch is still the R46 release for the shared/startup loaders. This branch adds only this folder.

## Install

1. Install [Live Lua Loader](https://github.com/HWG90/LLL) R38 (LuaJIT).
2. Copy `divers_best_friend` into `%LOCALAPPDATA%\LLL\Helldivers2\Mods`. Under Proton, that folder is inside the game's prefix. Replace any older `divers_best_friend` folder. Don't merge into it.
3. Start the game. The settings are in Mod Options Menu under Diver's Best Friend.

## Changes from the R46 release

- Ported to LuaJIT and game build 26251122.
- Starts at load instead of waiting for the stratagem menu to open once.
- Auto Terminal Complete, and Terminal input (Instant or Enter arrows).
- Instant complete Stratagems (off by default).
- Compact cooldown row option.
- A stratagem that leaves the list (such as SSSD Delivery) no longer leaves a ghost row behind.
- Uses the runtime's `hd2.memory` for reads when it is there.
- Weapon status strip next to the weapon row.

## Offline checks (stock LuaJIT, no game)

```
cc -O2 -shared -fPIC -o tests/fake_win32.so tests/fake_win32.c
luajit tests/offline_instant.lua divers_best_friend
luajit tests/offline_terminal.lua divers_best_friend
luajit tests/offline_cold.lua divers_best_friend
luajit tests/offline_scale_tween.lua divers_best_friend
luajit tests/offline_compact_row.lua divers_best_friend
luajit tests/offline_backend.lua divers_best_friend backend.txt
luajit tests/offline_runtime_memory.lua divers_best_friend runtime-memory
```

Run these from this folder. `fake_win32.so` stands in for kernel32/user32, and `synthetic_image.lua` lays out a synthetic game.dll image. `offline_capture.lua` needs a captured game image, and `offline_archive.lua` needs a built archive, so neither runs on this tree alone.

Synced from development commit `ee120fb`.
