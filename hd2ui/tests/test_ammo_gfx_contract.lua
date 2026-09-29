-- hd2ui/tests/test_ammo_gfx_contract.lua -- per-weapon-class GRAPHICAL design
-- contract. Every class gets its final look pinned here; if a future change
-- reintroduces decorative or duplicate text, this suite goes red.

package.path = 'hd2ui/?.lua;hd2ui/tests/?.lua;' .. package.path
local bars = require('hd2ui.ammo_bars')

local checks, fails = 0, 0
local function ok(cond, msg)
  checks = checks + 1
  if not cond then fails = fails + 1; print('FAIL: ' .. msg) end
end

local fake_colors = {}
function fake_colors.from_hex(h) return { hex = h, r = 1, g = 1, b = 1, a = 1 } end
function fake_colors.alpha(c, a) return { hex = c.hex, a = a, r = c.r, g = c.g, b = c.b } end
function fake_colors.mix(c1, c2, f)
  if (f or 0) >= 0.5 then return c2 end
  return c1
end
function fake_colors.from_rgb(r, g, b) return { hex = 'rgb', r = r, g = g, b = b, a = 1 } end

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

local function count_hex(sc, hex, amin, amax)
  local n = 0
  for _, r in ipairs(sc.rects) do
    if r.c.hex == hex and (not amin or (r.c.a >= amin and r.c.a <= (amax or 1))) then n = n + 1 end
  end
  return n
end
local function has_text(sc, s)
  for _, x in ipairs(sc.texts) do if x.t.str == s then return true end end
  return false
end
local function any_word_text(sc)
  for _, x in ipairs(sc.texts) do
    if x.t.str:match('%a') then return x.t.str end
  end
  return nil
end

-- == 1. mag-fed rifle: count only + cartridge rack; no '/spare' duplicate ==
local sc = fake_scene()
bars.draw(sc, { count = 7, label = '7/56', weapon_key = 9100, spare = 4, spare_kind = 'mags', spare_max = 8 }, 1, fake_colors)
ok(has_text(sc, '7'), 'rifle: big number is the live count only')
ok(not has_text(sc, '7/56'), 'rifle: reserve duplicate gone from graphics')
ok(count_hex(sc, '#d4b054') == 4, 'rifle: exactly spare-many cartridge pips')
ok(count_hex(sc, '#1a1e1a') >= 1, 'rifle: single panel binds the module')

-- == 2. laser: NO decorative words anywhere; pct + bar + sinks ==
sc = fake_scene()
bars.draw(sc, { label = 'HEAT 62%', weapon_key = 9200, heat_frac = 0.62, heat_pct = 62,
                spare = 3, spare_kind = 'sinks', spare_max = 6, spare_max = 6 }, 1, fake_colors)
ok(any_word_text(sc) == nil, 'laser: no decorative word text (HEAT caption removed)')
ok(has_text(sc, '62%'), 'laser: pct numeral present')
ok(count_hex(sc, '#d9d9d9', 0.5) == 3, 'laser: three full sink bricks')

-- == 3. Cremator (single-pool): dial + pct + needle; NOTHING else ==
sc = fake_scene()
bars.draw(sc, { label = '61% / 545', weapon_key = 9300, fuel_frac = 0.61, spare_kind = 'units', spare = 545 }, 1, fake_colors)
ok(has_text(sc, '61%'), 'cremator: pct under the dial')
ok(not has_text(sc, '61% / 545'), 'cremator: units not duplicated in graphics')
ok(count_hex(sc, '#e8b84a', 0.5) == 0, 'cremator: no tank bricks for a single pool')
local arcs = 0
for _, k in ipairs(sc.kinds) do if k.kind == 'arc' then arcs = arcs + 1 end end
ok(arcs >= 4, 'cremator: dial drawn (shadow+track+tick+fill)')

-- == 4. multi-tank flamethrower: dial + tank bricks ==
sc = fake_scene()
bars.draw(sc, { label = '88% / 3', weapon_key = 9400, fuel_frac = 0.88, spare_kind = 'tanks', spare = 3 }, 1, fake_colors)
ok(count_hex(sc, '#e8b84a', 0.5) == 3, 'flamethrower: three full tank bricks')

-- == 5. rounds gun (shotgun/sniper/railgun base): full counter stays ==
sc = fake_scene()
bars.draw(sc, { count = 7, label = '7/28', weapon_key = 9500, spare = 28, spare_kind = 'rounds' }, 1, fake_colors)
ok(has_text(sc, '7/28'), 'rounds: reserve has no other visual -> full label kept')

-- == 6. Autocannon composite: zero text, cyan clip state, red empty ==
sc = fake_scene()
bars.draw(sc, { label = '3/10', weapon_key = 9600, spare = 6, spare_kind = 'backpack',
                pack = { remain = 6, total = 10 }, mag_rounds = 3, mag_cap = 10 }, 1, fake_colors)
ok(any_word_text(sc) == nil, 'AC: no text but digits')
ok(has_text(sc, '3/10') or count_hex(sc, '#7fd4ff') > 0, 'AC: clip-ready cyan state')
local red = count_hex(sc, '#e03030')
sc = fake_scene()
bars.draw(sc, { label = '0/10', weapon_key = 9601, spare = 6, spare_kind = 'backpack',
                pack = { remain = 6, total = 10 }, mag_rounds = 0, mag_cap = 10 }, 1, fake_colors)
ok(count_hex(sc, '#e03030') > 0, 'AC: empty magazine reads red (slow swap)')

-- == 7. charge overlay composes with any class ==
sc = fake_scene()
bars.draw(sc, { label = '1', weapon_key = 9700, spare = 4, spare_kind = 'rounds', charge_pct = 0.5 }, 1, fake_colors)
ok(count_hex(sc, '#3fa8d8') == 1, 'charge: cyan fill bar beside counter')

print(string.format('ammo_gfx_contract: %d checks, %d failures', checks, fails))
if fails > 0 then error('gfx contract violated') end
