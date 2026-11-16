-- Run the real expanded-wheel renderer against recorded native widget calls.
-- Optional source path + 'baseline' prints the old call budget for comparison.
local ffi=require('ffi')
ffi.cdef 'typedef struct { float x,y; } NSR_vec2;'
local base,id,parent,resource=0x10000000,0x20000000,0x21000000,0x30000000
local links,props,storage={},{},{}
local in_scope,calls,sets,validations=false,0,0,0
local native={}
local function construct(p)
    assert(in_scope and p%16==0);props[p]={};links[p+0xf8]=resource
end
native[0x1446840]=construct;native[0x143eab0]=construct
native[0x144c5c0]=function(p,c) assert(in_scope and not links[c+0xf0]);links[c+0xf0]=p end
native[0x144c2c0]=function() assert(in_scope) end
native[0x144cfb0]=function(p,v) assert(props[p]);props[p].visible=v end
native[0x1448ad0]=function(p,v) assert(in_scope);props[p].opacity=v end
native[0x1448ef0]=function(p,v) assert(in_scope);props[p].rotation=v end
native[0x14481a0]=function(p,v) assert(in_scope);props[p].rotation_pivot={v.x,v.y} end
native[0x14491f0]=function(p,v) assert(in_scope);props[p].order=v end
native[0x1448690]=function(p,v) assert(in_scope);props[p].color={v[0],v[1],v[2]} end
native[0x144f800]=function(p,v) assert(in_scope);props[p].asset=v end
native[0x143eef0]=function(p,a,b) assert(in_scope);props[p].uv={a.x,a.y,b.x,b.y} end
local proxy=setmetatable({}, {__index=ffi})
proxy.cast=function(t,v)
    if t:find('(*)',1,true) then
        local fn=assert(native[v-base], 'unexpected native call')
        return function(...) calls=calls+1;return fn(...) end
    end
    return ffi.cast(t,v)
end
local deny_set
local b={base=base,
    valid=function(owner) validations=validations+1;return owner==id end,
    pointer=function(p) return links[p] end,
    read=function(p,n) return ffi.string(ffi.new('uint64_t[1]',links[p] or 0),n) end,
    alloc_widget=function(size)
        local value=ffi.new('uint8_t[?]',size);storage[#storage+1]=value;return value
    end,
    set=function(p,key,value)
        assert(in_scope and props[p] and p~=parent,'only owned widgets may be cached')
        sets=sets+1
        if deny_set==key then return false end
        props[p][key]={value[1],value[2]}
    end,
    release_owned_ui=function(_,address) links[address+0xf0]=nil;return true end,
}
local scope={context_scope=function(p,fn)
    assert(p==parent and not in_scope);in_scope=true
    local ok,value=pcall(fn,resource);in_scope=false;assert(ok,value);return value
end}
local sequence={1,2,3,4,1}
local input={display_codes=function(rows)
    local codes={};for i in ipairs(rows) do codes[i]=sequence end;return codes
end,presentation=function(kind) return {kind=kind} end}
local env=setmetatable({require=function() return proxy end,radial={},
    style=dofile('hellforge/hud/hd2_ui_style.lua'),
    selectable_kind=function(k) return type(k)=='number' and k>0 and k<=197 end,
    configure_stratagem_icon=function(_,icon,info,cooling)
        assert(in_scope);props[icon].kind=info.kind;props[icon].cooling=cooling;calls=calls+1
    end}, {__index=_G})
local path=arg[1] or 'hellforge/hud/wheel_expanded.lua'
local make=setfenv(assert(loadfile(path)),env)().expanded_wheel
local rows={}
for i=1,16 do rows[i]={address=100+i,kind=i,entry=i-1,list_y=17-i} end
local snap={identity=id,list=parent,open=true,center={400,300},rows=rows}
local w=make(b,scope,input)
local function draw(selected)
    local prepared=w.prepare(snap)
    assert(w.draw(selected or 101,prepared.rows)==(selected or 101)-100)
    return prepared
end
draw()
local root
for p in pairs(props) do if links[p+0xf0]==parent then root=p end end
assert(root and props[root].visible==1)
local function slot(i) return root+0x110+(i-1)*0x1560 end
calls,sets,validations=0,0,0
local start=os.clock()
for i=1,120 do draw() end
local elapsed=os.clock()-start
print(string.format('Static 16-slot wheel, 120 frames: %d native calls, %d vector setters (%.3f ms/frame fixture CPU)',
    calls,sets,elapsed*1000/120))
if arg[2]=='baseline' then return end
assert(calls==0 and sets==0,'unchanged owned widgets must not call engine setters')
assert(validations>=120,'retaining visuals must not cache HUD ownership across frames')
-- Only the old and new selected slots need repainting.
calls,sets=0,0;draw(102)
assert(calls>0 and calls<=56 and sets==0,'selection must update without relaying out the wheel')
assert(props[slot(2)+0x220].opacity==0.95 and props[slot(1)+0x220].opacity==0.5)
calls,sets=0,0;draw(102);assert(calls==0 and sets==0)
env.radial.wedge_darkness=90;draw(102)
local ink=env.style.tokens.colors.field_active
assert(math.abs(props[slot(1)+0x220].color[1]-ink[1]/255*0.1)<1e-6)
env.radial.wedge_opacity=80;draw(102);assert(props[slot(1)+0x220].opacity==0.8)
env.radial.full_color=false;rows[2].timer_kind='cooldown';rows[2].timer_seconds=4
draw(102);assert(props[slot(2)+0x380].opacity==0.55)
rows[2].timer_kind=nil;rows[2].timer_seconds=nil
draw(102);assert(props[slot(2)+0x380].opacity==1)
env.radial.icon_scale=1.2;draw(102);assert(props[slot(2)+0x380].scale[1]==1.2)
sequence={4,3};draw(102)
assert(props[slot(2)+0x4e0].visible==1 and props[slot(2)+0x4e0+2*0x160].visible==0)
-- Layout updates still follow live center motion and retry refused setters.
deny_set='position';snap.center={450,320};draw(102)
assert(props[root].position[1]==400)
deny_set=nil;draw(102);assert(props[root].position[1]==450)
calls,sets=0,0;w.hide();w.hide();assert(calls==1 and props[root].visible==0)
draw(102);assert(props[root].visible==1)
-- Compact, grow, and reconstruct at a new HUD identity.
snap.rows={rows[1],rows[2]};draw(102)
assert(props[slot(3)+0x380].visible==0 and props[slot(9)].visible==0)
snap.rows=rows;draw(102);assert(props[slot(16)+0x380].visible==1)
id=id+8;calls,sets=0,0;w.hide();assert(calls==0 and sets==0,'stale HUD must never be mutated')
snap.identity=id;draw(102)
assert(calls>0 and sets>0,'new generation must initialize fresh retained state')
calls,sets=0,0;draw(102);assert(calls==0 and sets==0)
-- Child ownership validation remains live even when geometry is unchanged.
local new_root
for p in pairs(props) do if p~=root and links[p+0xf0]==parent then new_root=p end end
links[new_root+0x110+0xf0]=0
assert(not pcall(draw,102),'detached child must fail before reuse')
print('Retained transforms/highlights, live settings/codes/cooldowns, failed setters, resize, reopen and ownership passed')
