local function source(n) local f=assert(io.open('native-selection-poc/'..n,'rb'));local s=f:read('*a');f:close();return s end
local make=assert(loadstring(source('camera.lua')..'\nreturn camera_capture'))()
local owner,flag,writes=0x100000,0,0
local b={base=0,pointer=function() return owner end,read=function() return string.char(flag) end,
    pulse_byte=function(at,value) assert(at==owner+0x1a9);writes=writes+1;flag=value end}
local camera=make(b)
camera.capture();assert(flag==1 and writes==1)
camera.capture();assert(writes==1,'avoid unnecessary gate writes')
flag=0;camera.capture();assert(flag==1 and writes==2,'reassert after native per-frame reset')
camera.release();assert(flag==0 and writes==3)
flag=1;camera.capture();camera.release();assert(flag==1 and writes==3,'preserve another native menu capture')
flag=0;camera.capture();owner=owner+8;camera.release();assert(writes==4,'never write an old input owner')
local radial=assert(loadstring(source('layout.lua')..'\nreturn radial'))()
local scales={[10]={0.9,0.9},[20]={1,1}}
local opacity={[10]=0.8,[20]=1};local opacity_writes=0
local valid=true
local layout={valid=function() return valid end,get=function(p,k) assert(k=='scale');return scales[p] end,
    set=function(p,k,v) assert(k=='scale','list must never change positions or animations');scales[p]={v[1],v[2]} end}
layout.opacity_targets=function(p)return {p}end -- fixture addresses represent labels
layout.get_opacity=function(p)return opacity[p]end
layout.set_opacity=function(p,v)opacity[p]=v;opacity_writes=opacity_writes+1 end
local list=radial.list_controller(layout)
local s={identity=1,open=true,rows={{address=10},{address=20}}}
radial.selected=10;list.step(true,s);assert(math.abs(scales[10][1]-0.99)<1e-8)
assert(opacity[10]==0.8 and opacity[20]==0.35)
local writes_before=opacity_writes
list.step(true,s);assert(math.abs(scales[10][1]-0.99)<1e-8,'highlight must not grow cumulatively')
assert(opacity_writes==writes_before,'unchanged opacity must stay idle')
radial.selected=20;list.step(true,s);assert(scales[10][1]==0.9 and scales[20][1]==1.1)
assert(opacity[20]==1 and opacity[10]==0.8*0.35)
s.open=false;list.step(true,s);assert(scales[20][1]==1,'close restores stock row')
assert(opacity[10]==0.8 and opacity[20]==1,'close restores opacity')
s.open=true;list.step(true,s);scales[20]={0.8,0.8};list.restore();assert(scales[20][1]==0.8,'preserve a later native change')
list.step(true,s);valid=false;list.restore();assert(scales[20][1]==0.8*1.1,'do not follow a stale owner')
print('Mode helpers passed: native camera gate ownership/reset/release and stock-list highlight/restoration.')

valid=true;opacity[10]=0.8;opacity[20]=1
radial.selected=10;list.step(true,s)
opacity[20]=0.6;list.restore();assert(opacity[20]==0.6,'preserve later native opacity')
list.step(true,s);s.rows={{address=10}};list.step(true,s)
assert(opacity[20]==0.6,'restore removed row')
s.rows={{address=10},{address=20}};list.step(true,s)
radial.selected=nil;list.step(true,s);assert(opacity[20]==0.6,'no selection restores all rows')
radial.selected=10;list.step(true,s);valid=false
local stale=opacity[20];list.restore();assert(opacity[20]==stale,'never restore stale HUD opacity')

-- Native row roots are rewritten after Lua; presentation children stay dim.
valid=true;radial.selected=10
local child_opacity={[11]=1,[12]=1,[21]=1,[22]=1}
layout.opacity_targets=function(p)return {p+1,p+2}end
layout.get_opacity=function(p)return child_opacity[p]end
layout.set_opacity=function(p,v)child_opacity[p]=v end
local child_list=radial.list_controller(layout)
child_list.step(true,s);assert(child_opacity[21]==0.35 and child_opacity[22]==0.35)
opacity[20]=1 -- native root fade reset
child_list.step(true,s);assert(child_opacity[21]==0.35,'native root reset cannot erase dimming')
radial.selected=20;child_list.step(true,s)
assert(child_opacity[21]==1 and child_opacity[11]==0.35,'selection transfers child dimming')
child_list.restore();assert(child_opacity[11]==1 and child_opacity[12]==1,'children restore on close')

local styles={[11]={1,1,1,1},[12]={1,1,1,1},[21]={1,1,1,1},[22]={1,1,1,1},[31]={1,.4,.5,.6},[32]={.8,.4,.5,.6}}
local writes=0
layout.get_text_style=function(p)return {unpack(assert(styles[p]))}end
layout.set_text_style=function(p,v)assert(p~=31 and p~=32,'cooldown text must never be rewritten');styles[p]={unpack(v)};writes=writes+1 end
local styled=radial.list_controller(layout);valid=true;scales[10]={1,1};scales[20]={1,1};scales[30]={1,1}
local snap={identity=2,open=true,rows={{address=10},{address=20},{address=30,timer_kind='cooldown',timer_seconds=60}}}
radial.selected=10;styled.step(true,snap)
assert(styles[21][1]==1 and styles[21][2]==.35 and styles[22][1]==1,'text containers tint without changing native fade alpha')
local n=writes;styled.step(true,snap);assert(writes==n,'unchanged styles perform no writes')
radial.selected=20;styled.step(true,snap);assert(styles[21][2]==1 and styles[11][2]==.35,'text container restores on selection')
styled.restore();assert(styles[11][2]==1 and styles[21][2]==1)
for i=1,50 do
 radial.selected=10;styled.step(true,snap)
 styles[21][1]=.6;styles[22][1]=.7 -- native fade changes only alpha
 radial.selected=20;styled.step(true,snap)
 assert(styles[21][2]==1 and styles[21][1]==.6,'selection restores colour despite native alpha change')
 assert(styles[11][2]==.35,'unselected tint must never compound')
 styles[11][1]=.8;styles[12][1]=.9
 styled.restore();assert(styles[11][2]==1 and styles[11][1]==.8,'close restores colour while preserving fade')
end
print('Cooldown style, child restoration, cooldown no-write and unchanged-state no-write regressions passed')
radial.selected=10;styled.step(true,snap);assert(styles[21][2]==.35)
radial.dim_unselected=false;styled.step(true,snap);assert(styles[21][2]==1,'toggle off immediately restores text')
local idle=writes;styled.step(true,snap);assert(writes==idle,'disabled dimming stays idle')
radial.dim_unselected=true;styled.step(true,snap);assert(styles[21][2]==.35,'toggle on reapplies dimming')
styled.restore()
