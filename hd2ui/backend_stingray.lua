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
