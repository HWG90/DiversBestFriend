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
local valid=true
local layout={valid=function() return valid end,get=function(p,k) assert(k=='scale');return scales[p] end,
    set=function(p,k,v) assert(k=='scale','list must never change positions or animations');scales[p]={v[1],v[2]} end}
local list=radial.list_controller(layout)
local s={identity=1,open=true,rows={{address=10},{address=20}}}
radial.selected=10;list.step(true,s);assert(math.abs(scales[10][1]-0.99)<1e-8)
list.step(true,s);assert(math.abs(scales[10][1]-0.99)<1e-8,'highlight must not grow cumulatively')
radial.selected=20;list.step(true,s);assert(scales[10][1]==0.9 and scales[20][1]==1.1)
s.open=false;list.step(true,s);assert(scales[20][1]==1,'close restores stock row')
s.open=true;list.step(true,s);scales[20]={0.8,0.8};list.restore();assert(scales[20][1]==0.8,'preserve a later native change')
list.step(true,s);valid=false;list.restore();assert(scales[20][1]==0.8*1.1,'do not follow a stale owner')
print('Mode helpers passed: native camera gate ownership/reset/release and stock-list highlight/restoration.')
