# R50-hellforge.18-preview: HellForge 0.5

Prepared against `1b164b9` (.17 preview) for HellForge 0.5.0-beta (806685d, engine 0.1.58, SDK 20, game build
25480438), which updated itself on 2026-11-25. Public release remains .11.

## What broke

On 0.5 the .17 log stopped after start-up. The first new line was `witness owner_map_value: 4 of 20 bytes rewritten by
HellForge`, which no 0.4 session had logged. HellForge 0.5 logs `entity table: 4096 records a world (the game's 2048)
and entity maps of 8192 slots, behind the Game block`, and it rewrites every displacement that names those maps.

- **Registry keys.** R46 reads the local player's key at registry `+0xf32f20 + index*24`. The lea inside
  owner_map_value (`lea rax,[rax+0x1e65e4]`, scaled by 8) became `0x104c390`, so the keys moved to `+0x8261c80` and the
  old place reads 0. The code-entry chain then stopped at "avatar identity mismatch": no local player, no codes, no
  entry. The HUD's wheel input, terminal arrows and weapon strip read the same constant (the strip as records
  `+0xf32f18`).
- **Projectile list** (weapon strip only). With mods adding projectiles, HellForge copies the list into a block of its
  own and rewrites the reader at 0x75a376: bound `0x15f` to `0x164`, table `game+0x37c7670` to `game+0x14f29000`. The
  351 vanilla entries are identical in both, so vanilla ammunition still showed. Mods' projectiles were refused.
- The registry's lookups (`+0xf22ec8`, `+0xf1aeb0`) hold pointers to their slots and follow the move by themselves.
  The stratagem definition table move was already read from the code (`0x66d550`).

Evidence is read-only, from the running 0.5 game (pid 3415065, 2026-11-25 13:40Z). The live code was diffed against
the unpacked stock image (`native-work/evidence/game-pre1020.dll` in the Linux HD2 repo): 5104 changed runs, 3409
rewritten disp32s. Every DBF and HUD-Lua constant was matched against the rewritten values. Only the two above hit.
DBF's chain was then walked by hand. With 0xf32f20 the key read 0 and the unit key 0x44a did not match. With the
code's offset the key was 0x44a and the whole chain matched.

## Changes

- `tools/map_addresses.py`: an address may be `disp32_of` an emitted witness. The witness's R46 bytes there times the
  scale must equal an offset given earlier. `REGISTRY_KEYS_DISPLACEMENT` (0xfd9c53, owner_map_value+10, x 8 =
  `REGISTRY_KEYS_OFFSET`) is generated from the same R46 inputs; the header and receipt were regenerated.
- `src/game.c`: the chain reads the keys at `disp32 * 8` every read. Accepted are R46's offset, or one past it below
  2^31. Anything else is "registry keys unrecognised"; an unreadable disp32 is "registry keys unreadable".
- `hud/wheel_input.lua`, `hud/terminal.lua`, `hud/weapon_reader.lua`: the same rule. The weapon reader also gains the
  owner_map_value witness. It reads the projectile bound and table from 0x75a378 and 0x75a395: the bound must lie in
  `0x15f..0x115e`, and the table must be vanilla, or 8-aligned outside the image.
- Admission is unchanged. HellForge reports the rewritten bytes (`hellforge_lua_rewrites`), and they stay masked.
- `build.sh wine-test`: `DBF_WINE_CASES` runs only the cases named, with none of the probes. The non-entry cases open
  no window and press no keys, so they can run while the game is up.

## Tests

- `build.sh test`, with `DBF_R46_DIR` set to the R46 reference: 25 passed, 0 failed, and 61 Python tests OK. The
  real-input mapper tests pass, and the committed files are current.
- New: test_game `test_registry_keys_moved`, plus mapper `disp32_of` tests (an emitted address, and 11 refusals).
  The HUD Lua fixtures gain moved and refused cases (wheel input, terminal, weapon strip with a mod projectile at
  0x160). The new Wine case `moved-keys` runs the real DLL over the generated witness table and logs owner_map_value's
  4 masked bytes, as the live log did; every code is read.
- Each new case fails against the .17 sources: rows without codes in Wine, and failed asserts in the Lua fixtures.
- Wine cases run: host-api5, masked-log, moved-keys, retry (4 passed). The code-entry cases were not run, because
  they take the desktop's focus and keys and the game was running.

## Package

`build/exports/divers-best-friend-R50-hellforge.18-preview.zip`, SHA-256
`4a8cf815e8a400ede40b118634e254ed72c2b5d13bf276f88e899a9fc8e40029`, 75 files. `verify-package` passes.

## Install

Installed 2026-11-25 15:00Z, on the user's word. The launcher was open and the game was not running. The new zip was
copied into `mods/` as `.part`, the .17 zip (`8d9c3dba…`) was moved to
`backport-backups/20261125T150051Z-dbf-18-hellforge-0.5/` (with `receipt.json`), and the copy was renamed into place.
HellForge unpacked it to `mods/.unpacked/divers-best-friend-R50-hellforge.18-preview-4a8cf815e8a4`, whose DLL equals
the build's (`842a1d29…`). `HellForge.Cli mods` lists DBF Reforged R50-hellforge.18-preview, enabled, with no
problems. The in-game check is pending.

## Package for release

The package's INSTALL.md (from `NEST-BUNDLE.md`) still named .11, so it now names this zip and HellForge 0.5. Rebuilt
zip: SHA-256 `dc282f23fe4aca0e3a07fd2ca14e2de437b079cbe590c8d30b01a42dd521183a`, 75 files. `verify-package` passes, and
the DLL is unchanged (`842a1d29…`). The installed `4a8cf815…` zip differs only in INSTALL.md. No machine paths are in
the zip.

## R50-hellforge.19-preview: the cooldown dock on 0.5

In game on .18 (2026-11-25 15:36–15:37Z), the user reported that the dock's icons and overlays were "either
completely transparent or not aligned". Matching the screenshot paste times against the log's mode lines showed the
first was taken in Inside mode and the second in Below mode. In both, every drawing DBF places from a tile sat 36 px
(18 HUD units) too high: the timers, the charge count (DBF's own label; the native badge is hidden), and the Inside
backdrop. Shifted up, the backdrop dimmed the top of each tile and the band above it. The native tiles themselves drew
as in the accepted .17 look; the colours of icon and fill match.

Measured live in a mission (4K), read-only. The window capture used KWin's `kwin_capture`, and tile memory was read
from `/proc`:
- DBF's blur probe drew a 256 px square at screen centre in each world. The main world and the first other world, the
  one the dock uses, both put it on rows 952–1207 and columns 1792–2047, exactly as drawn. The other world's copy is
  dimmed by post-processing. Worlds 2–4 show nothing.
- In one synchronized capture, the tiles' own transforms (tile 0 at x 1752..1848, y 215.4..311.4 y-up) matched the
  drawn tiles to the pixel.

So the 18-unit lift .17 added (`GUI_LIFT_UNITS`, after a 0.4 session saw the timers 36 px low) is wrong on 0.5, and
.19 removes it. Dock points and tile rectangles are the HUD transforms as they are. The 0.4 offset was never traced
to an engine value, so the notes no longer claim 0.4. `dock_viewport_report` still logs the geometry.

Tests: `build.sh test` with `DBF_R46_DIR` gives 25/25 plus 61 Python tests. The dock test now expects unlifted points
and rectangles, and it fails on the lifted code. Wine: host-api5, masked-log, moved-keys and retry pass.

Package `build/exports/divers-best-friend-R50-hellforge.19-preview.zip`, SHA-256
`f30d9dc11c0d284b665b0597b7bfb144ca3992b267539da0031cd5723f9896b9`, DLL `94462d85…`. `verify-package` passes, and no
machine paths are inside. Not installed yet.
