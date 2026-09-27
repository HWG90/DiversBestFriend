local ffi=require('ffi')
local function source(n) local f=assert(io.open('native-selection-poc/'..n,'rb'));local s=f:read('*a');f:close();return s end
local base,id,parent=0x10000000,0x20000000,0x21000000
local links,shown,positions,angles,opacities={},{},{},{},{}
local constructed,in_scope,reads=0,false,0
local resource=0x30000000
local native={}
local wheel_address
native[0x18298f0]=function(p,unused,style,mode,flag)
    assert(in_scope and p%16==0 and unused==0 and style==0x226 and mode==1 and flag==0)
    wheel_address=p;constructed=constructed+1;links[p+0xf8]=resource
    ffi.cast('uint32_t *',p+0x1cd4)[0]=8
    ffi.cast('float *',p+0x52c)[0]=-22.5
end
native[0x144c5c0]=function(p,c) assert(in_scope and p==parent);links[c+0xf0]=p end
native[0x144c2c0]=function(p) assert(in_scope and p==parent) end
native[0x144cfb0]=function(p,v) shown[p]=v end
native[0x1448ad0]=function(p,v) assert(in_scope and v>=0 and v<=1);opacities[p]=v end
native[0x1448ef0]=function(p,v) assert(in_scope);angles[p]=v end
native[0x1450230]=function(p,material,hash,flag)
    assert(in_scope and flag==0 and tonumber(hash)>0)
end
local label_kind
local timer_values={}
native[0x143bf90]=function(p,hash) assert(in_scope and p==wheel_address+0xf50 and hash==0xa851371b) end
native[0x143c9d0]=function(p,key,value,flags)
    assert(in_scope and p==wheel_address+0xf50 and flags==0x3020);timer_values[key]=value
end
native[0x144f6e0]=function() return 65536 end
native[0x14498c0]=function() assert(in_scope) end
native[0x1441720]=function(p,hash) assert(in_scope and p==wheel_address+0xc98);label_kind=hash end
native[0x12f9540]=function() return 0x50000000 end
local desired=3
native[0x182b5c0]=function(p,owner,dt)
    reads=reads+1;assert(p==wheel_address and owner==0x60000000 and dt>0)
    assert(ffi.cast('uint32_t *',p+0x1cd4)[0]==8)
    assert(ffi.cast('float *',p+0x52c)[0]==-22.5)
    assert(ffi.cast('uint32_t *',p+0x1cd8)[0]==0xffffffff,'stale slot cleared before sampling')
    ffi.cast('float *',p+0x1ce8)[0]=0.5
    ffi.cast('float *',p+0x1ce8)[1]=-0.25
    ffi.cast('uint32_t *',p+0x1cd8)[0]=desired
end
local proxy=setmetatable({}, {__index=ffi})
proxy.cast=function(t,v)
    if t:find('(*)',1,true) then return assert(native[v-base],'unexpected native call') end
    return ffi.cast(t,v)
end
local b={base=base,valid=function(v) return v==id end,pointer=function(p)
    if p==base+0x346d560 or p==base+0x347cf18 then return 0x40000000 end
    return links[p]
end,read=function(p,n) return string.rep('\0',n) end,
set=function(p,k,v) assert(in_scope and p~=parent);positions[p..k]=v end}
local scope={context_scope=function(original,fn)
    assert(original==parent and not in_scope);in_scope=true
    local ok,value=pcall(fn,resource);in_scope=false;assert(ok,value);return value
end}
local input={presentation=function(k) return {label=k,category=0,texture=ffi.string(ffi.new('uint64_t[1]',k),8)} end}
local env=setmetatable({require=function() return proxy end,radial={vertical_offset=575,full_color=false}},{__index=_G})
local chunk=assert(loadstring(source('input.lua')..source('icon_colors.lua')..source('emote.lua')..source('pointing.lua')..source('selection.lua')..'\nreturn emote_wheel,native_pointing,selection_controller'))
setfenv(chunk,env);local make,make_point,make_selection=chunk()
local w=make(b,scope,input)
local rows={}
for i=1,16 do rows[i]={address=100+i,kind=i,entry=i-1,list_y=i*68} end
local snap={identity=id,open=true,list=parent,rows=rows,center={1000,300}}
local idle={next=false,previous=false,confirm=false}
local next_button={next=true,previous=false,confirm=false}
local page,changed=w.prepare(snap,idle,false)
assert(changed and constructed==1 and w.pages==2 and #page.rows==8)
assert(page.rows[1].kind==16 and page.rows[8].kind==9,'native display order')
assert(positions[wheel_address..'position'][2]==-275,'saved offset retained')
local pt=make_point(b)
local context={identity='player',input_owner=0x60000000}
local v=pt.sample(context,0.016,w.address)
assert(v[1]==0.5 and v[2]==-0.25 and v.slot==4 and reads==1)
assert(page.pointing_index(page.rows,v)==4)
w.draw(page.rows[4].address,v,page.rows)
assert(label_kind==13 and angles[wheel_address+0x890]==112.5)
assert(positions[(wheel_address+0xb40)..'position'][1]==120)
assert(positions[(wheel_address+0xb40)..'position'][2]==-60)
page.rows[4].timer_seconds,page.rows[4].timer_kind=62,'cooldown'
w.prepare(snap,idle,false);w.draw(page.rows[4].address,v,page.rows);w.timer(page.rows[4])
assert(opacities[wheel_address+0x1208+3*0x158]==0.55,'selected cooldown icon remains dim')
assert(shown[wheel_address+0xf50]==1 and timer_values[0x51d1e697]==1 and timer_values[0x4583b0d3]==2,'native timer receives minute/second values')
page.rows[4].timer_seconds=59;w.timer(page.rows[4])
assert(timer_values[0x51d1e697]==0 and timer_values[0x4583b0d3]==59,'countdown crosses minute boundary')
page.rows[4].timer_seconds,page.rows[4].timer_kind=nil,nil
w.prepare(snap,idle,false);w.draw(page.rows[4].address,v,page.rows);w.timer(page.rows[4])
assert(shown[wheel_address+0xf50]==0 and opacities[wheel_address+0x1208+3*0x158]==1,'expiry restores icon and hides timer')
page,changed=w.prepare(snap,next_button,false)
assert(changed and w.page==2 and page.rows[1].kind==8 and page.rows[8].kind==1)
page,changed=w.prepare(snap,next_button,false);assert(not changed and w.page==2,'held next does not repeat')
w.prepare(snap,idle,false)
page,changed=w.prepare(snap,next_button,true);assert(not changed and w.page==2,'no paging during entry')
w.prepare(snap,idle,false)
page,changed=w.prepare(snap,next_button,false);assert(changed and w.page==1,'wrap to first page')
-- Nine total items: page two has exactly one enabled sector, never slot overflow.
for i=16,10,-1 do table.remove(rows,i) end
w.prepare(snap,idle,false)
page=w.prepare(snap,next_button,false)
assert(w.page==2 and #page.rows==1)
for i=0,7 do assert(ffi.cast('uint8_t *',w.address+0x1cc8)[i]==(i==0 and 1 or 0)) end
desired=3;v=pt.sample(context,0.016,w.address);assert(v.slot==nil,'empty sector cannot select')
w.draw(nil,v,page.rows);assert(shown[w.address+0x890]==0 and shown[w.address+0xc98]==0)
w.hide();assert(shown[w.address]==0 and w.page==1)
page=w.prepare(snap,idle,false);assert(constructed==1,'reuse across reopen')
w.draw(page.rows[1].address,{0,1},page.rows,true)
assert(shown[w.address+0x488]==0 and shown[w.address+0x890]==0 and shown[w.address+0xc98]==0)
assert(shown[w.address+0xb40]==1 and opacities[w.address+0x1208]==0,'old rows use cursor-only wheel')
w.draw(page.rows[1].address,{0,1},page.rows,false)
assert(shown[w.address+0x488]==1 and shown[w.address+0x890]==1 and opacities[w.address+0x1208]==1,'native visuals restore after cursor-only mode')
w.caption(149);assert(label_kind==149 and shown[w.address+0xc98]==1,'caption outside native eight slots')
w.caption(nil);assert(shown[w.address+0xc98]==0)
id=id+8;w.hide();assert(shown[w.address]==1,'never touch stale HUD')
print('Native wheel adapter passed: constructor ABI/scope, bounded paging/order, owned visuals, native cursor/sector state, empty-slot rejection, busy/held paging, offset, reuse and stale owner.')

local started
local selection=make_selection({begin=function(k) started=k;return {kind=k} end},function() end)
page.rows={{address=1,kind=33},{address=2,kind=124}}
selection.step(page,idle,0,{1,0,slot=1})
assert(selection.selected==1,'native slot is authoritative over old ellipse geometry')
selection.step(page,{next=false,previous=false,confirm=true},1,{1,0,slot=1})
assert(started==33,'Confirm uses native selected slot kind')
selection.step(nil,nil,2)
selection.step(page,{next=false,previous=false,confirm=true},3,{1,0,slot=2})
assert(started==33 and not selection.job,'held Confirm cannot activate after page reset')
selection.step(page,idle,4,{1,0})
assert(not selection.selected,'empty native sector clears highlight')
print('Native sector selection passed: native index authority, confirmed kind, page-reset held-Confirm gating and empty-sector clearing.')
