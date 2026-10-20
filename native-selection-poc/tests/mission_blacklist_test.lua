local file=assert(io.open('native-selection-poc/mission_blacklist.lua'));local source=file:read('*a');file:close()
local configure=assert(loadstring(source..'\nreturn mission_blacklist_settings'))()
local specs,values,callbacks={},{},{}
local menu={register_option=function(id,spec)specs[id]=spec;return true end,set=function(id,v)values[id]=v;if callbacks[id]then callbacks[id](v)end;return true end,on_change=function(id,fn)callbacks[id]=fn end}
local saved=0;local state={enabled={[145]=true,[49]=true,[28]=true,[3]=true},save=function()saved=saved+1;return true end}
assert(next(configure(menu,state,nil))==nil)
local count=0;for id,spec in pairs(specs)do count=count+1;assert(spec.mod_id=='hwg90.divers_best_friend');assert(spec.type=='toggle' and not spec.choices and not id:find('mission_blacklist_',1,true))end;assert(count==2,'Bingus has exactly two blacklist toggles on the ship')
local prefix='native_stratagem_radial.'
assert(values[prefix..'hide_sos'] and values[prefix..'hide_eagle_rearm'])
local excluded=configure(menu,state,{3,28,49,145});assert(excluded[49] and excluded[145] and not excluded[28] and not excluded[3],'only SOS and Eagle work without MCM')
callbacks[prefix..'hide_eagle_rearm'](false);assert(not configure(menu,state,{49,145})[49] and saved>0)
callbacks[prefix..'hide_eagle_rearm'](true);assert(configure(menu,state,{49})[49]);assert(not configure(menu,state,{145})[49],'absent Eagle is protected')
local native_spec;DBFMCM={api=1,register=function(spec)
 native_spec=spec;local controls,stored={},{};for _,c in ipairs(spec.pages[1].controls)do if c.id then controls[c.id]=c;stored[c.id]=c.default end end
 return {set=function(key,value)local old=stored[key];stored[key]=value;if old~=value then controls[key].on_change(value)end;return true end,get=function(key)return stored[key]end,unregister=function()end}
end}
excluded=configure(menu,state,{3,28,49,145});assert(excluded[28] and not excluded[3] and #native_spec.pages[1].controls==41 and native_spec.pages[1].require_confirmation)
local grouped=native_spec.pages[1].controls;assert(grouped[2].id=='kind_49'and grouped[3].id=='kind_145'and grouped[2].column==1)
local seen,total={},0;for _,c in ipairs(grouped)do if c.id then assert(not seen[c.id]);seen[c.id]=true;total=total+1;assert(c.column==1 or c.column==2)end end;assert(total==37 and grouped[#grouped].column==2,'two columns retain every blacklist option exactly once')
state.native.set('kind_49',false);assert(not values[prefix..'hide_eagle_rearm'] and not configure(menu,state,{49})[49],'native changes sync the Bingus toggle')
callbacks[prefix..'hide_sos'](false);assert(not state.native.get('kind_145'),'Bingus changes sync native MCM')
DBFMCM=nil;assert(not configure(menu,state,{28})[28] and state.enabled[28],'advanced saved selections are preserved but inactive without MCM')
local old_open=io.open;local body;io.open=function(path)return {read=function()return 'version\t1\n1\t49\n2\t145\n3\t28\n'end,close=function()end}end
CowboyBingusModLoader={log_directory='fixture',open_log=function()return {write=function(_,text)body=text;return true end,close=function()end}end}
local migrated={};excluded=configure(menu,migrated,{49,145,28});assert(excluded[49] and excluded[145] and not excluded[28] and migrated.enabled[28]);assert(body:find('version\t2',1,true) and body:find('49\ttrue',1,true))
io.open=old_open;CowboyBingusModLoader=nil
print('Blacklist passed: exactly two static Bingus toggles, 37 optional MCM entries, confirmation, synchronization, mission/equipment guards, migration and shared persistence.')

state.owner={} -- Rebind after the independent migration fixture used the same provider.
local available={49,145}
configure(menu,state,available);callbacks[prefix..'hide_eagle_rearm'](false)
local stable=configure(menu,state,available)
local saves=saved
for i=1,1000 do assert(configure(menu,state,available)==stable) end
assert(saved==saves,'idle blacklist must not persist or rebuild')
assert(configure(menu,state,{49,145})==stable,'same mission resample retains exclusion identity')
callbacks[prefix..'hide_eagle_rearm'](true)
local changed=configure(menu,state,available);assert(changed[49] and changed~=stable)
callbacks[prefix..'hide_eagle_rearm'](false)
assert(not configure(menu,state,available)[49],'applied edit invalidates next frame')
local generation=configure(menu,state,{145});assert(not generation[49])
local provider2={register_option=menu.register_option,set=menu.set,on_change=menu.on_change}
configure(provider2,state,available)
assert(state.owner==provider2 and state.registered[49] and state.registered[145])
print('Blacklist cache: 1000 idle frames, equal availability, edits, mission changes and provider replacement passed.')

-- A real MCM duplicate is reused only when its exact DBF schema is recognized.
local definitions={};local attempts=0
for _,control in ipairs(native_spec.pages[1].controls) do if control.id then definitions[control.id]={id=control.id,type='toggle'} end end
local handle={set=function()return true end,unregister=function()end}
DBFMCM={api=1,mods={dbf_ass_blacklist={id='dbf_ass_blacklist',name="Diver's Best Friend - Blacklist",parent_name="Diver's Best Friend",controls=definitions,handle=handle}},register=function()attempts=attempts+1;error('duplicate registration')end}
local recovering={enabled={},save=function()return true end}
configure(provider2,recovering,{49,145});assert(recovering.native==handle and attempts==0)
local available={49,145}
for i=1,10000 do configure(provider2,recovering,available)end
assert(attempts==0,'adopted DBF menu never enters a registration retry loop')
DBFMCM.mods.dbf_ass_blacklist.name='Foreign owner'
local conflict={enabled={},save=function()return true end}
for i=1,10000 do configure(provider2,conflict,available)end
assert(attempts==0 and conflict.native==nil,'foreign owner is neither replaced nor repeatedly registered')
DBFMCM={api=1,register=function()attempts=attempts+1;error('temporary failure')end}
local unavailable={enabled={},save=function()return true end}
for i=1,10000 do configure(provider2,unavailable,available)end
assert(attempts==1,'registration error is not retried every frame')
print('MCM registration: exact DBF handle reuse, foreign ID protection and 10000 frames without repeated failures passed.')
