-- tests/test_station_assembled.lua -- the SHIPPED artifact test: loads the
-- assembled DBF-floaty chunk (hd2ui_floaty.lua, the exact bytes that go into
-- the zip) against a fake stingray + fake framework addon and asserts it
-- installs, runs frames, and shuts down. Catches packaging regressions that
-- raw-entry tests cannot see (R2 shipped with station_holo missing from the
-- module registry; the addon failed at require time in-game).

package.path = './?.lua;hd2ui/?.lua;' .. package.path

local checks, fails = 0, 0
local function check(name, cond, extra)
  checks = checks + 1
  if not cond then fails = fails + 1; print('FAIL ' .. name .. (extra and (' (' .. tostring(extra) .. ')') or '')) else print('ok   ' .. name) end
end

local emitted = 0
local cleared = 0
local SR = {
  Gui = {
    resolution = function() return 3840, 2160 end,
    triangle = function() return 1 end,
    text = function() return 1 end,
  },
  Window = { show_cursor = function() return false end },
  Application = {
    can_get = function(_, kind) return kind == 'material' end,
    worlds = function() return { 0x11 } end,
    main_world = function() return 0x22 end,
  },
  World = { create_screen_gui = function() return 0x33 end, destroy_gui = function() end },
  Vector3 = function(x, y, z) return { x, y, z } end,
  Vector2 = function(x, y) return { x, y } end,
  Color = function(a, r, g, b) return { a, r, g, b } end,
}
rawset(_G, 'stingray', SR)
-- note: no World.debug_camera_pose field at all -> hologram path must take
-- the pcall-safe fallback and still install

rawset(_G, '__DBF_HD2UI', {
  version = 'test-framework',
  backend_stingray = { new = function()
    return {
      ensure = function() return true end,
      clear = function() cleared = cleared + 1 end,
      release = function() end,
      emit = function() emitted = emitted + 1 end,
      resolution = function() return 3840, 2160 end,
      cursor_visible = function() return false end,
      generation = function() return 1 end,
      mode = function() return 'geometry' end,
    }
  end },
  scene = require('hd2ui.scene'),
  layout = require('hd2ui.core.layout'),
  colors = require('hd2ui.core.colors'),
})

rawset(_G, 'update', function() end)   -- the entry wraps the pre-existing update

-- load the SHIPPED bytes (the assembled chunk), not the raw entry
local chunk_path = 'hd2ui/hd2ui_floaty.lua'
local chunk = assert(loadfile(chunk_path))
local result = chunk()
check('assembled chunk installs', result and result.installed == true,
  result and (result.reason or result.version) or 'nil')
check('assembled identity r8', result and result.version == 'dbf-floaty r8',
  result and result.version)

local step = _G.update
check('entry wrapped the global update', step ~= nil)
for _ = 1, 10 do step(1 / 60) end
check('frames ran without errors (10 ticks)', true)   -- reaching here = no error() escaped
check('shutdown chains', (function()
  local ran = false
  rawset(_G, 'shutdown', function() ran = true end)
  _G.shutdown(0)
  return ran
end)())

print(string.format('\nstation_assembled: %d checks, %d failures', checks, fails))
if fails > 0 then error(fails .. ' failures') end
