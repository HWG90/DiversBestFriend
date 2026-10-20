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
assert(rejected.status:find('HUD+ stratagem adapter unsupported',1,true))
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
local trigger_restores,aim_releases=0,0
local actual_pick=setmetatable({row=7,written=99,
 ui={put=function(_,cell,value) assert(cell==1000 and value==2);trigger_restores=trigger_restores+1 end},
 weapon={manager=function() return 1000 end},n={input_system_rva=1},start=0,
 judge={call=function()aim_releases=aim_releases+1 end}},Pick)
if Pick.frame then actual_pick.hold=2;actual_pick.blocking=true;actual_pick.played=3;actual_pick.wait=0.2 end

local f=assert(io.open('native-selection-poc/hud_plus.lua'));local compat=assert(loadstring(f:read('*a')..'\nreturn hud_plus_compat'))();f:close()
local enabled=true
local c=compat(function() return enabled end)
local original_adapter=c
local opacity,closed,picked={},0,0
local feature=setmetatable({panel={editable=true,mission=100},ui={n={hud_widgets_panels_stratagem_hud_at=20,stratagem_panel_group=4,widget_opacity_default={1}},call=function(_,_,_,v) opacity[#opacity+1]=v end,destroy=function() end,alive=function() return nil end},inputs={prepare=function(_,_,_,select) return select end,observe=function(self) self.showing=true;self.listing=true end},list={close=function() closed=closed+1 end},card={close=function() end},pick=actual_pick},S)
local runtime={installed=true,program={}}
local function update() return runtime.program end
c.refresh(update)
runtime.program={world_hud={stratagem=feature}}
c.refresh(update)
assert(c.status:find('yield'),c.status)
feature.edited=124
assert(feature:prepare(true,{},false,false)==false)
feature:observe(true,{},1,{},false,{})
assert(opacity[1]==1 and feature.edited==nil,'restore hidden vanilla group')
assert(closed==1,'release duplicate and reset competing picker')
assert(actual_pick.row==nil and actual_pick.written==nil,'real pending picker selection cancelled')
if Pick.frame then assert(trigger_restores==1 and aim_releases==1 and actual_pick.hold==nil and actual_pick.played==nil and actual_pick.blocking==false,'paced picker restores menu trigger and aim exactly once') end
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
assert(closed==1,'no disabled-mode cleanup loop introduced')
print('HUD+ real owner feature: takeover, restoration, picker reset, no recreation, disable/resume, 10000 idle frames passed')

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

-- A future release may change presentation code while keeping the proven
-- lifecycle contract. It must not require a new version whitelist entry.
local future=setmetatable({panel=feature.panel,ui=feature.ui,inputs=feature.inputs,
 list=feature.list,card=feature.card,pick=actual_pick,edited=124},S)
local resumed=0
future.observe=function() resumed=resumed+1;return 'future-observe',nil,42 end
future.put=function()return 'future-put',nil,43 end
local future_runtime={installed=true,program={world_hud={stratagem=future}}}
local future_update=(function(runtime)return function()return runtime.program end end)(future_runtime)
local future_adapter=compat(function()return enabled end)
enabled=true;future_adapter.refresh(future_update)
assert(future_adapter.status:find('yield'),future_adapter.status)
future:observe(true,{},1,{},false,{});assert(resumed==0 and future.edited==nil)
local drop_count=closed
for i=1,10000 do future:prepare(true,{},false,false);future:observe(true,{},1,{},false,{});future:put(1,2,{}) end
assert(closed==drop_count,'active handoff never repeats drop/native cleanup')
enabled=false
local a,b,c=future:observe(true,{},1,{},false,{});assert(a=='future-observe' and b==nil and c==42)
a,b,c=future:put(1,2,{});assert(a=='future-put' and b==nil and c==43)
enabled=true;future:observe(true,{},1,{},false,{});assert(closed==drop_count+1)
-- Recreated feature gets one handoff, even under a program successor.
local replacement=setmetatable({panel=feature.panel,ui=feature.ui,inputs=feature.inputs,
 list=feature.list,card=feature.card,pick=actual_pick,edited=124},S)
future_runtime.program={world_hud={stratagem=replacement}}
future_adapter.refresh(future_update);assert(future_adapter.status:find('yield'))
replacement:observe(true,{},1,{},false,{});assert(replacement.edited==nil)
-- Reusing the same feature in another program must not double wrap it.
local wrapper=replacement.prepare
future_runtime.program={world_hud={stratagem=replacement}}
future_adapter.refresh(future_update);assert(replacement.prepare==wrapper)
-- An unfamiliar lifecycle or picker is never partially patched.
for _,target in ipairs({'lifecycle','picker'}) do
 local unknown=setmetatable({panel=feature.panel,ui=feature.ui,inputs=feature.inputs,
  list=feature.list,card=feature.card,pick=actual_pick},S)
 if target=='lifecycle' then unknown.drop=function()error('must not execute unknown cleanup')end
 else unknown.pick={reset=function()error('must not execute unknown picker')end} end
 local runtime={installed=true,program={world_hud={stratagem=unknown}}}
 local function update()return runtime.program end
 local before=unknown.prepare;local adapter=compat(function()return true end)
 adapter.refresh(update);assert(adapter.status:find('unsupported',1,true) and unknown.prepare==before)
end
print('HUD+ contract evolution: changed presentation accepted, unknown cleanup rejected, one-shot handoff, owner recreation, wrapper identity and tuples passed')

local same_program=future_runtime.program
local refreshed=setmetatable({panel=feature.panel,ui=feature.ui,inputs=feature.inputs,
 list=feature.list,card=feature.card,pick=actual_pick,edited=124},S)
same_program.world_hud.stratagem=refreshed
local scan_count=future_adapter.scans
future_adapter.refresh(future_update)
assert(future_adapter.scans==scan_count and refreshed.prepare~=S.prepare,'same-program feature recreation is detected without scanning')
refreshed:observe(true,{},1,{},false,{});assert(refreshed.edited==nil)
print('HUD+ same-program feature generation: immediate rebind without closure rescanning passed')

assert(future_adapter.close())
assert(refreshed.prepare==S.prepare and refreshed.observe==S.observe and refreshed.put==S.put,'reload restores inherited HUD+ methods')
assert(original_adapter.close())
assert(feature.prepare==S.prepare and feature.observe==S.observe,'original adapter restores owner')
print('HUD+ live teardown restores instance methods without class changes')
