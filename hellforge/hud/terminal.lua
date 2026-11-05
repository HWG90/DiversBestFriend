-- R50 Auto Terminal Complete, mapped to build 25480438. The game thread owns
-- the backend. Terminal admission is lazy and independent of display admission.
local MANAGER,REGISTRY,INVALID_ID=0x3326700,0x346bf98,0x3483c24
local CONTROLS,ARROW_INPUT,ARROW_UPDATE=0x347cf18,0x3fc8,0x989750
local ARROW_ACTION={3,2,4,1} -- code direction (1 up, 2 right, 3 down, 4 left) -> controls action
local PRESS_MISSES=3
local INSTANCE_SIZE,STATE_BASE,STATE_SIZE=0x1470,0x410,0x104
local DEFINITION_SIZE,STAGE_SIZE=0x28b8,0x278
local ARROW_STAGE,ARROW_LENGTH=12,0xd4
local MAX_INSTANCES,MAX_STAGES,MAX_CODE=64,16,62
local ZERO8=string.rep('\0',8)

local function terminal_controller(b,bridge,arrow_update)
    local ffi=require('ffi')
    local self={status='waiting_native'}
    local checked,pulse
    local clock,next_poll=0,0
    local misses,given_up=0,nil
    -- 989750(manager, stage state, definition+0xD4, entity, dt, local interactor),
    -- the arguments its caller 985839 passes. Cast on first use.
    -- Per update: whether to press arrows as host, and the delay between them.
    local entering,interval_ms,randomize=true,70,false
    local stage_delay={}
    local float_buffer=ffi.new('float[1]')
    local function u32(p)
        local value=b.u32(b.read(p,4),0);if value==nil then error(string.format('Terminal memory unavailable at 0x%x',p)) end
        return value
    end
    -- Native tables may be 4-byte aligned; object pointers are checked for 8.
    local function ptr(p,alignment)
        local bytes=b.read(p,8)
        local value=bytes and b.u32(bytes,0)+b.u32(bytes,4)*4294967296
        if not value or value<65536 or value>=2^47 or value%(alignment or 8)~=0 then
            error(string.format('Terminal pointer invalid at 0x%x',p))
        end
        return value
    end
    local function u8(p)
        local bytes=b.read(p,1);local value=bytes and bytes:byte();if value==nil then error(string.format('Terminal memory unavailable at 0x%x',p)) end
        return value
    end
    local function float(p)
        local bytes=b.read(p,4);if not bytes then error(string.format('Terminal memory unavailable at 0x%x',p)) end
        ffi.copy(float_buffer,bytes,4)
        local value=float_buffer[0]
        assert(value==value and math.abs(value)<math.huge,'Invalid terminal timer')
        return value
    end
    local function le32(v)
        return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256)
    end
    -- Open-addressed id map: data, capacity, empty key, seed (as in input.lua).
    local function find(owner,offset,key)
        local cap=u32(owner+offset+8)
        if cap==0 then return nil end
        local power=1;while power<cap do power=power*2 end
        assert(cap<=65536 and power==cap,'Invalid terminal map capacity')
        local empty,seed=u32(owner+offset+12),u32(owner+offset+16)
        local hash=(key%65536*seed+(math.floor(key/65536)*seed%65536)*65536)%4294967296
        local data=ptr(owner+offset,4)
        for probe=0,cap-1 do
            local slot=data+((hash+probe)%cap)*8
            local found=u32(slot)
            if found==empty then return nil end
            if found==key then return u32(slot+4) end
        end
        error('Terminal map has no terminating entry')
    end
    local function local_key(base)
        local pm=ptr(base+0x3326468)
        assert(u32(pm+0x88)>0,'No local player')
        local network=u32(pm+0x3a8)
        assert(network<0x7fff,'Local network index unavailable')
        local registry=ptr(base+REGISTRY)
        local index=find(registry,0xf22ec8,network)
        assert(index and index<65536,'Local ownership mapping unavailable')
        return u32(registry+0xf32f20+24*index)
    end
    -- 4FC110: a per-entity override first, else the resource's definition.
    local function definition(base,manager,entity)
        local id=u32(entity+8)
        if id~=u32(base+INVALID_ID) then
            local index=find(manager,0x70,id)
            -- 4FC190 zeroes the entry pointer on exhaustion and 4FC1A6
            -- dereferences it. A usable override lookup must terminate on a slot.
            assert(u32(manager+0x78)>0,'Terminal override map unavailable')
            if index and index~=0xffffffff then
                assert(index<u32(manager+0x14),'Terminal override exceeds allocation')
                return ptr(manager+0xb0)+index*DEFINITION_SIZE
            end
        end
        -- 4FBCF0: 150 buckets of {uint64 resource, uint32 index}, probed linearly.
        local key=b.read(entity,8)
        if not key or key==ZERO8 then return nil end
        local table_=ptr(ptr(base+REGISTRY)+0xf127a0,4)
        local bucket=(b.u32(key,4)%150*46+b.u32(key,0)%150)%150 -- 2^32 % 150 == 46
        for _=1,150 do
            local slot=table_+bucket*16
            local found=b.read(slot,8)
            if not found then error(string.format('Terminal memory unavailable at 0x%x',slot)) end
            if found==key then
                local index=u32(slot+8)
                assert(index<150,'Invalid terminal resource definition index')
                return table_+0x960+index*DEFINITION_SIZE
            end
            if found==ZERO8 then return nil end
            bucket=bucket==149 and 0 or bucket+1
        end
    end
    -- Code pages can stay unreadable until the game first runs them, so the
    -- witnesses are checked when an arrow stage is actually live.
    local function guards_ready()
        if checked then return true end
        for _,guard in ipairs(terminal_guards_25480438) do
            if bridge.dbf_hud_guard(guard.rva,guard.bytes,#guard.bytes)~=1 then
                return false,guard.name
            end
        end
        checked=true;return true
    end
    -- Seconds after each entered arrow: the input interval when entering arrows
    -- (a random 70-240 ms per stage if randomized), none for a client on Instant.
    local function pace(stage_key)
        if not entering then return 0 end
        if not randomize then return interval_ms/1000 end
        if stage_delay.key~=stage_key then stage_delay={key=stage_key,ms=math.random(70,240)} end
        return stage_delay.ms/1000
    end
    -- A failed write can have taken effect. Keep the receipt until readback
    -- confirms release, and never restore through a replaced controls pointer.
    function self.retry_cleanup()
        if not pulse then return true end
        local ok,why=pcall(function()
            assert(ptr(b.base+CONTROLS)==pulse.controls,'Terminal controls changed during restoration')
            local byte=u8(pulse.address)
            if byte==0 then return end
            assert(byte==1,'Terminal arrow byte changed during restoration')
            b.pulse_byte(pulse.address,0)
            assert(u8(pulse.address)==0,'Terminal arrow release did not take')
        end)
        if not ok then return false,tostring(why) end
        pulse=nil
        return true
    end
    -- Enter the next arrow: set the controls byte 98987D..9898F2 read, run the
    -- stage update once, restore the byte (always, as input.lua does), then
    -- check that progress moved. Never while the player holds an arrow.
    local function enter_arrow(base,manager,entity,stage_def,state,progress,length,label,stage_key,host)
        local controls=ptr(base+CONTROLS)
        local inputs=controls+ARROW_INPUT
        for action=1,4 do
            if u8(inputs+32*action)~=0 then self.status='Arrow key held; waiting';return end
        end
        local address=inputs+32*ARROW_ACTION[u32(state+4+4*progress)]
        local who=host and '' or 'Client: '
        if not arrow_update then
            arrow_update=ffi.cast('void (*)(uintptr_t, uintptr_t, uintptr_t, uintptr_t, float, uint8_t)',base+ARROW_UPDATE)
        end
        -- Terminal witnesses passed in complete(); writes are verified.
        pulse={controls=controls,address=address}
        local ok,why=pcall(function()
            b.pulse_byte(address,1)
            assert(u8(address)==1,'Terminal arrow press failed')
            arrow_update(manager,state,stage_def+ARROW_LENGTH,entity,0,1)
        end)
        if not ok then self.disabled='Terminal arrow call failed: '..tostring(why) end
        local restored,restore_error=self.retry_cleanup()
        assert(restored,restore_error)
        if self.disabled then error(self.disabled) end
        self.injecting,self.pace=true,pace(stage_key)
        local now=u32(state)
        if now==progress then
            misses=misses+1
            self.status=who..'Entering terminal code '..label..' (arrow not taken)'
            if misses>=PRESS_MISSES then
                misses=0
                self.status=who..'The terminal did not take the arrows'
                given_up={key=stage_key,status=self.status}
            end
        elseif now==0xffffffff then
            -- The terminal read a different arrow than the code: stop, never loop.
            misses=0
            self.status=who..'The terminal rejected an arrow'
            given_up={key=stage_key,status=self.status}
        else
            misses=0
            self.status=who..'Entering terminal code '..label..' ('..now..'/'..length..')'
            if now==length then
                self.status=who..'Entered terminal code stage '..label..' ('..length..' arrows)'
            end
        end
    end
    local function complete(base,manager,index,instance,entity)
        local stage,stages=u32(instance+0x404),u32(instance+0x40c)
        assert(stages<=MAX_STAGES and stage<=stages,'Invalid terminal stages')
        if stage==stages then self.status='Terminal finished';return end
        local def=assert(definition(base,manager,entity),'Terminal definition unavailable')
        local stage_def=def+stage*STAGE_SIZE
        if u32(stage_def)~=ARROW_STAGE then self.status='Terminal stage '..(stage+1)..'/'..stages..' is not an arrow code';return end
        local ready,page=guards_ready()
        if not ready then self.status='Waiting for terminal code page '..page;return end
        local length=u32(stage_def+ARROW_LENGTH)
        assert(length>=1 and length<=MAX_CODE,'Invalid terminal code length')
        local state=instance+STATE_BASE+stage*STATE_SIZE
        for i=1,length do local d=u32(state+4*i);assert(d>=1 and d<=4,'Invalid terminal direction') end
        local progress=u32(state)
        -- A wrong arrow sets progress to -1 and starts the reset timer.
        if progress==0xffffffff or float(state+0x30)>0 then self.status='Wrong arrow; waiting for the terminal to reset';return end
        if float(state+0x34)>0 then self.status='Terminal not accepting input yet';return end
        if progress>=length then self.status='Code entered; waiting for the terminal';return end
        local label=(stage+1)..'/'..stages
        local host=u32(entity+0x14)%2==1
        -- The native update resolves the entity again and indexes both arrays.
        -- Require the same instance and synchronized stage even for a host skip.
        local id=u32(entity+8)
        assert(id~=u32(base+0x3483c20) and find(manager,0x30,id)==index,
            'Terminal update entity index changed')
        local synced=ptr(manager+0x60)+48*index
        assert(u32(synced+4)==stage,'Terminal synchronized stage changed')
        if entering or not host then
            local stage_key=instance..':'..stage
            if given_up and given_up.key==stage_key then self.status=given_up.status;return end
            return enter_arrow(base,manager,entity,stage_def,state,progress,length,label,stage_key,host)
        end
        if not b.replace_bytes(state,le32(progress),le32(length)) then self.status='Terminal progress changed; retrying';return end
        assert(u32(state)==length,'Terminal progress write failed')
        self.status='Completed terminal code stage '..label..' ('..length..' arrows)'
    end
    local function poll()
        local base=b.base
        self.injecting=false
        if u32(ptr(base+0x3326340)+0xac21c)~=4 then self.status='Not in gameplay';return end
        local manager=b.pointer(base+MANAGER)
        if not manager then self.status='No terminals';return end
        local count=u32(manager+0x20)
        if count==0 then self.status='No terminals';return end
        assert(count<=MAX_INSTANCES,'Invalid terminal count')
        local key=local_key(base)
        local invalid=u32(base+0x3483c4c)
        assert(key~=invalid,'Local avatar unavailable')
        local instances,entities=ptr(manager+0x58),ptr(manager+0x48)
        for index=0,count-1 do
            local instance=instances+index*INSTANCE_SIZE
            if u32(instance+0x145c)==key and u8(instance+0x1460)==1 then
                local primary=u32(instance+0x1458)
                if primary==invalid or primary==key then
                    return complete(base,manager,index,instance,ptr(entities+8*index))
                end
            end
        end
        self.status='Waiting for a terminal'
    end
    function self.update(dt,settings)
        local restored,why=self.retry_cleanup()
        if not restored then self.status='Terminal arrow release pending';self.reason=why;return end
        clock=clock+(type(dt)=='number'and math.max(0,math.min(dt,1))or 1/60)
        if clock<next_poll then return end;next_poll=clock+.1
        local enabled=settings and settings.enabled~=false and settings.auto_terminal_complete==true
        entering=not settings or settings.terminal_input~=1 -- only an explicit Instant choice skips pacing
        randomize=settings and settings.randomize_input_delay==true
        interval_ms=settings and settings.input_interval_ms
        if type(interval_ms)~='number' or interval_ms~=interval_ms or interval_ms<0 or interval_ms>250 then interval_ms=70 end
        if self.disabled then self.status='refused';self.reason=self.disabled;return end
        if not enabled then self.status='off';self.reason=nil;return end
        local ok,why=pcall(poll)
        if ok then self.reason=nil else self.status='refused';self.reason=tostring(why);next_poll=clock+1 end
        -- While entering: the next arrow after the pace (0 = next frame).
        if ok and self.injecting then next_poll=clock+self.pace end
    end
    return self
end
return {terminal_controller=terminal_controller}
