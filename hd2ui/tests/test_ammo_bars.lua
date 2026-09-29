-- tests/test_ammo_bars.lua -- ammo_bars graphical layer unit checks against
-- a fake scene (collects add('rect'|'text')) and fake colors API. Verifies:
-- heat/fuel hazard zones are placed on the correct end of the bar, stripe
-- rects stay inside the bar bounds, the 45-degree phase advances per row,
-- zone activation switches at the gauge thresholds, the numeric counter is
-- always present, and the spare-mag bar shrinks with consumption.

local checks, fails = 0, 0
local function ok(c, msg)
  checks = checks + 1
  if not c then fails = fails + 1; print('FAIL: ' .. msg) else print('ok   ' .. msg) end
end

local bars = require('hd2ui.ammo_bars')

local fake_colors = {
  from_hex = function(hex) return { hex = hex } end,
  alpha = function(c, a) return { hex = c.hex, a = a } end,
  mix = function(a, b, t) return { hex = 'mix' } end,
}

local function fake_scene()
  local rects, texts, kinds = {}, {}, {}
  return {
    rects = rects, texts = texts, kinds = kinds,
    add = function(self, kind, t, col)
      if kind == 'rect' then rects[#rects + 1] = { t = t, c = col }
      elseif kind == 'text' then texts[#texts + 1] = { t = t, c = col }
      else kinds[#kinds + 1] = { kind = kind, t = t, c = col } end
    end,
  }
end

local function hex_in(rects, h)
  local n = 0
  for _, r in ipairs(rects) do if r.c.hex == h then n = n + 1 end end
  return n
end

-- ------------------------------------------------------------- heat weapon
local sc = fake_scene()
bars.draw(sc, { label = 'HEAT 95%', weapon_key = 1, heat_frac = 0.95, heat_pct = 95,
                spare = 3, color = '#f2f2f2' }, 1, fake_colors)

-- bar geometry: x=24 w=10 bottom=-24 h=34 -> heat anchors TOP; hazard band BOTTOM
local yellow, dark = hex_in(sc.rects, '#e8c020'), hex_in(sc.rects, '#141410')
ok(yellow > 0, 'heat: hazard yellow stripes drawn')
ok(dark > 0, 'heat: hazard dark base drawn')
local in_field, out_of_bounds, in_bottom = 0, false, false
for _, r in ipairs(sc.rects) do
  local p = r.t
  if r.c.hex == '#e8c020' or r.c.hex == '#141410' then
    in_field = in_field + 1
    if p.x < 132 - 0.001 or p.x + p.w > 141 + 0.001 then out_of_bounds = true end
    if p.y >= -13 - 0.001 and p.y < -6 then in_bottom = true end
  end
end
ok(in_field > 0 and in_field < 20, 'heat: 95% fill carves field down to bottom band, rows=' .. in_field)
ok(not out_of_bounds, 'heat: all stripe segments inside bar bounds')
ok(in_bottom, 'heat: hazard band at the TOP (heat rises into it)')
local anchored = false
for _, r in ipairs(sc.rects) do
  local p = r.t
  if r.c.hex == 'mix' and math.abs((p.y + p.h) - 13) < 0.7 then anchored = true end
end
ok(anchored, 'heat: fill anchored to the top edge')
-- carve rule: no stripe row may live above the fill's bottom edge (fy)
local fill_bottom = nil
for _, r in ipairs(sc.rects) do
  if r.c.hex == 'mix' then fill_bottom = r.t.y end
end
local bleed = false
for _, r in ipairs(sc.rects) do
  if (r.c.hex == '#e8c020' or r.c.hex == '#141410') and fill_bottom and r.t.y > fill_bottom + 0.01 then
    bleed = true
  end
end
ok(not bleed, 'heat: fill overwrites stripes (no rows inside the filled area)')
local active = false
for _, r in ipairs(sc.rects) do
  if r.c.hex == '#e8c020' and r.c.a >= 0.9 then active = true end
end
ok(active, 'heat: zone brightens when gauge in zone')

-- phase advances per row (diagonal). Use a LOW gauge draw: 95% fill carves
-- the field down to one row, which cannot show a phase shift by definition.
local sc_ph = fake_scene()
bars.draw(sc_ph, { label = 'x', weapon_key = 22, heat_frac = 0.80, heat_pct = 80 }, 1, fake_colors)
local row_x, row_ys = {}, {}
for _, r in ipairs(sc_ph.rects) do
  if r.c.hex == '#e8c020' then
    if row_x[r.t.y] == nil then row_x[r.t.y] = r.t.x row_ys[#row_ys + 1] = r.t.y end
  end
end
table.sort(row_ys)
local phase_ok = #row_ys >= 2 and row_x[row_ys[1]] ~= row_x[row_ys[2]]
ok(phase_ok, 'heat: stripe phase shifts per row (45-degree)')

-- split readout: bare percent right of gauge, bricks side-by-side left,
-- ghost rails for spent slots, and NO duplicate composite label
local pct_ok, dup_ok = false, false
for _, x in ipairs(sc.texts) do
  if x.t.str == '95%' then pct_ok = true end
  if x.t.str == 'HEAT 95% / 3' then dup_ok = true end
end
ok(pct_ok, 'heat: bare percent text beside bar')
ok(not dup_ok, 'heat: composite duplicate label suppressed')
local solid, ghost = 0, 0
for _, r in ipairs(sc.rects) do
  if r.c.hex == '#d9d9d9' then
    if r.c.a and r.c.a < 0.5 then ghost = ghost + 1 else solid = solid + 1 end
  end
end
ok(solid == 3, 'heat: 3 solid sink bricks (got ' .. tostring(solid) .. ')')
-- spare_max unknown in this model -> total = n -> no ghosts expected
ok(ghost == 0, 'heat: no ghosts when max unknown (got ' .. tostring(ghost) .. ')')

-- with max known: 2 of 3 remaining -> one ghost rail
sc = fake_scene()
bars.draw(sc, { label = 'x', weapon_key = 9, heat_frac = 0.5, heat_pct = 50,
                spare = 2, spare_max = 3 }, 1, fake_colors)
solid, ghost = 0, 0
for _, r in ipairs(sc.rects) do
  if r.c.hex == '#d9d9d9' then
    if r.c.a and r.c.a < 0.5 then ghost = ghost + 1 else solid = solid + 1 end
  end
end
ok(solid == 2 and ghost == 1, 'heat: 2 bricks + 1 spent-slot ghost')

-- regression: the <=25% HEAT gauge must NOT light hazard (precedence trap)
sc = fake_scene()
bars.draw(sc, { label = 'x', weapon_key = 51, heat_frac = 0.20, heat_pct = 20 }, 1, fake_colors)
local leak_bright, leak_faint = 0, 0
for _, r in ipairs(sc.rects) do
  if r.c.hex == '#e8c020' then
    if (r.c.a or 0) > 0.9 then leak_bright = leak_bright + 1 else leak_faint = leak_faint + 1 end
  end
end
ok(leak_bright == 0 and leak_faint > 0, 'heat: marks visible but UNLIT at 20% (no clause-leak)')

-- alarm semantics: below threshold the bar is CLEAN (no stripes at all)
sc = fake_scene()
bars.draw(sc, { label = 'x', weapon_key = 21, heat_frac = 0.30, heat_pct = 30 }, 1, fake_colors)
local exposed, lit = 0, 0
for _, r in ipairs(sc.rects) do
  if r.c.hex == '#e8c020' then
    exposed = exposed + 1
    if (r.c.a or 0) > 0.9 then lit = lit + 1 end
  end
end
ok(exposed > 0 and lit == 0, 'heat: marks visible but unlit at 30%')

-- at 80%: alarm ON, stripes in the exposed area below the fill edge
sc = fake_scene()
bars.draw(sc, { label = 'x', weapon_key = 23, heat_frac = 0.80, heat_pct = 80 }, 1, fake_colors)
exposed = 0
for _, r in ipairs(sc.rects) do if r.c.hex == '#e8c020' then exposed = exposed + 1 end end
ok(exposed > 0, 'heat: alarm ON at 80% (stripes appear)')



-- fuel is a DIAL now: arcs, pct text inside, red at <=25%
sc = fake_scene()
bars.draw(sc, { label = '5%', weapon_key = 3, fuel_frac = 0.05 }, 1, fake_colors)
local arcs = 0
for _, k in ipairs(sc.kinds) do if k.kind == 'arc' then arcs = arcs + 1 end end
ok(arcs >= 4, 'fuel dial: track + zone + end ticks + fill arcs (' .. arcs .. ')')
local needle, hub = 0, 0
for _, k in ipairs(sc.kinds) do
  if k.kind == 'tri' then needle = needle + 1 end
  if k.kind == 'circle' then hub = hub + 1 end
end
ok(needle == 1, 'fuel dial: needle drawn')
ok(hub >= 2, 'fuel dial: hub cap drawn')
local side = false
for _, x in ipairs(sc.texts) do if x.t.str:find('/ ') then side = true end end
ok(not side, 'fuel dial: no redundant side text (gauge alone)')
local red = false
for _, k in ipairs(sc.kinds) do if k.c.hex == '#e03030' then red = true end end
ok(red, 'fuel dial: fill turns alert red at 5%')
local pct_txt = false
for _, x in ipairs(sc.texts) do if x.t.str == '5%' then pct_txt = true end end
ok(pct_txt, 'fuel dial: percent shown inside the dial')

sc = fake_scene()
bars.draw(sc, { label = '80%', weapon_key = 4, fuel_frac = 0.80 }, 1, fake_colors)
local amber = false
for _, k in ipairs(sc.kinds) do if k.c.hex == '#e8b84a' then amber = true end end
ok(amber, 'fuel dial: amber when healthy')

-- ------------------------------------------------------- spare mag bar
sc = fake_scene()
bars.draw(sc, { label = '7/56', weapon_key = 4, spare = 4, spare_kind = 'mags', spare_max = 8 }, 1, fake_colors)
local brass, ghosts, noses = 0, 0, 0
for _, r in ipairs(sc.rects) do
  if r.c.hex == '#d4b054' then brass = brass + 1 end
  if r.c.hex == '#d9d9d9' and (r.c.a or 1) < 0.3 then ghosts = ghosts + 1 end
end
for _, k in ipairs(sc.kinds) do if k.kind == 'tri' then noses = noses + 1 end end
ok(brass == 4 and noses == 4, 'mag module: 4 live rounds (brass=' .. brass .. ' noses=' .. noses .. ')')
ok(ghosts == 4, 'mag module: 4 spent slots ghosted (got ' .. ghosts .. ')')
local panel = false
for _, r in ipairs(sc.rects) do if r.c.hex == '#1a1e1a' then panel = true end end
ok(panel, 'mag module: cohesive frosted panel behind count + rack')
sc = fake_scene()
bars.draw(sc, { label = '7/56', weapon_key = 41, spare = 0, spare_kind = 'mags', spare_max = 8 }, 1, fake_colors)
brass = 0
for _, r in ipairs(sc.rects) do if r.c.hex == '#d4b054' then brass = brass + 1 end end
ok(brass == 0, 'cartridge pips: emptied magazine rack shows only ghosts')
-- >12 spares still falls back to the horizontal bar
sc = fake_scene()
bars.draw(sc, { label = '7/56', weapon_key = 42, spare = 20, spare_kind = 'mags', spare_max = 40 }, 1, fake_colors)
local bar = false
for _, r in ipairs(sc.rects) do if r.c.hex == '#d4b054' and r.t.w >= 26 then bar = true end end
ok(bar, 'spare >12 falls back to the long bar')

-- ------------------------------------------------------- backpack mag grid
sc = fake_scene()
bars.draw(sc, { label = '46/6', weapon_key = 30, spare = 6, spare_kind = 'backpack',
                pack = { remain = 6, total = 10 } }, 1, fake_colors)
solid, ghost = 0, 0
local panel = false
for _, r in ipairs(sc.rects) do
  if r.c.hex == '#1a1e1a' then panel = true end
  if r.c.hex == '#d9d9d9' and r.t.h > 5 then solid = solid + 1 end
  if r.c.hex == '#d9d9d9' and r.t.h <= 2 then ghost = ghost + 1 end
end
ok(panel, 'pack grid: frame panel drawn')
ok(solid == 6, 'pack grid: one bar per drum remaining (got ' .. solid .. ')')
ok(ghost == 4, 'pack grid: ghost rails for the 4 spent slots (got ' .. ghost .. ')')

sc = fake_scene()
bars.draw(sc, { label = '46/0', weapon_key = 31, spare = 0, spare_kind = 'backpack',
                pack = { remain = 0, total = 10 } }, 1, fake_colors)
solid = 0
for _, r in ipairs(sc.rects) do if r.c.hex == '#d9d9d9' and r.t.h > 5 then solid = solid + 1 end end
ok(solid == 0, 'pack grid: empty backpack = no solid bars')

print(string.format('ammo_bars: %d checks, %d failures', checks, fails))
if fails > 0 then error(fails .. ' failures') end
