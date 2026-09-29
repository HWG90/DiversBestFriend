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
