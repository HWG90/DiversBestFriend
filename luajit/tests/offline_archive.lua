-- Offline lifecycle check of the built DBF-ASS archive in stock LuaJIT: the
-- exact Addon Lua that LLL loads, against a mocked LiveLuaLoader and the
-- synthetic game image. Runs on_enable, frames of on_update and on_disable.
--   luajit offline_archive.lua <Addon/63ab3b8f046c401d.lua> <source tree> <log dir> [frames]
local addon,tree,log_dir,frames=arg[1],arg[2],arg[3],tonumber(arg[4] or 120)
local here=arg[0]:match('^(.*)/[^/]*$') or '.'
local env=dofile(here..'/synthetic_image.lua')(tree..'/src/guards.lua',tree..'/src/weapon_status_layouts.lua')
local function slurp(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
-- Widget setters as Lua stand-ins (the image holds only their witness bytes):
-- a frame that calls one writes the synthetic widget instead of crashing.
-- Function-pointer ctypes never compare equal, so match bind's casts by address.
-- The stand-ins are made here, not in the wrapper: a closure made inside it
-- aborts every JIT trace through the mod's casts (~4x the steady cost).
local ffi=require('ffi')
local real_cast=ffi.cast
local function setter(offset)
    return function(address,v)local f=real_cast('float *',address+offset);f[0],f[1]=v.x,v.y end
end
local setters={[0x12df3b0]=setter(4),[0x12dee70]=setter(12),[0x12dfbe0]=setter(20),[0x12e6e70]=setter(44),[0x12e6de0]=setter(60)}
ffi.cast=function(ct,value)
    local stub=type(value)=='number' and setters[value-env.image]
    if stub and tostring(ffi.typeof(ct)):find('(*)',1,true) then return stub end
    return real_cast(ct,value)
end
-- A removed card left drawn at full size by a cancelled leave tween: DBF
-- must finish it to height 0 while the list is open (2026-10-29).
local frozen=env.list+0x110+6*0x3760
env.put(frozen,'uint32_t',0x45011);env.put(frozen+0x3728,'uint8_t',1)
env.put(frozen+20,'float',1);env.put(frozen+24,'float',1)

-- No other provider of the globals DBF-ASS checks for exists in this state.
local log={}
rawset(_G,'LiveLuaLoader',{api=1,modules={},set_enabled=function()return true end})
rawset(_G,'CowboyBingusModLoader',{api=1,log_directory=log_dir,open_log=function(name)return io.open(log_dir..'/'..name,'w')end})
local definition=assert(loadstring(slurp(addon),'@archive'))()
assert(type(definition)=='table' and definition.live_lua_api==1,'not an LLL lifecycle definition')
assert(definition.on_enable,'on_enable missing')
definition.on_enable()
local owner=rawget(_G,'DiversBestFriend')
assert(type(owner)=='table','DiversBestFriend not published')
local errors=0
local function run(n)
    for _=1,n do
        local ok,why=pcall(definition.on_update,1/60)
        if not ok then errors=errors+1;log[#log+1]=tostring(why) end
    end
end
run(math.min(frames,120)) -- startup: native fingerprints, first snapshots
local reads_before=env.stats.reads
collectgarbage('collect');collectgarbage('stop')
local kb,clock=collectgarbage('count'),os.clock()
run(frames)
local elapsed,garbage=os.clock()-clock,(collectgarbage('count')-kb)*1024
collectgarbage('restart')
print(string.format('steady %d frames: %.2f us/frame, %.0f B garbage/frame, %.1f reads/frame',
    frames,elapsed/frames*1e6,garbage/frames,(env.stats.reads-reads_before)/frames))
local statuses={}
for _,key in ipairs({'selection_status','native_status','weapon_status','status'})do
    if owner[key]~=nil then statuses[#statuses+1]=key..'='..tostring(owner[key]) end
end
print('frames',frames,'update_errors',errors,'reads',env.stats.reads)
print('status',table.concat(statuses,' | '))
for i=1,math.min(#log,5)do print('error',log[i])end
local height=ffi.cast('float *',frozen+24)[0]
local native_log=slurp(log_dir..'/DiversBestFriend-native.log')
print('frozen removed card height',height)
assert(height==0 and native_log:find('collapsed removed list card 6',1,true),'frozen removed card not collapsed and logged')
-- Unloading with the stratagem menu open is refused (rows would be left moved).
local open_ok,open_why=definition.on_disable()
print('on_disable with menu open',open_ok,open_why)
assert(open_ok==false and tostring(open_why):find('Close the stratagem menu',1,true),'unload must wait for the menu to close')
env.put(env.panel+0x38769,'uint8_t',0)
local ok,why=definition.on_disable()
print('on_disable',ok,why)
assert(errors==0,'on_update raised')
assert(ok,'on_disable refused')
print('PASS archive lifecycle')
