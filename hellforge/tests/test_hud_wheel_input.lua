-- Sparse target memory for the local avatar, its mission, live menu bindings
-- and one HellForge kind. No Win32 calls or engine DLL are needed.
local ffi=require('ffi')
local m={}
local function put(p,s) for i=1,#s do m[p+i-1]=s:sub(i,i) end end
local function read(p,n)
    local t={}
    for i=1,n do t[i]=m[p+i-1];if not t[i] then return nil end end
    return table.concat(t)
end
local function packed(n) return ffi.string(ffi.new('uint32_t[1]',n),4) end
local function word(p,n) put(p,packed(n)) end
local function ptr(p,n) put(p,ffi.string(ffi.new('uint64_t[1]',n),8)) end
local function u32(bytes,off) return tonumber(ffi.cast('const uint32_t *',bytes:sub(off+1))[0]) end
local function pointer(p) return tonumber(ffi.cast('const uint64_t *',assert(read(p,8)))[0]) end
local next_map=0x18000000
local function map(p,key,index)
    next_map=next_map+128
    ptr(p,next_map);word(p+8,8);word(p+12,0xffffffff);word(p+16,1)
    word(next_map+key%8*8,key);word(next_map+key%8*8+4,index)
end
local base,state,hud,pm,registry,manager,unit,session,mission,controls,ui=
    0x100000,0x20000000,0x21000000,0x22000000,0x23000000,0x25000000,
    0x26000000,0x27000000,0x28000000,0x29000000,0x30000000
local key,kind=42,154
local avatar=manager+0x53d8b0
local component,actions=avatar+0x8d0,manager+0x4118
local list_open=hud+0x395100+0x38769
ptr(base+0x3326340,state);word(state+0xac21c,4)
ptr(base+0x346d538,hud);put(list_open,'\0')
ptr(base+0x3326468,pm);word(pm+0x88,1);word(pm+0x3a8,7)
ptr(base+0x346bf98,registry);map(registry+0xf22ec8,7,0);word(registry+0xf32f20,key)
ptr(base+0x3326d20,manager);word(manager+0x70,1);map(manager+0xf8,key,0)
ptr(manager+0x110,unit);word(unit+8,key)
put(component,string.rep('\0',0x38));word(component+0x28,key)
word(avatar+0xfd8,0);word(avatar+0x110c,5);word(avatar+0x420,key);word(avatar+0x424,5)
map(pm+0xd0,5,1);put(pm+0x2c8+0x38,'local123')
ptr(base+0x347cef0,session);put(session+0xb398,'local123')
ptr(base+0x347ce50,mission);word(mission+0x2d200,1);put(mission,'local123')
local payload=mission+0x38
word(payload+0x788,8);put(payload+0x188,string.rep('\0',8*0x30));word(payload+0x188+4*0x30,kind)
local binding=0x31000000
local source_type=controls+808+32*(97*5)+24
local hold=packed(0x2ff41)..packed(10)..packed(2)..packed(0)..packed(0)
ptr(base+0x347cf18,controls);word(controls+686808,256);ptr(controls+686800,binding)
word(binding,0x50000);word(binding+4,1);put(binding+8,hold)
put(controls+808+32*(97*5),'\0');word(source_type,2)
ptr(base+0x347ce28,ui);word(ui+0x429c+20,0)
for a=0,4 do put(actions+a*32,'\0') end
word(actions+24,2)
local deny_reopen,restore_fault=true,true
local seq={1,4}
local backend={base=base,read=read,u32=u32,pointer=pointer,valid=function(id) return id==hud end}
function backend.replace_bytes(p,expected,replacement)
    if p==binding+8 and replacement==hold and restore_fault then error('injected rollback failure') end
    assert(read(p,#expected)==expected);put(p,replacement);return true
end
function backend.open_input()
    if deny_reopen then return false end
    put(list_open,'\1');word(avatar+0xfd8,512);return true
end
function backend.close_input() put(list_open,'\0');word(avatar+0xfd8,0) end
local pulses=0
function backend.pulse_byte(p,v) put(p,string.char(v));pulses=pulses+1 end
function backend.invoke_input()
    local n=u32(read(component,4),0)
    local dir=seq[n+1]
    assert(read(actions+32*({3,2,4,1})[dir],1)=='\1')
    put(component+4+n,string.char(dir));word(component,n+1)
    if n+1==#seq then word(component+0x14,kind) end
end
local bridge={
    dbf_hud_blacklisted=function() return 0 end,
    dbf_hud_code=function(k,buf,cap)
        assert(k==kind and cap>=#seq)
        for i,d in ipairs(seq) do buf[i-1]=d end
        return #seq
    end,
}
local env=setmetatable(dofile('hellforge/hud/wheel_latch.lua'),{__index=_G})
local make=setfenv(assert(loadfile('hellforge/hud/wheel_input.lua')),env)().input_backend
local input=make(backend,bridge)
assert(not pcall(input.begin_shortcut,1) and read(binding+8,20)~=hold,'failed reopen left journal to retry')
restore_fault=false;input.retry_cleanup()
assert(read(binding+8,20)==hold and u32(read(actions+24,4),0)==2)
deny_reopen=false
local job=input.begin_shortcut(1)
assert(job.kind==kind and job.code[1]==1)
seq={2,4}
assert(not pcall(input.advance,job) and pulses==0,'changed scrambled code blocked before pulse')
seq={1,4}
assert(not input.advance(job) and input.advance(job) and pulses==4)
-- Failed avatar probe restores global map, retains local trigger for retry.
m[base+0x3326d20]=nil
assert(not pcall(input.end_release,job,true) and read(binding+8,20)==hold)
assert(u32(read(actions+24,4),0)==0,'must retain unverified local trigger')
ptr(base+0x3326d20,manager);input.end_release(job,true)
assert(u32(read(actions+24,4),0)==2 and read(list_open,1)=='\0')
print('Equipped modded slot, code changes, pulse restoration, reopen rollback and transient avatar cleanup passed')
