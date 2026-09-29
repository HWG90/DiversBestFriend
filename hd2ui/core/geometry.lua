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
