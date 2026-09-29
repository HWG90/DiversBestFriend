-- hd2ui/ammo_bars.lua -- Graphical presentation layer for the ammo HUD.
-- Orthogonal to the position styles (crosshair/gunside/world): the style owns
-- the anchor; this layer draws scene primitives in LOCAL coordinates around
-- the anchor (rect x,y = left/bottom corner, y-up, matching the framework's
-- gunside backdrop convention).
--
--   HEAT  (lasers):      vertical bar FILLS as heat rises; red + LOCK at cap.
--   FUEL  (burn guns):   vertical bar EMPTIES as the tank drains.
--   counter:             numeric label always kept (user spec).
--   spare magazines:     horizontal bar that shrinks as packs are consumed
--                        and returns when refilled (ratio vs the highest
--                        spare count seen for this weapon id, or the config
--                        max when known).
--
-- Lua 5.1 / LuaJIT. M.draw(sc, model, mult, colors) -- colors is api.colors
-- (the framework palette module; there is no standalone hd2ui.colors).

local M = {}
M.seen = {}   -- weapon_key -> { spare = max seen }

local function heat_color(colors, frac, locked)
  if locked then return colors.from_hex('#e03030') end
  local pale, amber = colors.from_hex('#d9d4c8'), colors.from_hex('#e0a030')
  local red = colors.from_hex('#e03030')
  if frac < 0.5 then return colors.mix(pale, amber, frac * 2) end
  return colors.mix(amber, red, (frac - 0.5) * 2)
end

-- hazard overlay: 45-degree yellow/black caution stripes confined to a zone
-- [y0, y0+zh] of the bar. Rendered as 1-unit scanline steps whose phase
-- advances 1 unit per row (true diagonal at this resolution; no clipping
-- needed because every segment is intersected with the bar width).
local STRIPE_W, STRIPE_PERIOD = 2, 4   -- pattern units (yellow 2 of every 4)
local ROW = 1.25                          -- stripe scanline thickness (ref units)

local function hazard_zone(sc, colors, x, y0, w, zh, active)
  local yellow = colors.from_hex('#e8c020')
  local dark   = colors.from_hex('#141410')
  local a_stripe, a_dark = active and 0.95 or 0.30, active and 0.85 or 0.45
  local row = 0
  while row < zh - 0.5 do
    local phase = row % STRIPE_PERIOD
    local yy = y0 + row
    -- dark base line
    sc:add('rect', { x = x, y = yy, w = w, h = ROW }, colors.alpha(dark, a_dark))
    -- yellow segments clipped to [x, x+w]
    local p = phase
    while p < w do
      local seg_x = x + p
      local seg_w = math.min(STRIPE_W, w - p)
      if seg_w > 0 then
        sc:add('rect', { x = seg_x, y = yy, w = seg_w, h = ROW }, colors.alpha(yellow, a_stripe))
      end
      p = p + STRIPE_PERIOD
    end
    row = row + 1.25
  end
end

-- Vertical bar spanning [bottom, bottom+h].
-- mode 'heat': fills TOP-DOWN (anchored at the top; danger grows toward the
--              hazard-striped BOTTOM 10%).  mode 'fuel': fills from the bottom
--              and empties down into the same bottom hazard band.
local function vert_bar(sc, colors, x, bottom, h, w, frac, col, label, mode)
  local fill = math.max(0, math.min(1, frac))
  sc:add('rect', { x = x, y = bottom, w = w, h = h },
         colors.alpha(colors.from_hex('#1e211d'), 0.35))
  -- both gauges hang from the TOP: heat grows down INTO the hazard field,
  -- fuel shrinks up to EXPOSE it. The fill carves the field: stripe rows
  -- are only drawn below the fill's leading edge, and the fill itself is
  -- near-opaque, so the gauge cleanly overwrites the stripes (user spec).
  local fy = mode and (bottom + h * (1 - fill)) or bottom
  if mode then
    -- hazard stripes are a THRESHOLD ALARM: they exist only once the gauge
    -- enters the danger quarter (heat >= 75% / fuel <= 25%), carved by the
    -- fill's leading edge so the gauge still overwrites them.
    -- hazard marks are ALWAYS drawn (faint); they LIT UP past the threshold
    -- (heat >= 75% / fuel <= 25%). Carve at the fill's bottom edge so the
    -- gauge still overwrites the band where it physically covers it.
    local danger
    if mode == 'heat' then danger = fill >= 0.75 else danger = fill <= 0.25 end
    local zh = math.max(3, math.floor(h * 0.25 + 0.5))
    local cut = bottom + h * (1 - fill)
    local visible_h = math.max(0, math.min(bottom + zh, cut) - bottom)
    if visible_h > 0.5 then
      hazard_zone(sc, colors, x, bottom, w, visible_h, danger)
    end
  end
  if fill > 0.005 then
    sc:add('rect', { x = x, y = fy, w = w, h = h * fill },
           colors.alpha(col, 0.9))
  end
  if label then
    sc:add('text', { str = label, x = x + w / 2, y = bottom - 12, size = 8, align = 'center' },
           colors.alpha(colors.from_hex('#c8c8c8'), 0.8))
  end
end

-- left-anchored horizontal bar (spare mags): empties as packs are consumed
local function horiz_bar(sc, colors, x, y, total_w, h, frac, col)
  local fill = math.max(0, math.min(1, frac))
  sc:add('rect', { x = x, y = y, w = total_w, h = h },
         colors.alpha(colors.from_hex('#1e211d'), 0.30))
  if fill > 0.005 then
    sc:add('rect', { x = x, y = y, w = total_w * fill, h = h }, colors.alpha(col, 0.85))
  end
end

-- per-element offset helper (dashboard-movable)
local function off(LAY, id, mult)
  local x, y = LAY.get(id)
  return x * mult, y * mult
end

-- sub-tray: a shallow drawer welded to the panel's bottom edge, so secondary
-- rows (sinks, tanks, charge) read as PART of the station, not floaters
local function tray(sc, colors, x, y, w, mult)
  -- deliberately DARKER than the panel body so the two-tone station reads
  sc:add('rect', { x = x, y = y + 2 * mult, w = w, h = 11 * mult },
         colors.alpha(colors.from_hex('#040504'), 0.80))
  sc:add('rect', { x = x, y = y + 2 * mult, w = w, h = 0.8 * mult },
         colors.alpha(colors.from_hex('#4a5158'), 0.55))
end

-- model fields consumed: label, color, weapon_key, spare, spare_kind,
-- spare_max, heat_frac, heat_lock, heat_pct, fuel_frac, charge_pct,
-- pack {remain,total}, mag_rounds, mag_cap, layout_all (dashboard).
--
-- UNIFIED PANEL DESIGN (R52): every weapon class docks into ONE frosted core
-- panel at a fixed station right of the crosshair. The panel is the contract;
-- only its contents change per class. Coordinate convention stated once:
-- scene space is y-DOWN (backend flips at emit): larger y = lower on screen.
function M.draw(sc, model, mult, colors)
  mult = mult or 1
  local m = model
  local LAY = M.LAY or { active = false, get = function() return 0, 0 end }
  local lox, loy = off(LAY, 'label', mult)
  local PX = 34 * mult + lox            -- panel top-left (y-down)
  local PY = -17 * mult + loy
  local PW = 120 * mult                 -- panel width (grows for AC)
  local PH = 34 * mult

  -- observed max spare (rack/brick denominators)
  local ref = math.max(m.spare_max or 0, 1)
  if m.weapon_key and m.spare_kind == 'mags' then
    local seen = M.seen[m.weapon_key]
    if not seen then seen = { spare = 0 }; M.seen[m.weapon_key] = seen end
    if (m.spare or 0) > seen.spare then seen.spare = m.spare end
    ref = math.max(ref, seen.spare, 1)
  end

  local is_ac   = m.pack and m.mag_rounds ~= nil and (m.mag_cap or 1) > 1
  local is_heat = m.heat_frac ~= nil
  local is_fuel = m.fuel_frac ~= nil
  if is_ac then PW = 128 * mult end

  local function panel_bg()
    -- two-tone: charcoal body + near-black tray = one visible station
    sc:add('rect', { x = PX, y = PY, w = PW, h = PH },
           colors.alpha(colors.from_hex('#1a1e1a'), 0.66))
    sc:add('rect', { x = PX, y = PY, w = PW, h = 1.2 * mult },
           colors.alpha(colors.from_hex('#000000'), 0.5))
    sc:add('rect', { x = PX, y = PY + PH - 1.2 * mult, w = PW, h = 1.2 * mult },
           colors.alpha(colors.from_hex('#c9d2d6'), 0.30))
  end

  local function big_text(str, x, y, size, col, a)
    sc:add('text', { str = str, x = x + 1.2 * mult, y = y + 1.2 * mult,
                     size = size, align = 'left' },
           colors.alpha(colors.from_hex('#000000'), 0.6))
    sc:add('text', { str = str, x = x, y = y, size = size, align = 'left' },
           colors.alpha(colors.from_hex(col or '#f6f6f6'), a or 1.0))
  end

  -- =================================================================== AC ==
  if is_ac then
    panel_bg()
    local cap = math.min(14, m.mag_cap)
    local rounds = math.max(0, math.min(cap, m.mag_rounds))
    local ready = rounds > 0 and rounds <= 5
    -- mini magazine column inside the panel (slot 0 = top; drains downward)
    local cx0, cy0, rh = PX + 7 * mult, PY + 3 * mult, (PH - 6 * mult) / cap
    if rounds == 0 then
      sc:add('rect', { x = cx0 - 1 * mult, y = cy0, w = 12 * mult + 2, h = cap * rh },
             colors.alpha(colors.from_hex('#e03030'), 0.25))
    end
    for i = 0, cap - 1 do
      local alive = i < rounds
      local col = alive and colors.alpha(colors.from_hex(ready and '#7fd4ff' or '#d9d9d9'), 0.92)
                     or  colors.alpha(colors.from_hex('#d9d9d9'), 0.14)
      sc:add('rect', { x = cx0, y = cy0 + i * rh, w = 12 * mult, h = rh - 0.7 * mult }, col)
    end
    -- clip line through the 5th slot's middle
    local ly = cy0 + (cap - 5) * rh + (rh - 0.7 * mult) / 2
    local dx = cx0 - 2 * mult
    while dx < cx0 + 15 * mult do
      sc:add('rect', { x = dx, y = ly - 0.4 * mult, w = 2.2 * mult, h = 0.9 * mult },
             colors.alpha(colors.from_hex(ready and '#7fd4ff' or '#c8c8c8'), ready and 0.95 or 0.4))
      dx = dx + 4.4 * mult
    end
    -- live count
    big_text(tostring(rounds), PX + 26 * mult, PY + 6 * mult, 22 * mult)
    -- backpack magazine bars: solid bars + ghost slots, bottom-right first
    local remain = math.max(0, m.pack.remain or 0)
    local total = math.max(m.pack.total or 0, remain, 1)
    if total > 14 then total = 14 end
    local bx0, bw, gap = PX + 58 * mult, 4.6 * mult, 1.8 * mult
    local rows = math.ceil(total / 7)
    for i = 0, total - 1 do
      local c = i % 7
      local r = math.floor(i / 7)
      local bx, by = bx0 + c * (bw + gap), PY + 5 * mult + r * 15 * mult
      if i < remain then
        sc:add('rect', { x = bx, y = by, w = bw, h = 12 * mult },
               colors.alpha(colors.from_hex('#d9d9d9'), 0.92))
        sc:add('rect', { x = bx, y = by, w = bw, h = 1.6 * mult },
               colors.alpha(colors.from_hex('#000000'), 0.35))
      else
        sc:add('rect', { x = bx, y = by + 10.4 * mult, w = bw, h = 1.6 * mult },
               colors.alpha(colors.from_hex('#d9d9d9'), 0.28))
      end
    end
  -- ================================================================ LASER ==
  elseif is_heat then
    panel_bg()
    local frac = math.max(0, math.min(1, m.heat_frac))
    big_text(string.format('%d%%', m.heat_pct or 0), PX + 9 * mult, PY + 6 * mult,
             22 * mult, m.color)
    -- heat bar rides the panel's right edge: fills UP from bottom into the
    -- hazard band at the base (band always drawn faint, lit >=75%)
    local bx, by, bw2, bh = PX + PW - 22 * mult, PY + 4 * mult, 9 * mult, PH - 8 * mult
    sc:add('rect', { x = bx, y = by, w = bw2, h = bh },
           colors.alpha(colors.from_hex('#141410'), 0.8))
    local fill_h = bh * frac
    if fill_h > 0.5 then
      sc:add('rect', { x = bx, y = by + bh - fill_h, w = bw2, h = fill_h },
             colors.alpha(heat_color(colors, frac, m.heat_lock), 0.95))
    end
    -- hazard band = TOP quarter (heat rises INTO danger; the fill carves the
    -- band from below as it approaches full)
    local band_h = bh * 0.25
    local fill_top = by + bh - fill_h
    local limit = math.min(by + band_h, fill_top)
    local danger = frac >= 0.75
    local SW, PER = 2 * mult, 4 * mult
    local sy = by
    while sy < limit - 0.5 do
      local row_h = math.min(1.3 * mult, limit - sy)
      local shift = (sy - by) % PER               -- 45-degree phase walk
      local sx2 = bx - PER + shift
      while sx2 < bx + bw2 do
        local x0 = math.max(bx, sx2)
        local x1 = math.min(bx + bw2, sx2 + SW)
        if x1 > x0 then
          sc:add('rect', { x = x0, y = sy, w = x1 - x0, h = row_h },
                 colors.alpha(colors.from_hex('#e8c020'), danger and 0.92 or 0.32))
        end
        sx2 = sx2 + PER
      end
      sy = sy + 1.3 * mult
    end
    -- heat sinks: brick row in the sub-tray drawer (spare, then ghosts to max)
    tray(sc, colors, PX, PY + PH, PW, mult)
    local n = math.max(0, math.min(8, m.spare or 0))
    local tot = math.max(m.spare_max or 0, n, 1)
    if tot > 8 then tot = 8 end
    for i = 0, tot - 1 do
      sc:add('rect', { x = PX + 4 * mult + i * 11 * mult, y = PY + PH + 7 * mult,
                       w = 9 * mult, h = 4.6 * mult },
             colors.alpha(colors.from_hex('#d9d9d9'), i < n and 0.92 or 0.22))
    end
  -- ============================================================== FUEL gun ==
  elseif is_fuel then
    panel_bg()
    local frac = math.max(0, math.min(1, m.fuel_frac))
    big_text(string.format('%d%%', math.floor(frac * 100 + 0.5)),
             PX + 9 * mult, PY + 6 * mult, 22 * mult,
             frac <= 0.25 and '#e88080' or m.color)
    -- gas-tank dial INTEGRATED into the panel's right half (nothing pokes
    -- outside the station silhouette)
    local ox2, oy2 = off(LAY, 'fuel', mult)
    local dcx, dcy, r = PX + PW - 33 * mult + ox2 * 0.4, PY + PH - 9 * mult + oy2 * 0.4, 13.5 * mult
    local th = 3.2 * mult
    local AE, AF = math.rad(-200), math.rad(20)
    local alert = frac <= 0.25
    local fill_col = alert and '#e03030' or '#e8b84a'
    sc:add('arc', { cx = dcx, cy = dcy, r = r + 1.6 * mult, th = th + 2 * mult,
                    a0 = AE, a1 = AF }, colors.alpha(colors.from_hex('#0b0c0a'), 0.4))
    sc:add('arc', { cx = dcx, cy = dcy, r = r, th = th, a0 = AE, a1 = AF },
           colors.alpha(colors.from_hex('#1e211d'), 0.6))
    local a25 = AE + (AF - AE) * 0.25
    sc:add('arc', { cx = dcx, cy = dcy, r = r - 1, th = th + 2, a0 = a25 - 0.05, a1 = a25 + 0.05 },
           colors.alpha(colors.from_hex('#8899aa'), alert and 0.6 or 0.25))
    local ang = AE + (AF - AE) * frac
    if frac > 0.003 then
      sc:add('arc', { cx = dcx, cy = dcy, r = r, th = th, a0 = AE, a1 = ang },
             colors.alpha(colors.from_hex(fill_col), 0.92))
    end
    local ca, sa = math.cos(ang), math.sin(ang)
    local hub, tipr = 1.4 * mult, r + 3 * mult
    sc:add('tri', { x1 = dcx - sa * hub, y1 = dcy + ca * hub,
                    x2 = dcx + sa * hub, y2 = dcy - ca * hub,
                    x3 = dcx + ca * tipr, y3 = dcy + sa * tipr },
           colors.alpha(colors.from_hex(alert and '#ffd0c0' or '#f2f2f2'), 0.95))
    sc:add('circle', { cx = dcx, cy = dcy, r = 2.4 * mult },
           colors.alpha(colors.from_hex('#2a2e2a'), 0.92))
    sc:add('circle', { cx = dcx, cy = dcy, r = 1 * mult },
           colors.alpha(colors.from_hex('#c8c8c8'), 0.8))
    -- multi-tank: spare tank bricks under the panel
    if m.spare_kind == 'tanks' and (m.spare or 0) > 0 then
      tray(sc, colors, PX, PY + PH, PW, mult)
      for i = 0, math.min(6, m.spare) - 1 do
        sc:add('rect', { x = PX + 4 * mult + i * 11 * mult, y = PY + PH + 7 * mult,
                         w = 9 * mult, h = 4.6 * mult },
               colors.alpha(colors.from_hex('#e8b84a'), 0.9))
      end
    end
  -- ====================================================== plain counter ==
  elseif (m.label or '') ~= '' or m.layout_all then
    local _had_pack = m.pack and true or false
    panel_bg()
    local txt = m.label
    if is_ac then txt = '' end
    -- de-dup: the pip rack already depicts reserve, text = live count only
    if m.spare_kind == 'mags' then txt = tostring(m.count or '') end
    big_text(txt, PX + 9 * mult, PY + 6 * mult, 22 * mult, m.color)
    -- spare-mag pips inside the panel right half
    if m.spare_kind == 'mags' then
      local n = math.max(0, m.spare or 0)
      local total = math.max(ref, n, 1)
      if total <= 12 then
        local cols = math.min(6, total)
        for i = 0, total - 1 do
          local px = PX + 60 * mult + (i % cols) * 5 * mult
          local py = PY + 5 * mult + math.floor(i / cols) * 13 * mult
          if i < n then
            sc:add('rect', { x = px, y = py, w = 3.4 * mult, h = 8.4 * mult },
                   colors.alpha(colors.from_hex('#d4b054'), 0.97))
            sc:add('tri', { x1 = px, y1 = py, x2 = px + 3.4 * mult, y2 = py,
                            x3 = px + 1.7 * mult, y3 = py - 2.4 * mult },
                   colors.alpha(colors.from_hex('#e0cf94'), 0.97))
          else
            sc:add('rect', { x = px, y = py, w = 3.4 * mult, h = 8.4 * mult },
                   colors.alpha(colors.from_hex('#d9d9d9'), 0.2))
          end
        end
      else
        horiz_bar(sc, colors, PX + 60 * mult, PY + 14 * mult, 52 * mult, 5 * mult,
                  n / total, colors.from_hex('#d4b054'))
      end
    end
    -- support guns fed from a backpack (mortar etc): magazine bars in the tray
    if m.pack then
      tray(sc, colors, PX, PY + PH, PW, mult)
      local remain = math.max(0, m.pack.remain or 0)
      local total2 = math.max(m.pack.total or 0, remain, 1)
      if total2 > 11 then total2 = 11 end
      for i = 0, total2 - 1 do
        if i < remain then
          sc:add('rect', { x = PX + 4 * mult + i * 10 * mult, y = PY + PH + 5 * mult,
                           w = 6 * mult, h = 8 * mult },
                 colors.alpha(colors.from_hex('#d9d9d9'), 0.92))
        else
          sc:add('rect', { x = PX + 4 * mult + i * 10 * mult, y = PY + PH + 12.4 * mult,
                           w = 6 * mult, h = 1.6 * mult },
                 colors.alpha(colors.from_hex('#d9d9d9'), 0.28))
        end
      end
    end
  else
    panel_bg()   -- charge-only guns still get the station
  end

  -- charge gauge: strip inside a sub-tray drawer flush to the panel
  if m.charge_pct then
    local ox3, oy3 = off(LAY, 'charge', mult)
    tray(sc, colors, PX, PY + PH, PW, mult)
    local cx0, cy0 = PX + 2 * mult + ox3, PY + PH + 7 * mult + oy3
    sc:add('rect', { x = cx0, y = cy0, w = PW, h = 4 * mult },
           colors.alpha(colors.from_hex('#12212b'), 0.6))
    local f = math.max(0, math.min(1, m.charge_pct))
    if f > 0.003 then
      sc:add('rect', { x = cx0, y = cy0, w = PW * f, h = 4 * mult },
             colors.alpha(colors.from_hex(f >= 1 and '#66e0ff' or '#3fa8d8'), 0.95))
    end
    sc:add('rect', { x = cx0 + PW - 1.2 * mult, y = cy0 - 1 * mult, w = 1.2 * mult, h = 6 * mult },
           colors.alpha(colors.from_hex('#66e0ff'), 0.55))
  end

  -- == dashboard chrome: brackets + hint ==
  if LAY.active then
    local id = LAY.current()
    local b = LAY.box[id]
    if b then
      local ox, oy = off(LAY, id, mult)
      bracket(sc, colors, (b.x + ox / mult) * mult, (b.y + oy / mult) * mult, b.w * mult, b.h * mult)
    end
    -- == control panel: the whole editor lives on screen ==
    local px, py, pw2, ph2 = -150 * mult, 58 * mult, 236 * mult, 64 * mult
    sc:add('rect', { x = px, y = py, w = pw2, h = ph2 },
           colors.alpha(colors.from_hex('#0b0c0a'), 0.82))
    sc:add('rect', { x = px, y = py, w = pw2, h = 1.4 * mult },
           colors.alpha(colors.from_hex('#7fd4ff'), 0.55))
    sc:add('text', { str = 'DBF LAYOUT  ' .. (LAY.names[id] or id) ..
                     string.format('  (%d/%d)', LAY.sel or 1, #LAY.order),
                     x = px + 6 * mult, y = py + 6 * mult, size = 12 * mult, align = 'left' },
           colors.alpha(colors.from_hex('#7fd4ff'), 0.98))
    local ox2, oy2 = LAY.get(id)
    sc:add('text', { str = string.format('x %+d  y %+d', math.floor(ox2), math.floor(oy2)),
                     x = px + 6 * mult, y = py + 22 * mult, size = 10 * mult, align = 'left' },
           colors.alpha(colors.from_hex('#c8d0d4'), 0.85))
    local function keycap(kx, ky, label, hint)
      local kw = #label * 6.2 * mult + 8 * mult
      sc:add('rect', { x = kx, y = ky, w = kw, h = 11 * mult },
             colors.alpha(colors.from_hex('#26292b'), 0.95))
      sc:add('rect', { x = kx, y = ky, w = kw, h = 0.9 * mult },
             colors.alpha(colors.from_hex('#9aa4a8'), 0.35))
      sc:add('text', { str = label, x = kx + kw / 2, y = ky + 3 * mult, size = 9 * mult, align = 'center' },
             colors.alpha(colors.from_hex('#e8e8e8'), 0.95))
      sc:add('text', { str = hint, x = kx + kw / 2, y = ky + 15 * mult, size = 8 * mult, align = 'center' },
             colors.alpha(colors.from_hex('#8899aa'), 0.85))
      return kx + kw + 6 * mult
    end
    local kx = px + 6 * mult
    kx = keycap(kx, py + 32 * mult, 'TAB', 'next')
    kx = keycap(kx, py + 32 * mult, 'WASD+ARROWS', 'move')
    kx = keycap(kx, py + 32 * mult, 'ENTER', 'save')
    kx = keycap(kx, py + 32 * mult, 'ESC', 'exit+save')
    -- element strip: current highlighted
    for li = 1, #LAY.order do
      local lx = px + 6 * mult + (li - 1) * 33 * mult
      if li == LAY.sel then
        sc:add('rect', { x = lx, y = py + 54 * mult, w = 31 * mult, h = 6 * mult },
               colors.alpha(colors.from_hex('#7fd4ff'), 0.28))
      end
      sc:add('text', { str = (LAY.names[LAY.order[li]] or '?'):sub(1, 5),
                       x = lx + 1 * mult, y = py + 55 * mult, size = 5.5 * mult, align = 'left' },
             colors.alpha(colors.from_hex(li == LAY.sel and '#7fd4ff' or '#8899aa'), 0.9))
    end
  end
end

return M
