local function source(path)
    local f=assert(io.open('native-selection-poc/'..path,'rb'))
    local text=f:read('*a'); f:close(); return text
end
local radial=assert(loadstring(source('layout.lua')..'\nreturn radial'))()
radial.vertical_offset=0 -- Existing geometry/controller fixtures use unshifted center.
local checks=0
local function check(value,message) checks=checks+1; assert(value,message) end
for count=0,16 do
    local rows={}
    for i=1,count do rows[i]={address=i,width=355,height=100} end
    local layout=radial.layout(rows)
    check(#layout==count,'membership')
    for _,row in ipairs(layout) do
        local p,s=row.position,row.scale[1]
        check(p[1]==p[1] and p[2]==p[2],'finite')
        check(p[1]-355*s/2>=-960 and p[1]+355*s/2<=960,'horizontal bounds at reference 1920x1080')
        check(p[2]+100*s/2<=540 and p[2]-100*s/2>=-540,'vertical bounds at reference 1920x1080')
    end
end
-- Screen-centering regression: native ancestor offsets and scale must not
-- translate the ring away from the viewport midpoint.
for _,width in ipairs({1920,2849,3440}) do
    for _,scale in ipairs({0.65,1,1.8}) do
        local viewport={width=width,height=1080,matrix={1.3,0,0,1.3,17,39}}
        local list={width=355,height=544,matrix={scale,0,0,scale,-710,200}}
        local center=radial.center(viewport,list)
        local rows={}
        for i=1,8 do rows[i]={address=i,width=270,height=68} end
        local x,y=0,0
        for _,row in ipairs(radial.layout(rows,center)) do
            x=x+(row.position[1]+list.width/2)*scale-710
            y=y+(row.position[2]+list.height/2)*scale+200
        end
        check(math.abs(x/8-(width*1.3/2+17))<0.001,'screen center X across viewport widths and scales')
        check(math.abs(y/8-(1080*1.3/2+39))<0.001,'screen center Y across viewport widths and scales')
    end
end
check(not pcall(radial.center,{width=1920,height=1080,matrix={1,0,0,1,0,0}},
    {width=1,height=1,matrix={0,0,0,0,0,0}}),'reject singular transforms')
local state,valid,writes={},true,0
local snapshot={identity=1,panel=10,list=20,open=true,rows={
    {address=30,width=355,height=100},{address=40,width=355,height=100}}}
local backend={}
function backend.valid(id) return valid and id==snapshot.identity end
function backend.snapshot() return snapshot end
function backend.get(address,property)
    local key=address..':'..property
    state[key]=state[key] or {12,34}
    return {state[key][1],state[key][2]}
end
function backend.set(address,property,value)
    writes=writes+1;state[address..':'..property]={value[1],value[2]}
end
local controller=radial.controller(backend)
controller.step(true)
check(controller.count==2 and #controller.saved==12,'initial layout')
radial.vertical_offset=200
controller.step(true)
check(math.abs(state['30:position'][2]-80)<0.001,'positive offset lowers card by 200 HUD units')
check(state['30:animation_a'][2]==state['30:position'][2] and
    state['30:animation_b'][2]==state['30:position'][2],'offset applies to both animation endpoints')
radial.vertical_offset=0
controller.step(true)
check(state['10:position']==nil and state['20:position']==nil,'never reposition the native panel or list')
check(state['20:size']==nil,'native list dimensions must be left alone')
-- Regression for the user's POC1 screenshot: the native update runs AFTER
-- our callback and regenerates each card position from its animation data.
local expected=radial.layout(snapshot.rows)
for _,blend in ipairs({0,0.25,0.5,0.75,1}) do
    for i,row in ipairs(snapshot.rows) do
        local a,b=backend.get(row.address,'animation_a'),backend.get(row.address,'animation_b')
        local p={blend*a[1]+(1-blend)*b[1],blend*a[2]+(1-blend)*b[2]}
        backend.set(row.address,'position',p)
        check(math.abs(p[1]-expected[i].position[1])<0.001 and
            math.abs(p[2]-expected[i].position[2])<0.001,'native animation must preserve radial layout')
    end
end
snapshot.rows={snapshot.rows[1]}
controller.step(true)
check(state['40:position'][1]==12 and state['40:scale'][1]==12,'removed card restored')
check(state['40:animation_a'][1]==12 and state['40:animation_b'][2]==34,'removed animation endpoints restored')
state['30:position']={77,88} -- native animation advanced
controller.step(true)
controller.step(false)
check(state['30:position'][1]==77,'restore most recent native layout')
check(state['30:animation_a'][1]==12 and state['30:animation_b'][2]==34,'disable restores native animation')
check(state['30:anchor'][1]==12 and #controller.saved==0,'disable restores')
controller.step(true)
state['30:anchor']={99,99} -- another owner changed a property
snapshot.open=false
controller.step(true)
check(state['30:anchor'][1]==99,'do not overwrite another owner')
snapshot.open=true
controller.step(true)
valid=false
local before=writes
controller.restore()
check(writes==before,'invalid HUD must never be written during restore')
valid=true
controller.step(true)
snapshot.identity=2
before=writes
controller.restore()
check(writes==before,'replacement HUD must never receive stale writes')

-- LuaJIT must be able to parse the complete packaged addon.
check(loadfile('native-selection-poc/NativeStratagemRadial.lua')~=nil,'packaged Lua syntax')

-- Run the entry wrapper with a simulated native backend, including nil returns.
local env=setmetatable({}, {__index=_G})
env._G=env
env.update=function(...) check(select('#',...)==3,'forward update arguments');return nil,'kept',42 end
local chunk=assert(loadstring(source('layout.lua')..'\n'..
    'local native_backend=function() return fixture_backend end\n'..source('entry.lua')))
env.fixture_backend=backend
setfenv(chunk,env);chunk()
local function results(...) check(select('#',...)==3,'return arity');local a,b,c=...;check(a==nil and b=='kept' and c==42,'return values') end
results(env.update(0.016,nil,'argument'))
backend.snapshot=function() error('simulated read failure') end
results(env.update(0.016,nil,'argument'))
check(env.NativeStratagemRadial.status:find('disabled after error',1,true)~=nil,'error isolation')
results(env.update(0.016,nil,'argument')) -- previous callback still runs
print('Native radial POC: '..checks..' checks passed')
