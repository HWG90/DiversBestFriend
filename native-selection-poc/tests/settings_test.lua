local f=assert(io.open('native-selection-poc/settings.lua'));local source=f:read('*a');f:close()
local configure=assert(loadstring(source..'\nreturn canary_settings'))()
local values,registered={},{};local menu={get=function(id) return values[id] end,register_option=function(id,s) registered[#registered+1]=s;return true end}
local state,radial={registered={}},{ }
local v=configure(menu,state,radial);assert(v.select_on_release==false and v.selection_sounds==true and radial.wheel_scale==1)
assert(#registered==7 and registered[1].gap and registered[4].gap and registered[6].gap and registered[7].gap)
assert(v.hide_sos==nil and v.blacklist_kind_1==nil)
values['native_stratagem_radial.appearance_preset']=2;configure(menu,state,radial);assert(radial.wheel_scale==0.85)
values['native_stratagem_radial.wheel_size']=125;configure(menu,state,radial);assert(radial.wheel_scale==0.85)
values['native_stratagem_radial.appearance_preset']=1;configure(menu,state,radial);assert(radial.wheel_scale==1.25)
values['native_stratagem_radial.wheel_size']=0/0;values['native_stratagem_radial.selection_sounds']=false
v=configure(menu,state,radial);assert(radial.wheel_scale==1.25 and v.selection_sounds==false and #registered==7)
print('Settings: grouped registration, presets, custom values, false toggles and bounds passed.')

values['native_stratagem_radial.vertical_offset']=500;configure(menu,state,radial);assert(radial.vertical_offset==0)
for _,spec in ipairs(registered) do assert(not spec.label:find('Wheel size',1,true) and not spec.label:find('Icon size',1,true) and not spec.label:find('Center label',1,true) and not spec.label:find('vertical offset',1,true)) end
