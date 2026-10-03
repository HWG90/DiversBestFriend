local file=assert(io.open('native-selection-poc/mission_blacklist.lua'));local source=file:read('*a');file:close()
local configure=assert(loadstring(source..'\nreturn mission_blacklist_settings'))()
local specs,values,callbacks={},{},{}
local menu={register_option=function(id,spec)specs[id]=spec;return true end,set=function(id,v)values[id]=v;if callbacks[id]then callbacks[id](v)end;return true end,on_change=function(id,fn)callbacks[id]=fn end}
local saved=0;local state={enabled={[145]=true,[49]=true,[28]=true,[3]=true},save=function()saved=saved+1;return true end}
assert(next(configure(menu,state,nil))==nil)
local count=0;for id,spec in pairs(specs)do count=count+1;assert(spec.type=='toggle' and not spec.choices and not id:find('mission_blacklist_',1,true))end;assert(count==2,'Bingus has exactly two blacklist toggles on the ship')
local prefix='native_stratagem_radial.'
assert(values[prefix..'hide_sos'] and values[prefix..'hide_eagle_rearm'])
local excluded=configure(menu,state,{3,28,49,145});assert(excluded[49] and excluded[145] and not excluded[28] and not excluded[3],'only SOS and Eagle work without MCM')
callbacks[prefix..'hide_eagle_rearm'](false);assert(not configure(menu,state,{49,145})[49] and saved>0)
callbacks[prefix..'hide_eagle_rearm'](true);assert(configure(menu,state,{49})[49]);assert(not configure(menu,state,{145})[49],'absent Eagle is protected')
local native_spec;DBFMCM={api=1,register=function(spec)
 native_spec=spec;local controls,stored={},{};for _,c in ipairs(spec.pages[1].controls)do controls[c.id]=c;stored[c.id]=c.default end
 return {set=function(key,value)local old=stored[key];stored[key]=value;if old~=value then controls[key].on_change(value)end;return true end,get=function(key)return stored[key]end,unregister=function()end}
end}
excluded=configure(menu,state,{3,28,49,145});assert(excluded[28] and not excluded[3] and #native_spec.pages[1].controls==37 and native_spec.pages[1].require_confirmation)
state.native.set('kind_49',false);assert(not values[prefix..'hide_eagle_rearm'] and not configure(menu,state,{49})[49],'native changes sync the Bingus toggle')
callbacks[prefix..'hide_sos'](false);assert(not state.native.get('kind_145'),'Bingus changes sync native MCM')
DBFMCM=nil;assert(not configure(menu,state,{28})[28] and state.enabled[28],'advanced saved selections are preserved but inactive without MCM')
local old_open=io.open;local body;io.open=function(path)return {read=function()return 'version\t1\n1\t49\n2\t145\n3\t28\n'end,close=function()end}end
CowboyBingusModLoader={log_directory='fixture',open_log=function()return {write=function(_,text)body=text;return true end,close=function()end}end}
local migrated={};excluded=configure(menu,migrated,{49,145,28});assert(excluded[49] and excluded[145] and not excluded[28] and migrated.enabled[28]);assert(body:find('version\t2',1,true) and body:find('49\ttrue',1,true))
io.open=old_open;CowboyBingusModLoader=nil
print('Blacklist passed: exactly two static Bingus toggles, 37 optional MCM entries, confirmation, synchronization, mission/equipment guards, migration and shared persistence.')
