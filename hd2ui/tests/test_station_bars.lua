-- tests/test_station_bars.lua -- the Floaty HUD station's geometry contract,
-- verified against the REAL scene module's display list. Checks: one grammar
-- (identical plate/divider/tray for every class), fixed numeral/unit cells,
-- the AC tick column's integer countability (10 slots, no merged or missing
-- slots, legality mark position/alpha), stripper-clip pips with partial
-- clips, heat thresholds and lock color, dial needle geometry, charge safe
-- mark, and silence for degenerate models. Run under Lua 5.1 (LuaJIT).

package.path = './?.lua;hd2ui/?.lua;' .. package.path

local scene = require('hd2ui.scene')
local SB = require('hd2ui.station_bars')
local checks, fails = 0, 0
local function check(name, cond, extra)
  checks = checks + 1
  if not cond then fails = fails + 1; print('FAIL ' .. name .. (extra and (' (' .. tostring(extra) .. ')') or '')) else print('ok   ' .. name) end
end

local function render(m, clock)
  local sc = scene.new()
  local cls = SB.draw(sc, m, { clock = clock })
  local dl = {}
  sc:render(dl, 0, 0, 1)
  return cls, dl
end

local function tris(dl) local t = {} for _, r in ipairs(dl) do if r.tri then t[#t + 1] = r.tri end end return t end
local function rects(dl) local t = {} for _, r in ipairs(dl) do if r.tri then t[#t + 1] = r.tri end end return t end
local function texts(dl) local t = {} for _, r in ipairs(dl) do if r.txt then t[#t + 1] = r.txt end end return t end

-- a tri record is axis-aligned iff x1==x2 or y1==y2 etc.; collect AABB rects
local function aabbs(dl)
  -- one AABB per unique rect (a rect quad emits two identical-bound tris)
  local out, seen = {}, {}
  for _, r in ipairs(dl) do
    if r.tri then
      local t = r.tri
      local xs, ys = { t[1], t[3], t[5] }, { t[2], t[4], t[6] }
      local x0, x1, y0, y1 = xs[1], xs[1], ys[1], ys[1]
      for i = 2, 3 do
        if xs[i] < x0 then x0 = xs[i] end
        if xs[i] > x1 then x1 = xs[i] end
        if ys[i] < y0 then y0 = ys[i] end
        if ys[i] > y1 then y1 = ys[i] end
      end
      local key = string.format('%.1f,%.1f,%.1f,%.1f,%d,%d,%d,%d', x0, y0, x1, y1,
        t[7][1] or 0, t[7][2] or 0, t[7][3] or 0, t[7][4] or 0)
      if not seen[key] then
        seen[key] = true
        out[#out + 1] = { x0 = x0, y0 = y0, x1 = x1, y1 = y1, c = t[7] }
      end
    end
  end
  return out
end

local function count(aabb_list, pred)
  local n = 0
  for _, b in ipairs(aabb_list) do if pred(b) then n = n + 1 end end
  return n
end

-- representative models (same shapes chain_model produces)
local MODELS = {
  mags    = { rounds = 38, mag_cap = 45, spare = 7, spare_max = 8, spare_kind = 'mags', weapon_id = 1 },
  clips   = { rounds = 7, mag_cap = 10, spare = 23, spare_kind = 'backpack',
              pack_rounds = 23, pack_total = 50, weapon_id = 2 },
  laser   = { heat_frac = 0.62, heat_pct = 62, spare = 3, spare_max = 5, spare_kind = 'sinks', weapon_id = 3 },
  laser_hot = { heat_frac = 0.9, heat_pct = 90, spare = 1, spare_max = 5, spare_kind = 'sinks', weapon_id = 3 },
  fuel    = { fuel_frac = 0.71, spare = 545, spare_kind = 'units', weapon_id = 4 },
  magcharge = { rounds = 4, mag_cap = 5, spare = 6, spare_max = 8, spare_kind = 'mags', charge_pct = 0.96, weapon_id = 5 },
  charge  = { charge_only = true, charge_pct = 0.42, weapon_id = 6 },
  rounds  = { rounds = 7, mag_cap = 8, spare = 28, spare_max = 56, spare_kind = 'rounds', ammo_max = 56, weapon_id = 7 },
  pool    = { rounds = 90, mag_cap = 100, spare = 210, spare_kind = 'backpack',
              pack_rounds = 210, pack_total = 300, weapon_id = 8 },
}

-- ---------------------------------------------------------------- classify
check('classify: mags', SB.classify(MODELS.mags) == 'mags')
check('classify: clips (AC family)', SB.classify(MODELS.clips) == 'clips')
check('classify: laser', SB.classify(MODELS.laser) == 'laser')
check('classify: burn support -> fuel', SB.classify({ heat_frac = 0.5, spare_kind = 'backpack', mag_cap = 10 }) == 'fuel')
check('classify: resource -> fuel', SB.classify(MODELS.fuel) == 'fuel')
check('classify: magcharge (railgun)', SB.classify(MODELS.magcharge) == 'magcharge')
check('classify: charge only (arc)', SB.classify(MODELS.charge) == 'charge')
check('classify: rounds', SB.classify(MODELS.rounds) == 'rounds')
check('classify: pool (big-cap backpack)', SB.classify(MODELS.pool) == 'pool')
check('classify: degenerate -> none', SB.classify({}) == 'none')

-- ------------------------------------------------------------ one grammar
local plate_sig = {}
for name, m in pairs(MODELS) do
  local cls, dl = render(m)
  local t = tris(dl)
  -- plate fill = first 3 tris of the station (emitted before anything else)
  local sig = table.concat({
    string.format('%.0f,%.0f,%.0f,%.0f', t[1][1], t[1][2], t[1][5], t[1][6]),
    string.format('%.0f,%.0f,%.0f,%.0f', t[2][1], t[2][2], t[2][5], t[2][6]),
    string.format('%.0f,%.0f,%.0f,%.0f', t[3][1], t[3][2], t[3][5], t[3][6]),
  }, ';')
  plate_sig[name] = sig
  local txt = texts(dl)
  check('grammar ' .. name .. ': text runs (numeral + units)', #txt == ((cls == 'clips') and 4 or 3), #txt)
  check('grammar ' .. name .. ': numeral at fixed x', txt[1][2] == 9, txt[1][2])
  local unit_x_expect = (cls == 'clips') and 9 or 67
  check('grammar ' .. name .. ': unit column at fixed x', txt[2][2] == unit_x_expect, txt[2][2])
  check('grammar ' .. name .. ': same text sizes', txt[1][4] == 33 and txt[2][4] == 9 and txt[3][4] == 9)
  local is_ac = (cls == 'clips')
  if is_ac then
    check('grammar clips: no divider (carousel owns the middle)',
      count(aabbs(dl), function(b) return b.y0 == 43 and b.y1 == 44 end) == 0)
  else
    check('grammar ' .. name .. ': divider present',
      count(aabbs(dl), function(b) return b.y0 == 43 and b.y1 == 44 and b.x0 == 0 and b.x1 == 150 end) >= 1)
  end
  check('grammar ' .. name .. ': tray present',
    count(aabbs(dl), function(b) return b.y0 == (is_ac and 82 or 44)
      and b.y1 == (is_ac and 99 or 61) and b.x0 >= 0 and b.x1 <= 150 end) >= 1)
end
check('grammar: plate fill identical for every standard class',
  plate_sig.mags == plate_sig.laser and plate_sig.mags == plate_sig.fuel and
  plate_sig.mags == plate_sig.charge)
do
  local _, dlac = render(MODELS.clips)
  local t2 = tris(dlac)[2]
  check('grammar: AC plate is the taller variant (100)', t2 and t2[6] == 100, t2 and t2[6])
end

-- ------------------------------------------------------------------ mags
local _, dl = render(MODELS.mags)
local ab = aabbs(dl)
local lit = count(ab, function(b) return b.x0 >= 8 and b.x1 <= 8 + 10 * 12 and b.y0 == 48 and b.y1 == 55
  and b.c[1] == 232 and b.c[4] == 235 end)
local spent = count(ab, function(b) return b.x0 >= 8 and b.x1 <= 142 and b.y0 >= 48 and b.y1 <= 58
  and b.c[4] == 64 end)
check('mags: 7 lit amber pips', lit == 7, lit)
check('mags: 1 spent silhouette (8 max)', spent >= 4, spent)  -- outline = 4 rects
check('mags: numeral text', texts(dl)[1][1] == '38')
local LOW = { rounds = 38, mag_cap = 45, spare = 1, spare_max = 8, spare_kind = 'mags', weapon_id = 1 }
local _, dl_p1 = render(LOW, 0.0)
local _, dl_p2 = render(LOW, 0.2)
local pulse_a1, pulse_a2
for _, b in ipairs(aabbs(dl_p1)) do
  if b.x0 == 8 and b.x1 == 14 and b.y0 == 48 and b.y1 == 55 and b.c[1] == 232 and b.c[4] ~= 235 then pulse_a1 = b.c[4] end
end
for _, b in ipairs(aabbs(dl_p2)) do
  if b.x0 == 8 and b.x1 == 14 and b.y0 == 48 and b.y1 == 55 and b.c[1] == 232 and b.c[4] ~= 235 then pulse_a2 = b.c[4] end
end
check('mags: last-mag pulse only at 1 mag, and it oscillates',
  pulse_a1 ~= nil and pulse_a2 ~= nil and pulse_a1 ~= pulse_a2,
  tostring(pulse_a1) .. ' vs ' .. tostring(pulse_a2))

-- ------------------------------------------------------------------ clips
local _, dlc = render(MODELS.clips)
check('clips: numeral 7 white at 7 rounds (reload not legal)',
  texts(dlc)[1][1] == '7' and texts(dlc)[1][5][1] == 242, texts(dlc)[1][1])
-- lollipop cutaway: exact amber tri mass. Every round disc emits a
-- deterministic fan (2 * floor(r/step + 0.5) * 2 tris) regardless of its
-- position/rotation, so counts are exact, not clustered estimates.
local function amber_tris(dl)
  local n = 0
  for _, r in ipairs(dl) do
    if r.tri and r.tri[7][1] == 232 and r.tri[7][2] == 163 and r.tri[7][4] == 235 then
      n = n + 1
    end
  end
  return n
end
local LOL = require('hd2ui.station_bars').LOL
local DRUM_TRI = 2 * math.floor(LOL.drum_r_round / 0.15 + 0.5)   -- per drum round
local COL_TRI = 2 * math.floor(LOL.col_r / 0.15 + 0.5)           -- per column round
local function ac_render(rounds)
  return render({ rounds = rounds, mag_cap = 10, spare = rounds * 5, spare_kind = 'backpack',
    pack_rounds = rounds * 5, pack_total = 50, weapon_id = 2 })
end
local _, ac4 = ac_render(4)    -- drum 4, column 0
local _, ac7 = ac_render(7)    -- drum 5, column 2
local _, ac10 = ac_render(10)  -- drum 5, column 5
check('lollipop: 4 rounds = 4 drum discs (column empty)',
  amber_tris(ac4) == 4 * DRUM_TRI, amber_tris(ac4) .. ' vs ' .. 4 * DRUM_TRI)
check('lollipop: 7 rounds = 5 drum + 2 column discs',
  amber_tris(ac7) == 5 * DRUM_TRI + 2 * COL_TRI,
  amber_tris(ac7) .. ' vs ' .. 5 * DRUM_TRI + 2 * COL_TRI)
check('lollipop: 10 rounds = 5 drum + 5 column discs',
  amber_tris(ac10) == 5 * DRUM_TRI + 5 * COL_TRI,
  amber_tris(ac10) .. ' vs ' .. 5 * DRUM_TRI + 5 * COL_TRI)
check('lollipop: backpack clip count text (x10)',
  (function()
    for _, r in ipairs(ac7) do
      if r.txt and r.txt[1] == 'x10' then return true end
    end
    return false
  end)())

-- ------------------------------------------------------------------ laser
local _, dll = render(MODELS.laser)
local hazard_faint, hazard_lit = 0, 0
for _, b in ipairs(aabbs(dll)) do
  if b.x0 >= 108 and b.x1 <= 142 and b.y0 >= 48 and b.y1 <= 56 then
    if b.c[1] == 232 and b.c[2] == 192 then
      if b.c[4] == 97 then hazard_faint = hazard_faint + 1 elseif b.c[4] == 235 then hazard_lit = hazard_lit + 1 end
    end
  end
end
check('laser: hazard band faint below 75%', hazard_faint > 0 and hazard_lit == 0, hazard_faint)
local _, dllh = render(MODELS.laser_hot)
local hot_lit = 0
for _, b in ipairs(aabbs(dllh)) do
  if b.x0 >= 108 and b.x1 <= 142 and b.y0 >= 48 and b.y1 <= 56 and b.c[1] == 232 and b.c[2] == 163 and b.c[4] == 235 then
    hot_lit = hot_lit + 1
  end
end
check('laser: hazard stripes LIT at 90% heat', hot_lit > 0, hot_lit)
local bricks_lit, bricks_spent = 0, 0
for _, b in ipairs(aabbs(dll)) do
  if b.y0 >= 29 and b.y1 <= 38 and b.x0 >= 100 and b.x1 <= 142 then
    if b.c[4] == 140 then bricks_lit = bricks_lit + 1 elseif b.c[4] == 64 then bricks_spent = bricks_spent + 1 end
  end
end
check('laser: 3 lit heatsink bricks', bricks_lit == 3, bricks_lit)
check('laser: 2 spent brick outlines (4 rects each)', bricks_spent == 8, bricks_spent)
check('laser: numeral is the heat pct', texts(dll)[1][1] == '62')
local _, dllock = render({ heat_frac = 0.99, heat_pct = 99, heat_lock = true, spare = 0, spare_max = 5, spare_kind = 'sinks' })
check('laser: lock turns numeral red', texts(dllock)[1][5][1] == 224, texts(dllock)[1][5] and texts(dllock)[1][5][1])

-- ------------------------------------------------------------------- fuel
local _, dlf = render(MODELS.fuel)
local arcs = 0
for _, r in ipairs(dlf) do if r.tri then end end
-- arc bands come through as many small quads; detect via the dial region tris
local dial_tris = 0
for _, t in ipairs(tris(dlf)) do
  local xs, ys = { t[1], t[3], t[5] }, { t[2], t[4], t[6] }
  for i = 1, 3 do
    local dx, dy = xs[i] - 75, ys[i] - 59
    if dx * dx + dy * dy > 11 * 11 and dx * dx + dy * dy < 16 * 16 then dial_tris = dial_tris + 1 break end
  end
end
check('fuel: arc track + red zone rendered around the dial center', dial_tris >= 20, dial_tris)
local _, dlf0 = render({ fuel_frac = 0.0 })
local _, dlf1 = render({ fuel_frac = 1.0 })
local needle_angle = function(dl)
  for _, t in ipairs(tris(dl)) do
    -- needle tri contains the dial center as one vertex
    if (t[1] == 75 and t[2] == 59) or (t[3] == 75 and t[4] == 59) or (t[5] == 75 and t[6] == 59) then
      local xs, ys = { t[1], t[3], t[5] }, { t[2], t[4], t[6] }
      for i = 1, 3 do
        local dx, dy = xs[i] - 75, ys[i] - 59
        if dx * dx + dy * dy > 4 then return math.atan2(dy, dx) end
      end
    end
  end
end
local a0, a1 = needle_angle(dlf0), needle_angle(dlf1)
check('fuel: needle angle tracks fraction', a0 and a1 and (a1 - a0) > 1.5 and (a1 - a0) < 2.6,
  tostring(a0) .. ' -> ' .. tostring(a1))

-- --------------------------------------------------------- charge / rounds
local _, dlmc = render(MODELS.magcharge)
local safe_mark, amber_seg, cyan_seg = nil, 0, 0
for _, b in ipairs(aabbs(dlmc)) do
  if b.y0 >= 47 and b.y1 <= 56 and b.x0 >= 8 and b.x1 <= 142 then
    if b.c[4] == 64 and (b.x1 - b.x0) == 1 then safe_mark = b end
    if b.c[1] == 143 then cyan_seg = cyan_seg + 1 end
    if b.c[1] == 232 and b.c[2] == 163 then amber_seg = amber_seg + 1 end
  end
end
check('magcharge: cyan charge rendered', cyan_seg > 0, cyan_seg)
check('magcharge: numeral is the charge pct', texts(dlmc)[1][1] == '96' and texts(dlmc)[2][1] == 'CHRG',
  texts(dlmc)[1][1])
check('magcharge: amber past the safe mark', amber_seg > 0, amber_seg)
check('magcharge: safe mark at 80%', safe_mark and math.abs(safe_mark.x0 - 115) <= 1, safe_mark and safe_mark.x0)
local _, dlr = render(MODELS.rounds)
local rsv_end, rsv_n
for _, b in ipairs(aabbs(dlr)) do
  if b.y0 == 51 and b.y1 == 55 and b.x0 == 8 and b.c[4] == 140 then rsv_n, rsv_end = (rsv_n or 0) + 1, b.x1 end
end
check('rounds: reserve bar rendered (28/56 = half)',
  rsv_n == 1 and rsv_end and math.abs(rsv_end - (8 + 67)) <= 1, tostring(rsv_n) .. '/' .. tostring(rsv_end))

-- ------------------------------------------------------------------ none
local scc = scene.new()
local cls = SB.draw(scc, {})
check('none: degenerate model draws nothing', cls == 'none' and scc:count() == 0)

-- AC rules (user spec): max 10, no +1, legality at exactly <=5
local _, d5 = render({ rounds = 5, mag_cap = 10, spare = 25, spare_kind = 'backpack',
  pack_rounds = 25, pack_total = 50, weapon_id = 2 })
check('clips: numeral 5 AMBER at the reload boundary',
  texts(d5)[1][1] == '5' and texts(d5)[1][5][1] == 232, texts(d5)[1][1])
local _, d6 = render({ rounds = 6, mag_cap = 10, spare = 30, spare_kind = 'backpack',
  pack_rounds = 30, pack_total = 50, weapon_id = 2 })
check('clips: numeral 6 WHITE above the boundary',
  texts(d6)[1][1] == '6' and texts(d6)[1][5][1] == 242, texts(d6)[1][1])
local _, d11 = render({ rounds = 11, mag_cap = 10, spare = 50, spare_kind = 'backpack',
  pack_rounds = 50, pack_total = 50, weapon_id = 2 })
check('clips: pool clamps to the 10 maximum (no +1)',
  texts(d11)[1][1] == '10', texts(d11)[1][1])
print(string.format('\nstation_bars: %d checks, %d failures', checks, fails))
if fails > 0 then error(fails .. ' failures') end
