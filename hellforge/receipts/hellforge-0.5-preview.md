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
