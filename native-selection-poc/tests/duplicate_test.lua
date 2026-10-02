-- Exercise actual duplication adapter with mocked native calls and real FFI storage.
local ffi=require('ffi')
ffi.cdef 'typedef struct { float x,y; } NSR_vec2;'
local f=assert(io.open('native-selection-poc/duplicate.lua','rb'));local source=f:read('*a');f:close()
local base,identity,panel,original=0x10000000,0x20000000,0x21000000,0x22000000
local links,properties,visibility={}, {}, {}
local manager=0x30000000
local resource=manager+5*0x3698
local depth,stack,pushes,pops=0xffffffff,{},0,0
-- Resolve the fixture's pointer slot from the captured native pop instruction,
-- independently of the adapter constant. This catches the r10 typo.
local gf=assert(io.open('native-selection-poc/guards.lua','rb'));local gs=gf:read('*a');gf:close()
local guards=assert(loadstring(gs..'\nreturn native_guards'))()
local manager_rva
for _,g in ipairs(guards) do
    if g.name=='widget_context_pop' then
        local a,c,d,e=g.bytes:byte(4,7)
        manager_rva=g.rva+7+a+c*256+d*65536+e*16777216
    end
end
assert(manager_rva==0x347ce90)
links[base+manager_rva]=manager;links[original+0xf8]=resource;links[resource+8]=0x40000000
local constructors,updates,roots,releases=0,0,0,0
local snapshot={identity=identity,panel=panel,list=original,open=true,center={123,-272},rows={}}
for i=0,7 do snapshot.rows[#snapshot.rows+1]={address=original+0x110+i*0x3760,entry=i,kind=i+1,width=270,height=68} end
local native={}
native[0x1446840]=function(p,kind)
    assert(kind==1 and depth==0 and stack[0]==5,'constructor must run in original HUD context')
    assert(p%16==0,'native allocation must be SIMD aligned')
    roots=roots+1;properties[p]={};links[p+0xf8]=resource
end
native[0x18358d0]=function(p,pos,anchor,pivot,style,index)
    assert(style==0x226 and index==constructors%16);assert(pos.x==0 and anchor.y==1 and pivot.y==1)
    assert(depth==0 and stack[0]==5);constructors=constructors+1;properties[p]={};links[p+0xf8]=resource
end
native[0x144c5c0]=function(parent,child) assert(not links[child+0xf0]);links[child+0xf0]=parent end
native[0x144c2c0]=function(p) assert(p==panel+0x220) end
native[0x1836510]=function(p,dt,context,payload,width,fade)
    assert(depth==0 and stack[0]==5,'card update must run in HUD resource context')
    assert(properties[p] and context==5 and payload==123456 and dt>0 and width==270 and fade==1)
    updates=updates+1
end
native[0x144cfb0]=function(p,v) assert(properties[p]);visibility[p]=v end
native[0x1448ad0]=function(p,v) assert(properties[p] and v==1) end
native[0x144dd70]=function(p) releases=releases+1;links[p+0xf0]=nil end
native[0x12ef4b0]=function(p,index)
    assert(p==manager);depth=(depth==0xffffffff and -1 or depth)+1;stack[depth]=index;pushes=pushes+1
end
native[0x12ef4d0]=function() depth=depth==0 and 0xffffffff or depth-1;pops=pops+1 end
local proxy=setmetatable({}, {__index=ffi})
proxy.cast=function(kind,value)
    if kind:find('(*)',1,true) then return assert(native[value-base],'unknown native entry point') end
    return ffi.cast(kind,value)
end
local b={base=base,valid=function(id) return id==identity end,pointer=function(p) return links[p] end,
    read=function(p,n)
        if p==manager+0x2c5bc then return ffi.string(ffi.new('uint32_t[1]',depth),4) end
        if p>=manager+0x2c5b8 and p<manager+0x2c5bc then return string.char(stack[p-manager-0x2c5b8] or 0) end
        return string.rep('\0',n)
    end,
    u32=function(s) if s then local w=ffi.new('uint32_t[1]');ffi.copy(w,s,4);return tonumber(w[0]) end end}
function b.get(p,key) assert(p==original);return key=='size' and {270,544} or {1,1} end
function b.set(p,key,value)
    assert(p~=original and properties[p],'never write the original list/cards')
    properties[p][key]=value
end
local env=setmetatable({require=function() return proxy end},{__index=_G})
local chunk=assert(loadstring(source..'\nreturn duplicate_cards'));setfenv(chunk,env)
local d=chunk()(b)
local context={context=5,payload=123456}
local copy=d.prepare(snapshot,context,1/60)
assert(roots==1 and constructors==16 and updates==16 and #copy.rows==8)
assert(depth==0xffffffff and pushes==1 and pops==1,'restore context after success')
assert(copy.list~=original and copy.center==snapshot.center and visibility[copy.list]==1)
for i,row in ipairs(copy.rows) do
    assert(d.owns(row.address) and row.entry==i-1 and row.kind==i)
    assert(not d.owns(snapshot.rows[i].address),'original is never owned by radial')
end
d.hide();assert(visibility[copy.list]==0)
local again=d.prepare(snapshot,context,1/60)
assert(again.list==copy.list and roots==1 and constructors==16 and updates==32,'reuse widgets across reopen')
local original_rows=snapshot.rows
snapshot.rows={original_rows[1],original_rows[4]}
local filtered=d.prepare(snapshot,context,1/60)
assert(#filtered.rows==2 and visibility[copy.list+0x110]==1)
assert(visibility[copy.list+0x110+0x3760]==0,'excluded copied card must be hidden after native updates')
assert(visibility[copy.list+0x110+3*0x3760]==1,'allowed copied cards retain their native entry indices')
snapshot.rows=original_rows;d.prepare(snapshot,context,1/60)
assert(visibility[copy.list+0x110+0x3760]==1,'restoring membership must restore copied-card visibility')
identity=identity+8
assert(not d.owns(copy.rows[1].address),'reject stale HUD owner')
d.hide();assert(visibility[copy.list]==1,'do not write stale HUD')
identity=identity-8
d.close();assert(releases==1 and not d.owns(copy.rows[1].address))
local saved_get=b.get
b.get=function() error('simulated layout read failure') end
assert(not pcall(d.prepare,snapshot,context,1/60))
assert(depth==0xffffffff and pushes==pops,'restore context after Lua failure')
b.get=saved_get
depth=3;local before=pushes
assert(not pcall(d.prepare,snapshot,context,1/60) and pushes==before,'full context stack must fail before native push')
depth=0xffffffff
links[original+0xf8]=manager+1
assert(not pcall(d.prepare,snapshot,context,1/60) and pushes==before,'invalid resource context must fail before native push')
print('Duplicate cards passed: HUD context/restore/full-stack guards, SIMD alignment, constructor ABI, separate storage/links, native updates, original untouched, reopen reuse and owner guards.')
