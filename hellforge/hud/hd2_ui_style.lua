-- The Helldivers mod UI for engine-Gui (Lua) mods: HD2-UI-Style/DESIGN.md says how it should look; this draws it.
-- Copy this file into your mod. Plain Lua 5.1: no FFI, no globals, so it runs on Boot Mod Loader, Chef, LLL and MDL3.
--
--   local style = <load this file>
--   local ui = style.new{Gui = Gui, Vector2 = Vector2, Vector3 = Vector3, Color = Color, scale = height / 1080}
--   ui.rounded_rect(gui, x, y, w, h, style.tokens.style.window_rounding, layer, ui.color("panel"))
--
-- Coordinates are the engine Gui's (screen pixels, y up from the bottom); x, y is a shape's bottom-left corner.
-- Sizes in M.tokens.style are 1080p pixels: the functions below multiply radii and widths by scale themselves.
-- env.measure(gui, text, font, size) -> width, when given, sizes key caps and centres button labels exactly.
local M = {}

-- BEGIN GENERATED TOKENS (tools/gen.py writes this block from tokens.json; do not edit by hand)
M.tokens = {
  colors = {
    danger = {224, 72, 72, 255},
    field = {38, 36, 32, 255},
    field_active = {57, 54, 49, 255},
    field_hover = {47, 44, 40, 255},
    hud_plate = {27, 26, 24, 204},
    hud_shadow = {0, 0, 0, 160},
    line = {57, 54, 49, 255},
    line_strong = {82, 78, 71, 255},
    on_yellow = {20, 20, 20, 255},
    panel = {27, 26, 24, 240},
    panel_alt = {21, 20, 18, 245},
    select = {255, 232, 0, 36},
    select_hover = {255, 232, 0, 56},
    success = {96, 192, 96, 255},
    text = {233, 231, 227, 255},
    text_dim = {146, 141, 133, 255},
    text_off = {94, 90, 84, 255},
    yellow = {255, 232, 0, 255},
    yellow_hover = {255, 240, 77, 255},
    yellow_press = {230, 208, 0, 255},
  },
  style = {
    bold_px = 1,
    check_rounding = 4,
    child_rounding = 8,
    frame_border = 0,
    frame_padding = {10, 6},
    frame_rounding = 6,
    grab_min_size = 12,
    grab_rounding = 12,
    hud_plate_rounding = 6,
    item_inner_spacing = {8, 6},
    item_spacing = {10, 8},
    key_cap_rounding = 4,
    letter_space_px = 1,
    lua_bold_offset = 0.65,
    popup_border = 1,
    popup_rounding = 8,
    scrollbar_rounding = 12,
    scrollbar_size = 8,
    secondary_border = 1,
    selected_bar = 3,
    tab_rounding = 6,
    tab_underline = 2,
    window_border = 1,
    window_padding = {14, 12},
    window_rounding = 10,
  },
}
-- END GENERATED TOKENS

local SEGMENTS = 4 -- triangles per rounded corner

-- Shapes as data, for mods that keep their own retained Gui primitives (War Journalist's view.lua). Each shape is
-- {kind = "rect", x =, y =, w =, h =} or {kind = "triangle", points = {x1, y1, x2, y2, x3, y3}}, in screen pixels
-- with y up, like everything else here. Draw a rect as Gui.rect(gui, Vector3(x, y, layer), Vector2(w, h), color) and
-- a triangle as Gui.triangle(gui, Vector3(x1, 0, y1), Vector3(x2, 0, y2), Vector3(x3, 0, y3), layer, color).
-- r and t are screen pixels (already scaled). segments is triangles per corner (default 4); 0 gives square corners.
-- The shapes never overlap, so a translucent colour stays even.

-- corners in drawing order: the angle each quarter turn starts at, then whether it sits right and at the top
local CORNERS = {{180, false, false}, {270, true, false}, {0, true, true}, {90, false, true}}

local function arc(cx, cy, r, degrees)
  local a = math.rad(degrees)
  return cx + r * math.cos(a), cy + r * math.sin(a)
end

local function add_rect(shapes, x, y, w, h)
  if w > 0 and h > 0 then shapes[#shapes + 1] = {kind = "rect", x = x, y = y, w = w, h = h} end
end

local function add_triangle(shapes, x1, y1, x2, y2, x3, y3)
  shapes[#shapes + 1] = {kind = "triangle", points = {x1, y1, x2, y2, x3, y3}}
end

-- which corners round, in CORNERS order
local ROUNDED = {
  all = {true, true, true, true}, top = {false, false, true, true}, bottom = {true, true, false, false},
  left = {true, false, false, true}, right = {false, true, true, false},
}

-- a filled rounded rectangle: the corner fans first, then three rects. corners is "all" (the default), "top",
-- "bottom", "left" or "right": the corners that round, so a title bar can round only its top inside a rounded window.
-- A corner that stays square gets an r × r rect instead of its fan.
function M.rounded_rect_shapes(x, y, w, h, r, segments, corners)
  segments = segments or SEGMENTS
  local round = ROUNDED[corners or "all"]
  if round == nil then error("unknown corners: " .. tostring(corners), 2) end
  r = math.min(r, w / 2, h / 2)
  local shapes = {}
  if r < 1 or segments < 1 then
    add_rect(shapes, x, y, w, h)
    return shapes
  end
  for n, k in ipairs(CORNERS) do
    if round[n] then
      local cx, cy = k[2] and x + w - r or x + r, k[3] and y + h - r or y + r
      for i = 0, segments - 1 do
        local ax, ay = arc(cx, cy, r, k[1] + 90 * i / segments)
        local bx, by = arc(cx, cy, r, k[1] + 90 * (i + 1) / segments)
        add_triangle(shapes, cx, cy, ax, ay, bx, by)
      end
    end
  end
  add_rect(shapes, x + r, y, w - 2 * r, h)
  add_rect(shapes, x, y + r, r, h - 2 * r)
  add_rect(shapes, x + w - r, y + r, r, h - 2 * r)
  for n, k in ipairs(CORNERS) do
    if not round[n] then add_rect(shapes, k[2] and x + w - r or x, k[3] and y + h - r or y, r, r) end
  end
  return shapes
end

-- a rounded border t pixels thick, inside x, y, w, h; its hole is the rounded rectangle inset by t with radius r - t
function M.rounded_outline_shapes(x, y, w, h, r, t, segments)
  segments = segments or SEGMENTS
  if t * 2 >= math.min(w, h) then return M.rounded_rect_shapes(x, y, w, h, r, segments) end
  r = math.min(r, w / 2, h / 2)
  local shapes = {}
  if r < 1 or segments < 1 then
    add_rect(shapes, x, y, w, t)
    add_rect(shapes, x, y + h - t, w, t)
    add_rect(shapes, x, y + t, t, h - 2 * t)
    add_rect(shapes, x + w - t, y + t, t, h - 2 * t)
    return shapes
  end
  local inner = r - t
  for _, k in ipairs(CORNERS) do
    local cx, cy = k[2] and x + w - r or x + r, k[3] and y + h - r or y + r
    for i = 0, segments - 1 do
      local a0, a1 = k[1] + 90 * i / segments, k[1] + 90 * (i + 1) / segments
      local ax, ay = arc(cx, cy, r, a0)
      local bx, by = arc(cx, cy, r, a1)
      if inner > 0 then
        local px, py = arc(cx, cy, inner, a0)
        local qx, qy = arc(cx, cy, inner, a1)
        add_triangle(shapes, ax, ay, bx, by, qx, qy)
        add_triangle(shapes, ax, ay, qx, qy, px, py)
      else
        add_triangle(shapes, cx, cy, ax, ay, bx, by)
      end
    end
  end
  add_rect(shapes, x + r, y, w - 2 * r, t)
  add_rect(shapes, x + r, y + h - t, w - 2 * r, t)
  if inner > 0 then
    add_rect(shapes, x, y + r, t, h - 2 * r)
    add_rect(shapes, x + w - t, y + r, t, h - 2 * r)
  else
    -- a border at least as thick as the radius: the sides stop at the bands, and r × (t - r) pieces fill beside the fans
    add_rect(shapes, x, y + t, t, h - 2 * t)
    add_rect(shapes, x + w - t, y + t, t, h - 2 * t)
    add_rect(shapes, x, y + r, r, t - r)
    add_rect(shapes, x + w - r, y + r, r, t - r)
    add_rect(shapes, x, y + h - t, r, t - r)
    add_rect(shapes, x + w - r, y + h - t, r, t - r)
  end
  return shapes
end

function M.new(env)
  local Gui, Vector2, Vector3, Color = env.Gui, env.Vector2, env.Vector3, env.Color
  local scale = env.scale or 1
  local colors, style = M.tokens.colors, M.tokens.style
  local triangles = type(Gui.triangle) == "function"
  local ui = {scale = scale}

  function ui.color(name, alpha)
    local c = colors[name]
    if c == nil then error("unknown colour: " .. tostring(name), 2) end
    local a = alpha or c[4]
    if Color then return Color(a, c[1], c[2], c[3]) end
    return {a, c[1], c[2], c[3]}
  end

  local function rect(gui, x, y, w, h, layer, color)
    Gui.rect(gui, Vector3(x, y, layer), Vector2(w, h), color)
  end

  local function width_of(gui, text, font, size)
    if env.measure then return env.measure(gui, text, font, size) end
    return #text * size * 0.55
  end

  -- false when the engine refused it. Solid Gui triangles take screen points as Vector3(x, 0, y), unlike rects'
  -- Vector3(x, y, layer); the layer is the triangle's own argument.
  local function triangle(gui, p, layer, color)
    return (pcall(Gui.triangle, gui, Vector3(p[1], 0, p[2]), Vector3(p[3], 0, p[4]), Vector3(p[5], 0, p[6]), layer, color))
  end

  -- radius in 1080p pixels; corners as for rounded_rect_shapes; returns how many primitives it drew
  function ui.rounded_rect(gui, x, y, w, h, radius, layer, color, corners)
    local shapes = M.rounded_rect_shapes(x, y, w, h, radius * scale, triangles and SEGMENTS or 0, corners)
    for i, s in ipairs(shapes) do
      if s.kind == "rect" then
        rect(gui, s.x, s.y, s.w, s.h, layer, color)
      elseif not triangle(gui, s.points, layer, color) and i == 1 then
        triangles = false -- this engine has no usable Gui.triangle: plain rectangles from now on
        rect(gui, x, y, w, h, layer, color)
        return 1
      end
    end
    return #shapes
  end

  -- bold draws the text a second time a fraction of a pixel to the right (FS Sinclair has no Bold in the game)
  function ui.text(gui, text, font, size, material, x, y, layer, color, bold)
    Gui.text(gui, text, font, size, material, Vector3(x, y, layer), color)
    if bold then Gui.text(gui, text, font, size, material, Vector3(x + style.lua_bold_offset * scale, y, layer), color) end
  end

  function ui.selected_row(gui, x, y, w, h, layer, hovered)
    ui.rounded_rect(gui, x, y, w, h, style.frame_rounding, layer, ui.color(hovered and "select_hover" or "select"))
    rect(gui, x, y, style.selected_bar * scale, h, layer + 1, ui.color("yellow"))
  end

  -- returns the key cap's width
  function ui.key_cap(gui, key, font, material, x, y, layer)
    local size, pad, h = 14 * scale, 6 * scale, 22 * scale
    local label = string.upper(key)
    local w = width_of(gui, label, font, size) + 2 * pad
    local border = style.secondary_border * scale
    ui.rounded_rect(gui, x, y, w, h, style.key_cap_rounding, layer, ui.color("line"))
    ui.rounded_rect(gui, x + border, y + border, w - 2 * border, h - 2 * border, style.key_cap_rounding, layer + 1,
      ui.color("field"))
    ui.text(gui, label, font, size, material, x + pad, y + 6 * scale, layer + 2, ui.color("text"), true)
    return w
  end

  -- an uppercase yellow heading with a rule along its bottom; returns its height
  function ui.heading(gui, text, font, material, x, y, w, layer)
    rect(gui, x, y, w, 1 * scale, layer, ui.color("line"))
    ui.text(gui, string.upper(text), font, 20 * scale, material, x, y + 6 * scale, layer + 1, ui.color("yellow"), true)
    return 28 * scale
  end

  -- state: "idle", "hover" or "press"
  function ui.button_primary(gui, label, font, material, x, y, w, h, layer, state)
    local fill = state == "press" and "yellow_press" or state == "hover" and "yellow_hover" or "yellow"
    ui.rounded_rect(gui, x, y, w, h, style.frame_rounding, layer, ui.color(fill))
    local size = 16 * scale
    local text = string.upper(label)
    local tx = x + math.max(10 * scale, (w - width_of(gui, text, font, size)) / 2)
    ui.text(gui, text, font, size, material, tx, y + (h - size) / 2, layer + 1, ui.color("on_yellow"), true)
  end

  return ui
end

return M
