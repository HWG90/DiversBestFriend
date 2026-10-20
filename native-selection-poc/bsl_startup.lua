-- HD2-Addon: mods/EquippedStratagems/NativeStratagemRadial
-- Restart-only BSL bootstrap. Each embedded module compiles in its own chunk.
if rawget(_G,'NativeStratagemRadial') or rawget(_G,'DiversBestFriend') then return end
local sources={
-- __MODULES__
}
local order={-- __ORDER__
}
local scope=setmetatable({}, {__index=_G})
local cache={}
local function require_module(name)
    if cache[name] then return cache[name] end
    local source=assert(sources[name],'ASS module missing: '..tostring(name))
    local chunk=assert(loadstring(source,'@DiversBestFriend/'..name))
    setfenv(chunk,scope)
    local exports=chunk()
    assert(type(exports)=='table','ASS module must export a table: '..name)
    cache[name]=exports
    sources[name]=nil
    return exports
end
for _,name in ipairs(order) do
    for key,value in pairs(require_module(name)) do scope[key]=value end
end
assert(type(scope.update)=='function','ASS startup callback unavailable')
rawset(_G,'update',scope.update)
