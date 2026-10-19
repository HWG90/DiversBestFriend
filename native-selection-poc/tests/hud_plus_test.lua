-- Set HD2_HUD_PLUS_SOURCE to an extracted, unmodified local HUD+ product Lua.
-- Third-party source is read as a fixture and is never included in ASS builds.
local function read(path)
 local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s
end
local factory=assert(loadstring(read('native-selection-poc/hud_plus.lua')..'\nreturn hud_plus_compat'))()
local rejected=factory(function() return true end)
local runtime={installed=true,program={world_hud={stratagem={prepare=function()end}}}}
local function unknown() return runtime.program end
rejected.refresh(unknown)
assert(rejected.status=='HUD+ stratagem adapter unsupported')
assert(runtime.program.world_hud.stratagem.observe==nil,'unknown owner unchanged')
for i=1,100 do rejected.refresh(unknown) end
assert(rejected.scans==1,'no repeated discovery')
local path=os.getenv('HD2_HUD_PLUS_SOURCE')
if not path then print('HUD+ rejection and idle checks passed; real-owner fixture requires HD2_HUD_PLUS_SOURCE');return end
local text=read(path)
local first=assert(text:find('modules["features.stratagem"] = function(require)',1,true))
local last=assert(text:find('modules["features.stratagem_cooldown"]',first,true))
local modules={}
assert(loadstring('local modules=...\n'..text:sub(first,last-1)))(modules)
local S=modules["features.stratagem"](function() return {} end)
local pick_first=assert(text:find('modules["game.stratagem_pick"] = function(require)',1,true))
local pick_last=assert(text:find('\nmodules[',pick_first+1,true))
assert(loadstring('local modules=...\n'..text:sub(pick_first,pick_last-1)))(modules)
local Pick=modules["game.stratagem_pick"]()
local actual_pick=setmetatable({row=7,written=99},Pick)

local f=assert(io.open('native-selection-poc/hud_plus.lua'));local compat=assert(loadstring(f:read('*a')..'\nreturn hud_plus_compat'))();f:close()
local enabled=true
local c=compat(function() return enabled end)
local opacity,closed,picked={},0,0
local feature=setmetatable({panel={editable=true,mission=100},ui={n={hud_widgets_panels_stratagem_hud_at=20,stratagem_panel_group=4,widget_opacity_default={1}},call=function(_,_,_,v) opacity[#opacity+1]=v end,destroy=function() end,alive=function() return nil end},inputs={prepare=function(_,_,_,select) return select end,observe=function(self) self.showing=true;self.listing=true end},list={close=function() closed=closed+1 end},card={close=function() end},pick={reset=function() picked=picked+1;actual_pick:reset() end}},S)
local runtime={installed=true,program={}}
local function update() return runtime.program end
c.refresh(update)
runtime.program={world_hud={stratagem=feature}}
c.refresh(update)
assert(c.status:find('yield'),c.status)
assert(feature:prepare(true,{},false,false)==false)
feature.edited=124
feature:observe(true,{},1,{},false,{})
assert(opacity[1]==1 and feature.edited==nil,'restore hidden vanilla group')
assert(closed==1 and picked==1,'release duplicate and reset competing picker')
assert(actual_pick.row==nil and actual_pick.written==nil,'real 0.2.8 pending left-release selection cancelled')
assert(feature:put(1,2,{})==nil,'do not recreate 3D list')
local scans=c.scans
local started=os.clock()
for i=1,10000 do c.refresh(update) end
print(string.format("HUD+ idle generation checks: %.3f ms / 10000 fixture frames",(os.clock()-started)*1000))
assert(c.scans==scans,'unchanged update must not be rescanned')
enabled=false
assert(feature:prepare(true,{},false,false)==true,'delegate when ASS disabled')
assert(feature:put(1,2,{})==false,'original put resumes')
feature:observe(true,{},1,{},false,{})
assert(opacity[2]==0 and feature.edited==124,'HUD+ reacquires vanilla visibility')
assert(closed==1 and picked==1,'no disabled-mode cleanup loop introduced')
print('HUD+ real 0.2.8 feature: takeover, restoration, picker reset, no recreation, disable/resume, 10000 idle frames passed')

-- Run HUD+'s actual update wrapper, not a hand-built imitation. Both load
-- orders must converge without replacing its callback or losing return values.
local first=assert(text:find('modules["core.runtime"] = function(require)',1,true))
local last=assert(text:find('modules["core.settings"]',first,true))
assert(loadstring('local modules=...\n'..text:sub(first,last-1)))(modules)
local Runtime=modules["core.runtime"]()
for _,hud_first in ipairs({true,false}) do
 enabled=true
 local owned=setmetatable({panel=feature.panel,ui=feature.ui,inputs=feature.inputs,
    list=feature.list,card=feature.card,pick=feature.pick,edited=124},S)
 local program={world_hud={stratagem=owned},step=function() owned:observe(true,{},1,{},false,{}) end,close=function() end}
 local environment={update=function() return 7,nil,9 end}
 local runtime=Runtime.new(program)
 local adapter=compat(function() return enabled end)
 local function install_ass()
  local previous=environment.update
  environment.update=function(...)
   adapter.refresh(environment.update)
   return previous(...)
  end
 end
 if hud_first then runtime:install(environment);install_ass()
 else install_ass();runtime:install(environment) end
 for i=1,3 do local a,b,c=environment.update();assert(a==7 and b==nil and c==9,'preserve update return tuple') end
 assert(adapter.status:find('yield'),adapter.status)
 assert(owned.edited==nil,'original group visible in both load orders')
 enabled=false;environment.update();assert(owned.edited==124,'owner resumes')
 enabled=true;environment.update();assert(owned.edited==nil,'takeover resumes')
end
print('HUD+ real core.runtime: both load orders, callback return values, disable/re-enable passed')
