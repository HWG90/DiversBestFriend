local f=assert(io.open('native-selection-poc/settings.lua'));local source=f:read('*a');f:close()
local configure=assert(loadstring(source..'\nreturn canary_settings'))()
local values,registered={},{};local menu={get=function(id) return values[id] end,register_option=function(id,s) registered[#registered+1]=s;return true end}
local state,radial={registered={}},{ }
local v=configure(menu,state,radial);assert(v.select_on_release==false and v.selection_sounds==true and radial.wheel_scale==1)
assert(#registered==15 and registered[1].gap and registered[4].gap and registered[13].gap and registered[14].gap)
values['native_stratagem_radial.appearance_preset']=2;configure(menu,state,radial);assert(radial.wheel_scale==0.85)
values['native_stratagem_radial.wheel_size']=125;configure(menu,state,radial);assert(radial.wheel_scale==0.85)
values['native_stratagem_radial.appearance_preset']=1;configure(menu,state,radial);assert(radial.wheel_scale==1.25)
values['native_stratagem_radial.wheel_size']=0/0;values['native_stratagem_radial.selection_sounds']=false
v=configure(menu,state,radial);assert(radial.wheel_scale==1.25 and v.selection_sounds==false and #registered==15)
print('Settings: grouped registration, presets, custom values, false toggles and bounds passed.')
