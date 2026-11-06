# Programmable weapon icons, build 25480438

## Evidence boundary

Read-only analysis of `hob-game-6AB3B43F.bin`, SHA-256
`642b0aac0b4f577054993a965054827455ef143ced9895b2dfd09d1ecd433a37`,
PE timestamp `0x6ab3b43f`, mapped size `0x4744000`. All addresses below are
RVAs. The added reader witnesses are checked against this image by
`hellforge/tools/test_weapon_strip.py`. No game-process writes or installation
were performed. This establishes the native decoding contract, not an in-game
visual acceptance result or an inventory of currently obtainable weapons.

The previous reader admitted only option kind 11, then decoded exact packed
words `0x50/0x54` using an autocannon resource whitelist. These are different
native selectors. The strip also accepted only the two named FLAK/APHET icons.
The new reader/strip carry the native texture ID directly, without a weapon
resource whitelist or an ammo-name-to-icon whitelist.

## Selector and icon dispatch

Four option kinds come from the identity-checked control/option manager's
`+0x58` array, stride `0x3f0`, row offsets `0x350/354/358/35c`.
The active packed word is the second uint32 (`+4`) of the control manager's
`+0x60` array, stride 12. Manager global: `0x3326ce0`.

`0x755ba0` is the native selection getter. Its kind-minus-one jump table at
`0x755f58` selects the following paths. The five packed fields end at `0x755f3a`
with `and eax,3`; kind 4 returns its separate component index unmasked.
`0x759c00` enumerates available choices (dispatch table `0x75a0a0`), and
`0x75a0d0` resolves their native icon (dispatch table `0x75a4b4`).

| Kind | Getter RVA | Selector | Native icon source |
| --- | --- | --- | --- |
| 4 | `0x755d50` | rounds component `+0x58`, 20-byte row, uint32 `+4` | Selected projectile catalog record, icon `+0x10` |
| 8 | `0x755ef8` | `(word >> 2) & 3` | Selected projectile catalog record, icon `+0x10` |
| 9 | `0x755f09` | `(word >> 6) & 3` | Definition `+0x80 + index*0x10` |
| 10 | `0x755f1a` | `(word >> 8) & 3` | Definition `+0x18 + index*0x28` |
| 11 | `0x755ed9` | `(word >> 10) & 3` | Weapon definition `+0xa0/+0xa8` |
| 12 | `0x755f2b` | `(word >> 14) & 3` | Definition `+0x158 + index*0x178` |

All six enumerate exactly two choices. The reader refuses selector values
2/3 instead of guessing an icon. Unrelated packed bits, including `0x1000`,
are naturally excluded by each field mask. Fixed/non-programmable axes do not
produce programmable icons. Duplicate kinds are deduplicated; at most four
icons can result from the four native axes.

## Definition paths

Kind 4 uses the rounds manager `0x3326cf0`, entity map `+0x28`, record
array `+0x40`. The selected index is uint32 `+4` in its `+0x58` array,
20-byte rows (`0x755dff`). Choice enumeration at `0x759fb7` calls `0x4fdd20`:
entity override map `+0x68`, definitions `+0xa8`, stride `0x88`; fallback
`0x4fd8e0` uses owner `+0xf12820`, 50 hash slots, stride `0x88`.
The two projectile IDs are definition `+0x40/+0x44`. Their icon lookup is
identical to kind 8. This separate selector must not be decoded from control
word bits, and is re-read during final source verification.

Kind 8 choice enumeration at `0x759fe4..0x75a081` uses manager global
`0x33266d8`, entity map `+0x50`, record-pointer array `+0x68`, then definition
getter `0x515100`. The reader validates component record identity before and
after reading, including again at the end of the snapshot.

That getter first checks its entity override map `+0x90`, definition array
`+0xd0`, stride `0x268` (`0x5151b2`). Otherwise `0x514c10` resolves the resource
in owner `+0xf12e80`, 542 hash slots, definition stride `0x268`.
Choice 0 uses definition uint32 `+0`; choice 1 uses `+0x240`.
The icon helper `0x75a36e` requires projectile ID `<0x15f` (351), uses inline
record `base+0x37c7560` for ID 0 and pointer table
`base+0x37c7670 + ID*8` otherwise. Its returned icon is record uint64 `+0x10`
(the copy at `0x75a409` reads the corresponding stack field).

Kinds 9–12 use the weapon resource's static native definition, matching the
icon helper rather than substituting the mutable weapon-control definition:

| Kind | Native getter | Owner table | Hash slots | Definition stride |
| --- | --- | --- | --- | --- |
| 9 | `0x50e360` | `+0xf12cd8` | 22 | `0xc0` |
| 10 | `0x50e2c0` | `+0xf12cd0` | 18 | `0x58` |
| 11 | `0x509570` | `+0xf12bd8` | 730 | `0x4d0` |
| 12 | `0x50c720` | `+0xf12c88` | 10 | `0x2f0` |

These maps use 16-byte resource-hash slots followed by fixed-size definition
rows. Lookups retain both uint32 halves of the resource key exactly, enforce
index bounds, and retain the reader's bounded read/probe budget. Missing or
zero icons suppress that optional glyph, preserving valid other axes. Control
words are reread in full and control-component identity is revalidated before
publication, so same-weapon mode changes cannot publish a stale icon. Each
successful ammo icon's source is also resolved again at the end of the snapshot:
override map presence/index, definition row address, selected projectile,
catalog record address and icon must match. This covers the reviewer's override
relocation reproduction, array relocation, same-row projectile mutation and
absent-to-present overrides. A stale result refuses the snapshot and retries
on the next poll.

## Reference comparison and limits

The September reader at `~/Projects/protonMods/mods/dbf_hud/src` names
AC (`a8cffb316f0b5c5f`) APHET/FLAK, recoilless (`9f80d67a12a7e40f`) HEAT/HE,
airburst (`26e40437ea275296`) FLAK/CLUSTER, and missile pistol
(`14d5d4506056c7a4`) GUIDED/UNGUIDED. Its exact-word tables are reference
labels, not the generic native contract. The later `luajit-26251122` branch
reverses the AC labels and already admits kind 8; those later labels must not
be transplanted into this build. Neither set of names is needed by this patch.

The implementation covers all six native ammunition/programmable option kinds using
the same definition/icon dispatch as the target menu. It does not claim that
every named reference weapon is obtainable or has been equipped on this build.
Definition-provided art still requires a live renderer/resource check. The
RGB-mask material, inherited tint, UV crop, dimensions and cleanup are unchanged.

## Validation

- `luajit hellforge/tests/weapon_strip.lua hellforge/hud`: both choices of all
  six kinds, unrelated bits, invalid choices, static/override projectile
  definitions, catalog bounds/zero entry, missing texture, arbitrary weapon
  resource, four programmable axes, duplicate kinds, same-weapon selection
  changes, immediate and late component changes, override-row/array relocation,
  absent-to-present overrides, and native renderer lifecycle.
- `DBF_WEAPON_IMAGE=<mapped image> python3 -m unittest discover -s hellforge/tools
  -p test_weapon_strip.py -v`: Lua fixture and all target code witnesses.
- `./hellforge/build.sh dll`: regenerate embedded payload, compile DLL and
  check SDK/imports. Package creation, installation and publishing are separate.

Completed local checks: targeted fixture and mapped-image witness test both
passed. Full test command with `DBF_WEAPON_IMAGE` set reported 25 passed groups,
0 failed; Python ran 58 tests with 14 environment-dependent skips (13 R46 input
checks and one BSL/ZIP integration check). Final DLL SDK/import checks passed;
SHA-256 `546f77b17866491464cade94466472ea6442926e0cd8f86af9ceefd30e2316b5`.
Logs: `/tmp/dbf-programmable-tests.log`, `/tmp/dbf-programmable-build.log`.

Independent re-review (Confucius): override-relocation regression fails against
the preserved pre-fix reader and passes against this fix. Reviewer also checked
the kind-4 selector, stride, definition offsets and fallback against the target
image, reran the weapon fixture and target-byte checks, and reported no remaining
blocking finding. In-game appearance and actual weapon-mode transitions remain
for the user's next-launch acceptance check.

## Local preview installation

Commit `6b85c0b` passed independent re-review (including the stale override
regression failing before the fix). The combined ZIP was built with the
existing slate NEST preview and verified against source and the embedded HUD.
Installed for next launch at `HellForge/mods/divers-best-friend-R50-hellforge.11.zip`.

- Bundle SHA-256: `7736e05e33fde41aff660613aaf7a0bbb4b84029867272b8c1dda042a8553c41`
- DLL SHA-256: `546f77b17866491464cade94466472ea6442926e0cd8f86af9ceefd30e2316b5`
- Previous bundle: `0fd7299c3dc0fc3020ede9ca9b7dde654b5b17c999a871939e74321756c95962`
- Verified rollback copy and receipt: `HellForge/backport-backups/dbf-programmable-20261106T022818Z/`

This remains a local preview with the existing `.11` manifest. No public
release was replaced. Restart and live programmable weapon transitions remain
unverified; offline tests and installation hashes do not establish appearance.
