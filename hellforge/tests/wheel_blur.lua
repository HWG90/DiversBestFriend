-- Exercise the actual retained GUI owner and the exact textured Gui.triangle ABI.
local scope=setmetatable({_G={}}, {__index=_G})
for _,name in ipairs({'cooldown_gui','wheel_expanded'}) do
    local chunk=setfenv(assert(loadfile('hellforge/hud/'..name..'.lua')),scope)
    for k,v in pairs(chunk()) do scope[k]=v end
end
scope.radial={wheel_scale=1,vertical_offset=0}
scope.style=dofile('hellforge/hud/hd2_ui_style.lua')
local prepass='content/ui/shared/material/gui_blur'
local preferred='content/ui/shared/material/blur_background'
local fallback=preferred
local available,world,probes,creates,next_id=nil,{},0,0,0
local triangles,vertices={},{}
local fail_at,visible,reject,return_nil,last_material,scalar_fail,configured
local scalar_calls=0
local function available_material(name) return available=="both" or available==name end
local sr={Gui={},Application={},World={},Material={}}
scope._G.stingray=sr
sr.Application.worlds=function() return {world} end
sr.Application.main_world=function() return world end
sr.Application.can_get=function(kind,name)
    assert(kind=='material' and name==preferred,'never probe the incompatible transparent_pre material')
    probes=probes+1
    return available_material(name)
end
sr.World.create_screen_gui=function(w) assert(w==world);creates=creates+1;return {} end
sr.Gui.set_visible=function(_,v)
    if v then assert(configured,'never show a grayscale or unconfigured blur material') end
    visible=v
end
sr.Gui.material=function(_,name)
    assert(available_material(name) and next(triangles))
    last_material=name;configured=false
    return name~=reject and {name=name} or false
end
sr.Material.set_scalar=function(handle,name,value)
    assert(handle.name==preferred and name=='desaturate' and value==0 and not visible)
    scalar_calls=scalar_calls+1
    if scalar_fail then error('parameter unavailable') end
    configured=true
end
sr.Gui.resolution=function() return 1920,1080 end
sr.Gui.reset=function() assert(next(triangles)==nil) end
sr.Vector2=function(x,y) return {x,y} end
sr.Vector3=function(x,y,z) return {x,y,z} end
sr.Color=function(a,r,g,b) return {a,r,g,b} end
sr.Gui.triangle=function(_,a,b,c,z,tint,name,ua,ub,uc)
    assert(z==0x225 and available_material(name))
    for i,vertex in ipairs({a,b,c}) do
        local uv=({ua,ub,uc})[i]
        assert(vertex[2]==0 and uv[1]==vertex[1]/1920 and uv[2]==vertex[3]/1080)
    end
    next_id=next_id+1
    if next_id==fail_at then
        assert(name==preferred)
        if return_nil then return nil end
        error('GPU probe failed')
    end
    vertices[#vertices+1]={a,b,c,tint[1]}
    triangles[next_id]=true
    return next_id
end
sr.Gui.destroy_triangle=function(_,id) assert(triangles[id]);triangles[id]=nil end

local blur=scope.wheel_blur()
local plane={1,0,0,1,960,540}
local function draw(count,expanded,alpha,t)
    local source={list_geometry={width=100,height=30,matrix=plane},center={-50,-15}}
    blur.draw(source,count,expanded,alpha,t)
end
draw(1,false,0,0)
assert(probes==0 and creates==0)
draw(3,false,0.4,1);draw(3,false,0.4,200)
assert(probes==1 and creates==0,'negative probe cached')
available=fallback
draw(3,false,0.4,5001)
assert(probes==2 and creates==1 and visible and #vertices==96)
for _,tri in ipairs(vertices) do assert(tri[4]==102,'native opacity applies once to the entire plate') end
draw(3,false,0.4,5002);assert(#vertices==96 and probes==2,'static HUD retains its mesh')

-- Recover wedge-local geometry from an inherited nonuniform transform,
-- vertical offset and tangential squeeze. Test the chords as well as vertices.
scope.radial.wheel_scale=1.2;scope.radial.vertical_offset=35
plane={1.25,0.1,-0.15,0.75,950,500}
for _,count in ipairs({1,8,9,16}) do
    vertices={}
    draw(count,true,0.5,5010)
    local sectors=math.max(8,count)
    assert(#vertices==sectors*12)
    for i,tri in ipairs(vertices) do
        local slot=math.floor((i-1)/12)+1
        assert(tri[4]==(slot>count and 34 or 128),'empty and occupied sector coverage')
        local angle=math.rad(90-(slot-1)*360/sectors)
        local stretch=math.tan(math.pi/sectors*0.97)/math.tan(math.pi/8)
        for j=1,3 do
            local a,b=tri[j],tri[j%3+1]
            for _,t in ipairs({0,0.5,1}) do
                local x=a[1]+(b[1]-a[1])*t-plane[5]
                local y=a[3]+(b[3]-a[3])*t-plane[6]
                local det=plane[1]*plane[4]-plane[2]*plane[3]
                local dx=(x*plane[4]-y*plane[3])/det/1.2
                local dy=((y*plane[1]-x*plane[2])/det+35)/1.2
                local u=dx*math.cos(angle)+dy*math.sin(angle)
                local v=(-dx*math.sin(angle)+dy*math.cos(angle))/stretch
                local radius=math.sqrt(u*u+v*v)
                assert(radius>119 and radius<255.01 and math.abs(math.deg(math.atan2(v,u)))<21.01)
            end
        end
    end
end
blur.hide();assert(not visible and next(triangles)==nil)
available='both'
for _,missing_id in ipairs({false,true}) do
    world={};return_nil=missing_id;fail_at=next_id+5
    local before=probes
    assert(not pcall(draw,8,false,1,5100))
    assert(not visible and next(triangles)==nil,'partial mesh must be removed')
    draw(8,false,1,6100)
    assert(not visible and probes==before+1,'failure retry waits five seconds')
    draw(8,false,1,10100)
    assert(visible and probes==before+2 and last_material==preferred,'retry stays on transparent material')
    blur.hide();blur.hide();assert(not visible and next(triangles)==nil)
end
local before=probes
world={};reject=preferred
draw(8,false,1,11000);assert(not visible and next(triangles)==nil,'unbound triangles must stay hidden')
reject=nil
draw(8,false,1,16000);assert(visible and probes==before+2,'binding failure recovers after delay')
blur.hide()
scalar_fail=true;world={}
draw(8,false,1,17000)
assert(not visible and next(triangles)==nil,'parameter failure must clean every retained primitive')
scalar_fail=false
draw(8,false,1,22000);assert(visible,'parameter setup retries without losing cleanup')
blur.hide()
-- Having only the native prepass material cannot silently select it again.
world={};available=prepass
before=creates;draw(8,false,1,23000)
assert(creates==before and not visible,'unavailable transparent pass stays hidden')
print('Transparent-pass wedge material, color parity, clipping, opacity and teardown passed')

-- Stage diagnostics must remain quiet across retained and rebuilt geometry.
local logs={}
blur=scope.wheel_blur(function(message) logs[#logs+1]=message end)
local function contains(fragment)
    for _,message in ipairs(logs) do
        if message:find(fragment,1,true) then return true end
    end
    return false
end
available=fallback;reject=nil;fail_at=nil
local triangle_api=sr.Gui.triangle
sr.Gui.triangle=nil
draw(8,true,0.5,10000)
assert(contains('api: invalid: Gui.triangle'))
local n=#logs
draw(8,true,0.5,10001);assert(#logs==n,'invalid API gate logs once')
sr.Gui.triangle=triangle_api
available=nil
draw(8,true,0.5,10002)
assert(contains('material: unavailable'))
n=#logs
draw(8,true,0.5,10003);draw(8,true,0.5,15003)
assert(#logs==n,'negative material retries must not repeat diagnostics')
available=fallback
draw(8,true,0.5,20003)
for _,fragment in ipairs({'api: ready','world:','material: selected:',
    'triangles: submitted: 96','binding: bound:','parameters: desaturate=0','activation: active'}) do
    assert(contains(fragment),fragment)
end
n=#logs
draw(8,true,0.5,20004)
plane[5]=plane[5]+1
draw(8,true,0.5,20005)
assert(#logs==n,'retention and moving geometry must not repeat stage logs')
blur.hide();assert(#logs==n+1 and contains('activation: inactive'))
blur.hide();assert(#logs==n+1,'repeated cleanup must be quiet')
draw(8,true,0.5,20006);assert(#logs==n+2,'reopening logs activation only')
blur.hide();world={};reject=fallback
draw(8,true,0.5,20007)
assert(contains('binding: failed:') and not visible and next(triangles)==nil)
reject=nil
draw(8,true,0.5,25008)
assert(visible,'binding rejection retains delayed recovery')
blur.hide()
print('Blur stage diagnostics deduplicate gates, retries and moving geometry; binding recovery passes')
