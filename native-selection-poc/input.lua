-- Native input adapter. Only one evaluated direction byte is temporarily
-- changed, restored synchronously after the normal input handler returns.
-- Descriptor bounds and mission membership are checked before activation.
local function selectable_kind(kind)
    return type(kind)=='number' and kind>0 and kind<150 and kind%1==0
end
local function input_backend(b)
    local base=b.base
    local ffi=require('ffi')
    local timer_float=ffi.new('float[1]')
    local function decorate_timer(row)
        row.timer_seconds,row.timer_kind=nil,nil
        -- Read the same cached seconds/state the original HUD renders. This
        -- includes native special cases (shared Reinforce and Eagle timers).
        -- An unreadable or not-yet-updated card means unknown, never "ready".
        local bytes=b.read(row.address+0x3718,0x44)
        if not bytes or #bytes~=0x44 or b.u32(bytes,0x34)~=row.kind then return end
        local state=b.u32(bytes,0x40)
        if state~=3 and state~=4 then return end
        local offset=state==3 and 0 or 8
        ffi.copy(timer_float,bytes:sub(offset+1,offset+4),4)
        local seconds=tonumber(timer_float[0])
        if seconds~=seconds or seconds<=0 or seconds>86400 then return end
        row.timer_seconds=math.ceil(seconds)
        row.timer_kind=state==3 and 'incoming' or 'cooldown'
    end
    local function read(p,n)
        local s=b.read(p,n); assert(s and #s==n,'Selection memory unavailable'); return s
    end
    local function num(p) return b.u32(read(p,4),0) end
    local function ptr(p,alignment)
        local s=read(p,8)
        local value=b.u32(s,0)+b.u32(s,4)*4294967296
        assert(value>=65536 and value<2^47 and value%(alignment or 8)==0,
            string.format('Selection pointer invalid at 0x%x (value=0x%x, alignment=%d)',p,value,alignment or 8))
        return value
    end
    local function lookup(owner,offset,key,limit)
        local cap=num(owner+offset+8)
        assert(cap>0 and cap<=65536,'Invalid lookup capacity')
        local power=1; while power<cap do power=power*2 end
        assert(power==cap,'Lookup capacity is not power of two')
        local empty,seed=num(owner+offset+12),num(owner+offset+16)
        local hash=(key%65536*seed+(math.floor(key/65536)*seed%65536)*65536)%4294967296
        -- Entries are pairs of uint32_t (key/index), not pointer objects.
        -- Live r7 capture: table pointer ended in C4C, valid 4-byte alignment.
        local data=ptr(owner+offset,4)
        for probe=0,cap-1 do
            local slot=read(data+((hash+probe)%cap)*8,8)
            local found=b.u32(slot,0)
            if found==key then
                local index=b.u32(slot,4)
                assert(index<limit,'Lookup index out of bounds'); return index
            end
            if found==empty then break end
        end
        error('Local ownership mapping unavailable')
    end
    local function context(activation,allow_closed)
        local state=ptr(base+0x3326340)
        assert(num(state+0xac21c)==4,'Not in gameplay')
        local hud=ptr(base+0x346d538)
        assert(b.valid(hud),'HUD hierarchy changed')
        local hud_open=read(hud+0x395100+0x38769,1)=='\1'
        assert(allow_closed or hud_open,'Keep the stratagem menu open')
        local pm=ptr(base+0x3326468)
        assert(num(pm+0x88)>0,'No local player')
        local network=num(pm+0x3a8)
        assert(network<0x7fff,'Local network index unavailable')
        local registry=ptr(base+0x346bf98)
        local key=num(registry+0xf32f20+24*lookup(registry,0xf22ec8,network,65536))
        local manager=ptr(base+0x3326d20)
        local count=num(manager+0x70)
        assert(count>0 and count<=8,'Invalid avatar count')
        local index=lookup(manager,0xf8,key,count)
        local unit=ptr(manager+0x110+8*index)
        assert(num(unit+8)==key,'Avatar identity mismatch')
        local avatar=manager+0x53d8b0+index*0x1238
        local component=avatar+0x8d0
        assert(num(component+0x28)==key,'Input owner mismatch')
        -- Same menu-active bit tested by A8E780; HUD visibility alone is insufficient.
        local menu_active=math.floor(num(avatar+0xfd8)/512)%2==1
        assert(allow_closed or menu_active,'Native input menu is inactive')
        if activation then assert(num(avatar+0x11b8)==0,'Scrambled stratagem codes are not supported') end
        local player_context=num(avatar+0x110c)
        -- The matching routine dereferences the corresponding mission payload.
        -- Verify that its context-to-peer resolution maps to this session first.
        local player_index=lookup(pm,0xd0,player_context,32)
        local peer=read(pm+0x2c8+player_index*0x38,8)
        local session=ptr(base+0x347cef0)
        assert(peer==read(session+0xb398,8) and peer~=string.rep('\0',8),'Local peer mismatch')
        local mission=ptr(base+0x347ce50)
        local peers=num(mission+0x2d200)
        assert(peers<=32,'Invalid mission peer count')
        local payload
        for i=0,peers-1 do
            if read(mission+i*0x1690,8)==peer then
                assert(not payload,'Ambiguous local payload'); payload=mission+i*0x1690+0x38
            end
        end
        assert(payload,'Local mission payload unavailable')
        return {component=component,actions=manager+index*0xa7aec+0x4118,input_owner=manager+index*0xa7aec+0x150,
            key=key,payload=payload,context=player_context,identity=manager..':'..key,
            hud=hud,hud_open=hud_open,menu_active=menu_active}
    end
    local function code(kind)
        assert(selectable_kind(kind),'Invalid stratagem kind')
        local settings=ptr(base+0x348e8f8)
        -- Packed settings descriptors can be 4 mod 8 (live Maelstrom kind 50).
        -- Keep object-pointer alignment at 8; only this data record accepts 4.
        local info=ptr(base+0x37cb600+kind*8,4)
        assert(info>=settings and info+400<=settings+80280 and num(info)==kind,'Invalid definition')
        local n=num(info+0x48); local data=ptr(info+0x40,4)
        assert(n>=1 and n<=12 and data>=settings and data+n*4<=settings+80280,'Invalid code array')
        local result={}
        for i=0,n-1 do
            local d=num(data+i*4); assert(d>=1 and d<=4,'Invalid direction'); result[#result+1]=d
        end
        return result
    end
    -- Presentation fields used by native name/icon routines (66D554/183A1E5).
    local function presentation(kind)
        assert(selectable_kind(kind),'Invalid presentation kind')
        local settings=ptr(base+0x348e8f8)
        local info=ptr(base+0x37cb600+kind*8,4)
        assert(info>=settings and info+400<=settings+80280 and num(info)==kind,'Invalid presentation definition')
        return {label=num(info+0x28),texture=read(info+0xb0,8),category=num(info+0xb8)}
    end
    local function idle_actions(c)
        for a=1,4 do assert(read(c.actions+32*a,1)=='\0','Manual direction input detected') end
    end
    local out={presentation=presentation,view_context=function() return context(false) end}
    function out.decorate(snapshot)
        if not snapshot or not snapshot.open then return end
        -- Highlighting only needs the same peer-owned list used by the HUD.
        -- Activation-specific guards belong in begin/advance, not navigation.
        local peer=read(ptr(base+0x347cef0)+0xb398,8)
        assert(peer~=string.rep('\0',8),'Local session unavailable')
        local mission=ptr(base+0x347ce50)
        local count=num(mission+0x2d200)
        assert(count<=32,'Invalid mission peer count')
        local payload
        for i=0,count-1 do
            if read(mission+i*0x1690,8)==peer then
                assert(not payload,'Ambiguous local payload');payload=mission+i*0x1690+0x38
            end
        end
        assert(payload,'Local mission payload unavailable')
        local n=num(payload+0x788); assert(n<=32,'Invalid stratagem entry count')
        for _,row in ipairs(snapshot.rows) do
            -- Card+3748 is the native payload-entry index. Card+36F8 is
            -- cached arrow progress, not a stratagem kind (1837B14/183856B).
            if row.entry and row.entry>=0 and row.entry<n then row.kind=num(payload+0x188+row.entry*0x30)
            else row.kind=nil end
            row.timer_seconds,row.timer_kind=nil,nil
            if selectable_kind(row.kind) then decorate_timer(row) end
        end
    end
    function out.begin(kind)
        local c=context(true)
        assert(num(c.component)==0 and num(c.component+0x14)==0 and num(c.component+0x2c)==0,
            'Close and reopen the menu before confirming')
        idle_actions(c)
        local n=num(c.payload+0x788); assert(n<=32,'Invalid stratagem entry count')
        local found=false
        for i=0,n-1 do if num(c.payload+0x188+i*0x30)==kind then found=true end end
        assert(found,'Stratagem no longer belongs to the local mission list')
        return {identity=c.identity,component=c.component,kind=kind,code=code(kind),sent=0}
    end
    function out.advance(job)
        local c=context(true)
        assert(c.identity==job.identity and c.component==job.component,'Local avatar changed')
        assert(num(c.component)==job.sent and num(c.component+0x14)==0,'Native input changed; cancelled')
        for i=1,job.sent do assert(read(c.component+3+i,1):byte()==job.code[i],'Native sequence changed') end
        idle_actions(c)
        local direction=assert(job.code[job.sent+1])
        -- Native actions: left=1 right=2 up=3 down=4.
        local action=({3,2,4,1})[direction]
        local address=c.actions+action*32
        local ok,why=pcall(function()
            b.pulse_byte(address,1)
            b.invoke_input(c.component)
        end)
        -- Always attempt restoration, even when the write or callback fails.
        local restored,restore_error=pcall(b.pulse_byte,address,0)
        assert(restored,'Direction restoration failed: '..tostring(restore_error))
        assert(ok,why)
        job.sent=job.sent+1
        local n,matched=num(c.component),num(c.component+0x14)
        if job.sent==#job.code then
            assert(n==job.sent and matched==job.kind,'Game rejected the selected code or availability')
            return true,'Native handler matched kind '..matched..'; normal equip update pending'
        end
        assert(n==job.sent and matched==0,'Game rejected the code prefix or availability')
        return false,'Entering native code '..job.sent..'/'..#job.code
    end
    function out.release_state()
        local c=context(true,true)
        -- The native menu updater reads action 5:0, its evaluated byte and
        -- trigger type at +24. Only Hold/LongHold (2/9) have release semantics.
        local trigger=num(c.actions+24)
        c.hold=trigger==2 or trigger==9
        local down=read(c.actions,1)
        assert(down=='\0' or down=='\1','Invalid stratagem menu action')
        c.down=down=='\1'
        c.clean=num(c.component)==0 and num(c.component+0x14)==0 and num(c.component+0x2c)==0
        for a=1,4 do if read(c.actions+32*a,1)~='\0' then c.clean=false end end
        local ui=ptr(base+0x347ce28)
        c.unobstructed=num(ui+0x429c+20)==0
        return c
    end
    function out.begin_release(kind,armed)
        local c=out.release_state()
        assert(c.identity==armed.identity and c.component==armed.component and c.hud==armed.hud,
            'Release owner changed')
        assert(c.hold and not c.down and c.unobstructed,'Not an unobstructed Hold release')
        assert(num(c.component)==0 and num(c.component+0x14)==0 and num(c.component+0x2c)==0,
            'Manual input or completed selection cancels release')
        idle_actions(c)
        -- Revalidate membership/descriptor before asking the normal guarded
        -- native opener to resume a menu already closed by this frame's update.
        local n=num(c.payload+0x788);assert(n<=32,'Invalid stratagem entry count')
        local found=false
        for i=0,n-1 do if num(c.payload+0x188+i*0x30)==kind then found=true end end
        assert(found,'Released stratagem no longer belongs to the mission')
        code(kind)
        local controls=ptr(base+0x347cf18)
        local menu_action=read(controls+808+32*(97*5),1)
        assert(menu_action=='\0' or menu_action=='\1','Invalid native controls menu action')
        local lease=native_menu_latch(b).acquire(controls,c.actions)
        local reopened=false
        local ok,result=pcall(function()
            if not c.menu_active then
                if b.checkpoint then b.checkpoint('release native opener enter') end
                assert(b.open_input(c.component),'Native game state rejected release selection')
                reopened=true
                if b.checkpoint then b.checkpoint('release native opener returned') end
            end
            return out.begin(kind)
        end)
        if not ok then
            lease.restore(true)
            if reopened then b.close_input(c.component) end
            error(result)
        end
        result.hud=c.hud
        result.actions=c.actions
        result.controls=controls
        result.reopened=reopened
        result.latch=lease
        return result
    end
    function out.hold_release(job)
        local c=out.release_state()
        assert(c.identity==job.identity and c.component==job.component and c.hud==job.hud,
            'Release owner changed')
        assert(c.unobstructed,'Release interrupted by native UI')
        assert(c.menu_active,'Native menu closed before release code completed')
        assert(not c.down,'Manual menu activation cancels release selection')
        job.latch.refresh()
    end
    function out.end_release(job,cancelled)
        local current_ok,c=pcall(context,false,true)
        local avatar_valid=current_ok and c.identity==job.identity and c.component==job.component
        job.latch.restore(avatar_valid)
        if cancelled and avatar_valid and c.menu_active then b.close_input(c.component) end
    end
    function out.release_complete(job)
        local c=context(false,true)
        assert(c.identity==job.identity and c.component==job.component and c.hud==job.hud,
            'Release completion owner changed')
        local count,matched,queued=num(c.component),num(c.component+0x14),num(c.component+0x2c)
        local state='menu='..tostring(c.menu_active)..'; count='..count..'; matched='..matched..'; queued='..queued
        if not c.menu_active then return true,'Native menu finished; '..state end
        assert(matched==job.kind or queued==job.kind,'Native match disappeared before completion; '..state)
        -- The native update can wait for weapon/equip state before its normal
        -- A8FB50 close. Keep Press semantics through that entire transition.
        out.hold_release(job)
        return false,'Waiting for native completion; '..state
    end
    function out.advance_release(job)
        out.hold_release(job)
        return out.advance(job)
    end
    return out
end
