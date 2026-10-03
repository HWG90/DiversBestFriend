local f=assert(io.open('native-selection-poc/mission_blacklist.lua'));local source=f:read('*a');f:close()
local configure=assert(loadstring(source..'\nreturn mission_blacklist_settings'))()
local specs,values,callbacks={},{},{}
local saved=0
local menu={register_option=function(id,spec) specs[id]=spec;return true end,
    set=function(id,v) values[id]=v;return true end,
    on_change=function(id,fn) callbacks[id]=fn;return true end}
local state={kinds={145,28,3},save=function() saved=saved+1;return true end}
local excluded=configure(menu,state,{3,28,145})
assert(excluded[145] and excluded[28] and not excluded[3])
local n=0
for id,s in pairs(specs) do
    n=n+1;assert(s.type=='choice' and #s.choices==3 and s.choices[1]=='None')
    assert(s.choices[2]=='SEAF Artillery' and s.choices[3]=='SOS Beacon')
    assert(not id:find('hide_sos',1,true))
end
assert(n==3 and state.kinds[3]==0 and values['native_stratagem_radial.mission_blacklist_3']==1)
callbacks['native_stratagem_radial.mission_blacklist_1'](1)
excluded=configure(menu,state,{28,145})
assert(not excluded[145] and excluded[28] and saved>=2,'None clears SOS; applies persist stable IDs')
excluded=configure(menu,state,{3})
assert(next(excluded)==nil,'mission changes cannot exclude equipment or absent entries')
excluded=configure(menu,state,nil)
assert(next(excluded)==nil,'unreadable ownership fails safe')
assert(#state.choices==3,'indices cannot be remapped during a game session')
local prefix='native_stratagem_radial.'
local old_open=io.open
io.open=function(path)
    if path:find('DiversBestFriendBlacklist.log',1,true) then return nil end
    if path:find('ModOptionsMenu.values',1,true) then
        return {read=function() return prefix..'blacklist_kind_1\t3\n'..prefix..'blacklist_kind_2\t28\n'..prefix..'hide_sos\ttrue\n' end,close=function() end}
    end
    return old_open(path)
end
local old_loader=CowboyBingusModLoader
local body
CowboyBingusModLoader={log_directory='fixture',open_log=function() return {write=function(_,s) body=s;return true end,close=function() end} end}
local migrated={}
excluded=configure(menu,migrated,{28,145})
assert(excluded[28] and excluded[145] and not excluded[3],'legacy SOS migrates, equipped exclusions discarded')
assert(body:find('version\t1',1,true))
io.open=function(path)
    return {read=function() return body end,close=function() end}
end
local restarted={}
excluded=configure(menu,restarted,{145,28})
assert(excluded[28] and excluded[145],'restart reads native IDs independently of choice ordering')
io.open=old_open;CowboyBingusModLoader=old_loader
print('Mission blacklist: three named choices, None/SOS, equipment protection, ownership failure, migration, persistence and index stability passed.')

local eagle={kinds={49,0,0},save=function()return true end}
local eagle_excluded=configure(menu,eagle,{3,49,145})
assert(eagle.choices[2]=='Eagle Rearm' and eagle.ids[2]==49 and eagle_excluded[49] and not eagle_excluded[3])
callbacks['native_stratagem_radial.mission_blacklist_1'](1)
assert(not configure(menu,eagle,{49,145})[49],'None clears Eagle Rearm')
callbacks['native_stratagem_radial.mission_blacklist_1'](2)
assert(configure(menu,eagle,{49,145})[49],'Eagle Rearm persists by native ID')
assert(not configure(menu,eagle,{145})[49],'Absent Eagle Rearm cannot be filtered')
print('Eagle Rearm: named choice, stable kind 49, selection, None, absence guard and equipment protection passed.')
