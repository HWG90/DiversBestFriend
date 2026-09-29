# stingray screen-GUI facts (verified against shipping mods)

Sources studied: **ReticleAmmoHUD 1.1.4** (Nexus 16467) and **DRIVER HUD 1.4.5**
(Nexus 16358, MIT — FireScallion). Both are Bingus Shared Loader v15/API 1
addons that draw with the engine's 2-D screen GUI. HD2 HUD+ was only looked at
for *how*, not *what* — nothing from it is copied here.

## Calls that work in-game

```lua
local sr = rawget(_G, 'stingray')
local App, World, Gui = sr.Application, sr.World, sr.Gui
local V2, V3, Color   = sr.Vector2, sr.Vector3, sr.Color

local worlds = App.worlds()                 -- pick a world that is NOT main_world (UI world)
local gui = World.create_screen_gui(world, 'scale', 1, 1)
local w, h = Gui.resolution()               -- live viewport in pixels
local id = Gui.triangle(gui, V3(x1,0,y1), V3(x2,0,y2), V3(x3,0,y3),
                        LAYER, Color(a,r,g,b), MATERIAL, uv, uv, uv)
local id = Gui.text(gui, str, FONT, size, FONT, V2(x,y), Color(a,r,g,b))
local lo, hi = Gui.text_extents(gui, str, FONT, size)   -- Vector2 min/max; use for centering
Gui.destroy_triangle(gui, id); Gui.destroy_text(gui, id)
World.destroy_gui(world, gui)
App.can_get('material', MATERIAL)           -- true if our solid material is loaded
sr.Window.show_cursor()                     -- true while a menu/cursor is up -> hide HUD
```

## Conventions that bite

| Thing | Fact |
|---|---|
| `Color(...)` | **(alpha, r, g, b)** — alpha first. |
| Y axis | **Up.** `y=0` is the bottom edge. Core is y-down → backend flips `h - y`. |
| Positions | `V3(x, 0, y)` — y goes in the *z* slot. |
| Layer | 4 for the main pass, 3 for a drop shadow. |
| uv | Constant `V2(0.5,0)` / `V2(0.5,0.5)` — sample one texel of the solid texture. |
| Font | `core/performance_hud/debug` (both mods). `performance_hud/monaco` also present in game data. |
| Lifetime | Retained: store every id, destroy all each frame (or on change), recreate. |
| World loss | Check the gui's world is still in `App.worlds()` each frame; recreate if not. |
| Update hook | Wrap `_G.update`, `pcall` your frame, back off ~1 s on error, call the original. Wrap `_G.shutdown` to destroy the gui. |

## Shipping a solid material (so `Gui.triangle` works)

`Gui.triangle` needs a material. Neither mod found a stock one; both ship their
own tiny material + texture pair inside a second patch file. The format is the
same archive container `build.py::make_archive` already writes (magic
`0xF0000011`), with **two resource types** instead of one:

| Resource | Type hash (`resource_hash(name)`) | Data |
|---|---|---|
| texture  | `texture`  → `cd4238c6a0c69e32` | 192-byte HD2 header (zeros; `0xffffffff` at +8) + 148-byte DDS/DX10 header. Pixel payload goes in `.gpu_resources` (entry `gpu_size`). |
| material | `material` → `eac0b497876adedf` | 160 bytes. At `+0x80`: `u32 template = 0x5f8113d2`, `u32 slot = murmur32("diffuse_map") = 0x3aa8b87e`, `u64 texture_name_hash`. |

- Both entries share **one name hash** — e.g. `resource_hash('mods/dbf/hd2ui/solid')`.
- The texture in the reference is 8×16 **BC3** (DXGI 77), 5 mips → 208 bytes
  (13 blocks). A solid-white BC3 block is trivial to generate; we do **not**
  need anyone else's pixels.
- `0x5f8113d2` is a game GUI shader template id (a constant, not content).
- `.stream` is empty; `.gpu_resources` holds only the texture payload.
- Entry record layout (80 bytes, `<7Q6I`): name, type, data_off, stream_off,
  gpu_off, u1 (`0xb000`), u2 (`0x7c100`), data_size, stream_size, gpu_size,
  align 16, align 64, index (1-based).

`resource_hash` confirmed identical to the reference mods' hashes for:
`mods/driver_hud/solid`, `mods/driverhud/driver_hud`, `material`, `texture`, `lua`.

## Font-independent digits

DRIVER HUD's `font=new` mode draws digits as **7-segment quads through the same
triangle path**, so numbers work even where the debug font material is
missing/oddly transformed. Worth an `hd2ui` glyph element (own implementation).
