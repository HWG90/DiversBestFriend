-- hd2ui/station_bars.lua -- the Floaty HUD station (concepts/floaty-hud).
-- Pure display: one 150x62 chamfered plate (1080p reference units, local
-- coords, y-down, plate top-left at 0,0) that every weapon class docks into.
-- One grammar (DESIGN.md rule 1): plate, divider, numeral row and tray are
-- IDENTICAL for all classes; only the tray gauge and the unit words change.
--
-- Model contract (produced by station_entry's chain_model):
--   { rounds, mag_cap, spare, spare_max, spare_kind, pack_rounds, pack_total,
--     heat_frac, heat_lock, fuel_frac, charge_pct, charge_only, weapon_id }
-- classify() derives the presentation class; draw() emits scene elements.
--
-- Geometry is integer-disciplined wherever countability matters (the AC tick
-- column): fractional heights/gaps subpixel-snap and merge adjacent elements.
--
-- Lua 5.1 / LuaJIT.

local M = {}
M.W, M.H = 150, 62            -- plate box (reference units)
M.H_AC = 100                  -- AC variant: taller, the magazine cutaway fits
M.DIVIDER_Y = 43              -- primary row / tray boundary
M.NUM_X = 9                   -- numeral cell (fixed width -> nothing reflows)
M.UNIT_X = 67
M.BAR_X, M.BAR_W, M.BAR_Y, M.BAR_H = 8, 134, 48, 7
M.HAZARD_FRAC = 0.75          -- last quarter of the bar is the hazard band
M.CLIP_SLOTS = 10             -- AC backpack: stripper-clip pips (data-driven count)

local INK = { 242, 242, 242, 255 }
local INK_DIM = { 242, 242, 242, 140 }
local INK_FAINT = { 242, 242, 242, 64 }
local PLATE = { 14, 16, 13, 140 }     -- .55 alpha; no backdrop blur in-game
local BORDER = { 242, 242, 242, 41 }  -- .16
local TRAY = { 8, 9, 7, 115 }         -- .45
local AMBER = { 232, 163, 61, 235 }
local RED = { 224, 48, 48, 255 }
local CYAN = { 143, 216, 232, 235 }
local HAZ_Y = { 232, 192, 32, 97 }    -- faint stripe (always visible)
local HAZ_DARK = { 20, 20, 16, 115 }
local PALE = { 217, 212, 200, 235 }   -- heat fill low end

local floor, cos, sin, pi = math.floor, math.cos, math.sin, math.pi
local DEG = pi / 180

------------------------------------------------------------------------------
-- classification: model -> presentation class (pure, unit-tested)
------------------------------------------------------------------------------
function M.classify(m)
  if not m then return 'none' end
  -- an ok chain row always carries at least one numeric story; anything else
  -- is a degenerate sample -> hide (never a ghost "0" station)
  if not (m.rounds or m.count or m.heat_frac or m.fuel_frac or m.charge_pct or m.charge_only) then
    return 'none'
  end
  if m.charge_only then return 'charge' end
  if m.heat_frac then
    if m.spare_kind == 'backpack' then return 'fuel' end   -- burn support: 'heat' field is the fuel level
    return 'laser'
  end
  if m.fuel_frac then return 'fuel' end                    -- resource path (Cremator)
  if m.charge_pct and (m.rounds or m.count) then return 'magcharge' end  -- railgun
  if m.spare_kind == 'backpack' and (m.mag_cap or m.capacity) then
    local cap = m.mag_cap or m.capacity
    if cap >= 5 and cap <= 16 then return 'clips' end      -- autocannon family
    return 'pool'                                          -- round-pool support guns (MG-43)
  end
  if m.spare_kind == 'rounds' then return 'rounds' end
  return 'mags'
end

local function shown_rounds(m)
  return m.rounds or m.count or 0
end
local function mag_cap(m)
  local c = m.mag_cap or m.capacity or 1
  if c < 1 then c = 1 end
  return c
end

------------------------------------------------------------------------------
-- small composites
------------------------------------------------------------------------------
local function outline(sc, x, y, w, h, col)
  sc:add('rect', { x = x, y = y, w = w, h = 1 }, col)
  sc:add('rect', { x = x, y = y + h - 1, w = w, h = 1 }, col)
  sc:add('rect', { x = x, y = y + 1, w = 1, h = h - 2 }, col)
  sc:add('rect', { x = x + w - 1, y = y + 1, w = 1, h = h - 2 }, col)
end

local function heat_fill_color(frac, locked)
  if locked then return RED end
  if frac < 0.5 then
    local t = frac * 2
    return { PALE[1] + (AMBER[1] - PALE[1]) * t, PALE[2] + (AMBER[2] - PALE[2]) * t,
             PALE[3] + (AMBER[3] - PALE[3]) * t, PALE[4] }
  end
  local t = math.min(1, (frac - 0.5) * 2)
  return { AMBER[1] + (RED[1] - AMBER[1]) * t, AMBER[2] + (RED[2] - AMBER[2]) * t,
           AMBER[3] + (RED[3] - AMBER[3]) * t, AMBER[4] }
end

-- hazard band: 45-degree stripes confined to [x0,x1], faint always, lit above
-- the threshold. Integer rows (2px), phase advancing 2px per row.
local function hazard(sc, x0, x1, y0, y1, lit)
  local row, stripe_a = y0, (lit and AMBER or HAZ_Y)
  while row < y1 - 0.01 do
    local rh = math.min(2, y1 - row)
    local phase = (row - y0) % 4
    sc:add('rect', { x = x0, y = row, w = x1 - x0, h = rh }, HAZ_DARK)
    local p = phase
    while p < (x1 - x0) do
      local seg_w = math.min(2, (x1 - x0) - p)
      if seg_w > 0 then sc:add('rect', { x = x0 + p, y = row, w = seg_w, h = rh }, stripe_a) end
      p = p + 4
    end
    row = row + 2
  end
end

local function bar_gauge(sc, frac, fill_col, safe_frac, opts)
  local x, w, y, h = M.BAR_X, M.BAR_W, M.BAR_Y, M.BAR_H
  sc:add('rect', { x = x, y = y, w = w, h = h }, { 242, 242, 242, 26 })   -- 10% track
  frac = math.max(0, math.min(1, frac or 0))
  if safe_frac then
    local safe_w = floor(w * safe_frac + 0.5)
    if frac <= safe_frac then
      sc:add('rect', { x = x, y = y, w = floor(w * frac + 0.5), h = h }, fill_col)
    else
      sc:add('rect', { x = x, y = y, w = safe_w, h = h }, fill_col)
      sc:add('rect', { x = x + safe_w, y = y, w = floor(w * frac + 0.5) - safe_w, h = h },
             (opts and opts.over_col) or AMBER)
    end
    sc:add('rect', { x = x + safe_w, y = y - 1, w = 1, h = h + 2 }, INK_FAINT)  -- safe mark
  else
    sc:add('rect', { x = x, y = y, w = floor(w * frac + 0.5), h = h }, fill_col)
  end
end

-- up-facing arc dial with needle (gas-tank style), centered in the tray
local DIAL_CX, DIAL_CY, DIAL_R = 75, 59, 13
local DIAL_A0, DIAL_SWEEP = 210 * DEG, 120 * DEG
local function dial(sc, frac)
  local a0, sweep = DIAL_A0, DIAL_SWEEP
  sc:add('arc', { cx = DIAL_CX, cy = DIAL_CY, r = DIAL_R, th = 1.4,
                  a0 = a0, a1 = a0 + sweep, step = 0.06 }, { 242, 242, 242, 71 })  -- 28% track
  sc:add('arc', { cx = DIAL_CX, cy = DIAL_CY, r = DIAL_R, th = 1.4,
                  a0 = a0 + sweep * 0.75, a1 = a0 + sweep, step = 0.06 }, { 224, 48, 48, 153 })
  frac = math.max(0, math.min(1, frac or 0))
  local ang = a0 + sweep * frac
  local tx, ty = DIAL_CX + 10 * cos(ang), DIAL_CY + 10 * sin(ang)
  local px, py = -sin(ang) * 0.7, cos(ang) * 0.7
  sc:add('tri', { x1 = DIAL_CX, y1 = DIAL_CY, x2 = tx + px, y2 = ty + py, x3 = tx - px, y3 = ty - py }, INK)
  sc:add('circle', { cx = DIAL_CX, cy = DIAL_CY, r = 1.3, step = 0.12 }, AMBER)
end

------------------------------------------------------------------------------
-- tray gauges + aux elements per class
------------------------------------------------------------------------------
local function legality_ink(legal)
  -- one legality signal: the numeral itself turns amber at <=5 rounds
  return legal and AMBER or INK
end
-- one magazine pip: chamfered bullet (approved mock shape) -- rect body plus
-- a down-pointing tip, 6x10 total
local function pip_body(sc, x, col, y0)
  y0 = y0 or 48
  sc:add('rect', { x = x, y = y0, w = 6, h = 7 }, col)
  sc:add('tri', { x1 = x, y1 = y0 + 7, x2 = x + 6, y2 = y0 + 7, x3 = x + 3, y3 = y0 + 10 }, col)
end

local function pip_row(sc, lit, total, partial, x0, pulse_a, y0)
  y0 = y0 or 48
  total = math.min(total, M.CLIP_SLOTS)
  for i = 1, total do
    local x = x0 + (i - 1) * 12
    if i <= lit then
      pip_body(sc, x, AMBER, y0)
    elseif partial and i == lit + 1 then
      sc:add('rect', { x = x, y = y0 + 5, w = 6, h = 5 }, AMBER)              -- partial clip: half fill
      outline(sc, x, y0, 6, 10, INK_FAINT)
    else
      outline(sc, x, y0, 6, 10, INK_FAINT)                                    -- spent silhouette
    end
  end
  if pulse_a and lit == 1 and total >= 2 then                                  -- last mag: pulse
    local pa = { AMBER[1], AMBER[2], AMBER[3], floor(AMBER[4] * pulse_a) }
    pip_body(sc, x0, pa, y0)
  end
end

local function tray_bar_pool(sc, remain, total)
  local frac = (total and total > 0) and remain / total or 0
  sc:add('rect', { x = M.BAR_X, y = 51, w = M.BAR_W, h = 4 }, { 242, 242, 242, 26 })
  sc:add('rect', { x = M.BAR_X, y = 51, w = floor(M.BAR_W * math.min(1, frac) + 0.5), h = 4 }, INK_DIM)
end

local function laser_bricks(sc, sinks, sinks_max)
  local n = math.min(sinks_max or sinks or 0, 8)
  if n < 1 then return end
  for i = 1, n do
    local x = 142 - 4 - (n - i) * 7
    if i <= (sinks or 0) then
      sc:add('rect', { x = x, y = 29, w = 4, h = 9 }, INK_DIM)
    else
      outline(sc, x, 29, 4, 9, INK_FAINT)
    end
  end
end

-- autocannon magazine: a LOLLIPOP cutaway (user render, 2026-09-29): a
-- straight single-file tube up top feeding a large rotating drum below.
-- Rounds ride the INSIDE of the drum rim around an empty hub; the tube
-- column drains from the top as rounds feed down into the drum. User rules:
-- max 10 (no chamber +1), reload legal at <=5, reloads happen in fives.
local LOL = {
  col_x = 74, col_top = 6, col_slots = 5, col_space = 9, col_r = 4.3,
  drum_cx = 78, drum_cy = 62, drum_r = 30, drum_ring_r = 19, drum_slots = 5,
  drum_r_round = 5.3, hub_r = 9,
}
local TUBE_FILL = { 8, 9, 7, 205 }
M.LOL = LOL   -- exposed for tests (per-round tri mass derives from these)
local HUB_FILL = { 20, 22, 19, 220 }

local function lollipop(sc, rounds)
  rounds = math.max(0, math.min(rounds, 10))
  local drum_n = math.min(rounds, LOL.drum_slots)
  local col_n = rounds - drum_n

  -- drum: dark disc + hairline rim + empty hub with an axle
  sc:add('circle', { cx = LOL.drum_cx, cy = LOL.drum_cy, r = LOL.drum_r, step = 0.08 }, TUBE_FILL)
  sc:add('ring', { cx = LOL.drum_cx, cy = LOL.drum_cy, r0 = LOL.drum_r,
                   r1 = LOL.drum_r + 1, a0 = 0, a1 = 2 * pi, step = 0.08 }, BORDER)
  sc:add('circle', { cx = LOL.drum_cx, cy = LOL.drum_cy, r = LOL.hub_r, step = 0.1 }, HUB_FILL)
  sc:add('ring', { cx = LOL.drum_cx, cy = LOL.drum_cy, r0 = LOL.hub_r,
                   r1 = LOL.hub_r + 1, a0 = 0, a1 = 2 * pi, step = 0.1 }, INK_FAINT)
  sc:add('circle', { cx = LOL.drum_cx, cy = LOL.drum_cy, r = 2.5, step = 0.2 }, INK_FAINT)

  -- drum rounds: pentagon on the inside of the rim; the cylinder indexes
  -- 72 deg per shot so the remaining rounds stay evenly spread
  local off = (LOL.drum_slots - drum_n) * (2 * pi / LOL.drum_slots)
  for i = 0, LOL.drum_slots - 1 do
    local ang = -pi / 2 + off + i * (2 * pi / LOL.drum_slots)
    local x = LOL.drum_cx + LOL.drum_ring_r * cos(ang)
    local y = LOL.drum_cy + LOL.drum_ring_r * sin(ang)
    if i < drum_n then
      sc:add('circle', { cx = x, cy = y, r = LOL.drum_r_round, step = 0.15 }, AMBER)
    else
      sc:add('ring', { cx = x, cy = y, r0 = 4.0, r1 = 5.0, a0 = 0, a1 = 2 * pi, step = 0.2 }, INK_FAINT)
    end
  end

  -- column tube feeding the drum from above (border pass, then dark fill)
  sc:add('rect', { x = LOL.col_x - 6.5, y = LOL.col_top - 1, w = 13,
                   h = LOL.drum_cy - LOL.drum_r + LOL.hub_r - LOL.col_top + 1 }, BORDER)
  sc:add('circle', { cx = LOL.col_x, cy = LOL.col_top, r = 6.5, step = 0.15 }, BORDER)
  sc:add('rect', { x = LOL.col_x - 5.5, y = LOL.col_top, w = 11,
                   h = LOL.drum_cy - LOL.drum_r + LOL.hub_r - LOL.col_top }, TUBE_FILL)
  sc:add('circle', { cx = LOL.col_x, cy = LOL.col_top, r = 5.5, step = 0.15 }, TUBE_FILL)

  -- column rounds: the BOTTOM col_n are lit (they feed the drum first), the
  -- top empties out as the magazine burns down
  for i = 0, LOL.col_slots - 1 do
    local y = LOL.col_top + 4 + (LOL.col_slots - 1 - i) * LOL.col_space
    if i < col_n then
      sc:add('circle', { cx = LOL.col_x, cy = y, r = LOL.col_r, step = 0.15 }, AMBER)
    else
      sc:add('ring', { cx = LOL.col_x, cy = y, r0 = 3.3, r1 = 4.1, a0 = 0, a1 = 2 * pi, step = 0.2 }, INK_FAINT)
    end
  end
end

------------------------------------------------------------------------------
-- the station (rule 1: one grammar). opts: { clock } for the pulse.
------------------------------------------------------------------------------
function M.draw(sc, m, opts)
  opts = opts or {}
  local cls = M.classify(m)
  if cls == 'none' then return cls end

  -- plate: chamfered fill (8px cut, top-right) as three tris + hairline border.
  -- The AC variant is taller: the magazine cutaway lives beside the numeral.
  local W, H, C = M.W, (cls == 'clips') and M.H_AC or M.H, 8
  sc:add('tri', { x1 = 0, y1 = 0, x2 = W - C, y2 = 0, x3 = W, y3 = C }, PLATE)
  sc:add('tri', { x1 = 0, y1 = 0, x2 = W, y2 = C, x3 = W, y3 = H }, PLATE)
  sc:add('tri', { x1 = 0, y1 = 0, x2 = W, y2 = H, x3 = 0, y3 = H }, PLATE)
  sc:add('rect', { x = 0, y = 0, w = W - C, h = 1 }, BORDER)
  sc:add('quad', { ax = W - C, ay = 0, bx = W, by = C, cx = W, cy = C + 1, dx = W - C - 1, dy = 1 }, BORDER)
  sc:add('rect', { x = W - 1, y = C, w = 1, h = H - C }, BORDER)
  sc:add('rect', { x = 0, y = H - 1, w = W, h = 1 }, BORDER)
  sc:add('rect', { x = 0, y = 0, w = 1, h = H }, BORDER)

  -- divider + tray. AC: no divider (the carousel owns the middle) and the
  -- tray drops to the bottom of the taller plate.
  local tray_y = M.DIVIDER_Y + 1
  if cls == 'clips' then
    tray_y = H - 18
  else
    sc:add('rect', { x = 0, y = M.DIVIDER_Y, w = W, h = 1 }, { 242, 242, 242, 31 })
  end
  sc:add('rect', { x = 1, y = tray_y, w = W - 2, h = H - tray_y - 1 }, TRAY)

  local num_x, unit_x = M.NUM_X, M.UNIT_X
  local numeral, unit1, unit2 = '', '', ''
  local legal_ammo = false
  local clip_total
  local pulse = opts.clock and (0.55 + 0.45 * sin(opts.clock * 5)) or nil

  if cls == 'mags' then
    local shown, spare, smax = shown_rounds(m), m.spare, m.spare_max
    numeral, unit1, unit2 = tostring(shown), 'RNDS', 'MAGS'
    if spare ~= nil then
      local total = math.min(smax or spare, M.CLIP_SLOTS)
      pip_row(sc, spare, total, false, M.BAR_X, pulse)
    end
  elseif cls == 'clips' then
    local cap = mag_cap(m)
    local shown, pack_r, pack_t = shown_rounds(m), m.pack_rounds or m.spare or 0,
                                  m.pack_total or 0
    -- user rules: max 10, no chamber +1, reload legal at <=5, reloads in fives
    shown = math.min(shown, cap)
    numeral, unit1, unit2 = tostring(shown), 'RNDS', 'CLPS'
    num_x, unit_x = 9, 9            -- units stack under the numeral; the
    -- carousel owns the middle of the tall plate
    local clip = math.max(1, floor(cap / 2))
    local total = math.min(floor((pack_t + clip - 1) / clip), M.CLIP_SLOTS)
    local lit = floor(pack_r / clip)
    local partial = (pack_r - lit * clip) > 0
    if lit > total then lit = total end
    lollipop(sc, shown)
    legal_ammo = shown <= clip
    clip_total = total
  elseif cls == 'laser' then
    local frac = math.min(1, m.heat_frac or 0)
    numeral = tostring(m.heat_pct or floor(frac * 100 + 0.5))
    unit1, unit2 = 'HEAT', 'PCT'
    laser_bricks(sc, m.spare, m.spare_max)
    bar_gauge(sc, frac, heat_fill_color(frac, m.heat_lock), nil, nil)
    hazard(sc, M.BAR_X + floor(M.BAR_W * M.HAZARD_FRAC), M.BAR_X + M.BAR_W, M.BAR_Y, M.BAR_Y + M.BAR_H, frac >= M.HAZARD_FRAC)
  elseif cls == 'fuel' then
    -- burn support arrives as heat_frac (the chain's 'heat' field IS the fuel
    -- level there); resource weapons (Cremator) arrive as fuel_frac.
    local fuel = m.fuel_frac or m.heat_frac or 0
    numeral = tostring(floor(fuel * 100 + 0.5))
    unit1, unit2 = 'FUEL', 'PCT'
    dial(sc, fuel)
  elseif cls == 'magcharge' then
    -- railgun: the charge IS the story (DESIGN.md) -- charge % in the numeral,
    -- cyan strip with the safe-charge mark in the tray
    numeral = tostring(floor((m.charge_pct or 0) * 100 + 0.5))
    unit1, unit2 = 'CHRG', 'PCT'
    bar_gauge(sc, m.charge_pct, CYAN, 0.8, nil)
  elseif cls == 'charge' then
    numeral = tostring(floor((m.charge_pct or 0) * 100 + 0.5))
    unit1, unit2 = 'CHRG', 'PCT'
    bar_gauge(sc, m.charge_pct, CYAN, 0.8, nil)
  elseif cls == 'rounds' then
    numeral, unit1, unit2 = tostring(shown_rounds(m)), 'RNDS', 'RSV'
    if m.spare ~= nil then
      tray_bar_pool(sc, m.spare, m.spare_max or m.ammo_max or (m.spare * 2))
    end
  elseif cls == 'pool' then
    numeral, unit1, unit2 = tostring(shown_rounds(m)), 'RNDS', 'POOL'
    tray_bar_pool(sc, m.pack_rounds or m.spare or 0, m.pack_total or 0)
  end

  local ink = INK
  if cls == 'laser' and m.heat_lock then ink = RED
  elseif legal_ammo then ink = legality_ink(true) end
  sc:add('text', { str = numeral, x = num_x, y = 34, size = 33, align = 'left' }, ink)
  local uy1, uy2 = 18, 28
  if cls == 'clips' then uy1, uy2 = 42, 52 end
  sc:add('text', { str = unit1, x = unit_x, y = uy1, size = 9, align = 'left' }, INK_DIM)
  sc:add('text', { str = unit2, x = unit_x, y = uy2, size = 9, align = 'left' }, INK_DIM)
  if cls == 'clips' and clip_total then
    -- backpack reserve in stripper clips, e.g. "x10"
    sc:add('text', { str = 'x' .. tostring(clip_total), x = 9, y = 62, size = 9, align = 'left' }, INK_DIM)
  end
  return cls
end

return M
