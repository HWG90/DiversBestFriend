-- Auto Terminal Complete (build 26251122). Objective terminals run arrow codes
-- as InteractableMinigame stages of definition type 12. On the host, the stage
-- update (99B400) copies local progress into the synced record every frame and
-- ends the stage once progress reaches the definition's code length, so one
-- compare-and-write of the progress counter completes the code (live test,
-- 2026-10-25). A client reports progress to the host only when the stage update
-- itself sees an arrow (RPC E095A8BA), so a client enters each arrow the way
-- input.lua enters stratagem codes: set the controls byte that update reads,
-- run the update once (dt 0), restore the byte. A byte set from Lua alone is
-- never seen by the game's own update (live 2026-10-29: 3 of 3 presses untaken).
-- Terminal input "Enter arrows" does the same as host, paced by the stratagem
-- input interval.
local GUARDS=mod.require('src/terminal_guards.lua')
local MANAGER,REGISTRY,INVALID_ID=0x2ce18b0,0x2ce41b8,0x2e3f0d4
local CONTROLS,ARROW_INPUT,ARROW_UPDATE=0x2e38250,0x3fc8,0x99b400
local ARROW_ACTION={3,2,4,1} -- code direction (1 up, 2 right, 3 down, 4 left) -> controls action
local PRESS_MISSES=3
local INSTANCE_SIZE,STATE_BASE,STATE_SIZE=0x1470,0x410,0x104
local DEFINITION_SIZE,STAGE_SIZE=0x28c0,0x278
local ARROW_STAGE,ARROW_LENGTH=12,0xd4
local MAX_INSTANCES,MAX_STAGES,MAX_CODE=64,16,62
local ZERO8=string.rep('\0',8)

local M={}
function M.new(factories)
    local ffi=require('ffi')
    local self={status='waiting_native'}
    local b,checked
    local clock,next_poll=0,0
    local misses,given_up=0,nil
    -- 99B400(manager, stage state, definition+0xD4, entity, dt, local interactor),
    -- the arguments its caller 9974BF passes. Cast on first use.
    local arrow_update=factories.terminal_arrow_update -- offline checks substitute it
    -- Per update: whether to press arrows as host, and the delay between them.
    local entering,interval_ms,randomize=false,70,false
    local stage_delay={}
    local events={}
    local float_buffer=ffi.new('float[1]')
    local function publish()
        local api=rawget(_G,'DiversBestFriend')
        if api then api.terminal_status=self.status;api.terminal_reason=self.reason end
    end
    local function event(message)
        local dated,stamp=pcall(os.date,'%H:%M:%S ')
        events[#events+1]=(dated and stamp or '')..message
        if #events>8 then table.remove(events,1) end
        pcall(function()
            local loader=rawget(_G,'CowboyBingusModLoader')
            local file=loader and loader.open_log and loader.open_log('DiversBestFriend-terminal.log')
            if file then file:write(table.concat(events,'\n')..'\n');file:close() end
        end)
    end
    local function u32(p)
        local value=b.read_u32(p);if value==nil then error(string.format('Terminal memory unavailable at 0x%x',p)) end
        return value
    end
    -- Native tables may be 4-byte aligned; object pointers are checked for 8.
    local function ptr(p,alignment)
        local value=b.read_u64(p)
        if not value or value<65536 or value>=2^47 or value%(alignment or 8)~=0 then
            error(string.format('Terminal pointer invalid at 0x%x',p))
        end
        return value
    end
    local function u8(p)
        local value=b.read_u8(p);if value==nil then error(string.format('Terminal memory unavailable at 0x%x',p)) end
        return value
    end
    local function float(p)
        local bytes=b.read(p,4);if not bytes then error(string.format('Terminal memory unavailable at 0x%x',p)) end
        ffi.copy(float_buffer,bytes,4);return float_buffer[0]
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
            if found==key then return u32(slot+4) end
            if found==empty then return nil end
        end
    end
    local function local_key(base)
        local pm=ptr(base+0x2ce1618)
        assert(u32(pm+0x88)>0,'No local player')
        local network=u32(pm+0x3a8)
        assert(network<0x7fff,'Local network index unavailable')
        local registry=ptr(base+REGISTRY)
        local index=find(registry,0xf24990,network)
        assert(index and index<65536,'Local ownership mapping unavailable')
        return u32(registry+0xf349e8+24*index)
    end
    -- 5044B0: a per-entity override first, else the resource's definition.
    local function definition(base,manager,entity)
        local id=u32(entity+8)
        if id~=u32(base+INVALID_ID) then
            local index=find(manager,0x70,id)
            if index and index~=0xffffffff then return ptr(manager+0xb0)+index*DEFINITION_SIZE end
        end
        -- 504090: 150 buckets of {uint64 resource, uint32 index}, probed linearly.
        local key=b.read(entity,8)
        if not key or key==ZERO8 then return nil end
        local table_=ptr(ptr(base+REGISTRY)+0xf14250,4)
        local bucket=(b.u32(key,4)%150*46+b.u32(key,0)%150)%150 -- 2^32 % 150 == 46
        for _=1,150 do
            local slot=table_+bucket*16
            local found=b.read(slot,8)
            if not found then error(string.format('Terminal memory unavailable at 0x%x',slot)) end
            if found==key then return table_+0x960+u32(slot+8)*DEFINITION_SIZE end
            if found==ZERO8 then return nil end
            bucket=bucket==149 and 0 or bucket+1
        end
    end
    -- Code pages can stay unreadable until the game first runs them, so the
    -- witnesses are checked when an arrow stage is actually live.
    local function guards_ready(base)
        if checked then return true end
        for _,guard in ipairs(GUARDS) do
            local bytes=b.read(base+guard.rva,#guard.bytes)
            if bytes==nil then return false,guard.name end
            if bytes~=guard.bytes then self.disabled='Terminal code changed: '..guard.name;error(self.disabled) end
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
    -- Enter the next arrow: set the controls byte 99B52F..99B5A4 read, run the
    -- stage update once, restore the byte (always, as input.lua does), then
    -- check that progress moved. Never while the player holds an arrow.
    local function enter_arrow(base,manager,entity,stage_def,state,progress,length,label,stage_key,host)
        local inputs=ptr(base+CONTROLS)+ARROW_INPUT
        for action=1,4 do
            if u8(inputs+32*action)~=0 then self.status='Arrow key held; waiting';return end
        end
        local address=inputs+32*ARROW_ACTION[u32(state+4+4*progress)]
        local who=host and '' or 'Client: '
        if not arrow_update then
            -- Logged before the first call, so a crash leaves it as the last line.
            event(who..'First terminal arrow through 99B400 (stage '..label..')')
            arrow_update=ffi.cast('void (*)(uintptr_t, uintptr_t, uintptr_t, uintptr_t, float, uint8_t)',base+ARROW_UPDATE)
        end
        -- Terminal witnesses passed in complete(); writes are verified.
        local ok,why=pcall(function()
            b.pulse_byte(address,1,true)
            arrow_update(manager,state,stage_def+ARROW_LENGTH,entity,0,1)
        end)
        local restored,restore_error=pcall(b.pulse_byte,address,0,true)
        assert(restored,'Arrow restoration failed: '..tostring(restore_error))
        assert(ok,why)
        self.injecting,self.pace=true,pace(stage_key)
        local now=u32(state)
        if now==progress then
            misses=misses+1
            self.status=who..'Entering terminal code '..label..' (arrow not taken)'
            if misses>=PRESS_MISSES then
                misses=0
                self.status=who..'The terminal did not take the arrows';event(self.status..' (stage '..label..')')
                given_up={key=stage_key,status=self.status}
            end
        elseif now==0xffffffff then
            -- The terminal read a different arrow than the code: stop, never loop.
            misses=0
            self.status=who..'The terminal rejected an arrow';event(self.status..' (stage '..label..')')
            given_up={key=stage_key,status=self.status}
        else
            misses=0
            self.status=who..'Entering terminal code '..label..' ('..now..'/'..length..')'
            if now==length then
                self.status=who..'Entered terminal code stage '..label..' ('..length..' arrows)';event(self.status)
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
        local ready,page=guards_ready(base)
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
        if entering or not host then
            local stage_key=instance..':'..stage
            if given_up and given_up.key==stage_key then self.status=given_up.status;return end
            return enter_arrow(base,manager,entity,stage_def,state,progress,length,label,stage_key,host)
        end
        if not b.replace_bytes(state,le32(progress),le32(length),true) then self.status='Terminal progress changed; retrying';return end
        self.status='Completed terminal code stage '..label..' ('..length..' arrows)'
        event(self.status..'; terminal '..index)
    end
    local function poll()
        local base=b.base
        self.injecting=false
        if u32(ptr(base+0x2ce1508)+0xac29c)~=4 then self.status='Not in gameplay';return end
        local manager=b.pointer(base+MANAGER)
        if not manager then self.status='No terminals';return end
        local count=u32(manager+0x20)
        if count==0 then self.status='No terminals';return end
        assert(count<=MAX_INSTANCES,'Invalid terminal count')
        local key=local_key(base)
        local instances,entities=ptr(manager+0x58),ptr(manager+0x48)
        for index=0,count-1 do
            local instance=instances+index*INSTANCE_SIZE
            if u32(instance+0x145c)==key and b.read_u8(instance+0x1460)==1 then
                return complete(base,manager,index,instance,ptr(entities+8*index))
            end
        end
        self.status='Waiting for a terminal'
    end
    function self.update(dt)
        clock=clock+(type(dt)=='number'and math.max(0,math.min(dt,1))or 1/60)
        if clock<next_poll then return end;next_poll=clock+.1
        local api=rawget(_G,'DiversBestFriend')
        local function setting(key)
            local value=api and api[key]
            if value==nil then value=(mod.config.preferences or {})[key] end
            return value
        end
        local enabled=setting('auto_terminal_complete')==true
        entering,randomize=setting('terminal_input')==2,setting('randomize_input_delay')==true
        interval_ms=setting('input_interval_ms')
        if type(interval_ms)~='number' or interval_ms~=interval_ms or interval_ms<0 or interval_ms>250 then interval_ms=70 end
        if self.disabled then self.status='refused';self.reason=self.disabled;publish();return end
        if not enabled or (api and api.enabled==false) then self.status='off';publish();return end
        if not b then
            local ok,value=pcall(factories.native_backend)
            if not ok then self.status='waiting_native';self.reason=tostring(value);next_poll=clock+1;publish();return end
            b=value
        end
        local ok,why=pcall(poll)
        if ok then self.reason=nil else self.status='refused';self.reason=tostring(why);next_poll=clock+1 end
        -- While entering: the next arrow after the pace (0 = next frame).
        if ok and self.injecting then next_poll=clock+self.pace end
        publish()
    end
    return self
end
return M
