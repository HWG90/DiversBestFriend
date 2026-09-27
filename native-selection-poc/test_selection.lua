local function source(name)
    local f=assert(io.open('native-selection-poc/'..name,'rb')); local s=f:read('*a'); f:close(); return s
end
local factory=assert(loadstring(source('input.lua')..'\n'..source('pointing.lua')..'\n'..source('selection.lua')..'\nreturn input_backend,selection_controller'))
local make_input,make_selection=factory()
local memory={}
local function put(at,s) for i=1,#s do memory[at+i-1]=s:sub(i,i) end end
local function read(at,n)
    local t={}; for i=0,n-1 do if not memory[at+i] then return nil end; t[#t+1]=memory[at+i] end
    return table.concat(t)
end
local function u32(s,o)
    if not s or #s<o+4 then return nil end
    local a,b,c,d=s:byte(o+1,o+4); return a+b*256+c*65536+d*16777216
end
local function num(at,n)
    local s=''; for i=1,4 do s=s..string.char(n%256);n=math.floor(n/256) end; put(at,s)
end
local function ptr(at,n) num(at,n);num(at+4,0) end
local base,state,hud,pm,registry,manager,unit,session,mission,settings=
    0x10000000,0x20000000,0x21000000,0x22000000,0x23000000,0x25000000,0x26000000,0x27000000,0x28000000,0x29000000
-- Native key/index tables may start at 4 mod 8, including inline storage.
local alloc=0x30000004
local function map(owner,off,key,index)
    alloc=alloc+0x100; ptr(owner+off,alloc);num(owner+off+8,8);num(owner+off+12,0xffffffff);num(owner+off+16,1)
    put(alloc,string.rep('\255',64));num(alloc+(key%8)*8,key);num(alloc+(key%8)*8+4,index)
end
ptr(base+0x3326340,state);num(state+0xac21c,4)
ptr(base+0x346d538,hud);put(hud+0x395100+0x38769,'\1')
ptr(base+0x3326468,pm);num(pm+0x88,1);num(pm+0x3a8,7)
ptr(base+0x346bf98,registry);map(registry,0xf22ec8,7,2);num(registry+0xf32f20+48,42)
ptr(base+0x3326d20,manager);num(manager+0x70,2);map(manager,0xf8,42,1)
ptr(manager+0x118,unit);num(unit+8,42)
local avatar=manager+0x53d8b0+0x1238
local component=avatar+0x8d0;put(component,string.rep('\0',0x38));num(component+0x28,42)
num(avatar+0xfd8,512);num(avatar+0x11b8,0);num(avatar+0x110c,5)
map(pm,0xd0,5,1);put(pm+0x2c8+0x38,'local123')
ptr(base+0x347cef0,session);put(session+0xb398,'local123')
ptr(base+0x347ce50,mission);num(mission+0x2d200,1);put(mission,'local123')
local payload=mission+0x38;num(payload+0x788,7)
ptr(base+0x348e8f8,settings)
-- The sixth is a synthetic mission-owned descriptor outside the old allowlist.
local cases={{3,{1,2,3,3,3}},{136,{2,2,3,4,2,3}},{4,{2,3,4,1,1}},{25,{3,4,3,1,1,2}},{33,{3,3,1,2}},{124,{1,4,2}},{50,{4,3,2,3,4,3,1,4,2}}}
for i,c in ipairs(cases) do
    num(payload+0x188+(i-1)*0x30,c[1])
    local info=settings+i*400+(c[1]==50 and 4 or 0); local code=settings+4004+i*64
    ptr(base+0x37cb600+c[1]*8,info);num(info,c[1]);ptr(info+0x40,code);num(info+0x48,#c[2])
    for j,d in ipairs(c[2]) do num(code+(j-1)*4,d) end
end
local actions=manager+0xa7aec+0x4118
for a=0,4 do put(actions+a*32,'\0') end
local writes,calls,fail,reject=0,0,false,false
local expected
local b={base=base,read=read,u32=u32,valid=function(p) return p==hud end}
function b.pointer(at) local s=read(at,8); if not s then return nil end; return u32(s,0)+u32(s,4)*4294967296 end
function b.pulse_byte(at,value)
    assert(at==actions+32 or at==actions+64 or at==actions+96 or at==actions+128)
    assert(value==0 or value==1); writes=writes+1;put(at,string.char(value))
end
function b.invoke_input(at)
    assert(at==component);calls=calls+1
    if fail then error('fixture handler failure') end
    local direction
    for a=1,4 do if read(actions+32*a,1)=='\1' then assert(not direction);direction=({4,2,1,3})[a] end end
    assert(direction)
    local n=u32(read(component,4),0)
    assert(direction==expected[2][n+1])
    put(component+4+n,string.char(direction));n=n+1
    num(component,reject and 0 or n)
    if not reject and n==#expected[2] then num(component+0x14,expected[1]) end
end
local input=make_input(b)
local cards={open=true,rows={{address=123,entry=0},{address=456,entry=4},{address=789,entry=20}}}
input.decorate(cards)
assert(cards.rows[1].kind==3 and cards.rows[2].kind==33 and cards.rows[3].kind==nil,'cards use local payload index')
-- Native card cache already contains the HUD's special-case countdowns.
local ffi=require('ffi')
local function cached(row,kind,state,seconds)
    put(row.address+0x3718,string.rep('\0',0x44))
    num(row.address+0x374c,kind);num(row.address+0x3758,state)
    local value=ffi.new('float[1]',seconds)
    put(row.address+(state==3 and 0x3718 or 0x3720),ffi.string(value,4))
end
cached(cards.rows[1],3,4,61.25);cached(cards.rows[2],33,3,9.2)
input.decorate(cards)
assert(cards.rows[1].timer_kind=='cooldown' and cards.rows[1].timer_seconds==62)
assert(cards.rows[2].timer_kind=='incoming' and cards.rows[2].timer_seconds==10)
for _,seconds in ipairs({0,-1,0/0,math.huge,86401}) do
    cached(cards.rows[1],3,4,seconds);input.decorate(cards)
    assert(cards.rows[1].timer_seconds==nil,'expired/invalid timer never remains stale')
end
cached(cards.rows[1],136,4,60);input.decorate(cards)
assert(cards.rows[1].timer_seconds==nil,'stale native kind rejected')
cached(cards.rows[1],3,5,60);input.decorate(cards)
assert(cards.rows[1].timer_seconds==nil,'other unavailability is not mislabeled cooldown')
cards.rows[1].entry=5;cached(cards.rows[1],124,4,22.1);input.decorate(cards)
assert(cards.rows[1].kind==124 and cards.rows[1].timer_seconds==23,'shared Reinforce native countdown preserved')
cards.rows[1].entry=0;cached(cards.rows[1],3,1,0);input.decorate(cards)
assert(cards.rows[1].timer_seconds==nil and cards.rows[1].timer_kind==nil,'ready state clears previous cooldown')
local function reset() num(component,0);num(component+0x14,0);num(component+0x2c,0) end
for _,c in ipairs(cases) do
    reset(); expected=c
    local job=input.begin(c[1]);assert(job.component==component)
    for i=1,#c[2] do
        local done=input.advance(job);assert(done==(i==#c[2]))
        for a=1,4 do assert(read(actions+32*a,1)=='\0','every pulse restored') end
    end
end
-- Relaxing descriptor alignment must not accept corrupt records or pointers.
reset()
local tank_slot=base+0x37cb600+50*8
local tank_info=settings+7*400+4
for _,invalid in ipairs({tank_info+2,settings-4,settings+80280-396}) do
    ptr(tank_slot,invalid);local before=writes
    assert(not pcall(input.begin,50) and writes==before,'invalid definition rejected before input')
end
ptr(tank_slot,tank_info);num(tank_info,49)
assert(not pcall(input.begin,50),'descriptor identity still checked')
num(tank_info,50)
reset();assert(not pcall(input.begin,149),'non-member kind refused')
num(avatar+0x11b8,1);assert(not pcall(input.begin,33));num(avatar+0x11b8,0)
num(avatar+0xfd8,0);assert(not pcall(input.begin,33));num(avatar+0xfd8,512)
num(avatar+0xfd8,0);num(avatar+0x11b8,1)
input.decorate(cards)
assert(cards.rows[1].kind==3,'highlighting must survive activation-only guard failures')
num(avatar+0xfd8,512);num(avatar+0x11b8,0)
expected=cases[5];local job=input.begin(33);local before=writes
put(actions+32,'\1');assert(not pcall(input.advance,job));assert(writes==before);put(actions+32,'\0')
job=input.begin(33);fail=true;assert(not pcall(input.advance,job));fail=false
for a=1,4 do assert(read(actions+32*a,1)=='\0','handler failure restores pulse') end
reset();job=input.begin(33);reject=true;assert(not pcall(input.advance,job));reject=false
reset();job=input.begin(33);num(component+0x28,99);before=writes
assert(not pcall(input.advance,job));assert(before==writes);num(component+0x28,42)
reset();job=input.begin(33);put(hud+0x395100+0x38769,'\0');assert(not pcall(input.advance,job));put(hud+0x395100+0x38769,'\1')
-- UI state machine: held confirm, missing bindings, membership and timeouts.
local starts,advances=0,0
local fake={begin=function(kind) starts=starts+1;return {kind=kind} end,
    advance=function() advances=advances+1;return true,'matched' end}
local events={};local s=make_selection(fake,function(m) events[#events+1]=m end)
local snap={identity=1,open=true,rows={{address=10,kind=3},{address=11,kind=0},{address=12,kind=33}}}
local neutral={next=false,previous=false,confirm=false}
s.step(snap,{next=false,previous=false,confirm=true},0);assert(starts==0 and s.selected==10)
s.step(snap,neutral,1);s.step(snap,{next=true,previous=false,confirm=false},2);assert(s.selected==12)
s.step(snap,neutral,3);s.step(snap,{next=false,previous=false,confirm=true},4);assert(starts==1)
s.step(snap,neutral,5);assert(advances==1 and not s.job)
s.step(snap,{next=false,previous=false,confirm=true},6);assert(starts==2)
s.step(nil,nil,7);assert(not s.job and not s.selected and advances==1)
s.step(snap,neutral,8);s.step(snap,{next=false,previous=false,confirm=true},9)
s.step(snap,neutral,4000);assert(not s.job and advances==1)
s.step(snap,neutral,4001);s.step(snap,{next=false,previous=false,confirm=true},4002)
snap.rows[1].kind=4;s.step(snap,neutral,4003);assert(not s.job and advances==1)
assert(loadfile('native-selection-poc/NativeStratagemRadial.lua'),'assembled syntax')
print('Selection fixtures passed: five original codes, nine-direction Maelstrom with a 4-byte-aligned definition, plus a dynamic descriptor, local slot 1 ownership, membership/menu/scramble guards, manual-input cancellation, native rejection, pulse restoration, held-confirm gating, menu cancellation, timeout and card changes.')
