-- hd2ui/scene.lua -- Pure-Lua composition of widgets into a display list.
-- A scene holds an ordered list of elements. Each element has:
--   kind    : 'rect' | 'hline' | 'vline' | 'arc' | 'ring' | 'circle' | 'diamond' | 'text' | 'quad' | 'tri'
--   params  : kind-specific numbers (x, y, w, h, r, a0, a1, ...)
--   color   : RGBA tuple (see core/colors)
--   anchor  : optional override anchor (see core/layout)
--   scale   : optional per-element scale multiplier (default 1.0)
-- The scene renders into a display list in reference space (1080p px).
-- The backend scales that list to the live viewport before drawing.
local geometry = require('hd2ui.core.geometry')
local layout   = require('hd2ui.core.layout')
local colors   = require('hd2ui.core.colors')
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
