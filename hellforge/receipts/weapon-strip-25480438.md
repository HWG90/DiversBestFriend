# Weapon status strip for build 25480438

The reference implementation is the repository's `luajit-26251122` branch under `luajit/divers_best_friend/src/weapon_status*.lua`. The strip retains its configurable-axis policy, native sprite material IDs, UV crop, row alignment, and ownership checks. Game art is resolved by resource ID. The screen-Gui backing uses the shared Lua kit's colours.

The local September-build DBF HUD reader (`protonMods/mods/dbf_hud/src/{layouts,reader,ammo_types}.lua`) identifies the player, owner, inventory, selector, driver, weapon-control and RPM components. Its September autocannon mapping uses 0x50 for APHET and 0x54 for FLAK. The control data uses a 12-byte stride and the weapon definition uses a 0x4d0-byte stride. The code checks component/record identity before displaying any icon.

The target was independently checked against the mapped image `hob-game-6AB3B43F.bin` (SHA-256 `642b0aac0b4f577054993a965054827455ef143ced9895b2dfd09d1ecd433a37`, timestamp 0x6ab3b43f, SizeOfImage 0x4744000). In the following rows addresses are RVAs. Matching option consumers in the earlier retail dump `game-26088801.dll` locate the equivalent routine in the target.

| Use | Retail | 25480438 | Observation |
| --- | --- | --- | --- |
| Weapon options | 0x16a8f89, 0x16a8fda | 0x1828099, 0x18280ea | Paired RIP loads resolve to 0x3326ce0 and 0x33264c0. |
| Option row | 0x16a90de | 0x18281ee | Indexed row stride 0x3f0 in the array at +0x58. |
| Four axes | 0x16a915c through 0x16a939c | 0x182826c, 0x182832c, 0x18283ec, 0x18284ac | Reads at row +0x358, +0x350, +0x354, +0x35c. |
| Zoom | 0x765080, 0x7613d9, 0x7616aa | 0x759d00, 0x755c69, 0x755f3a | Three definition floats at +0x154/158/15c, selected by (control[1] >> 4) & 3. |
| Stock weapon image | 0x169968a, 0x169aa9d, 0x169bcef | 0x181843a, 0x181984d, 0x181aa9f | Sprite construction, size and update at frame +0x30c8. The target call at 0x12e97c6 constructs the frame and attaches sub-HUD +0x60 to its parent. At 0x181843a the frame constructor initializes the sprite at +0x30c8 and calls the native asset setter. The original row alignment uses HUD +0x24e340 +0x60 +0x30c8. At runtime the strip checks ancestry to that frame and the exact HUD container. |
| RPM | 0x620c14 | 0x617974 | RIP load of 0x33266d8. Identity-checked component +0x70 has 0x20-byte rows with rates and selected index. |

To reproduce, set `DBF_WEAPON_IMAGE` to the mapped target file and run `python3 -m unittest discover -s hellforge/tools -p test_weapon_strip.py -v` from the checkout. The byte test checks the same witnesses the reader requires before reading actors. The LuaJIT fixture exercises a local avatar, selected weapon, four configurable axes, selector changes, hidden fixed axes, mismatched identity and refused code witnesses. Actual icon appearance, current weapon transitions and native widget teardown require an in-mission check.
