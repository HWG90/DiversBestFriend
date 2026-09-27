-- Exercise the real adapter against a bounded fake address space. Actual
-- LuaJIT handles the cdata buffers/float vectors; no game process is touched.
local ffi=require('ffi')
local function source(name)
    local f=assert(io.open('native-selection-poc/'..name,'rb'))
    local s=f:read('*a');f:close();return s
end
local guards=assert(loadstring(source('guards.lua')..'\nreturn native_guards'))()
local memory={}
local function put(address,data) for i=1,#data do memory[address+i-1]=data:sub(i,i) end end
local function blob(address,size)
    local out={}
    for i=0,size-1 do if not memory[address+i] then return nil end;out[#out+1]=memory[address+i] end
    return table.concat(out)
end
local function word(address,value) local b=ffi.new('uint32_t[1]',value);put(address,ffi.string(b,4)) end
local function ptr(address,value) local b=ffi.new('uint64_t[1]',value);put(address,ffi.string(b,8)) end
local function pair(address,x,y) local b=ffi.new('float[2]',x,y);put(address,ffi.string(b,8)) end
local function matrix(address,a,b,c,d,x,y)
    -- Full native GUI X/Z matrix. Depth stays at unit scale/zero origin:
    -- the old X/Y extraction looked valid but ignored vertical placement.
    local values=ffi.new('float[16]',{a,0,b,0, 0,1,0,0, c,0,d,0, x,0,y,1})
    put(address+0x64,ffi.string(values,64))
end
local base,root,state=0x10000000,0x20000000,0x30000000
put(base,string.rep('\0',64));put(base,'MZ');word(base+60,128)
put(base+128,string.rep('\0',32));put(base+128,'PE\0\0');word(base+136,1790161983)
for _,g in ipairs(guards) do put(base+g.rva,g.bytes) end
ptr(base+0x346d538,root);ptr(base+0x3326340,state)
put(root+0x24e334,'\1');word(state+0xac21c,4)
local panel=root+0x24e340+0x146dc0
local list=panel+0x1040
ptr(panel+0xf0,root+0x820);ptr(panel+0x110+0xf0,panel)
ptr(panel+0x220+0xf0,panel+0x110);ptr(list+0xf0,panel+0x220)
ptr(root+0x820+0xf0,root+0x258)
pair(root+0x258+0x24,1920,1080)
matrix(root+0x258,1,0,0,1,0,0)
pair(list+0x24,355,544)
matrix(list,1.25,0,0,1.25,-710,200)
put(panel+0x38769,'\1')
for i=0,15 do
    local row=list+0x110+i*0x3760
    word(row+0x3748,i);ptr(row+0xf0,list);put(row+0x36f0,i<4 and '\1' or '\0')
    pair(row+12,270,68);pair(row+20,1,1);pair(row+28,0.8,0.8)
    pair(row+0x3738,20,-i*68);pair(row+0x3740,0,-i*68)
end
local kernel={GetModuleHandleA=function() return ffi.cast('void *',base) end,
    GetCurrentProcess=function() return ffi.cast('void *',1) end}
function kernel.ReadProcessMemory(_,address,buffer,size,received)
    local data=blob(tonumber(ffi.cast('uintptr_t',address)),size)
    if not data then return 0 end
    ffi.copy(buffer,data,size);received[0]=size;return 1
end
local reject_write=false
function kernel.WriteProcessMemory(_,address,buffer,size,received)
    if reject_write then return 0 end
    assert(size==8,'only a single animation vector may be written')
    put(tonumber(ffi.cast('uintptr_t',address)),ffi.string(buffer,size))
    received[0]=size;return 1
end
local offsets={[0x14476a0]=4,[0x1447160]=12,[0x1447ed0]=20,[0x144f160]=44,[0x144f0d0]=60}
local proxy=setmetatable({}, {__index=ffi})
proxy.load=function(name) assert(name=='kernel32' or name=='user32');return kernel end
proxy.cast=function(kind,value)
    if kind=='void (*)(uintptr_t)' then assert(value==base+0xa900d0);return function() error('must not invoke input during drawing') end end
    if kind=='void (*)(uintptr_t, NSR_vec2)' then
        local offset=assert(offsets[value-base])
        return function(address,vector) pair(address+offset,vector.x,vector.y) end
    end
    return ffi.cast(kind,value)
end
local env=setmetatable({require=function(name) assert(name=='ffi');return proxy end},{__index=_G})
local chunk=assert(loadstring(source('layout.lua')..'\n'..source('guards.lua')..'\n'..source('native.lua')..'\nreturn native_backend'))
setfenv(chunk,env)
local make=chunk()
local backend=make()
local snapshot=assert(backend.snapshot())
assert(snapshot.panel==panel and snapshot.list==list and #snapshot.rows==4)
assert(math.abs((snapshot.center[1]+355/2)*1.25-710-960)<0.001,'native snapshot screen center')
assert(math.abs((snapshot.center[2]+544/2)*1.25+200-540)<0.001,'native snapshot vertical center uses Z')
for _,height in ipairs({1080,1440,1821}) do
    for _,scale in ipairs({0.65,1,1.8}) do
        pair(root+0x258+0x24,2849,height)
        matrix(root+0x258,2,0,0,2,17,39)
        -- Include off-diagonal components so both projected bases matter.
        matrix(list,scale,0.125,-0.25,scale,-639,900)
        local s=assert(backend.snapshot())
        local x,y=s.center[1]+355/2,s.center[2]+544/2
        assert(math.abs(x*scale-y*0.25-639-(2849+17))<0.001,'projected X midpoint')
        assert(math.abs(x*0.125+y*scale+900-(height+39))<0.001,'projected Z midpoint')
    end
end
matrix(list,1,0,0,0,0,0)
assert(backend.snapshot()==nil,'reject singular screen plane even when depth scale is valid')
matrix(list,1.25,0,0,1.25,-710,200)
assert(backend.get(list+0x110,'scale')[1]==1,'read local scale, not inherited scale')
backend.set(list+0x110,'scale',{0.65,0.65})
assert(math.abs(backend.get(list+0x110,'scale')[1]-0.65)<0.00001)
backend.set(list+0x110,'animation_a',{123,456})
assert(backend.get(list+0x110,'animation_a')[1]==123)
assert(backend.get(list+0x110,'animation_b')[1]==0,'only the requested endpoint changes')
assert(not pcall(backend.set,list,'animation_a',{1,2}),'reject writes outside native cards')
reject_write=true
assert(not pcall(backend.set,list+0x110,'animation_b',{1,2}),'propagate write failures')
reject_write=false
put(panel+0x38769,'\0');assert(not backend.snapshot().open)
put(panel+0x38769,'\1');ptr(list+0xf0,0x40000000)
assert(backend.snapshot()==nil,'reject incorrect parent hierarchy')
ptr(list+0xf0,panel+0x220);word(state+0xac21c,3)
assert(backend.snapshot()==nil,'reject different HUD mode')
word(state+0xac21c,4);pair(list+0x110+12,0,68)
assert(backend.snapshot()==nil,'reject invalid card dimensions')
put(base+guards[1].rva,'\0')
local ok,why=pcall(make)
assert(not ok and tostring(why):find('Native signature changed',1,true),'reject changed native entry point')
print('Native radial adapter: snapshot, ABI vectors, local scale, hierarchy, mode, dimensions, and signatures passed')
