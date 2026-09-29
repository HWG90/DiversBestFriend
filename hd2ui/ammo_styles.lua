-- hd2ui/ammo_styles.lua -- Ammo HUD style implementations for the DBF Ammo
-- addon. CONSUMES the HD2UI framework (passed in as `api` = the table from
-- require('mods/dbf/hd2ui')); nothing here edits the framework.
--
-- Model contract (same as demo_counter): { count, label, capacity }.
-- A style returns an object:
--   frame(model, backend, vp_w, vp_h)  -- build display list + emit
--   style                              -- name
--   provisional                        -- true when the intended 3D binding
--                                        -- fell back to a screen anchor
--
-- 'world' (The Division style: text floating beside the gun) needs a
-- world->screen projector: a function (x, y, z) -> sx, sy or nil. The game's
-- camera matrix lives in memory we can read, so a projector is implementable
-- (derive the view matrix chain + use the weapon transform), but until it is
-- wired in the style falls back to the gunside screen anchor and flags itself
-- provisional instead of failing. Pass api-style opts.projector when available.
--
-- Lua 5.1.

local M = {}
local BARS = require('hd2ui.ammo_bars')

local function base_setup(api)
  return api.scene, api.layout, api.colors, api.geometry
end

------------------------------------------------------------------------------
-- crosshair: the framework demo counter right of the reticle (verified path)
------------------------------------------------------------------------------
local function style_crosshair(api, cfg)
  local counter = api.demo_counter.new({
    side = cfg.side or 'right',
    offset_x = cfg.offset_x or 140,
    offset_y = cfg.offset_y or 0,
    scale = cfg.scale or 1.0,
    opacity = cfg.opacity or 0.9,
    color = cfg.color or '#f2f2f2',
  })
  local scene, layout, colors = base_setup(api)
  local sc = scene.new()
  local gfx_reported = false
  return {
    style = 'crosshair',
    frame = function(model, backend, w, h)
      if cfg.display == 'graphical' then
        sc:clear()
        BARS.draw(sc, model, (cfg.scale or 1.0), colors)
        local s = layout.scale_factor(h, 1.0)
        local ox, oy = layout.place(w, h, 990, 540, s)   -- right of the reticle
        local dl = {}
        sc:render(dl, ox, oy, s)
        if cfg.log and not gfx_reported then
          gfx_reported = true
          local nr, nt = 0, 0
          for _, el in ipairs(sc.elements) do
            if el.kind == 'rect' then nr = nr + 1 elseif el.kind == 'text' then nt = nt + 1 end
          end
          cfg.log(string.format('GFX crosshair prims=%d rects=%d texts=%d label=%s spare=%s kind=%s',
            sc:count(), nr, nt, tostring(model.label),
            tostring(model.spare), tostring(model.spare_kind)))
        end
        backend.emit(dl, cfg.opacity or 0.9)
        return
      end
      counter.frame(model, backend, w, h)
    end,
  }
end

------------------------------------------------------------------------------
-- gunside: bigger readout low-right, where the first-person weapon sits.
-- (First-person weapon render is camera-locked, so a fixed anchor here reads
-- as "next to the gun"; the world style refines this with real projection.)
------------------------------------------------------------------------------
local function style_gunside(api, cfg)
  local scene, layout, colors = base_setup(api)
  local sc = scene.new()
  local sc_reported = false
  local col = (type(cfg.color) == 'string') and colors.from_hex(cfg.color) or (cfg.color or colors.from_hex('#f2f2f2'))
  local size_mult = (cfg.scale or 1.0)
  -- Reference anchor (1080p): right-of-center, below the midline.
  local ref_x, ref_y = cfg.ref_x or 1285, cfg.ref_y or 705

  local function build(model)
    sc:clear()
    if cfg.display == 'graphical' then
      BARS.draw(sc, model, size_mult, colors)
      if cfg.log and not sc_reported then
        sc_reported = true
        local nr, nt = 0, 0
        for _, el in ipairs(sc.elements) do
          if el.kind == 'rect' then nr = nr + 1 elseif el.kind == 'text' then nt = nt + 1 end
        end
        cfg.log(string.format('GFX gunside prims=%d rects=%d texts=%d label=%s spare=%s kind=%s',
          sc:count(), nr, nt, tostring(model.label),
          tostring(model.spare), tostring(model.spare_kind)))
      end
      return
    end
    -- soft backing plate + the two numbers
    sc:add('rect', { x = -46, y = -34, w = 92, h = 46 }, colors.alpha(col, 0.16))
    sc:add('text', { str = model.label, x = 0, y = -6, size = 26 * size_mult, align = 'center' },
           colors.alpha(col, 0.95))
    sc:add('text', { str = 'mag / reserve', x = 0, y = -26, size = 10 * size_mult, align = 'center' },
           colors.alpha(col, 0.55))
  end

  return {
    style = 'gunside',
    frame = function(model, backend, w, h)
      build(model)
      local s = layout.scale_factor(h, 1.0)
      local ox, oy = layout.place(w, h, ref_x, ref_y, s)
      local dl = {}
      sc:render(dl, ox, oy, s)
      backend.emit(dl, cfg.opacity or 0.9)
    end,
  }
end

------------------------------------------------------------------------------
-- world: text bound to a 3D point beside the weapon, projected to screen each
-- frame. opts.projector(x,y,z) -> sx, sy (screen px) or nil when unavailable.
-- No projector (yet): falls back to gunside geometry, provisional = true.
------------------------------------------------------------------------------
local function style_world(api, cfg)
  local scene, layout, colors = base_setup(api)
  local sc = scene.new()
  local col = (type(cfg.color) == 'string') and colors.from_hex(cfg.color) or (cfg.color or colors.from_hex('#f2f2f2'))
  local projector = cfg.projector   -- wired by the entry when the camera chain resolves
  local size_mult = (cfg.scale or 1.0)
  -- Anchor point in WEAPON-LOCAL space (meters right/up/forward of the ammo
  -- component's entity origin). Only meaningful once projection exists.
  local wx, wy, wz = cfg.world_x or 0.18, cfg.world_y or -0.06, cfg.world_z or 0.32
  local fallback = style_gunside(api, cfg)
  local last_projected = false

  local function build(model)
    sc:clear()
    sc:add('text', { str = model.label, x = 0, y = 0, size = 24 * size_mult, align = 'center' },
           colors.alpha(col, 0.95))
    sc:add('text', { str = 'mag / reserve', x = 0, y = -20, size = 9 * size_mult, align = 'center' },
           colors.alpha(col, 0.5))
  end

  local obj
  obj = {
    style = 'world',
    provisional = true,
    frame = function(model, backend, w, h)
      local sx, sy = nil, nil
      if projector then
        local ok, rx, ry = pcall(projector, wx, wy, wz)
        if ok and rx then sx, sy = rx, ry end
      end
      if not sx then
        if obj.provisional and not last_projected then fallback.frame(model, backend, w, h) end
        obj.provisional = true
        return
      end
      -- Real projection: build the scene at the projected point.
      obj.provisional = false
      last_projected = true
      build(model)
      local s = layout.scale_factor(h, 1.0)
      local dl = {}
      sc:render(dl, sx, sy, s)
      backend.emit(dl, cfg.opacity or 0.9)
    end,
  }
  return obj
end

M.styles = { crosshair = style_crosshair, gunside = style_gunside, world = style_world }

function M.new(name, api, cfg)
  cfg.display = cfg.display or 'text'
  local f = M.styles[name] or M.styles.crosshair
  return f(api, cfg or {})
end

return M
