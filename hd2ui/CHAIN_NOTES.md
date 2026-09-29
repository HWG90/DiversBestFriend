# DBF ammo derivation — live chain notes (session 2026-09-28/29)

Weapon used for derivation: **R-4 Deadeye** sidearm, mag cap 8, reserve per-round model confirmed (reserve -3 per reload).
PE build: game.dll base observed 0x7FFCDF350000 (ASLR; user build PE 0x6A86132E).

## Confirmed field layout (component struct)
Two independent sessions produced byte-identical layouts, both with the magazine
u32 at a page offset ending 0x7CC:

```
M-0x0C  u32  1        (flag)
M-0x08  u32  reserve  (60 -> 57 across one 3-round reload)  [confirmed vs UI]
M-0x04  f32  1.0      (aim/hot state?)
M+0x00  u32  magazine (8 full; stepped 5->6->7->8 DURING reload anim)
M+0x04  u32  4
M+0x0C  u32  4?/0s
M+0x14  u32  4
M+0x28.. f128 hash-ish bytes (identical across sessions)
```
Session A mag:  0x24AD50A97CC  (narrowed 4.1M->633->5->1, reload-verified live)
Session B mag:  0x29A510697CC  (narrowed 4.18M->1169->2; layout dumped, identical shape)

Low 3 nibbles '7CC' repeated across sessions => allocator places this component
type at a STABLE page offset within its chunk. The chunk base moves per session.

## Chain climb (pointer-of scan via R7 `pointers <addr>`)
- mag 0x29A510697CC -> 3 holders; the stable one:
  **0x7CED21C0** record: `ptr(mag) | 0x28 | 0x2B | self-linked ptrs` inside arena
  full of "commit global/callback changed" debug strings => subscription/callback record.
- 0x7CED21C0 -> 12 holders, clustered:
  * 0x2F15308 / 0x2F15348 / 0x2F15388 (+2F15328/368 nearby, stride 0x40): LOW STATIC
    heap table; entries: ptr | flags | id (0x21/0x29...) | more ptrs. Best candidate.
  * 0x747CA3DD.. (stride 0x20, odd alignment) and 0x74BABFDC..: random-data areas,
    likely false positives (re-scan stability test pending).
- 0x7D78D97C node -> 9 holders; only real one: 0x1FE9E28 — ANOTHER subscription-table
  entry of the same shape family as 2F15xxx. => the climb is circling through the
  engine's callback/registry tables (heap-rooted, no module .data in sight).
  DECISION: stop upward climb on this branch. It is a SIDE channel (change-callbacks),
  not the authoritative access path.

## Anchor discovery (the actual win)
The 16 bytes at mag+0x24: `95 D2 A2 94 B5 2B D4 5E 6E D2 82 D0 E0 89 68 B9`
IDENTICAL across sessions A and B, still live in session C (00:57:54 dump).
=> Per-WEAPON-TYPE GUID hash at fixed struct offset. Reader design:
   locate = scanb(GUID); mag = hit - 0x24; reserve = hit - 0x2C.
   Anchor library is per-weapon; Deadeye resolved tonight.

## Next
1. [DONE 2026-09-29] ammo_reader anchor mode {guid, mag=-0x24, res=-0x2C} +
   redeploy validation — two fresh redeploys, content-based lock confirmed live.
2. [DONE] Ship the real HUD: R1 load-crash (ammo_cache missing from the
   assembler MODULES registry) -> R2 (registry fixed, per-build cache fast path,
   capacity from spec) -> R3 (concurrent session, verified green here): split
   into framework library + consumer addon, style/size presets via Mod Options,
   gunside style, SRAPI capability probe. R2's cache work carried into r3
   unchanged (e2e still asserts CACHE_LOCKED / no-SCAN_START).
3. In-game verify r3: deploy BOTH DBF-hd2ui-R2 (library) and DBF-ammo-R3 in
   Arsenal, restart, watch hd2ui_ammo.log for: FRAMEWORK r2, PRESETS style/size,
   STYLE line, SRAPI probe dump, LOCKED (first scan <= ~2.5 min) or CACHE_LOCKED
   on same-session re-install; HUD right of crosshair tracking fire/reload; try
   the gunside style + size presets from the Mod Options menu.
4. Switch-weapon test: AR-59 has its own GUID anchor + find heat f32 offset there.
5. Weapon auto-detect: scan for ALL anchors in the table, lock whichever
   validates (needs >= 2 anchors derived first).
6. World style: read the SRAPI probe log from a live session; if camera
   projection exists (or the camera matrix chain is derivable from memory),
   wire opts.projector in ammo_styles 'world' (provisional screen fallback
   until then).

## Tooling state
- In-game derive addon R7 (dbf-derive r7): file-RPC via
  %APPDATA%\Arrowhead\Helldivers2\derive_{in.txt,out.log,tag.txt}
  Commands: probe, scan <v> [f], scanb <hex>, pointers <addr>, next/nextf, hex,
  read, watch/unwatch, stop. Frame-budgeted (6MB scan / 20k recheck per frame).
- Drive from repo: `python hd2ui/drive_derive.py <timeout> "<cmd>" "<marker>"`
- Full memory sweep = ~2.5 min (16.5GB, in-process RPM). Narrow passes ~5-10s.
- Suite: 219 hd2ui checks + 67 unlock-all checks green under game LuaJIT
  (full scripts/test.py EXIT=0, verified 2026-09-29 ~03:35 on the quiet tree).
- Product = TWO addons since r3: DBF-hd2ui-R2.zip framework LIBRARY (GUID
  f1a4c7b0-6d2e-4b8f-9c15-3a7e2d0f8b46; lua resource mods/dbf/hd2ui; installs
  __DBF_HD2UI = {colors,geometry,layout,scene,backend_stingray,demo_counter,
  version}; ships solid material mods/dbf/hd2ui/solid) + DBF-ammo-R3.zip
  consumer (GUID 3d9b2e57-8a14-4cf6-b2a9-0e5f7c1d6a83; entry resource
  mods/dbf/ammo/entry; zip = CORE/ + STYLE/<key>/ + SIZE/<n>/ preset folders
  wired to Mod Options SubOptions; clean no-install when framework missing).
  Supersedes DBF-ammo-R2 GUID fd6e1e12. Log hd2ui_ammo.log; cache
  dbf_ammo_cache.txt (<pe_stamp_hex> <anchor_base_hex>, keyed to game.dll build).
- Side addon: unlock-all/ (DBF-UnlockAll-R1.zip) — session-local stratagem
  catalog unlock TEST build (availability 1->2, definition selectable/active
  flags, campaign parent) with drift-halt + rollback, PE-stamp gated; 52+15
  checks. Separate product line; keep its GUID/tests apart from ammo work.

## Open questions / risks
1. Callback-record chain may be per-loadout volatile — need to verify the chain
   survives: switch weapons, redeploy, match end. If it breaks, re-derive from
   the OTHER two mag holders or via chunk-base route.
2. Reserve field: found (M-8). Heat (f32) not found yet — Deadeye has no
   overheat; do this on AR-59 later (RAH layout had heat).
3. ammo_reader.lua expects an 8-hop chain + terminal offsets; final layout will
   be {chain hops with RVAs/base, mag_off=+0, res_off=-8, heat via f32 TBD}.
