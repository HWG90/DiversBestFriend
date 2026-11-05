-- Exercise the actual retained GUI owner and the exact textured Gui.triangle ABI.
local scope=setmetatable({_G={}}, {__index=_G})
for _,name in ipairs({'cooldown_gui','wheel_expanded'}) do
    local chunk=setfenv(assert(loadfile('hellforge/hud/'..name..'.lua')),scope)
    for k,v in pairs(chunk()) do scope[k]=v end
end
scope.radial={wheel_scale=1,vertical_offset=0}
scope.style=dofile('hellforge/hud/hd2_ui_style.lua')
local preferred='content/ui/shared/material/gui_blur'
local fallback='content/ui/shared/material/blur_background'
local available,world,probes,creates,next_id=nil,{},0,0,0
local triangles,vertices={},{}
local fail_at,visible,reject
local sr={Gui={},Application={},World={}}
scope._G.stingray=sr
sr.Application.worlds=function() return {world} end
sr.Application.main_world=function() return world end
sr.Application.can_get=function(kind,name)
    assert(kind=='material' and (name==preferred or name==fallback))
    probes=probes+1
    return name==available
end
sr.World.create_screen_gui=function(w) assert(w==world);creates=creates+1;return {} end
sr.Gui.set_visible=function(_,v) visible=v end
sr.Gui.material=function(_,name) assert(name==available and next(triangles));return name~=reject end
sr.Gui.resolution=function() return 1920,1080 end
sr.Gui.reset=function() assert(next(triangles)==nil) end
sr.Vector2=function(x,y) return {x,y} end
sr.Vector3=function(x,y,z) return {x,y,z} end
sr.Color=function(a,r,g,b) return {a,r,g,b} end
sr.Gui.triangle=function(_,a,b,c,z,tint,name,ua,ub,uc)
    assert(z==0x225 and name==available)
    for i,vertex in ipairs({a,b,c}) do
        local uv=({ua,ub,uc})[i]
        assert(vertex[2]==0 and uv[1]==vertex[1]/1920 and uv[2]==vertex[3]/1080)
    end
    next_id=next_id+1
    if next_id==fail_at then error('GPU probe failed') end
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
assert(probes==2 and creates==0,'negative probe cached')
available=fallback
draw(3,false,0.4,5001)
assert(probes==4 and creates==1 and visible and #vertices==96)
for _,tri in ipairs(vertices) do assert(tri[4]==102,'native opacity applies once to the entire plate') end
draw(3,false,0.4,5002);assert(#vertices==96 and probes==4,'static HUD retains its mesh')

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
world={};available=preferred;vertices={}
fail_at=next_id+5
assert(not pcall(draw,8,false,1,5100))
blur.hide();assert(not visible and next(triangles)==nil,'partial construction remains owned')
draw(8,false,1,5101)
assert(visible and probes==5,'new world uses the preferred material')
blur.hide();blur.hide();assert(not visible and next(triangles)==nil)
world={};reject=preferred
draw(8,false,1,5200);assert(not visible and next(triangles)==nil,'unbound triangles must stay hidden')
available=fallback
draw(8,false,1,5201);assert(visible and probes==7,'alternate material after GUI binding failure')
blur.hide()
print('Retained textured wedge blur, material fallback, transformed clipping, opacity and teardown passed')
