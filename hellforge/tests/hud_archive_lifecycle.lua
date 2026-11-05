-- Run from the HF-LLL checkout. Discover and execute the exact chunk in the fixture patch.
local archive, expected = arg[1], "mods/goose/divers_best_friend"
local file = assert(io.open(archive, "rb"))
local patch = file:read("*a")
file:close()
local name = "9ba626afa44a3aa3.patch_37"
local names, warnings, _, _, details = dofile("src/discovery.lua")({
    data = "data",
    files = function() return {name, name .. ".stream", name .. ".gpu_resources"} end,
    read = function(path) assert(path == "data/" .. name); return patch end,
})
assert(#warnings == 0 and #names == 1 and names[1] == expected)
local row = assert(details[expected])
assert(row.kind == "addon" and not row.chef)
local source = patch:sub(row.offset + 9, row.offset + row.length)
local function load_resource(id)
    assert(id == expected)
    return assert(loadstring(source, "@" .. id))()
end
local manager = dofile("src/manager.lua")({
    available = function(id) return id == expected end,
    require = load_resource,
    evict = function() end,
    report = function() end,
    can_retry = function() return false end, -- src/start.lua: archive has no live.catalog row
}, names)
assert(manager.modules[expected] == "loaded", manager.modules[expected])
local first = assert(manager.records[expected])
assert(manager.origins[expected].owner == "lll_archive")
manager.frame(0.25)
assert(updates == 1)
assert(manager.reload(expected) == false)
assert(manager.records[expected] == first and manager.pending_cleanup[expected])
local duplicate = load_resource(expected)
assert(not pcall(duplicate.on_enable))
assert(duplicate.on_disable() == true)
manager.frame(0.25)
assert(manager.records[expected] == first and updates == 1)
allow_release = true
manager.frame(0.25)
assert(not manager.records[expected] and not manager.pending_cleanup[expected])
assert(manager.modules[expected] == "disabled" and updates == 1)
duplicate.on_enable()
assert(first.on_disable() == true)
duplicate.on_update(0.25)
assert(updates == 2)
assert(duplicate.on_disable() == true)
