-- Private DBF record compiled into its DLL. The native driver calls it in the engine VM.
local factories = {
-- @modules@
}
local scope = setmetatable({}, { __index = _G })
local lease = "DBF_HellForge_HUD_Owner"
local record = { live_lua_api = 1, name = "Diver's Best Friend" }
local runtime, stopping

function record.on_enable()
    assert(not rawget(_G, lease), "DBF HUD already has an owner")
    stopping = false
    for _, factory in ipairs(factories) do
        setfenv(factory, scope)
        local exports = factory()
        for key, value in pairs(exports) do scope[key] = value end
    end
    runtime = scope.dbf_hud_runtime()
    assert(type(runtime) == "table" and type(runtime.shutdown) == "function"
        and type(runtime.update) == "function", "Incomplete DBF HUD runtime")
    rawset(_G, lease, record)
end

function record.on_update(dt)
    if runtime and not stopping and rawget(_G, lease) == record then
        runtime:update(dt)
    end
end

local function release()
    if rawget(_G, lease) ~= record then return true end
    stopping = true
    if runtime then
        local done, reason = runtime:shutdown()
        if done ~= true then return false, reason end
    end
    runtime = nil
    rawset(_G, lease, nil)
    return true
end

record.on_disable = release
record.on_cleanup_poll = release
return record
