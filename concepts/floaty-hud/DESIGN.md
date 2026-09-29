# Floaty HUD — design contract (v1, 2026-09-29)

**Concept.** A Division-style floating weapon readout for Helldivers 2: ammo,
magazines left, heat, fuel, charge — the same values the native HUD carries,
arranged as one quiet station beside the weapon. Built on the archived hd2ui
framework and the proven instant-read data chain from commit `954f75f`.

**The acceptance test.** Put a screenshot of the station next to a screenshot of
the native HUD. If you can immediately tell which element is the mod, it fails.
Every rule below exists to pass that test.

---

## Hard rules (MUST, no exceptions)

1. **One grammar.** Every weapon renders the *same station*: same plate, same
   font, same palette, same corner language, same anchor. Only the gauge inside
   the tray changes. No per-weapon layouts, no bespoke frames.
2. **Nothing moves.** The station's box is fixed. Values change inside it.
   Tabular numerals, fixed count-cell width, no reflow when digits change, no
   element ever crossing the crosshair or drifting between states.
3. **Succinct or gone.** The number is the element. A bar only where the game
   itself would use one (heat, fuel, charge). A label only where the game uses
   one. Any text not contributing to the read is deleted.
4. **Native behavior.** Visible exactly when the native weapon HUD is visible;
   hidden on the bridge, in menus, with empty hands, whenever the cursor is up.
   Updates every frame from the chain — no scan states, no lock-in, no
   last-known-value ghosts.
5. **Mock before Lua.** No visual change ships without a 1:1 rendered mock
   review first, and an in-game screenshot comparison after. This is the R52
   lesson, enforced from revision 1.

## The station (1080p reference units)

| Part | Spec |
| --- | --- |
| Anchor | Gun-side: plate top-left at (1258, 668). Variant under review: right of crosshair (990, 526) |
| Plate | 150 × 62. Fill `rgba(14,16,13,.55)` over a 3px backdrop blur. 1px border `rgba(242,242,242,.16)`. One 8px chamfer, top-right. No rounding anywhere |
| Primary row | 36px condensed semi-bold numeral, `#f2f2f2`, tabular. Tiny uppercase unit word at 55% white, +12% letter-spacing |
| Divider | 1px, 12% white, full plate width |
| Tray | 18px strip at plate bottom, fill `rgba(8,9,7,.45)` — the class gauge lives here |
| Palette | Ink `#f2f2f2` · dim ink 55% · accent amber `#e8a33d` · danger red `#e03030` · charge cyan `#8fd8e8` · hazard yellow `#e8c020` on `#141410` |

## Weapon gauges

| Class | Numeral | Tray gauge | Thresholds |
| --- | --- | --- | --- |
| Mag weapons (rifle, sidearm) | Rounds in mag | Magazine pips: one chamfered pip per remaining mag, spent = 25% outline | Last pip pulses amber at 1 mag |
| Autocannon | Rounds in mag | 10 stripper-clip pips (5 rounds each), partial clip = half fill, spent = silhouette | Round ticks at plate left edge, 10 slots, deplete top→bottom; amber boundary line after the 5th slot lights when remaining ≤5 (stripper-clip reload legal) |
| Laser | Heat % | Heat bar, fills left→right, pale→amber→red | Hazard band on the last 25%; stripes faint always, lit at ≥75% heat. Heatsink bricks right of the numeral |
| Flamer / Cremator | Fuel % | Compact up-facing arc gauge with needle, gas-tank style | Needle zone marks the last 25% red |
| Railgun | Charge % | Charge strip, cyan fill on 20% white track | Safe-charge mark; past-mark segment renders amber |
| Empty hands / bridge / menus | — | Station hidden | Fade 120ms, never a frozen value |

## Phases

- **v1 — screen-anchored (this contract).** Fixed gun-side anchor. Everything
  above is achievable with the archived framework + chain today.
- **v2 — world-bound.** Same station, projected beside the weapon (Division /
  Dead Space feel). Needs the camera projector seam already stubbed in
  `ammo_styles.lua` (`world` style, provisional screen fallback). Layout and
  grammar do not change — only the anchor source.
- **Out of scope for v1:** layout editor, extra readouts (health, stims),
  per-element user positioning. The archived layout editor returns only after
  the grammar is locked.

## Reuse (proven, archived at `954f75f`)

hd2ui framework + stingray backend (in-game verified) · instant ammo/heat/fuel
chain (`ammo_chain.lua`) · per-build cache · derive rig for new offsets ·
Mod Options + bindings integration · 280+ headless tests ·
`tools/mock_render.py` for 1:1 renders of the real bars code once it exists.

## Mock

`mock.html` in this folder renders this contract 1:1 over a neutral game frame.
Approve or edit the look here — then it becomes Lua.
