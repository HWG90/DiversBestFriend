-- hd2ui/tests/test_assembled.lua -- Run the ASSEMBLED demo chunk (what ships in
-- the zip) against a fake `stingray` global for a few frames.
-- Requires `python hd2ui/build_demo.py --lua-only` to have produced hd2ui/hd2ui_demo.lua
-- (scripts/test.py does that). Verifies: install, hooks, geometry-mode drawing,
-- ARGB colour order, y-flip, redraw-on-change, cursor hide, world loss, shutdown.
local checks, fails = 0, 0
local function ok(c, msg) checks = checks + 1 if not c then fails = fails + 1 print('FAIL: ' .. msg) end end

-- ---------------------------------------------------------------- fake engine
local main_world, ui_world = { name = 'main' }, { name = 'ui' }
local worlds = { main_world, ui_world }
local F = { tris = {}, texts = {}, next_id = 1, guis = 0, destroyed_gui = 0, cursor = false, can_get_material = true }
local function vec(x, y, z) return { x = x, y = y, z = z } end
local Gui = {}
function Gui.triangle(gui, a, b, c, layer, color, material, u1, u2, u3)
  assert(gui and gui.world, 'gui handle')
  local id = F.next_id F.next_id = id + 1
  F.tris[id] = { a = a, b = b, c = c, layer = layer, color = color, material = material }
  return id
end
function Gui.text(gui, s, font, size, font2, pos, color)
  assert(gui and gui.world, 'gui handle')
  local id = F.next_id F.next_id = id + 1
  F.texts[id] = { s = s, font = font, size = size, pos = pos, color = color }
  return id
end
function Gui.destroy_triangle(gui, id) assert(F.tris[id], 'destroy unknown tri ' .. tostring(id)) F.tris[id] = nil end
function Gui.destroy_text(gui, id) assert(F.texts[id], 'destroy unknown text ' .. tostring(id)) F.texts[id] = nil end
function Gui.resolution() return 2560, 1440 end
local World = {}
function World.create_screen_gui(world, mode, a, b)
  assert(mode == 'scale' and a == 1 and b == 1, 'create_screen_gui args')
  F.guis = F.guis + 1
  return { world = world }
end
function World.destroy_gui(world, gui) F.destroyed_gui = F.destroyed_gui + 1 end
local Application = {}
function Application.worlds() return worlds end
function Application.main_world() return main_world end
function Application.can_get(kind, name)
  if kind == 'material' then return F.can_get_material and name == 'mods/dbf/hd2ui/solid' end
  return false
end
local Window = {}
function Window.show_cursor() return F.cursor end
_G.stingray = {
  Gui = Gui, World = World, Application = Application, Window = Window,
  Vector2 = function(x, y) return vec(x, y) end,
  Vector3 = function(x, y, z) return vec(x, y, z) end,
  Color = function(a, r, g, b) return { a = a, r = r, g = g, b = b } end,
}
local base_updates, base_shutdowns = 0, 0
_G.update = function(dt) base_updates = base_updates + 1 end
_G.shutdown = function() base_shutdowns = base_shutdowns + 1 end

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- ---------------------------------------------------------------- load chunk
local chunk, err = loadfile('hd2ui/hd2ui_demo.lua')
ok(chunk, 'assembled chunk compiles: ' .. tostring(err))
local result = chunk()
ok(type(result) == 'table' and result.installed == true, 'entry reports installed')
ok(_G.__HD2UI_DEMO_INSTALLED == true, 'install guard set')
ok(_G.update ~= nil, 'update hooked')

-- ---------------------------------------------------------------- frame 1
_G.update(1 / 60)
ok(base_updates == 1, 'original update still called')
ok(F.guis == 1, 'one screen gui created')
local first_tris, first_texts = count(F.tris), count(F.texts)
ok(first_tris >= 4, 'geometry mode: triangles drawn (' .. first_tris .. ')')
ok(first_texts == 1, 'one text drawn')
-- colour order + y flip + layer + material
local any_tri
for _, t in pairs(F.tris) do any_tri = t break end
ok(any_tri.layer == 4, 'layer 4')
ok(any_tri.material == 'mods/dbf/hd2ui/solid', 'our material name')
ok(any_tri.color.a and any_tri.color.r == 242, 'Color(a,r,g,b) order: r=242 from #f2f2f2, alpha first')
ok(any_tri.a.y == 0, 'V3(x,0,y) layout: middle component zero')
local txt
for _, t in pairs(F.texts) do txt = t break end
ok(txt.s == '45', 'demo starts at full magazine')
ok(txt.font == 'core/performance_hud/debug', 'debug font')
-- 1440p: scale 4/3, right side => x = 1280 + 140*4/3 ~= 1466.7 ; y flipped => 1440 - 720 = 720
ok(math.abs(txt.pos.x - (1280 + 140 * 4 / 3)) < 30, 'text x near right-of-centre (' .. txt.pos.x .. ')')
ok(math.abs(txt.pos.y - 720) < 1e-6, 'text y flipped to y-up centre (' .. txt.pos.y .. ')')
ok(txt.color.a == math.floor(255 * 0.9 + 0.5), 'opacity applied to alpha (' .. tostring(txt.color.a) .. ')')

-- ---------------------------------------------------------------- unchanged frame => no redraw
local ids_before = F.next_id
_G.update(1 / 60)
ok(F.next_id == ids_before, 'no redraw when signature unchanged')

-- ---------------------------------------------------------------- value change => redraw, old ids destroyed
for _ = 1, 30 do _G.update(1 / 60) end   -- ~0.5 s => count drops to 44
for _, t in pairs(F.texts) do txt = t end
ok(txt.s == '44', 'counter ticks down (' .. txt.s .. ')')
ok(count(F.texts) == 1 and count(F.tris) == first_tris, 'retained ids destroyed before redraw')

-- ---------------------------------------------------------------- cursor hides everything
F.cursor = true
_G.update(1 / 60)
ok(count(F.tris) == 0 and count(F.texts) == 0, 'hidden while cursor visible')
F.cursor = false
_G.update(1 / 60)
ok(count(F.texts) == 1, 'redrawn after cursor hidden')

-- ---------------------------------------------------------------- world loss => gui recreated
worlds = { main_world, { name = 'ui2' } }
F.tris, F.texts = {}, {}   -- retained elements die with their world in the engine
_G.update(1 / 60)
ok(F.guis == 2, 'gui recreated after world loss (' .. F.guis .. ')')
ok(count(F.texts) == 1, 'draws on the new gui')

-- ---------------------------------------------------------------- shutdown
_G.shutdown()
ok(base_shutdowns == 1, 'original shutdown called')
ok(F.destroyed_gui >= 1, 'gui destroyed on shutdown')
ok(count(F.tris) == 0 and count(F.texts) == 0, 'all ids destroyed on shutdown')

-- ---------------------------------------------------------------- reinstall guard
local again = chunk()
ok(again.installed == true and F.guis == 2, 're-running chunk is a no-op')

if fails > 0 then print('hd2ui assembled: ' .. fails .. ' of ' .. checks .. ' checks FAILED') os.exit(1) end
print('hd2ui assembled: ' .. checks .. ' checks passed')
print('OK-ASSEMBLED')
