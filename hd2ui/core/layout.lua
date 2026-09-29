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
