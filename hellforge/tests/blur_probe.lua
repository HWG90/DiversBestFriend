local scope=setmetatable({}, {__index=_G})
for _,name in ipairs({'cooldown_gui','blur_probe'}) do
 local f=assert(loadfile('hellforge/hud/'..name..'.lua'));setfenv(f,scope)
 for k,v in pairs(f()) do scope[k]=v end
end
scope.style=dofile('hellforge/hud/hd2_ui_style.lua')
local main,other={},{}
local worlds={main,other}
local command,reads,creates,visible=nil,0,0,false
local primitives,draws,logs={}, {}, {}
local id,fail=0,false
local sr={Application={},World={},Gui={},Material={}}
local A,G=sr.Application,sr.Gui
A.main_world=function()return main end
A.worlds=function()return worlds end
A.can_get=function(_,name)assert(name=='content/ui/shared/material/blur_background');return true end
sr.Vector2=function(...)return {...}end
sr.Vector3=sr.Vector2
sr.Color=sr.Vector2
sr.World.create_screen_gui=function(w,flag,x,y)assert(flag=='scale' and x==1 and y==1);creates=creates+1;return {world=w}end
G.resolution=function()return 3840,2160 end
G.set_visible=function(_,v)visible=v end
G.reset=function()assert(next(primitives)==nil)end
for _,kind in ipairs({'triangle','bitmap','rect'})do
 G[kind]=function(gui,...)
  if fail and kind=='triangle' then error('test submission failure')end
  id=id+1;primitives[id]=kind;draws[#draws+1]={kind=kind,args={...},world=gui.world};return id
 end
 G['destroy_'..kind]=function(_,n)assert(primitives[n]==kind);primitives[n]=nil end
end
G.material=function(_,name)return name end
local scalar,scalar_fail=0,false
sr.Material.set_scalar=function(handle,key,value)
 assert(not visible and handle=='content/ui/shared/material/blur_background' and key=='desaturate' and value==0)
 if scalar_fail then error("scalar failed")end
 scalar=scalar+1
end
local probe=scope.blur_probe({dbf_hud_log=function(s)logs[#logs+1]=s end},{sr=sr,read=function()reads=reads+1;return command end})
probe.step(0);assert(creates==0)
command='1 0\n';probe.step(249);assert(reads==1)
probe.step(250);assert(visible and creates==1 and #draws==3 and scalar==0)
local t=draws[1].args
assert(t[1][1]==1792 and t[1][2]==0 and t[1][3]==952 and t[4]==950 and t[5][1]==255 and t[6]==nil)
probe.step(500);assert(#draws==3,'retained mesh unchanged')
command='2 0';probe.step(750);assert(visible and scalar==1 and #draws==6)
assert(draws[4].args[6]=='content/ui/shared/material/blur_background')
command='3 1';probe.step(1000);assert(visible and scalar==2)
local b=draws[7];assert(b.kind=='bitmap' and b.world==other)
assert(b.args[2][1]==1792 and b.args[2][2]==952 and b.args[2][3]==950 and b.args[3][1]==256)
probe.step(61000);assert(not visible and next(primitives)==nil,'60s deadline expires unchanged command')
probe.step(62000);assert(not visible,'unchanged command cannot rearm')
command='0 0';probe.step(62250)
command='1 0';probe.step(62500);assert(visible)
command=nil;probe.step(62750);assert(not visible and next(primitives)==nil)
for _,bad in ipairs({'1 9','4 0','1 0; print(1)','1 00',' 1 0','1 0\n\n',string.rep('x',64)}) do
 command=bad;probe.step(63000+reads*250);assert(not visible and next(primitives)==nil)
end
local now=100000
command='1 1';probe.step(now);assert(visible)
local before=id
worlds={main};probe.step(now+250);assert(id==before and next(primitives)~=nil,'retired native handles left to engine')
-- The actual engine retires its world primitives; fake that retirement too.
primitives={};visible=false
worlds={main,{}};probe.step(now+500);assert(not visible,'do not silently retarget a new world')
command='0 0';probe.step(now+750)
command='1 0';fail=true;probe.step(now+1000);assert(not visible and next(primitives)==nil)
fail=false;probe.step(now+1250);assert(visible,'submission retry')
probe.hide();assert(not visible and next(primitives)==nil)
command='2 0';scalar_fail=true;probe.step(now+1500)
assert(not visible and next(primitives)==nil,'scalar failure cleans both triangles and reference')
scalar_fail=false;probe.step(now+1750);assert(visible)
probe.hide()
local reloaded=scope.blur_probe({dbf_hud_log=function()end},{sr=sr,read=function()return command end})
reloaded.step(now+61500);assert(not visible,'reload must not extend prior command expiry')
-- Production file reader reads at most64bytes, closes, and never executes data.
local oldio,oldos=scope.io,scope.os
local closed=0
scope.os={getenv=function(k)assert(k=='LOCALAPPDATA');return 'LOCAL' end}
scope.io={open=function(path,mode)
 assert(path=='LOCAL/DBF/HellForge/blur-probe.txt' and mode=='rb')
 return {read=function(_,n)assert(n==64);return string.rep('1',64)end,close=function()closed=closed+1 end}
end}
local disabled=scope.blur_probe({dbf_hud_log=function()end},{sr=sr})
disabled.step(0);assert(closed==1 and not visible)
scope.io,scope.os=oldio,oldos
print('Blur probe: bounded file/grammar/polling/expiry, phase geometry, world retirement, cleanup and retry passed')

for _,fake_os in ipairs({{}, {getenv=function()error('getenv unavailable')end}})do
 scope.os=fake_os
 local absent=scope.blur_probe({dbf_hud_log=function()end},{sr=sr})
 absent.step(0);assert(not visible,'missing environment stays disabled')
end
scope.os=oldos

scope.os={getenv=function()return 'LOCAL'end}
local read_closed=false
scope.io={open=function()return {
 read=function()error('read failure')end,
 close=function()read_closed=true end,
}end}
local broken=scope.blur_probe({dbf_hud_log=function()end},{sr=sr})
broken.step(0);assert(read_closed and not visible,'read failure must close file and stay disabled')
scope.io=false
local noio=scope.blur_probe({dbf_hud_log=function()end},{sr=sr});noio.step(0);assert(not visible)
scope.os=false
local noos=scope.blur_probe({dbf_hud_log=function()end},{sr=sr});noos.step(0);assert(not visible)
scope.io,scope.os=oldio,oldos
