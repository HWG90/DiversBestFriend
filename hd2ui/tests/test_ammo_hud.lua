-- tests/test_ammo_hud.lua -- End-to-end test of the SHIPPED ammo HUD chunk:
-- loads hd2ui/hd2ui_ammo.lua (built by build_ammo.py --lua-only) under the
-- game's LuaJIT, plants a Deadeye component (GUID + mag/res at the anchor
-- offsets) in REAL host-process memory via ffi, lets the chunk self-attach,
-- background-scan, validate, lock, and render into a fake stingray GUI.
-- Verifies: install, scan->lock, live fire decrement, stale->rescan, shutdown.

local checks, fails = 0, 0
local function ok(c, msg)
  checks = checks + 1
  if not c then fails = fails + 1 print('FAIL: ' .. msg) else print('ok   ' .. msg) end
end

local ffi = rawget(_G, 'ffi')
if not ffi or not ffi.cdef then
  local k, m = pcall(require, 'ffi'); if k and m then ffi = m end
end
assert(ffi, 'test host needs ffi')

-- scratch dir for the entry log
ffi.cdef[[ int _putenv(const char* s); ]]
local scratch = (os.getenv('TEMP') or os.getenv('TMP') or '.') .. '\\dbf_ammo_test'
os.execute('mkdir "' .. scratch .. '" >NUL 2>&1')
ffi.C._putenv('DBF_AMMO_DIR=' .. scratch)
local LOG = scratch .. '\\hd2ui_ammo.log'
local CACHE = scratch .. '\\dbf_ammo_cache.txt'
os.remove(LOG)
os.remove(CACHE)   -- a stale cache from a previous run must not leak in

-- ------------------------------------------------------------- fake stingray
local main_world = { name = 'main' }
local F = { tris = {}, texts = {}, next_id = 1, guis = 0, destroyed = 0, cursor = false,
             presets = {} }
local function vec(x, y, z) return { x = x, y = y, z = z or 0 } end
local Gui = {}
function Gui.triangle(gui, a, b, c, layer, color, material, u1, u2, u3)
  local id = F.next_id; F.next_id = id + 1
  F.tris[id] = { a = a, b = b, c = c, layer = layer, color = color, material = material }
  return id
end
function Gui.text(gui, s, font, size, font2, pos, color)
  local id = F.next_id; F.next_id = id + 1
  F.texts[id] = { s = s, pos = pos, color = color }
  return id
end
function Gui.destroy_triangle(gui, id) F.tris[id] = nil end
function Gui.destroy_text(gui, id) F.texts[id] = nil end
function Gui.resolution() return 2560, 1440 end
local World = {}
function World.create_screen_gui(world, mode, a, b) F.guis = F.guis + 1; return { world = world } end
function World.destroy_gui(world, gui) F.destroyed = F.destroyed + 1 end
local Application = {}
function Application.worlds() return { main_world } end
function Application.main_world() return main_world end
function Application.can_get(kind, name)
  if kind == 'material' then return name == 'mods/dbf/hd2ui/solid' end
  if kind == 'lua' then return F.presets[name] == true end
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
_G.update = function() base_updates = base_updates + 1 end
_G.shutdown = function() base_shutdowns = base_shutdowns + 1 end

-- ------------------------------------------------- plant the component memory
-- 128-byte buffer; GUID at +64 so every negative context offset stays inside:
--   hit = buf+64; flag u32=1 at hit-0x30 (+16); res at hit-0x2C (+20);
--   aim f32 1.0 at hit-0x28 (+24); mag at hit-0x24 (+28).
local buf = ffi.new('uint8_t[128]')
local addr = tonumber(ffi.cast('unsigned long long', buf))
local GUID_OFF = 64
local guid_bytes = string.char(0x95,0xd2,0xa2,0x94,0xb5,0x2b,0xd4,0x5e,
                               0x6e,0xd2,0x82,0xd0,0xe0,0x89,0x68,0xb9)
ffi.copy(buf + GUID_OFF, guid_bytes, 16)
local function set_u32(off, v)
  local b = ffi.new('uint8_t[4]', v % 256, math.floor(v/256) % 256,
                    math.floor(v/65536) % 256, math.floor(v/0x1000000) % 256)
  ffi.copy(buf + off, b, 4)
end
set_u32(GUID_OFF - 0x30, 1)    -- structural flag
set_u32(GUID_OFF - 0x28, 0x3F800000)  -- aim f32 = 1.0
set_u32(GUID_OFF - 0x24, 7)    -- magazine
set_u32(GUID_OFF - 0x2C, 56)   -- reserve

-- ------------------------------------------- missing framework: clean refusal
local chunkA, errA = loadfile('hd2ui/hd2ui_ammo.lua')
ok(chunkA ~= nil, 'ammo chunk compiles: ' .. tostring(errA))
local resA = chunkA()
ok(type(resA) == 'table' and resA.installed == false
   and resA.reason == 'hd2ui framework not installed',
   'missing framework -> clean no-install (no crash)')
os.remove(LOG)

-- ---------------------------------------------- framework addon installs first
local fw = assert(loadfile('hd2ui/hd2ui_framework.lua'))
local api = fw()
ok(type(rawget(_G, '__DBF_HD2UI')) == 'table' and api.backend_stingray ~= nil,
   'framework chunk installs __DBF_HD2UI api')

-- ------------------------------------------------------------- run the chunk
local chunk = loadfile('hd2ui/hd2ui_ammo.lua')
local res = chunk()
ok(type(res) == 'table' and res.installed == true, 'ammo entry installs on framework')
ok(type(res) == 'table' and res.style == 'crosshair', 'default style is crosshair')
local update = _G.update

local function rfile(p)
  local f = io.open(p, 'r'); if not f then return '' end
  local s = f:read('*a'); f:close(); return s
end

-- Pump frames until the log shows LOCKED (background scan of real memory).
local locked
for _ = 1, 2000 do
  update(1 / 60)
  local log = rfile(LOG)
  locked = log:match('LOCKED base=0x(%x+) mag=(%d+) res=(%d+)')
  if locked then
    ok(tonumber('0x' .. locked) == addr + GUID_OFF, 'locked base == planted component')
    local _, mag, rsv = log:match('LOCKED base=0x(%x+) mag=(%d+) res=(%d+)')
    ok(tonumber(mag) == 7 and tonumber(rsv) == 56, 'locked mag/res match planted values')
    break
  end
end
ok(locked ~= nil, 'scan locked the planted anchor')
if not locked then
  print(rfile(LOG))
  print(string.format('ammo_hud: %d checks, %d failures', checks, fails))
  error('no lock')
end

-- the lock was persisted for the cache fast path (fresh installs lock instantly)
local cs_stamp, cs_base = rfile(CACHE):match('^(%x+)%s+(%x+)')
ok(cs_base ~= nil and tonumber('0x' .. cs_base) == addr + GUID_OFF,
   'cache file saved with the locked base')

-- HUD shows 7/56 (fake GUI text)
local function hud_text()
  for _, t in pairs(F.texts) do return t.s end
  return nil
end
update(1 / 60)
ok(hud_text() == '7/56', 'HUD renders 7/56 (got ' .. tostring(hud_text()) .. ')')

-- fire: magazine decrements live
set_u32(GUID_OFF - 0x24, 6)
for _ = 1, 10 do update(1 / 60) end
ok(hud_text() == '6/56', 'HUD tracks live fire -> 6/56 (got ' .. tostring(hud_text()) .. ')')

-- stale: out-of-range value forces rescan (simulates weapon switch/free)
set_u32(GUID_OFF - 0x24, 199)
for _ = 1, 30 do update(1 / 60) end
local log2 = rfile(LOG)
ok(log2:find('STALE') ~= nil or log2:find('anchor_stale') ~= nil
   or log2:find('rescanning') ~= nil or log2:find('no plausible hit') ~= nil,
   'implausible value triggers rescan')

-- cursor hides HUD
F.cursor = true
for _ = 1, 10 do update(1 / 60) end
local ntexts = 0 for _ in pairs(F.texts) do ntexts = ntexts + 1 end
ok(ntexts == 0, 'HUD hidden while cursor visible')

-- shutdown restores
_G.shutdown()
ok(base_shutdowns == 1, 'original shutdown called')


-- ------------------------------------------------- Mod Options Menu facility
-- fake _G.ModOptionsMenu: records registrations, flips ready after boot, then
-- the shipped entry must poll, register three options, and applying a change
-- (as the native page would) must rebuild the HUD live.
local mom = {
  ready_flag = false, reg = {}, values = {}, cbs = {},
}
function mom.ready() return mom.ready_flag end
function mom.register_option(id, spec)
  mom.reg[id] = spec
  if mom.values[id] == nil then mom.values[id] = spec.default end
  return true
end
function mom.get(id) return mom.values[id] end
function mom.on_change(id, cb) mom.cbs[id] = cb return true end
function mom.set(id, v)
  mom.values[id] = v
  local cb = mom.cbs[id]
  if cb then cb(v) end
  return true
end
_G.ModOptionsMenu = mom
-- ---------------------------------------------- second install: cache fast path
-- Same process, same planted component: a fresh chunk instance must lock
-- instantly from the cache file -- no SCAN_START, no heap walk.
set_u32(GUID_OFF - 0x24, 7)    -- plausible mag/res again (stale test left 199)
set_u32(GUID_OFF - 0x2C, 56)
rawset(_G, '__DBF_AMMO_INSTALLED', nil)
local base2_updates, base2_shutdowns = 0, 0
rawset(_G, 'update', function() base2_updates = base2_updates + 1 end)
rawset(_G, 'shutdown', function() base2_shutdowns = base2_shutdowns + 1 end)
F.tris = {}
F.texts = {}
F.cursor = false   -- the first phase left the cursor visible (hide test)
os.remove(LOG)
-- simulate the Mod Options menu: Arsenal deploys the chosen style as a tiny
-- lua resource; can_get says it exists and the game's require returns it.
local pf = 'mods/dbf/ammo/preset_style.lua'
os.execute('mkdir mods\\dbf\\ammo >NUL 2>&1')
local pff = io.open(pf, 'w'); pff:write("-- fixture preset\nreturn 'gunside'\n"); pff:close()
F.presets['mods/dbf/ammo/preset_style'] = true
local chunk2, err2 = loadfile('hd2ui/hd2ui_ammo.lua')
ok(chunk2 ~= nil, 'second chunk compiles: ' .. tostring(err2))
local res2 = chunk2 and chunk2() or nil
ok(type(res2) == 'table' and res2.installed == true, 'second install succeeds')
ok(type(res2) == 'table' and res2.style == 'gunside',
   'menu preset selects gunside style')
ok(type(res2) == 'table' and res2.version == 'dbf-ammo r8.1',
   'shipped identity is r3.2 (got ' .. tostring(type(res2) == 'table' and res2.version) .. ')')
local log3 = rfile(LOG)
ok(log3:find('CACHE_LOCKED') ~= nil, 'cache fast path locks on install')
ok(log3:find('SCAN_START') == nil, 'no heap scan on cache hit')
local update2 = _G.update
update2(1 / 60)
local function has_text(s)
  for _, t in pairs(F.texts) do if t.s == s then return true end end
  return false
end
ok(has_text('7/56'), 'gunside HUD renders 7/56 from cached lock')
ok(has_text('mag / reserve'), 'gunside HUD renders its subtitle')
ok(rfile(LOG):find('STYLE gunside') ~= nil, 'log records the chosen style')
ok(base2_updates == 1, 'original update called')
_G.shutdown()
ok(base2_shutdowns == 1, 'second shutdown chained')
os.remove(pf)
F.presets['mods/dbf/ammo/preset_style'] = nil

-- ------------------------------------------- live in-game settings via MOM
mom.ready_flag = true
for _ = 1, 130 do update2(1 / 60) end          -- poll interval is 1 sim-second
local log4 = rfile(LOG)
ok(log4:find('MOM options registered') ~= nil, 'entry registers options with Mod Options Menu')
ok(mom.reg.dbf_ammo_style ~= nil and mom.reg.dbf_ammo_size ~= nil
   and mom.reg.dbf_ammo_enabled ~= nil, 'style/size/enabled option rows all registered')
ok(mom.reg.dbf_ammo_style.type == 'choice' and mom.reg.dbf_ammo_size.type == 'slider',
   'option kinds match the menu facility')

mom.set('dbf_ammo_style', 1)                    -- user picks Crosshair in the game menu
for _ = 1, 5 do update2(1 / 60) end
local log5 = rfile(LOG)
ok(log5:find('STYLE crosshair') ~= nil, 'menu style change rebuilds HUD live')
ok(mom.values.dbf_ammo_style == 1, 'menu value is authoritative after set')

mom.set('dbf_ammo_size', 150)
for _ = 1, 5 do update2(1 / 60) end
ok(rfile(LOG):find('size=150%%') ~= nil, 'menu slider size applies live')

-- graphical display mode: numeric label kept, text subtitle gone (bars draw
-- via rect primitives; anchor model carries no heat/fuel so bars are absent)
mom.set('dbf_ammo_display', 2)
F.texts = {}
for _ = 1, 6 do update2(1 / 60) end       -- clear BEFORE pumping (dedupe cache)
ok(has_text('7/56'), 'graphical mode keeps the numeric counter')
local subtitle = false
for _, t in pairs(F.texts) do if t.s == 'mag / reserve' then subtitle = true end end
ok(not subtitle, 'graphical crosshair has no text subtitle')
mom.set('dbf_ammo_display', 1)
mom.set('dbf_ammo_style', 2)              -- gunside text mode: subtitle returns
F.texts = {}
for _ = 1, 6 do update2(1 / 60) end
ok(has_text('mag / reserve'), 'text gunside restores the subtitle')
ok(has_text('7/56'), 'text gunside keeps the numbers')

-- world style frame (the R25 obj-scope crash lived here; never covered before)
mom.set('dbf_ammo_style', 3)
F.texts = {}
for _ = 1, 6 do update2(1 / 60) end
ok(has_text('7/56'), 'world (provisional fallback) renders without frame errors')
ok(rfile(LOG):find('frame error') == nil, 'no frame errors across style matrix')
mom.set('dbf_ammo_enabled', false)
F.texts = {}
for _ = 1, 5 do update2(1 / 60) end
local ntexts = 0
for _ in pairs(F.texts) do ntexts = ntexts + 1 end
ok(ntexts == 0, 'enabled=false hides the HUD')
mom.set('dbf_ammo_enabled', true)
for _ = 1, 5 do update2(1 / 60) end
ok(has_text('7/56') or (function()
  for _, t in pairs(F.texts) do if t.s == '7/56' then return true end end
  return false
end)(), 'enabled=true brings the HUD back')

print(string.format('ammo_hud: %d checks, %d failures', checks, fails))
if fails > 0 then error(fails .. ' failures') end
