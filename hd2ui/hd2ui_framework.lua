-- HD2-Addon: mods/dbf/hd2ui
-- HD2UI framework r2; assembled by hd2ui/build_framework.py; do not edit.
local __hd2ui_modules, __hd2ui_loaded = {}, {}
local __hd2ui_real = require
local function __hd2ui_require(name)
  local m = __hd2ui_loaded[name]
  if m ~= nil then return m end
  local f = __hd2ui_modules[name]
  if not f then
    -- Not ours: defer to the game's require (Arsenal/BSL preset lua resources
    -- arrive as mods/<mod>/preset_* lookups the manager deployed).
    local ok, v = pcall(__hd2ui_real, name)
    if ok then
      __hd2ui_loaded[name] = v
      return v
    end
    error('hd2ui: missing module ' .. tostring(name))
  end
  m = f()
  if m == nil then m = true end
  __hd2ui_loaded[name] = m
  return m
end
__hd2ui_modules['hd2ui.core.colors'] = function()
-- hd2ui/core/colors.lua -- Pure-Lua color helpers. No game, no FFI.
-- Color is a 4-number RGBA tuple with channels 0..255.
local function clamp8(v)
  v = math.floor(v + 0.5)
  if v < 0 then v = 0 elseif v > 255 then v = 255 end
  return v
end
local function rgba(r, g, b, a)
  r, g, b = clamp8(r), clamp8(g), clamp8(b)
  if a == nil then a = 255 else a = clamp8(a) end
  return { r, g, b, a }
end
local function from_hex(hex, a)
  hex = hex:gsub('^#', '')
  local r, g, b
  if #hex == 6 then
    r = tonumber(hex:sub(1, 2), 16)
    g = tonumber(hex:sub(3, 4), 16)
    b = tonumber(hex:sub(5, 6), 16)
  elseif #hex == 3 then
    r = tonumber(hex:sub(1, 1) .. hex:sub(1, 1), 16)
    g = tonumber(hex:sub(2, 2) .. hex:sub(2, 2), 16)
    b = tonumber(hex:sub(3, 3) .. hex:sub(3, 3), 16)
  else
    return rgba(255, 255, 255)
  end
  return rgba(r, g, b, a)
end
local function mix(c1, c2, t)
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  local r = c1[1] + (c2[1] - c1[1]) * t + 0.5
  local g = c1[2] + (c2[2] - c1[2]) * t + 0.5
  local b = c1[3] + (c2[3] - c1[3]) * t + 0.5
  local a = c1[4] + (c2[4] - c1[4]) * t + 0.5
  return { math.floor(r), math.floor(g), math.floor(b), math.floor(a) }
end
local function alpha(c, f)
  if f < 0 then f = 0 elseif f > 1 then f = 1 end
  return { c[1], c[2], c[3], math.floor((c[4] * f + 0.5)) }
end
local function lighten(c, t)
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  local r = c[1] + (255 - c[1]) * t + 0.5
  local g = c[2] + (255 - c[2]) * t + 0.5
  local b = c[3] + (255 - c[3]) * t + 0.5
  return { math.floor(r), math.floor(g), math.floor(b), c[4] }
end
local function darken(c, t)
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  local r = c[1] * (1 - t) + 0.5
  local g = c[2] * (1 - t) + 0.5
  local b = c[3] * (1 - t) + 0.5
  return { math.floor(r), math.floor(g), math.floor(b), c[4] }
end
return { rgba = rgba, from_hex = from_hex, mix = mix, alpha = alpha, lighten = lighten, darken = darken }

end
__hd2ui_modules['hd2ui.core.geometry'] = function()
-- hd2ui/core/geometry.lua -- Pure-Lua 2-D drawing primitives.
-- Each primitive emits into a display list (dl) as:
--   { tri = {x1,y1,x2,y2,x3,y3,color} }  or  { txt = {str,x,y,size,color,align} }
-- No game, no FFI. The backend turns this into Gui.triangle / Gui.text calls.
local function push(dl, rec) dl[#dl + 1] = rec end
local function tri(dl, x1, y1, x2, y2, x3, y3, color) push(dl, { tri = {x1, y1, x2, y2, x3, y3, color} }) end
local function quad(dl, ax, ay, bx, by, cx, cy, dx, dy, color)
  tri(dl, ax, ay, bx, by, cx, cy, color)
  tri(dl, ax, ay, cx, cy, dx, dy, color)
end
local function rect(dl, x, y, w, h, color)
  if w <= 0 or h <= 0 then return end
  quad(dl, x, y, x + w, y, x + w, y + h, x, y + h, color)
end
local function hline(dl, x, y, w, th, color, cap)
  if w <= 0 then return end
  local e = cap and th / 2 or 0
  rect(dl, x - e, y - th / 2, w + e * 2, th, color)
end
local function vline(dl, x, y, h, th, color, cap)
  if h <= 0 then return end
  local e = cap and th / 2 or 0
  rect(dl, x - th / 2, y - e, th, h + e * 2, color)
end
-- A filled band between angles a0 and a1 (radians, CCW), inner radius r, thickness th.
local function arc(dl, cx, cy, r, th, a0, a1, color, step)
  local span = a1 - a0
  if span == 0 then return end
  local n = math.floor((math.abs(span) / (step or 0.08) + 0.5))
  if n < 1 then n = 1 end
  local ro = r + th
  for i = 0, n - 1 do
    local t0 = a0 + span * i / n
    local t1 = a0 + span * (i + 1) / n
    local c0, s0 = math.cos(t0), math.sin(t0)
    local c1, s1 = math.cos(t1), math.sin(t1)
    quad(dl, cx + c0 * r, cy + s0 * r, cx + c0 * ro, cy + s0 * ro, cx + c1 * ro, cy + s1 * ro, cx + c1 * r, cy + s1 * r, color)
  end
end
-- A filled circle approximated by a fan of quads around the center.
local function circle(dl, cx, cy, r, color, step)
  local n = math.floor((math.abs(r) / (step or 0.05) + 0.5))
  if n < 8 then n = 8 end
  local two_pi = 2 * math.pi
  for i = 0, n - 1 do
    local a0 = two_pi * i / n
    local a1 = two_pi * (i + 1) / n
    local c0, s0 = math.cos(a0), math.sin(a0)
    local c1, s1 = math.cos(a1), math.sin(a1)
    quad(dl, cx, cy, cx + c0 * r, cy + s0 * r, cx + c1 * r, cy + s1 * r, cx, cy, color)
  end
end
-- A ring (annulus) band between inner radius r0 and outer radius r1, from a0 to a1.
local function ring(dl, cx, cy, r0, r1, a0, a1, color, step)
  if r1 <= r0 then return end
  arc(dl, cx, cy, r0, r1 - r0, a0, a1, color, step)
end
local function diamond(dl, cx, cy, r, color)
  quad(dl, cx, cy - r, cx + r, cy, cx, cy, cx - r, cy, color)
  quad(dl, cx, cy, cx + r, cy, cx, cy + r, cx - r, cy, color)
end
local function text(dl, str, x, y, size, color, align)
  local w = #str * size * 0.5
  if align == 'right' then x = x - w elseif align == 'center' then x = x - w / 2 end
  push(dl, { txt = { str, x, y, size, color, align } })
  return w
end
return { tri = tri, quad = quad, rect = rect, hline = hline, vline = vline, arc = arc, circle = circle, ring = ring, diamond = diamond, text = text }

end
__hd2ui_modules['hd2ui.core.layout'] = function()
-- hd2ui/core/layout.lua -- Pure-Lua screen layout helpers.
-- Reference-space model: design at 1920x1080, scale to the live resolution.
local function clamp(v, lo, hi) if v < lo then v = lo elseif v > hi then v = hi end return v end
-- Uniform scale from a 1080p reference to a live viewport, with an optional user scale (1.0 = 100%).
local function scale_factor(viewport_h, user_scale)
  user_scale = user_scale or 1.0
  local base = (viewport_h or 1080) / 1080
  return base * clamp(user_scale, 0.05, 16)
end
-- Place a point in reference space (1080p px) at screen pixels.
local function place(vp_w, vp_h, ref_x, ref_y, s)
  local sx = vp_w / 2 + (ref_x - 960) * s
  local sy = vp_h / 2 + (ref_y - 540) * s
  return sx, sy
end
-- Anchor a point in reference space to an edge/corner of a 1080p frame.
-- anchor is one of: center, left, right, top, bottom, tl, tr, bl, br.
-- Returns {x, y}.
local function anchor(ref_w, ref_h, ax, ay, anchor)
  anchor = anchor or 'center'
  local x = ref_w / 2
  local y = ref_h / 2
  if anchor == 'left' then x = 0 elseif anchor == 'right' then x = ref_w
  elseif anchor == 'top' then y = 0 elseif anchor == 'bottom' then y = ref_h
  elseif anchor == 'tl' then x = 0; y = 0
  elseif anchor == 'tr' then x = ref_w; y = 0
  elseif anchor == 'bl' then x = 0; y = ref_h
  elseif anchor == 'br' then x = ref_w; y = ref_h
  end
  return { x + ax, y + ay }
end
-- A simple 2-D point helper.
local function point(x, y) return { x = x, y = y } end
return { clamp = clamp, scale_factor = scale_factor, place = place, anchor = anchor, point = point }

end
__hd2ui_modules['hd2ui.scene'] = function()
-- hd2ui/scene.lua -- Pure-Lua composition of widgets into a display list.
-- A scene holds an ordered list of elements. Each element has:
--   kind    : 'rect' | 'hline' | 'vline' | 'arc' | 'ring' | 'circle' | 'diamond' | 'text' | 'quad' | 'tri'
--   params  : kind-specific numbers (x, y, w, h, r, a0, a1, ...)
--   color   : RGBA tuple (see core/colors)
--   anchor  : optional override anchor (see core/layout)
--   scale   : optional per-element scale multiplier (default 1.0)
-- The scene renders into a display list in reference space (1080p px).
-- The backend scales that list to the live viewport before drawing.
local geometry = __hd2ui_require('hd2ui.core.geometry')
local layout   = __hd2ui_require('hd2ui.core.layout')
local colors   = __hd2ui_require('hd2ui.core.colors')
local function new()
  local self = setmetatable({}, { __index = { _is_scene = true } })
  self.elements = {}
  function self:add(kind, params, color)
    local el = { kind = kind, params = params, color = color or colors.rgba(255, 255, 255) }
    self.elements[#self.elements + 1] = el
    return el
  end
  function self:clear() self.elements = {} end
  function self:count() return #self.elements end
  -- Render all elements into the display list `dl` at the given screen coords.
  -- cx, cy are the scene's origin in screen pixels. s is the total scale.
  function self:render(dl, cx, cy, s)
    for i = 1, #self.elements do
      local el = self.elements[i]
      local p = el.params
      local k = el.kind
      if k == 'rect' then
        geometry.rect(dl, cx + p.x * s, cy + p.y * s, p.w * s, p.h * s, el.color)
      elseif k == 'hline' then
        geometry.hline(dl, cx + p.x * s, cy + p.y * s, p.w * s, p.th * s, el.color, p.cap)
      elseif k == 'vline' then
        geometry.vline(dl, cx + p.x * s, cy + p.y * s, p.h * s, p.th * s, el.color, p.cap)
      elseif k == 'arc' then
        geometry.arc(dl, cx + p.cx * s, cy + p.cy * s, p.r * s, p.th * s, p.a0, p.a1, el.color, p.step)
      elseif k == 'ring' then
        geometry.ring(dl, cx + p.cx * s, cy + p.cy * s, p.r0 * s, p.r1 * s, p.a0, p.a1, el.color, p.step)
      elseif k == 'circle' then
        geometry.circle(dl, cx + p.cx * s, cy + p.cy * s, p.r * s, el.color, p.step)
      elseif k == 'diamond' then
        geometry.diamond(dl, cx + p.cx * s, cy + p.cy * s, p.r * s, el.color)
      elseif k == 'tri' then
        geometry.tri(dl, cx + p.x1 * s, cy + p.y1 * s, cx + p.x2 * s, cy + p.y2 * s, cx + p.x3 * s, cy + p.y3 * s, el.color)
      elseif k == 'quad' then
        geometry.quad(dl, cx + p.ax * s, cy + p.ay * s, cx + p.bx * s, cy + p.by * s,
                      cx + p.cx * s, cy + p.cy * s, cx + p.dx * s, cy + p.dy * s, el.color)
      elseif k == 'text' then
        local w = geometry.text(dl, p.str, cx + p.x * s, cy + p.y * s, p.size * s, el.color, p.align)
      else
        error('scene: unknown kind ' .. tostring(k))
      end
    end
  end
  return self
end
return { new = new }

end
__hd2ui_modules['hd2ui.backend_stingray'] = function()
-- hd2ui/backend_stingray.lua -- In-game backend on the stingray 2-D screen GUI.
-- Uses the game's own engine object (exposed by Bingus Shared Loader v15+).
--   sr.World.create_screen_gui(world, 'scale', 1, 1) -> gui
--   sr.Gui.triangle(gui, V3, V3, V3, n, Color, material, uv, uv, uv) -> id
--   sr.Gui.text(gui, str, font, size, font, V2, Color) -> id
--   sr.Gui.resolution() -> w, h
--   sr.Application.can_get('material', name) -> bool
--   sr.Application.worlds / main_world
--   sr.World.destroy_gui(world, gui)
--   sr.Vector3, sr.Vector2, sr.Color
--
-- Conventions confirmed against two shipping mods (ReticleAmmoHUD, DRIVER HUD):
--   * sr.Color takes (alpha, r, g, b) -- alpha FIRST.
--   * Screen GUI y axis points UP (y=0 is the bottom edge). The pure core is
--     y-down (1080p reference, top=0), so this backend flips y = vp_h - y.
--   * Triangles need a solid material with a 'diffuse_map' texture shipped in
--     the addon; without it we fall back to text-only. Text needs no material.
--   * Layer 4 for the main pass; ids are retained and destroyed every frame.
--
-- The backend is thin: it takes a display list (triangles + texts) and a
-- (cx, cy, scale) and calls into stingray. All layout math is in the pure core.
--
-- This file is NOT headlessly testable (it touches the game). The pure core
-- (colors, geometry, layout, scene) is fully tested without it.
local function new(opts)
  opts = opts or {}
  local sr = rawget(_G, 'stingray')
  if type(sr) ~= 'table' then
    error('hd2ui backend_stingray: stingray not available (need Bingus Shared Loader v15+)')
  end
  local Gui, World, App, V3, V2, Color = sr.Gui, sr.World, sr.Application, sr.Vector3, sr.Vector2, sr.Color
  local MATERIAL = opts.material or 'mods/dbf/hd2ui/solid'
  local FONT = opts.font or 'core/performance_hud/debug'
  local LAYER = opts.layer or 4
  local state = { gui = nil, world = nil, ids = {}, mode = nil, font_ok = nil, vp_h = 0, gen = 0 }
  local function argb(c, a)
    -- core colors are {r,g,b,a}; stingray wants (a, r, g, b)
    local alpha = c[4]
    if a then alpha = math.floor(c[4] * a + 0.5) end
    return Color(alpha, c[1], c[2], c[3])
  end
  local function log(msg)
    if opts.log then opts.log(msg) end
  end
  local function clear()
    if state.gui then
      for i = #state.ids, 1, -1 do
        local e = state.ids[i]
        local ok = pcall(Gui[e[1]], state.gui, e[2])
        if not ok then log('destroy_' .. e[1] .. ' failed') end
      end
    end
    state.ids = {}
  end
  local function release(worlds)
    if state.gui then
      local alive = false
      for _, w in pairs(worlds or {}) do if w == state.world then alive = true break end end
      if alive then
        clear()
        local ok = pcall(World.destroy_gui, state.world, state.gui)
        if not ok then log('destroy_gui failed') end
      end
    end
    state.gui, state.world, state.ids, state.mode, state.font_ok = nil, nil, {}, nil, nil
  end
  local function ensure()
    local ok, worlds = pcall(App.worlds)
    if not ok or type(worlds) ~= 'table' then log('worlds failed: ' .. tostring(worlds)) return false end
    if state.gui then
      -- The UI world is torn down between missions; recreate when it goes away.
      for _, w in pairs(worlds) do if w == state.world then return true end end
      log('gui world gone; recreating')
      release(worlds)
    end
    local okm, main = pcall(App.main_world)
    local pick
    for _, w in pairs(worlds) do if (not okm or w ~= main) then pick = w break end end
    pick = pick or (okm and main or nil)
    if not pick then log('no world') return false end
    local okg, gui = pcall(World.create_screen_gui, pick, 'scale', 1, 1)
    if not okg or not gui then log('create_screen_gui failed: ' .. tostring(gui)) return false end
    state.gui, state.world = gui, pick
    state.gen = state.gen + 1  -- retained elements did not survive; callers must redraw
    -- Detect geometry mode: if a solid material is available, draw triangles;
    -- otherwise fall back to text-only (still works, just no vector shapes).
    if state.mode == nil then
      local okc, has = pcall(App.can_get, 'material', MATERIAL)
      state.mode = (okc and has) and 'geometry' or 'text'
      log('gui ready mode=' .. state.mode)
    end
    return true
  end
  local function emit(dl, a)
    -- a = global alpha 0..1 (optional). Display list holds final screen coords
    -- in the core's y-down space; flip to stingray's y-up here.
    local H = state.vp_h
    if state.mode == 'geometry' then
      local uv = V2(0.5, 0.5)
      local ntri, nok, nnil = 0, 0, 0
      for i = 1, #dl do
        local rec = dl[i]
        if rec.tri then
          ntri = ntri + 1
          local t = rec.tri
          local okk, id = pcall(Gui.triangle, state.gui,
            V3(t[1], 0, H - t[2]), V3(t[3], 0, H - t[4]), V3(t[5], 0, H - t[6]),
            LAYER, argb(t[7], a), MATERIAL, uv, uv, uv)
          if okk and id ~= nil then
            nok = nok + 1
            state.ids[#state.ids + 1] = { 'destroy_triangle', id }
          else
            nnil = nnil + 1
            if not okk and state.tri_err_logged ~= 3 then
              state.tri_err_logged = (state.tri_err_logged or 0) + 1
              log('TRI call failed: ' .. tostring(id))
            end
          end
        end
      end
      if ntri > 0 and state.tri_reported ~= true then
        state.tri_reported = true
        local okc2, has2 = pcall(App.can_get, 'material', MATERIAL)
        log('TRI recheck: can_get(material)=' .. tostring(okc2 and has2))
        log(string.format('TRI report: sent=%d ok=%d nil=%d layer=%d material=%s',
          ntri, nok, nnil, LAYER, tostring(MATERIAL)))
      end
    end
    -- Texts are always available (Gui.text does not need a material).
    for i = 1, #dl do
      local rec = dl[i]
      if rec.txt then
        local t = rec.txt
        local id = Gui.text(state.gui, t[1], FONT, t[4], FONT,
          V2(t[2], H - t[3]), argb(t[5], a))
        if id ~= nil then state.ids[#state.ids + 1] = { 'destroy_text', id } end
      end
    end
  end
  local function resolution()
    local ok, w, h = pcall(Gui.resolution)
    if ok and type(w) == 'number' and type(h) == 'number' and w > 0 and h > 0 then
      state.vp_h = h
      return w, h
    end
    return nil, nil
  end
  local function cursor_visible()
    -- Both reference mods hide their HUD while the OS cursor is shown (menus).
    local W = sr.Window
    if not W or type(W.show_cursor) ~= 'function' then return false end
    local ok, v = pcall(W.show_cursor)
    return ok and v == true
  end
  return {
    ensure = ensure,
    clear = clear,
    release = release,
    emit = emit,
    resolution = resolution,
    cursor_visible = cursor_visible,
    generation = function() return state.gen end,
    mode = function() return state.mode end,
  }
end
return { new = new }

end
__hd2ui_modules['hd2ui.demo_counter'] = function()
-- hd2ui/demo_counter.lua -- Demo: a configurable ammo counter off to the left/right
-- of center, built on the hd2ui core (pure layout) + stingray backend (drawing).
--
-- Configurable:
--   side       : 'left' | 'right' (default 'right')
--   offset_x   : additional horizontal nudge in 1080p px (default 120)
--   offset_y   : additional vertical nudge in 1080p px (default 0)
--   scale      : user scale 0.05..16 (default 1.0)
--   opacity    : 0..1 (default 1.0)
--   color      : hex string or RGBA (default '#f2f2f2')
--
-- Data source is injected as `source` (a function returning the ammo model),
-- so this file stays testable headless with a fake source. In-game, wire it
-- to ReticleAmmoHUD's reader or your own.
local scene  = __hd2ui_require('hd2ui.scene')
local layout = __hd2ui_require('hd2ui.core.layout')
local colors = __hd2ui_require('hd2ui.core.colors')
local function new(opts)
  opts = opts or {}
  local cfg = {
    side     = opts.side     or 'right',
    offset_x = opts.offset_x or 120,
    offset_y = opts.offset_y or 0,
    scale    = opts.scale    or 1.0,
    opacity  = opts.opacity  or 1.0,
    color    = opts.color or '#f2f2f2',
  }
  local col = (type(cfg.color) == 'string') and colors.from_hex(cfg.color) or cfg.color
  local sc = scene.new()
  -- A simple counter: a small rect backing + a number.
  -- In 1080p reference space, the counter sits at (960 +/- offset, 540 + offset_y).
  -- The scene's render() places elements relative to a (cx, cy) origin that the
  -- caller computes from the live viewport. So we define elements at local (0,0).
  local backing = { x = -14, y = -22, w = 28, h = 30 }
  local label   = { x = 0, y = 0, size = 22, align = 'center' }
  local pip     = { x = -10, y = 24, w = 20, h = 4 }
  -- Build the scene once; we re-render it each frame with fresh values.
  local function build(model)
    sc:clear()
    sc:add('rect', backing, colors.alpha(col, 0.25))
    sc:add('rect', pip, col)
    local n = model and model.count or 0
    local t = model and model.label or tostring(n)
    sc:add('text', { str = t, x = label.x, y = label.y, size = label.size, align = label.align }, col)
  end
  return {
    cfg = cfg,
    scene = sc,
    build = build,
    -- Compute the scene origin in screen px for the live viewport.
    origin = function(vp_w, vp_h)
      local s = layout.scale_factor(vp_h, cfg.scale)
      local sign = (cfg.side == 'left') and -1 or 1
      local ref_x = 960 + sign * cfg.offset_x
      local ref_y = 540 + cfg.offset_y
      local ox, oy = layout.place(vp_w, vp_h, ref_x, ref_y, s)
      return ox, oy, s
    end,
    -- Render one frame: builds from the model, then emits to the backend.
    frame = function(model, backend, vp_w, vp_h)
      build(model)
      local dl = {}
      local s = layout.scale_factor(vp_h, cfg.scale)
      local sign = (cfg.side == 'left') and -1 or 1
      local ox, oy = layout.place(vp_w, vp_h, 960 + sign * cfg.offset_x, 540 + cfg.offset_y, s)
      sc:render(dl, ox, oy, s)
      backend.emit(dl, cfg.opacity)
    end,
  }
end
return { new = new }

end
local api = { ['colors'] = __hd2ui_require('hd2ui.core.colors'), ['geometry'] = __hd2ui_require('hd2ui.core.geometry'), ['layout'] = __hd2ui_require('hd2ui.core.layout'), ['scene'] = __hd2ui_require('hd2ui.scene'), ['backend_stingray'] = __hd2ui_require('hd2ui.backend_stingray'), ['demo_counter'] = __hd2ui_require('hd2ui.demo_counter') }
api.version = 'r2'
rawset(_G, '__DBF_HD2UI', api)
return api
