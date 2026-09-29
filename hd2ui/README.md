# HD2 UI — a custom-UI framework for Helldivers 2

A small, testable framework for drawing **arbitrary custom HUD elements** in
Helldivers 2 — any shape, any color, any text, any layout — layered on
**Bingus Shared Loader** (the runtime) and the game's own `stingray` 2-D screen
GUI. **HD2Runtime** is available as a semantic data source when you want live
gameplay values.

The demo is a **configurable custom counter** that floats to the left or right
of screen centre and scales cleanly on any resolution.

## Why stingray

Early work assumed the only way to render custom HUD text/numbers was to reuse
the game's pre-built native widgets (the emote wheel's type‑7 label). That path
is real but narrow: it can only paint what the game already built a widget for.

A working reference mod (ReticleAmmoHUD, in the Arsenal library) shows the
actual drawing API: the `stingray` engine object, which the Shared Loader
exposes to the addon VM. It provides a genuine **2-D immediate-mode screen GUI**:

```lua
local sr = _G.stingray
local gui  = sr.World.create_screen_gui(world, 'scale', 1, 1)   -- a screen-space layer
sr.Gui.triangle(gui, V3(x,0,y), V3(x2,0,y2), V3(x3,0,y3), 4, Color(r,g,b,a), material, uv,uv,uv)
sr.Gui.text(gui, "45", font, size, font, V2(x,y), Color(r,g,b,a))
local w, h = sr.Gui.resolution()
sr.World.destroy_gui(world, gui)
```

So there *is* a free-form 2-D path: arbitrary colored triangles in screen
pixels **and** real text with a font, plus `sr.Application.can_get('material', …)`
for a solid material and `sr.Application.worlds` / `main_world` for the target.
This framework is built on that, not on the widget-reuse detour.

### Verified present in this environment
- **Bingus Shared Loader v18 (API 1)** — its bytecode exposes the `stingray` and
  `Application` globals to the addon VM.
- **Game data** — `data/bundles.01.nxa` contains `create_screen_gui`, `Gui`,
  `triangle`, `Vector3`, and the HUD font `core/performance_hud/monaco`.
- **A working reference** — ReticleAmmoHUD 1.1.4 draws with exactly this API
  (display-only, signature-scanned, self-disabling).

## Layout

```
hd2ui/
├─ core/                     # pure Lua — no FFI, fully headless-testable
│  ├─ colors.lua             #   RGBA helpers: rgba/hex/mix/alpha/lighten/darken
│  ├─ geometry.lua           #   2-D primitives → display list (rect/line/arc/ring/text/…)
│  └─ layout.lua             #   1080p reference-space scale + place + anchor
├─ scene.lua                 # composes elements, renders them into a display list
├─ backend_stingray.lua      # the in-game seam: display list → sr.Gui.triangle/text
├─ demo_counter.lua          # the demo UI (data-agnostic; reads an injectable model)
├─ demo_app.lua              # host-agnostic per-frame demo app (wraps counter + backend; MDL-ready)
├─ demo_entry.lua            # in-game entry: update/shutdown hooks, demo model, log
├─ memreader.lua             # memory-read seam: ReadProcessMemory transport + pointer-chain walk + test injection
├─ live_scan.lua             # region enum + Toolhelp32 module base + value scanner (headless live-pass tooling)
├─ live_pass.lua             # interactive REPL driver for external scans (limited: the game blocks ~95% of external reads)
├─ derive_entry.lua          # IN-GAME derivation addon: file-RPC (derive_in.txt -> derive_out.log), chunked scan/next/watch
├─ build_derive.py           # assembles the derive addon zip (no rendering, single lua resource)
├─ ammo_reader.lua           # ON TOP of memreader: content-anchor mode (per-weapon GUID -> mag/res at fixed negative offsets) + chain-walk mode + plausibility gates
├─ ammo_cache.lua            # per-build fast path: PE-stamp-keyed cache of the last validated anchor base (instant lock on live-reload / same session)
├─ ammo_entry.lua            # PRODUCT HUD entry: framework consumer; cache fast boot, menu presets, styles, sr probe
├─ ammo_cache.lua            # per-build stamp cache (PE timestamp + base), validated through the full gates before use
├─ ammo_styles.lua           # HUD styles (text): crosshair / gunside / world-bound (projection seam, screen fallback)
├─ build_framework.py        # HD2UI LIBRARY zip: framework modules + solid material, require('mods/dbf/hd2ui')
├─ build_ammo.py             # DBF Ammo HUD zip: product chunk + STYLE/SIZE preset option patches (Mod Options menu)
├─ build_ammo.py             # assembles the ammo addon zip (framework + reader + cache + own solid material)
├─ resolve_anchor.py         # dev tool: one-shot GUID anchor resolve against the running game via derive file-RPC
├─ CHAIN_NOTES.md            # live derivation log: verified layout, GUID anchors, chain-climb findings
├─ build_demo.py             # assembles one Lua chunk + generates the solid material → Arsenal zip
├─ STINGRAY_NOTES.md         # verified engine facts (ARGB, y-up, material format, hooks)
└─ tests/
   ├─ test_core.lua          # 65 checks: colors/geometry/layout/scene/counter
   ├─ test_assembled.lua     # 28 checks: the shipped chunk vs a fake `stingray`
   ├─ test_memreader.lua     # 13 checks: read_u32/read_ptr/walk vs a fake process memory
   ├─ test_live_scan.lua     # 17 checks: scan windows/overlap, page-straddling, only_image, holes vs a fake range map
   ├─ test_derive_headless.lua # 17 checks: end-to-end in-process derive (attach self, file-RPC, chunked scan, watch) against a planted marker
   ├─ test_ammo_reader.lua   # 28 checks: chain walk, plausibility gates, f32 decode, rederive, anchor mode + gates
   ├─ test_ammo_cache.lua    # 20 checks: PE stamp read, save/load round-trips, structural validation gates
   └─ test_ammo_hud.lua      # 19 checks: SHIPPED ammo chunk e2e — plant real component, scan/lock/render/fire/stale, cache fast-path re-install
```

## Two artifacts (framework is its own addon)

- **HD2UI - Stingray HUD Framework** (`DBF-hd2ui-R*.zip`): the shared library.
  Installs the module table as a requireable addon resource
  (`require('mods/dbf/hd2ui')` -> colors/geometry/layout/scene/backend_stingray/
  demo_counter) and owns the `mods/dbf/hd2ui/solid` material. Any other mod can
  depend on it; it touches no memory.
- **DBF Ammo HUD** (`DBF-ammo-R*.zip`): consumer. Product modules only
  (memreader/live_scan/ammo_reader/ammo_cache/ammo_styles + entry). Its
  manifest declares Mod Options menu entries (style + size) which the manager
  deploys as tiny preset lua resources the addon reads at install -- the same
  mechanism commercial BSL mods use, reimplemented here.

## Build the Arsenal zip

```bash
python hd2ui/build_demo.py      # -> hd2ui/DBF-hd2ui-demo-R<rev>.zip
```

Two patch archives: `patch_0` (one `lua` resource, the assembled chunk) and
`patch_1` (a `texture` + `material` pair named `mods/dbf/hd2ui/solid`, pixels
in `.gpu_resources`). All bytes are generated from format knowledge in
`STINGRAY_NOTES.md`; nothing third-party is copied.

## Architecture

The framework is split at a single, explicit seam so the interesting logic is
**proven without a game** and the game path stays thin:

```
  data source ──▶ demo_counter ──▶ core (colors/geometry/layout) + scene ──▶ display list ──▶ backend
  (clip,reserve)   (demo)            pure math: positions/sizes/colors          │
                                                                              ├─ backend_stingray → sr.Gui (in game)
  HD2Runtime ─────┘                                                                 └─ fake        → recorded (tests)
```

- **`core/` + `scene.lua`** are pure Lua. They never touch memory. They compute
  where and how big each element is from a fixed **1920×1080 reference space**
  and the live viewport, and emit a **display list** of triangles and text runs.
  This is what all tests exercise.
- **`backend_stingray.lua`** is the only game-facing code. It takes a display
  list (already in final screen pixels) and calls `sr.Gui.triangle` (when a solid
  material is available) and `sr.Gui.text` (always). It detects geometry-vs-text
  mode with `sr.Application.can_get('material', …)`, manages the GUI's lifetime,
  and tracks element IDs for clean destruction.
- **`demo_counter.lua`** is data-agnostic. It builds a backing rect + a pip + a
  number, positions it left/right of centre, and renders one frame per call with
  an injected model. Swap the fake model for HD2Runtime / ReticleAmmoHUD's
  weapon reader to go live.

### Clean scaling

Elements author layout in a fixed reference space (1920×1080). At runtime the
viewport is reported (e.g. via `sr.Gui.resolution()`); the framework picks a
single uniform scale factor `(viewport_h / 1080) * user_scale` and applies it to
every position and size. "120 px right of centre" therefore sits proportionally
at the right size on 1080p, 1440p, 4K, or ultrawide — verified by `test_core.lua`
across those resolutions.

### Configurable

The demo takes a plain options table (wire it to **Mod Options Menu** or the
Shared Loader preset mechanism in production):
- **Side**: left / right of centre
- **Offset** from centre (1080p px)
- **Size** (user scale)
- **Opacity**
- **Color** (hex or RGBA)

All layout/scale/option handling is pure Lua and testable with a fake backend.

## What is verified vs. what still needs a live pass

**Verified in-game (the real engine, not just unit tests):**
- The full `stingray` render path works live: `DBF-hd2ui-demo-R1.zip` loaded in
  Arsenal, in-game log shows `gui ready mode=geometry resolution=3840x2160`
  and a clean `shutdown`. `mode=geometry` (not `mode=text`) proves the generated
  solid material (BC3 texture + material pair) parses, loads, and binds in the
  real engine — the one thing that could not be proven headlessly. The demo
  counter renders anchored to the crosshair at 4K.

**Verified headlessly (run under the game's own LuaJIT via `scripts/test.py`):**
- color math: rgba/hex/mix/alpha/lighten/darken, clamping
- every geometry primitive emits the expected display-list records
- scale factor selection, clamping, and 1080p-reference placement
- anchor resolution for every corner/edge
- scene add/render/clear lifecycle, origin + scale application, unknown-kind error
- the counter's left/right positioning, clean scaling, and display-list emission
- `memreader.lua` transport: `read_u32` / `read_ptr` / `walk` (pointer-chain)
  against a fake process memory image, plus the test-injection seam swap-in/out
  (13 checks)

**Verified live in-game (2026-09-29, derive addon R7 file-RPC sessions):**
- **The ammo component is resolved by CONTENT ANCHOR, not a pointer chain.**
  Each weapon type's ammo component carries a 16-byte GUID at `mag+0x24`,
  byte-stable across sessions and redeploys (R-4 Deadeye:
  `95d2a294b52bd45e6ed282d0e08968b9`). Layout from the GUID hit: mag u32
  `-0x24`, reserve u32 `-0x2C`, aim f32 `-0x28`, flag u32==1 `-0x30` (the
  structural gates that reject asset-registry copies and scanner self-matches).
  Validated across two fresh redeploys: auto-resolved from a 4M-candidate heap,
  fire decremented the live value (8→7). A pointer-chain climb was tried first
  and abandoned — it circles engine callback/registry tables and never reaches
  a module static (see `CHAIN_NOTES.md`).

**Still needs a live pass:**
- In-game verification of `DBF-ammo-R2.zip` (the product HUD): deploy in
  Arsenal, restart, watch `%APPDATA%/Arrowhead/Helldivers2/hd2ui_ammo.log` for
  `LOCKED` (first run: background scan, up to ~2.5 min) and the counter right
  of the crosshair tracking fire/reload. On any re-install inside the same
  game session the cache fast path should log `CACHE_LOCKED` instantly.
- More weapon anchors (AR-59 next: own GUID + heat f32 offset) and a
  weapon-switch story.

## Run the tests

```bash
# all at once (existing DBF fixtures + hd2ui; requires the game's lua51.dll):
HD2_LUA51_DLL='D:/SteamLibrary/steamapps/common/Helldivers 2/bin/lua51.dll' \
  python scripts/test.py

# or just the framework:
HD2_LUA51_DLL='D:/SteamLibrary/steamapps/common/Helldivers 2/bin/lua51.dll' \
  python run_lua.py hd2ui/tests/test_core.lua
```

`scripts/test.py` runs the existing DBF fixtures **and** the
`hd2ui/tests/test_*.lua` files in one pass (verified: full suite green,
no regressions).

## Status

Framework core + demo + stingray backend + packager: **built, unit-verified, and
confirmed rendering in-game** (in-game log `mode=geometry` at 4K). The real ammo
reader: **derived and validated live** via the content anchor (above); the
product HUD ships as `DBF-ammo-R2.zip` (own GUID `fd6e1e12-…`, display-only)
with a per-build cache fast path (`dbf_ammo_cache.txt`) for instant
same-session locks. Suite: 65 core + 28 assembled + 13 memreader + 17
live_scan + 23 derive + 28 ammo_reader + 20 ammo_cache + 19 ammo_hud checks
green under the game's LuaJIT. Awaiting: in-game verification of R2, then more
weapon anchors (AR-59) and weapon auto-detect.
