-- Run before the native DBF harness dispatches the game's global update.
-- The compiled callback and stock Wwise functions come from the staged BSL ZIP.
local original = assert(update)
local addon = 'mods/cowboybingus/better_stratagem_bounce'
local starts, frames = 0, 0
local function wrapper(...)
    frames = frames + 1
    return original(...)
end
local real_require, real_getenv, real_package = require, os.getenv, package
-- The harness executable has a different PE identity from helldivers2.exe.
-- Where needed, use the upstream test adapter to supply the target identity.
local fixture = loadfile('bsl-test-source/tests/build_fixture.lua')
if fixture then fixture().known(_G) end
local app = assert(stingray.Application)
local lookup, build = app.can_get, app.build
app.build = function() return 'release' end
app.can_get = function(kind, name) return kind == 'lua' and name == addon end
-- Keep the upstream loader's filesystem/log discovery away from the player's installation.
os.getenv = function() return nil end
require = function(name)
    if name == 'ffi' then error('test isolates the BSL filesystem scanner') end
    if name == addon then
        starts = starts + 1
        update = wrapper
        return true
    end
    if name == 'core/wwise/lua/wwise_visualization' or
       name == 'core/wwise/lua/wwise_bank_reference' then return {} end
    return real_require(name)
end
local ok, why = pcall(function() assert(loadfile('bsl-callback.ljbc'))() end)
require, os.getenv, package, app.can_get = real_require, real_getenv, real_package, lookup
app.build = build
assert(ok, why)
local loader = assert(CowboyBingusModLoader)
assert(loader.modules[addon] == 'loaded' and starts == 1)
local stock = {}
for name, fn in pairs(WwiseFlowCallbacks) do stock[name] = fn end
assert(next(stock), 'stock Wwise callbacks missing')
function dbf_test_after_frames()
    assert(CowboyBingusModLoader == loader and loader.modules[addon] == 'loaded')
    assert(update == wrapper and starts == 1 and frames == _G.frames and frames > 0, 'BSL update chain lost')
    for name, fn in pairs(stock) do assert(WwiseFlowCallbacks[name] == fn, name) end
end
