local f=assert(io.open('native-selection-poc/settings.lua'));local source=f:read('*a');f:close()
local configure=assert(loadstring(source..'\nreturn canary_settings'))()
local values,registered={},{};local menu={get=function(id) return values[id] end,register_option=function(id,s) registered[#registered+1]=s;return true end}
local state,radial={registered={}},{ }
local v=configure(menu,state,radial);assert(v.select_on_release==false and v.controller_release_auto==true and v.selection_sounds==true and radial.wheel_scale==1)
assert(#registered==29 and registered[1].gap)
assert(v.hide_sos==nil and v.blacklist_kind_1==nil)
values['native_stratagem_radial.appearance_preset']=2;configure(menu,state,radial);assert(radial.wheel_scale==0.85)
values['native_stratagem_radial.wheel_size']=125;configure(menu,state,radial);assert(radial.wheel_scale==0.85)
values['native_stratagem_radial.appearance_preset']=1;configure(menu,state,radial);assert(radial.wheel_scale==1.25)
values['native_stratagem_radial.wheel_size']=0/0;values['native_stratagem_radial.selection_sounds']=false
v=configure(menu,state,radial);assert(radial.wheel_scale==1.25 and v.selection_sounds==false and #registered==29)
print('Settings: grouped registration, presets, custom values, false toggles and bounds passed.')

values['native_stratagem_radial.vertical_offset']=500;configure(menu,state,radial);assert(radial.vertical_offset==500)
local found={};for _,spec in ipairs(registered)do found[spec.label]=true end;assert(found['Appearance / Wheel size (%)']and found['Appearance / Radial vertical offset (down)'])

for _,spec in ipairs(registered) do assert(spec.mod_id=="hwg90.divers_best_friend","Core settings share stable menu identity") end

values['native_stratagem_radial.release_selection_mode']=3
v=configure(menu,state,radial);assert(not v.select_on_release and not v.controller_release_auto)
values['native_stratagem_radial.release_selection_mode']=2
v=configure(menu,state,radial);assert(v.select_on_release and not v.controller_release_auto)
local legacy={get=function(id) if id=='native_stratagem_radial.select_on_release' then return true end end,register_option=menu.register_option}
v=configure(legacy,{registered={}},{ });assert(v.select_on_release and not v.controller_release_auto)
local detect=assert(loadstring((function() local f=assert(io.open('native-selection-poc/pointing.lua'));local s=f:read('*a');f:close();return s end)()..'\nreturn controller_pointing'))()
for k=0,15 do assert(detect(k,0)==(k==1 or k==2)) end
assert(not detect(1,-1) and not detect(1,nil) and not detect(1,32))
print('Automatic controller release, explicit On/Off, legacy On and unknown devices passed.')

-- Event-capable providers perform no reads or derived writes on idle frames.
local reads,subscriptions=0,0
local callbacks={}
local event_menu={get=function(id) reads=reads+1;return values[id] end,
    register_option=function() return true end,
    on_change=function(id,fn) subscriptions=subscriptions+1;callbacks[id]=fn;return true end}
local cached,appearance={registered={}},{ }
local first=configure(event_menu,cached,appearance,0)
local baseline=reads
for i=1,1000 do assert(configure(event_menu,cached,appearance,i)==first) end
assert(reads==baseline and subscriptions==29,'steady settings must stay idle')
values['native_stratagem_radial.enabled']=false
callbacks['native_stratagem_radial.enabled'](false)
assert(not configure(event_menu,cached,appearance,1001).enabled,'disable takes effect on next update')
values['native_stratagem_radial.enabled']=true
callbacks['native_stratagem_radial.enabled'](true)
assert(configure(event_menu,cached,appearance,1002).enabled)
local refreshed=reads
cached.dirty=true;configure(event_menu,cached,appearance,1003)
assert(reads>refreshed and subscriptions==29,'explicit invalidation does not duplicate callbacks')
local old_callback=callbacks['native_stratagem_radial.enabled']
local replacement={get=event_menu.get,register_option=event_menu.register_option,on_change=event_menu.on_change}
configure(replacement,cached,appearance,1004);old_callback(false)
assert(not cached.dirty,'retired provider callbacks cannot invalidate replacement')
local fallback={registered={}}
configure(menu,fallback,{},0);local old=fallback.cached
assert(configure(menu,fallback,{},249)==old)
assert(configure(menu,fallback,{},250)~=old,'notification-free fallback is bounded at 250ms')
print('Settings cache: 1000 idle frames without reads; callbacks, explicit invalidation, provider replacement and bounded fallback passed.')

local opacity
for _,spec in ipairs(registered) do
 if spec.label=='Appearance / Wedge opacity (%)' then opacity=spec end
 if spec.choices and spec.label=='Selection / Mode' then assert(spec.choices[1]=='Wedge Wheel' and spec.choices[2]=='List Select' and spec.choices[3]=='Native wheel') end
end
assert(opacity and opacity.min==0 and opacity.max==100 and opacity.step==5)
values['native_stratagem_radial.wedge_opacity']=35
configure(menu,state,radial)
assert(radial.wedge_opacity==35)

for old=1,3 do
 local stored={['native_stratagem_radial.selection_mode']=old}
 local migration_menu={get=function(id)return stored[id]end,register_option=function(id,spec)
  if id=='native_stratagem_radial.selection_mode_ordered' then stored[id]=spec.default end
  return true
 end}
 local state={registered={}}
 local migrated=configure(migration_menu,state,{})
 assert(migrated.selection_mode==old and stored['native_stratagem_radial.selection_mode_ordered']==4-old)
 for choice=1,3 do
  stored['native_stratagem_radial.selection_mode_ordered']=choice
  assert(configure(migration_menu,state,{}).selection_mode==4-choice)
 end
end
print('Mode ordering and saved selection migration passed.')

local stable_subscriptions=subscriptions
for i=1,100 do configure(event_menu,{registered={}},{},2000+i) end
assert(subscriptions==stable_subscriptions,'reload replaces callback targets without adding provider subscriptions')
print('Reload subscriptions: 100 core generations without callback accumulation passed')

local fresh=configure({get=function()end,register_option=function(_,spec)
 if spec.label=='Selection / Mode' then assert(spec.default==1) end
 if spec.label=='Appearance / Wedge Wheel layout' then assert(spec.default==2) end
 if spec.label=='Appearance / Wedge opacity (%)' then assert(spec.default==50) end
 return true
end},{registered={}},{})
assert(fresh.selection_mode==3 and fresh.experimental_layout==2 and fresh.wedge_opacity==50,'fresh defaults select actual wedge renderer at half opacity')
print('New-user defaults: Wedge Wheel, Expanded wedges, opacity 50; existing selections preserved.')

assert(fresh.cooldown_icons==true)
local off=configure({get=function(id)if id=='native_stratagem_radial.cooldown_icons' then return false end end,register_option=function()return true end},{registered={}},{})
assert(off.cooldown_icons==false,'cooldown dock can be disabled without disabling the wheel')

assert(v.cooldown_timer==2 and v.cooldown_timers==true,"game-font timer labels default above and can be disabled")

assert(v.hide_closed_status==true and v.dock_gap==24)
