local ffi=require('ffi')
ffi.cdef 'typedef struct { float x,y; } NSR_vec2;'
local function source(n) local f=assert(io.open('native-selection-poc/'..n,'rb'));local s=f:read('*a');f:close();return s end
local base,id,parent,resource=0x10000000,0x20000000,0x21000000,0x30000000
local links,props,shown,angles={},{},{},{}
local in_scope,constructors,sprites=false,0,0
local native={}
native[0x1446840]=function(p,t)
    assert(in_scope and p%16==0 and t==1);constructors=constructors+1;props[p]={};links[p+0xf8]=resource
end
native[0x143eab0]=function(p)
    assert(in_scope and p%16==0);sprites=sprites+1;props[p]={};links[p+0xf8]=resource
end
native[0x144c5c0]=function(p,c)
    assert(in_scope and not links[c+0xf0]);links[c+0xf0]=p
end
native[0x144c2c0]=function() assert(in_scope) end
native[0x144cfb0]=function(p,v) assert(props[p]);shown[p]=v end
native[0x1448ad0]=function(p,v) assert(in_scope and props[p]);props[p].opacity=v end
native[0x1448ef0]=function(p,v) assert(in_scope and props[p]);angles[p]=v end
native[0x14481a0]=function(p,v) assert(in_scope);props[p].rotation_pivot={v.x,v.y} end
native[0x14491f0]=function(p,v) assert(in_scope);props[p].order=v end
native[0x1448690]=function(p,v) assert(in_scope);props[p].color={v[0],v[1],v[2]} end
native[0x144f800]=function(p,hash,flag) assert(in_scope and flag==0);props[p].asset=hash end
native[0x1450230]=function(p,material,hash,flag) assert(in_scope and flag==0);props[p].texture=tonumber(hash) end
local proxy=setmetatable({}, {__index=ffi})
proxy.cast=function(t,v)
    if t:find('(*)',1,true) then return assert(native[v-base],'unexpected native call') end
    return ffi.cast(t,v)
end
local b={base=base,valid=function(i) return i==id end,pointer=function(p) return links[p] end,
read=function(p,n) return ffi.string(ffi.new('uint64_t[1]',links[p] or 0),n) end,
set=function(p,k,v) assert(in_scope and props[p] and p~=parent,'never modify original widgets');props[p][k]=v end}
local scope={context_scope=function(p,fn)
    assert(p==parent and not in_scope);in_scope=true
    local ok,value=pcall(fn,resource);in_scope=false;assert(ok,value);return value
end}
local input={presentation=function(k) return {label=k,texture=ffi.string(ffi.new('uint64_t[1]',k),8)} end}
local env=setmetatable({require=function() return proxy end,radial={vertical_offset=575,full_color=false}},{__index=_G})
local chunk=assert(loadstring(source('input.lua')..source('icon_colors.lua')..source('expanded.lua')..source('selection.lua')..'\nreturn expanded_wheel,expanded_index,expanded_geometry,selection_controller'))
setfenv(chunk,env);local make,point,geometry,make_selection=chunk()
local checks=0
for n=0,16 do
    local rows={};for i=1,n do rows[i]={address=i,kind=i} end
    local sectors=math.max(8,n)
    for i=1,sectors do
        local angle,k,pos=geometry(n,i)
        local index=point(rows,{pos[1]/185,pos[2]/185})
        assert(index==(i<=n and i or nil),'icon center and angular selection disagree')
        -- Width of the centered native boundary rays after artwork correction:
        -- shrink Y, then rotate to the target center. Width must match sector.
        local half=math.atan2(math.sin(math.pi/8)*k,math.cos(math.pi/8))
        assert(math.abs(half-math.pi/sectors*0.97)<1e-8,'wedge transform width')
        checks=checks+1
    end
    assert(point(rows,{0,0})==nil and point(rows,{0.1,0.1})==nil)
end
assert(not pcall(geometry,17,1),'capacity bounded')
local rows={}
for i=1,16 do rows[i]={address=100+i,kind=i,entry=i-1,list_y=i*68} end
local snap={identity=id,list=parent,open=true,center={1000,300},rows=rows}
local w=make(b,scope,input)
local prepared,changed=w.prepare(snap)
assert(changed and constructors==33 and sprites==32 and #prepared.rows==16)
assert(prepared.rows[1].kind==16 and prepared.rows[16].kind==1,'stable visual row order')
local root
for p in pairs(props) do if links[p+0xf0]==parent then root=p end end
assert(root and props[root].position[2]==-275)
local turn=root+0x110
assert(angles[turn]==-90 and angles[turn+0x220]==67.5)
assert(math.abs(props[turn+0x110].scale[2]-math.tan(math.pi/16*0.97)/math.tan(math.pi/8))<1e-8)
assert(props[turn+0x380].texture==16)
-- Independent observed native transform model: positive native rotations are
-- CLOCKWISE, with an authored 67.5-degree sector bisector. These two historical
-- screenshots disambiguate phase from handedness: r17 NW selected -> SE art;
-- r18 W selected -> N art. Both must reproduce before testing the correction.
local function native_ray(pre,parent,scale)
    local raw=math.rad(67.5-pre)
    local x,y=math.cos(raw),math.sin(raw)*scale
    local a=math.rad(-parent)
    return x*math.cos(a)-y*math.sin(a),x*math.sin(a)+y*math.cos(a)
end
local x,y=native_ray(-22.5,135,1)
assert(x>0 and y<0,'r17 screenshot: NW selection had SE artwork')
x,y=native_ray(157.5,180,1)
assert(math.abs(x)<1e-8 and y>0,'r18 screenshot: W selection had N artwork')
for n=8,16 do
    for i=1,n do
        local angle,scale,icon=geometry(n,i)
        local wx,wy=native_ray(67.5,-angle,scale)
        assert(wx*icon[1]+wy*icon[2]>184.99,'corrected native art must face icon for every sector count')
    end
end
for i=1,16 do
    local group=root+0x110+(i-1)*0x4e0
    local wx,wy=native_ray(angles[group+0x220],angles[group],props[group+0x110].scale[2])
    local icon=props[group+0x380].position
    assert(wx*icon[1]+wy*icon[2]>184.99,'actual native calls must align wedge and icon')
end
local eight={};for i=1,8 do eight[i]={address=i,kind=i} end
assert(point(eight,{-1,1})==8,'screenshot NW cursor selects NW Autocannon slot')

assert(w.draw(prepared.rows[16].address,prepared.rows)==1,'last slot caption kind')
local last_wedge=root+0x110+15*0x4e0+0x220
assert(props[last_wedge].opacity==0.95 and props[turn+0x220].opacity==0.75,'darker defaults preserve selection')
assert(math.abs(props[turn+0x220].color[1]-0.15)<1e-6,'default darkness reduces background RGB')
local wedge=turn+0x220
local original_selection=prepared.rows[16].address
for _,darkness in ipairs({0,70,100}) do
    for _,alpha in ipairs({0,30,75,100}) do
        env.radial.wedge_darkness,env.radial.wedge_opacity=darkness,alpha
        assert(w.draw(original_selection,prepared.rows)==1,'appearance never changes selected kind')
        assert(math.abs(props[wedge].color[1]-0.5*(1-darkness/100))<1e-6,'darkness independently controls RGB')
        assert(math.abs(props[wedge].opacity-alpha/100)<1e-6,'opacity independently controls alpha')
        assert(props[last_wedge].color[1]==1 and props[last_wedge].opacity>=0.95,'selection stays visible at every setting')
        assert(props[turn+0x380].opacity==0.8,'background settings do not fade icons')
    end
end
env.radial.wedge_darkness,env.radial.wedge_opacity=0,30
w.draw(original_selection,prepared.rows)
assert(props[wedge].color[1]==0.5 and props[wedge].opacity==0.3,'legacy appearance remains available')
prepared,changed=w.prepare(snap);assert(not changed and sprites==32,'reuse owned widgets')
local started
local selection=make_selection({begin=function(k) started=k;return {kind=k} end},function() end)
local idle={next=false,previous=false,confirm=false}
local confirm={next=false,previous=false,confirm=true}
local _,_,pos=geometry(16,16)
local vector={pos[1]/185,pos[2]/185}
selection.step(prepared,idle,0,vector);selection.step(prepared,confirm,1,vector)
assert(started==1,'Confirm reaches the sixteenth slot')
for i=16,10,-1 do table.remove(rows,i) end
prepared,changed=w.prepare(snap);assert(changed and w.count==9)
assert(shown[root+0x110+9*0x4e0]==0,'removed sectors hidden')
for i=9,4,-1 do table.remove(rows,i) end
prepared=w.prepare(snap)
local empty=root+0x110+3*0x4e0+0x220
w.draw(nil,prepared.rows)
assert(math.abs(props[empty].opacity-0.08)<1e-6,'empty sectors preserve relative dimming')
assert(shown[root+0x110+3*0x4e0]==1 and shown[root+0x110+3*0x4e0+0x380]==0,'empty sectors have no icon')
assert(point(prepared.rows,{-1,0})==nil,'empty sector cannot select')
w.hide();assert(shown[root]==0)
w.prepare(snap);assert(constructors==33,'reopen reuses storage')
id=id+8;w.hide();assert(shown[root]==1,'stale owner is never mutated')
print('Expanded wedges passed: '..checks..' geometry/selection checks, 16-slot construction, scope/ownership, transformed width, slot-16 Confirm, membership resize, empty slots, reopen and stale HUD.')
