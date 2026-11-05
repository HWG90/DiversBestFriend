-- Run under the build-25480438 lua51.dll against the launcher-planned companion DLL.
-- The loader stub lets the addon resolve the already-loaded companion on frame two.
local ffi = require("ffi")
local addon = assert(loadfile("staged.lua"))
local companion = ffi.load("./divers_best_friend.dll")
local loader
for cycle = 1, 3 do
    local record = addon()
    assert(record.live_lua_api == 1)
    record.on_enable()
    assert(rawget(_G, "DBF_HellForge_HUD_Owner") == record)
    record.on_update(1 / 60)
    loader = loader or ffi.load("./hellforge_modloader.dll")
    record.on_update(0.51) -- pass the absent-companion retry interval
    assert(companion.dbf_hud_base() == 0, "expected a game-free host")
    assert(record.on_disable() == true)
    assert(rawget(_G, "DBF_HellForge_HUD_Owner") == nil)
end
local receipt = assert(io.open("vm-passed.txt", "wb"))
assert(receipt:write("PASS staged HUD VM: 3 enable/frame/shutdown cycles (" .. jit.version .. ")"))
assert(receipt:close())
