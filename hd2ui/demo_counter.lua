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
local scene  = require('hd2ui.scene')
local layout = require('hd2ui.core.layout')
local colors = require('hd2ui.core.colors')
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
