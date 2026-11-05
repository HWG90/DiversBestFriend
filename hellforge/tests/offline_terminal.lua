-- Port of R50 luajit/tests/offline_terminal.lua. No native code is executed.
local ffi=require('ffi')
local here=arg[0]:match('^(.*)/[^/]*$') or '.'
local guards=dofile(here..'/../hud/terminal_guards.lua').terminal_guards_25480438
local image_size=0x3490000
local image_storage=ffi.new('uint8_t[?]',image_size)
local image=tonumber(ffi.cast('uintptr_t',image_storage))
local function put(p,t,v) ffi.cast(t..' *',p)[0]=v end
local function get(p,t) return ffi.cast(t..' *',p)[0] end
local storage=ffi.new('uint8_t[?]',0x1100000+16)
local heap=math.floor((tonumber(ffi.cast('uintptr_t',storage))+15)/16)*16

local next_free=heap
local function alloc(size,align)
    next_free=math.floor((next_free+(align or 16)-1)/(align or 16))*(align or 16)
    local address=next_free;next_free=next_free+size;assert(next_free<=heap+0x1100000);return address
end
local env={state=alloc(0xac230)}
put(image+0x3326340,'uint64_t',env.state);put(env.state+0xac21c,'uint32_t',4)
local missing
local function read(p,n)
    if p==missing then return nil end
    assert((p>=heap and p+n<=heap+0x1100000) or (p>=image and p+n<=image+image_size),'invalid test address')
    return ffi.string(ffi.cast('const char *',p),n)
end
local backend={base=image,read=read,u32=function(s,i)
    if not s then return nil end
    local a,b,c,d=s:byte(i+1,i+4);return a+256*b+65536*c+16777216*d
end,pointer=function(p) return tonumber(get(p,'uint64_t')) end,
pulse_byte=function(p,v) put(p,'uint8_t',v) end,
replace_bytes=function(p,expected,value)
    if read(p,#expected)~=expected then return false end
    ffi.copy(ffi.cast('void *',p),value,#value);return true
end}
local registry=alloc(0xf40000)
local pm=alloc(0x400)
local manager=alloc(0x100)
local entities=alloc(8*4,8)
local instances=alloc(0x1470*4)
local entity_a,entity_b=alloc(0x20),alloc(0x20)
local network_map=alloc(8*8)
local override_map=alloc(8*8)
local override_defs=alloc(0x28b8*2)
local resources=alloc(150*16+0x960+40*0x28b8,4)+4 -- live table pointer ended in 4
local controls=alloc(0x4200)
put(image+0x347cf18,'uint64_t',controls)

-- Local avatar key through the same maps as input.lua's context().
local KEY,NETWORK=0x400169,7
put(image+0x3326468,'uint64_t',pm);put(pm+0x88,'uint32_t',1);put(pm+0x3a8,'uint32_t',NETWORK)
put(image+0x346bf98,'uint64_t',registry)
local function map(owner,offset,data,cap,seed,pairs_)
    put(owner+offset,'uint64_t',data);put(owner+offset+8,'uint32_t',cap)
    put(owner+offset+12,'uint32_t',0);put(owner+offset+16,'uint32_t',seed)
    for _,p in ipairs(pairs_)do
        local hash=(p[1]*seed)%4294967296
        for probe=0,cap-1 do
            local slot=data+((hash+probe)%cap)*8
            if get(slot,'uint32_t')==0 then put(slot,'uint32_t',p[1]);put(slot+4,'uint32_t',p[2]);break end
        end
    end
end
map(registry,0xf22ec8,network_map,8,3,{{NETWORK,3}})
put(registry+0xf32f20+24*3,'uint32_t',KEY)
put(image+0x3483c24,'uint32_t',0xffffffff)
for _,g in ipairs(guards)do ffi.copy(ffi.cast('void *',image+g.rva),g.bytes,#g.bytes)end

-- Resource definitions: the bucket is the 64-bit resource key modulo 150.
put(registry+0xf127a0,'uint64_t',resources)
local function resource(entity,key,index)
    put(entity,'uint64_t',key)
    local bucket=tonumber(key%150ULL)
    while get(resources+bucket*16,'uint64_t')~=0ULL do bucket=(bucket+1)%150 end
    put(resources+bucket*16,'uint64_t',key);put(resources+bucket*16+8,'uint32_t',index)
    return resources+0x960+index*0x28b8
end
local def_a=resource(entity_a,0xb7c9c0d0c39aa349ULL,33)
for stage,kind in ipairs({11,23,12,21,24,21})do put(def_a+(stage-1)*0x278,'uint32_t',kind)end
put(def_a+2*0x278+0xd4,'uint32_t',6)
put(entity_a+8,'uint32_t',0x40008d);put(entity_a+0x14,'uint32_t',1)
-- Entity b uses the per-entity override table instead.
put(entity_b,'uint64_t',0xacc611541cd839dbULL);put(entity_b+8,'uint32_t',0x4003d8);put(entity_b+0x14,'uint32_t',1)
map(manager,0x70,override_map,8,2,{{0x4003d8,1}})
put(manager+0xb0,'uint64_t',override_defs)
put(override_defs+0x28b8+0x278,'uint32_t',12);put(override_defs+0x28b8+0x278+0xd4,'uint32_t',4)

put(image+0x3326700,'uint64_t',manager)
put(manager+0x20,'uint32_t',2);put(manager+0x48,'uint64_t',entities);put(manager+0x58,'uint64_t',instances)
put(entities,'uint64_t',entity_a);put(entities+8,'uint64_t',entity_b)
local function state(instance,stage)return instance+0x410+stage*0x104 end
local synced
local function terminal(instance,stage,stages,progress,code,user)
    ffi.fill(ffi.cast('void *',instance),0x1470)
    put(synced+48*((instance-instances)/0x1470)+4,'uint32_t',stage)
    put(instance+0x1458,'uint32_t',0xffffffff)
    put(instance+0x404,'uint32_t',stage);put(instance+0x40c,'uint32_t',stages)
    put(instance+0x145c,'uint32_t',user or KEY);put(instance+0x1460,'uint8_t',1)
    put(state(instance,stage),'uint32_t',progress)
    for i,d in ipairs(code)do put(state(instance,stage)+4*i,'uint32_t',d)end
end
synced=alloc(48*2)
put(manager+0x60,'uint64_t',synced)
map(manager,0x30,alloc(8*8),8,1,{{0x40008d,0},{0x4003d8,1}})
put(manager+0x14,'uint32_t',2)
put(image+0x3483c20,'uint32_t',0xffffffff)
put(image+0x3483c4c,'uint32_t',0xffffffff)
local A,B=instances,instances+0x1470

local api={enabled=true,auto_terminal_complete=true}
local scope={terminal_guards_25480438=guards}
setmetatable(scope,{__index=_G})
local T=setfenv(assert(loadfile(here..'/../hud/terminal.lua')),scope)()
local bridge={dbf_hud_guard=function(rva,expected,size)
    return read(image+rva,size)==expected and 1 or 0
end}
local function controller() return T.terminal_controller(backend,bridge,scope.terminal_arrow_update) end

local failures=0
local function case(name,setup,check)
    local t=controller()
    setup(t)
    t.update(1,api)
    local ok,why=pcall(check,t)
    print((ok and 'PASS ' or 'FAIL ')..name..' | '..tostring(t.status)..(t.reason and ' ('..t.reason..')' or '')..(ok and '' or ' -> '..tostring(why)))
    if not ok then failures=failures+1 end
end
local CODE={3,2,3,4,3,3}
local function progress(instance,stage)return get(state(instance,stage),'uint32_t')end
case('host arrow stage completes',function()terminal(A,2,6,3,CODE);terminal(B,0,2,0,{1,1,1,1},0x325)end,
    function()assert(progress(A,2)==6);assert(progress(B,0)==0)end)
case('setting off leaves it alone',function()api.auto_terminal_complete=false;terminal(A,2,6,3,CODE)end,
    function()api.auto_terminal_complete=true;assert(progress(A,2)==3)end)
case('mod disabled leaves it alone',function()api.enabled=false;terminal(A,2,6,3,CODE)end,
    function()api.enabled=true;assert(progress(A,2)==3)end)
case('missing enable value fails closed',function()api.auto_terminal_complete=nil;terminal(A,2,6,0,CODE)end,
    function()api.auto_terminal_complete=true;assert(progress(A,2)==0)end)
case('non-arrow stage is skipped',function()terminal(A,1,6,0,{})end,
    function()assert(progress(A,1)==0)end)
-- Arrows: the module sets controls+0x3FC8+action*32 and runs the arrow stage
-- update (989750) itself. Offline a fake update stands in for 989750.
local function arrow(action)return controls+0x3fc8+32*action end
local function pressed()
    local list={}
    for action=1,4 do if get(arrow(action),'uint8_t')~=0 then list[#list+1]=action end end
    return list
end
local calls,behaviour={},'take'
-- Like the game: a pressed arrow advances the code, a wrong one sets -1.
scope.terminal_arrow_update=function(manager_,s,length_field,entity,dt,is_local)
    calls[#calls+1]={manager=manager_,state=s,length_field=length_field,entity=entity,dt=dt,is_local=is_local,pressed=pressed()}
    if behaviour=='error' then error('fake update failed') end
    if behaviour=='ignore' then return end
    local at=get(s,'uint32_t')
    for direction,action in ipairs({3,2,4,1})do
        if get(arrow(action),'uint8_t')~=0 then
            put(s,'uint32_t',behaviour~='reject' and get(s+4+4*at,'uint32_t')==direction and at+1 or 0xffffffff)
            return
        end
    end
end
local function client(on)put(entity_a+0x14,'uint32_t',on and 0 or 1)end
local function arrow_case(name,mode,interval,host,setup,frames,check)
    local t=controller();calls,behaviour={},'take'
    api.terminal_input,api.input_interval_ms=mode,interval;client(not host);setup()
    local seen={}
    for frame=1,frames do t.update(1/60,api);seen[frame]=progress(A,2)end
    local ok,why=pcall(check,t,seen)
    api.terminal_input,api.input_interval_ms=nil,nil;client(false);behaviour='take'
    for action=1,4 do put(arrow(action),'uint8_t',0)end
    print((ok and 'PASS ' or 'FAIL ')..name..' | '..tostring(t.status)..(ok and '' or ' -> '..tostring(why)))
    if not ok then failures=failures+1 end
end
arrow_case('client enters an arrow through the stage update',1,70,false,function()terminal(A,2,6,3,CODE)end,1,
    function(t,seen)
        local c=assert(calls[1],'989750 called')
        assert(#calls==1 and seen[1]==4,'one arrow, no direct write')
        assert(c.manager==manager and c.state==state(A,2) and c.entity==entity_a,'caller arguments')
        assert(c.length_field==def_a+2*0x278+0xd4,'definition+0xD4')
        assert(c.dt==0 and c.is_local==1,'dt 0, local interactor')
        assert(#c.pressed==1 and c.pressed[1]==1,'left (code 4) is action 1, pressed during the call')
        assert(#pressed()==0,'restored after the call')
        assert(t.status=='Client: Entering terminal code 3/6 (4/6)')end)
arrow_case('client on Instant: one arrow per frame',1,70,false,function()terminal(A,2,6,0,CODE)end,8,
    function(t,seen)assert(seen[1]==1 and seen[2]==2 and seen[6]==6);assert(#calls==6);assert(#pressed()==0)
        assert(t.status=='Code entered; waiting for the terminal')end)
arrow_case('gives up after 3 untaken arrows',1,70,false,function()terminal(A,2,6,1,CODE);behaviour='ignore'end,10,
    function(t,seen)assert(seen[10]==1 and #calls==3);assert(#pressed()==0);assert(t.status=='Client: The terminal did not take the arrows')end)
arrow_case('stops on a rejected arrow',1,70,false,function()terminal(A,2,6,0,CODE);behaviour='reject'end,10,
    function(t,seen)
        assert(#calls==1 and seen[1]==0xffffffff);assert(#pressed()==0)
        put(state(A,2),'uint32_t',0);t.update(1,api);t.update(1,api) -- reset timer expired
        assert(#calls==1,'never loops');assert(t.status=='Client: The terminal rejected an arrow')end)
arrow_case('restores the byte when the update fails',1,70,false,function()terminal(A,2,6,0,CODE);behaviour='error'end,1,
    function(t,seen)assert(#calls==1);assert(#pressed()==0);assert(t.status=='refused' and t.reason:find('fake update failed',1,true))end)
arrow_case('waits while an arrow is held',1,70,false,function()terminal(A,2,6,0,CODE);put(arrow(3),'uint8_t',1)end,5,
    function(t,seen)assert(#calls==0);assert(get(arrow(3),'uint8_t')==1 and #pressed()==1);assert(t.status=='Arrow key held; waiting')end)
-- Terminal input "Enter arrows": the host enters arrows too, paced by the interval.
arrow_case('host Enter arrows enters instead of writing',2,70,true,function()terminal(A,2,6,3,CODE)end,1,
    function(t,seen)assert(seen[1]==4 and #calls==1);assert(t.status=='Entering terminal code 3/6 (4/6)')end)
arrow_case('host Enter arrows at 70 ms',2,70,true,function()terminal(A,2,6,0,CODE)end,60,
    function(t,seen)assert(seen[15]<6,'paced, not instant');assert(seen[60]==6);assert(#calls==6);assert(#pressed()==0)end)
arrow_case('host Enter arrows at 0 ms: one per frame',2,0,true,function()terminal(A,2,6,0,CODE)end,8,
    function(t,seen)assert(seen[1]==1 and seen[2]==2 and seen[6]==6)end)
arrow_case('host Instant still writes',1,70,true,function()terminal(A,2,6,0,CODE)end,1,
    function(t,seen)assert(seen[1]==6 and #calls==0)end)
case('wrong arrow waits for reset',function()terminal(A,2,6,0xffffffff,CODE)end,
    function()assert(progress(A,2)==0xffffffff)end)
case('reset timer waits',function()terminal(A,2,6,0,CODE);put(state(A,2)+0x30,'float',0.5)end,
    function()assert(progress(A,2)==0)end)
case('input gate waits',function()terminal(A,2,6,0,CODE);put(state(A,2)+0x34,'float',0.25)end,
    function()assert(progress(A,2)==0)end)
case('another player at the terminal',function()terminal(A,2,6,1,CODE,0x400170)end,
    function()assert(progress(A,2)==1)end)
case('not in use',function()terminal(A,2,6,1,CODE);put(A+0x1460,'uint8_t',0)end,
    function()assert(progress(A,2)==1)end)
case('invalid direction refuses',function()terminal(A,2,6,1,{3,2,3,9,3,3})end,
    function(t)assert(progress(A,2)==1);assert(t.status=='refused')end)
case('override definition, second instance',function()terminal(A,0,6,0,{},0x325);terminal(B,1,2,2,{1,2,3,4})end,
    function()assert(progress(B,1)==4)end)
case('finished terminal',function()terminal(A,6,6,0,{})end,
    function(t)assert(t.status=='Terminal finished')end)
case('no gameplay',function()put(env.state+0xac21c,'uint32_t',3);terminal(A,2,6,3,CODE)end,
    function()put(env.state+0xac21c,'uint32_t',4);assert(progress(A,2)==3)end)
arrow_case('stale sync stage refuses native call',2,0,true,function()
    terminal(A,2,6,0,CODE);put(synced+4,'uint32_t',1)
end,1,function(t,seen) assert(#calls==0 and seen[1]==0 and #pressed()==0 and t.status=='refused') end)
arrow_case('stale entity index refuses native call',2,0,true,function()
    terminal(A,2,6,0,CODE);put(entity_a+8,'uint32_t',0x40008e)
end,1,function(t,seen)
    put(entity_a+8,'uint32_t',0x40008d)
    assert(#calls==0 and seen[1]==0 and #pressed()==0)
end)
case('active interactor belongs to another avatar',function()
    terminal(B,1,2,0,{1,2,3,4},KEY+1);terminal(A,2,6,0,CODE);put(A+0x1458,'uint32_t',KEY+1)
end,function(t) assert(progress(A,2)==0 and t.status=='Waiting for a terminal') end)
local random,draws=math.random,0
arrow_case('random delay chosen once per stage',2,70,true,function()
    math.random=function(lo,hi) assert(lo==70 and hi==240);draws=draws+1;return 115 end
    api.randomize_input_delay=true;terminal(A,2,6,0,CODE)
end,100,function(t,seen)
    math.random=random;api.randomize_input_delay=nil;assert(draws==1)
    local frames={}
    for i,p in ipairs(seen)do if i==1 or p~=seen[i-1] then frames[#frames+1]=i end end
    assert(#frames==6 and #calls==6)
    local step=frames[2]-frames[1]
    assert(step>=5 and step<=15)
    for i=3,6 do assert(frames[i]-frames[i-1]==step) end
end)
local guard=guards[10]
case('unreadable witness retries on next poll',function()
    terminal(A,2,6,0,CODE);missing=image+guard.rva
end,function(t)
    assert(progress(A,2)==0 and t.status:match('Waiting for terminal code page'))
    missing=nil;t.update(1,api);assert(progress(A,2)==6)
end)
case('encrypted witness blocks mutations until admitted',function()
        terminal(A,2,6,3,CODE);put(image+guard.rva,'uint8_t',0xcc)end,
    function(t)
        assert(progress(A,2)==3 and t.status:find(guard.name,1,true))
        t.update(1,api);assert(progress(A,2)==3)
        ffi.copy(ffi.cast('void *',image+guard.rva),guard.bytes,#guard.bytes)
        t.update(1,api);assert(progress(A,2)==6)end)
local pulse_byte=backend.pulse_byte
arrow_case('failed press and release retain cleanup without repeating native input',2,0,true,function()
    terminal(A,2,6,0,CODE)
    backend.pulse_byte=function(p,v)
        if v==1 then pulse_byte(p,v) end -- ambiguous failure after writing the byte
        error('write failed')
    end
end,2,function(t,seen)
    assert(#calls==0 and seen[2]==0 and #pressed()==1)
    local ok,why=t.retry_cleanup();assert(not ok and why:find('write failed',1,true))
    backend.pulse_byte=pulse_byte
    put(image+0x347cf18,'uint64_t',controls+8)
    assert(not t.retry_cleanup() and #pressed()==1,'do not write through a different owner')
    put(image+0x347cf18,'uint64_t',controls)
    assert(t.retry_cleanup() and #pressed()==0)
    t.update(1,api);assert(#calls==0 and t.status=='refused')
end)
arrow_case('successful arrow is not replayed during release retries',2,0,true,function()
    terminal(A,2,6,0,CODE)
    backend.pulse_byte=function(p,v)
        if v==0 then error('release pending') end
        pulse_byte(p,v)
    end
end,2,function(t,seen)
    assert(#calls==1 and seen[2]==1 and #pressed()==1)
    assert(not t.retry_cleanup())
    backend.pulse_byte=pulse_byte
    assert(t.retry_cleanup() and t.retry_cleanup() and #pressed()==0 and #calls==1)
end)
assert(storage and image_storage) -- keep the synthetic address ranges alive
print(failures==0 and 'PASS terminal' or ('FAIL terminal: '..failures))
os.exit(failures==0 and 0 or 1)
