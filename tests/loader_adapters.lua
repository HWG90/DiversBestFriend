local G=setmetatable({},{__index=_G});G._G=G
G.rawget=rawget;G.rawset=rawset
local old=function(...)return 'previous',nil,select('#',...)end
G.update=old
local scope=setmetatable({_G=G},{__index=G})
G.io={open=function(path,mode)
 local name=path:match('^C:/fixture/divers_best_friend/(.+)$')
 assert(name,'Module read escaped package')
 if name:find('%.log$')then return {write=function()end,flush=function()end,close=function()end}end
 assert(mode=='rb' and FILES[name],'Unexpected package read: '..tostring(name))
 return {read=function()return FILES[name]end,close=function()end}
end}
G.CowboyBingusModLoader={api=1,open_log=function()return{write=function()end,close=function()end}end}
local required,exposed={},false
local host={scope=scope,config={preferences={}}}
function host.require(name)
 assert(FILES[name] and not required[name],'Duplicate or foreign module')
 required[name]=true
 local chunk=assert(loadstring(FILES[name]));setfenv(chunk,scope);return chunk()
end
function host.expose(name,values)assert(name=='dbf' and values.settings);exposed=true end
scope.mod=host
local entry=LOADER=='LLL' and 'main.lua' or 'mod.lua'
local chunk=assert(loadstring(FILES[entry]));setfenv(chunk,scope)
local descriptor=chunk()
assert(G.update==old and not rawget(G,'DiversBestFriend'),'Import has no game/global effects')
assert(descriptor.on_disable()==true,'Unstarted adapter is removable')
local cleanups={}
local ctx={api=2,dir='C:/fixture/divers_best_friend',on_cleanup=function(fn)cleanups[#cleanups+1]=fn end}
if LOADER=='MDL' then
 assert(not pcall(descriptor.on_enable,{api=1}), 'Invalid MDL context rejected')
 G.CowboyBingusModLoader=nil -- exercise the private diagnostic fallback
 descriptor.on_enable(ctx)
 assert(#cleanups==1 and cleanups[1]()==false,'Cleanup retains restart-only owners')
 assert(not rawget(G,'CowboyBingusModLoader'),'Diagnostic facade does not leak globally')
else descriptor.on_enable();assert(exposed,'LLL preferences remain exposed') end
assert(G.DiversBestFriend.revision==45 and G.NativeStratagemRadial==G.DiversBestFriend)
assert(G.update~=old,'Owned update installed')
local installed=G.update
assert(not pcall(descriptor.on_enable,ctx),'Duplicate startup rejected')
assert(descriptor.on_disable()==false and G.update==installed,'Disable retains active hook until restart')
print(LOADER..' real-core adapter: import, API guard, startup, duplicate rejection, diagnostics and restart-only retention passed')
