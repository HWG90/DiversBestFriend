local function source(name)local f=assert(io.open('native-selection-poc/'..name));local s=f:read('*a');f:close();return s end
local make,interval=assert(loadstring(source('input.lua')..'\n'..source('release.lua')..'\nreturn release_controller,usage_interval'))()
local original=math.random;local rolls=0
math.random=function(a,b)assert(a==70 and b==240);rolls=rolls+1;return rolls%2==1 and 70 or 240 end
assert(interval({interval_ms=25})==25 and rolls==0)
local ended=0
local input={begin_shortcut=function(slot)assert(slot==1 or slot==4);return{kind=25,code={1,2}}end,
 hold_release=function()end,end_release=function()ended=ended+1 end,
 advance_release=function()return false,'entering'end}
local r=make(input,function()end);r.randomize_delay=true
local s={identity=10,open=false}
assert(r.shortcut(1,s,100));assert(r.job.interval_ms==70 and rolls==1)
assert(not r.shortcut(4,s,101)and rolls==1,'held or concurrent shortcut cannot restart a job')
r.step(true,s,nil,101,false);r.step(true,s,nil,120,false)
assert(rolls==1 and r.job.interval_ms==70,'one roll per use, never per direction')
r.reset();assert(ended==1)
assert(r.shortcut(4,s,200));assert(r.job.interval_ms==240 and rolls==2)
r.reset();math.random=original
local configure=assert(loadstring(source('settings.lua')..'\nreturn canary_settings'))()
local values={};local menu={register_option=function()return true end,get=function(k)return values[k]end,set=function(k,v)values[k]=v;return true end}
local state={registered={}};configure(menu,state,{})
values['native_stratagem_radial.randomize_input_delay']=true
assert(configure(menu,state,{}).randomize_input_delay)
values['native_stratagem_radial.input_interval_ms']=100
assert(not configure(menu,state,{}).randomize_input_delay and values['native_stratagem_radial.randomize_input_delay']==false)
print('Usage delay: one 70-240 ms roll per use, no overlapping shortcuts, cleanup, fixed override passed')
