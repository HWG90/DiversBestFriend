-- Own new native widget storage. Never memcpy a live widget or its links.
local function duplicate_cards(b)
    local ffi=require('ffi')
    local init=ffi.cast('void (*)(uintptr_t, uint32_t)',b.base+0x1446840)
    local card_init=ffi.cast('void (*)(uintptr_t, NSR_vec2, NSR_vec2, NSR_vec2, uint32_t, uint32_t)',b.base+0x18358d0)
    local card_update=ffi.cast('void (*)(uintptr_t, float, uint32_t, uintptr_t, float, float)',b.base+0x1836510)
    local attach=ffi.cast('void (*)(uintptr_t, uintptr_t)',b.base+0x144c5c0)
    local finish=ffi.cast('void (*)(uintptr_t)',b.base+0x144c2c0)
    local visible=ffi.cast('void (*)(uintptr_t, uint8_t)',b.base+0x144cfb0)
    local release=ffi.cast('void (*)(uintptr_t)',b.base+0x144dd70)
    local opacity=ffi.cast('void (*)(uintptr_t, float)',b.base+0x1448ad0)
    local push_context=ffi.cast('void (*)(uintptr_t, uint8_t)',b.base+0x12ef4b0)
    local pop_context=ffi.cast('void (*)(void)',b.base+0x12ef4d0)
    local storage,address,identity,parent
    local retired={} -- Pin uncertain old generations; never follow a stale HUD link.
    local self={}
    local function checkpoint(message) if b.checkpoint then b.checkpoint(message) end end
    local function context_scope(original,callback)
        -- Both 1446853 (constructor) and 12EF4D0 (pop) resolve here.
        -- The r10 value 348CE90 was a transcription error, not a live pointer.
        local manager=assert(b.pointer(b.base+0x347ce90),'UI context manager unavailable')
        local expected=assert(b.pointer(original+0xf8),'Original widget resource context unavailable')
        local index=(expected-manager)/0x3698
        assert(index>=0 and index<13 and index%1==0,'Original widget resource context is outside the native table')
        assert(b.pointer(expected+8),'HUD resource renderer unavailable')
        local before=assert(b.u32(b.read(manager+0x2c5bc,4),0),'UI context stack unreadable')
        local depth=before==0xffffffff and -1 or before
        assert(depth>=-1 and depth<3,'UI context stack is full')
        checkpoint('context push: HUD='..index..' previous depth='..depth)
        push_context(manager,index)
        -- Even a Lua guard failure must unwind the scope before propagating.
        local ok,result=pcall(function()
            assert(b.u32(b.read(manager+0x2c5bc,4),0)==depth+1,'UI context push failed')
            assert(b.read(manager+0x2c5b8+depth+1,1)==string.char(index),'Wrong active HUD context')
            return callback(expected)
        end)
        pop_context()
        assert(b.u32(b.read(manager+0x2c5bc,4),0)==before,'UI context stack did not restore')
        checkpoint('context restored')
        assert(ok,result)
        return result
    end
    local function check_bounds()
        if storage then
            assert(ffi.string(ffi.cast('const char *',address-16),16)==string.rep('\165',16),'Radial allocation prefix overwritten')
            assert(ffi.string(ffi.cast('const char *',address+0x37720),16)==string.rep('\165',16),'Radial allocation suffix overwritten')
        end
    end
    local function zero_pointer(at) return b.read(at,8)==string.rep('\0',8) end
    function self.owns(card)
        if not address or not b.valid(identity) or b.pointer(address+0xf0)~=parent then return false end
        local i=(card-address-0x110)/0x3760
        return i>=0 and i<16 and i%1==0 and b.pointer(card+0xf0)==address
    end
    b.radial_card=self.owns
    function self.hide()
        if address and b.valid(identity) and b.pointer(address+0xf0)==parent then visible(address,0) end
    end
    function self.close()
        if address and b.valid(identity) and b.pointer(address+0xf0)==parent then
            -- Native release recursively releases children and unlinks this root.
            release(address)
            assert(zero_pointer(address+0xf0),'Radial root did not detach')
            storage,address,identity,parent=nil,nil,nil,nil
        else self.hide() end
    end
    local function prepare(snapshot,context,dt,resource_context)
        if not snapshot or not snapshot.open then self.hide();return snapshot end
        local expected=snapshot.panel+0x220
        if address and (identity~=snapshot.identity or b.pointer(address+0xf0)~=expected) then
            -- HUD teardown normally detaches our root. If it did not, retain
            -- its storage so an old native link can never become a GC dangling pointer.
            if not zero_pointer(address+0xf0) then
                assert(#retired<8,'Too many unretired HUD generations; restart the game')
                retired[#retired+1]=storage
            end
            storage,address,identity,parent=nil,nil,nil,nil
        end
        if not address then
            -- Native UI objects use SIMD internally. Guarantee 16-byte alignment
            -- and reserve canaries outside the full sixteen-card allocation.
            storage=ffi.new('uint8_t[?]',0x37720+64)
            local raw=tonumber(ffi.cast('uintptr_t',storage))
            address=math.floor((raw+31)/16)*16
            ffi.fill(ffi.cast('void *',address-16),16,165)
            ffi.fill(ffi.cast('void *',address+0x37720),16,165)
            identity,parent=snapshot.identity,expected
            checkpoint('root constructor enter')
            init(address,1)
            checkpoint('root constructor returned')
            assert(b.pointer(address+0xf8)==resource_context,'Radial root has the wrong resource context')
            for i=0,15 do
                local card=address+0x110+i*0x3760
                checkpoint('card '..i..' constructor enter')
                card_init(card,ffi.new('NSR_vec2',{0,-i*68}),ffi.new('NSR_vec2',{0,1}),ffi.new('NSR_vec2',{0,1}),0x226,i)
                checkpoint('card '..i..' constructor returned')
                check_bounds()
                assert(b.pointer(card+0xf8)==resource_context,'Radial card has the wrong resource context')
                attach(address,card)
            end
            checkpoint('root attach enter')
            attach(parent,address)
            finish(parent)
            checkpoint('root attach returned')
        end
        assert(b.valid(identity),'HUD changed during radial construction')
        -- Match the original root's transform using scalar properties only.
        -- The established centering and saved vertical adjustment still apply.
        for _,property in ipairs({'position','size','scale','anchor','pivot'}) do
            b.set(address,property,assert(b.get(snapshot.list,property),'Original list geometry unavailable'))
        end
        opacity(address,1)
        local maxwidth=270
        for _,row in ipairs(snapshot.rows) do maxwidth=math.max(maxwidth,row.width) end
        -- Call the card updater, not the list updater: it would rebuild a
        -- vertical layout and has additional list-specific state.
        for i=0,15 do
            checkpoint('card '..i..' update enter')
            card_update(address+0x110+i*0x3760,dt,context.context,context.payload,maxwidth,1)
            checkpoint('card '..i..' update returned')
        end
        check_bounds()
        local rows={}
        local allowed={}
        for _,original in ipairs(snapshot.rows) do
            assert(original.entry>=0 and original.entry<16,'Native card entry out of bounds')
            local card=address+0x110+original.entry*0x3760
            assert(self.owns(card),'Radial card ownership changed')
            rows[#rows+1]={address=card,entry=original.entry,kind=original.kind,width=original.width,height=original.height}
            allowed[original.entry]=true
        end
        -- Native updates populate all mission entries, including excluded ones.
        for i=0,15 do visible(address+0x110+i*0x3760,allowed[i] and 1 or 0) end
        visible(address,1)
        return {identity=identity,panel=snapshot.panel,list=address,rows=rows,open=true,center=snapshot.center,geometry=snapshot.geometry}
    end
    function self.prepare(snapshot,context,dt)
        if not snapshot or not snapshot.open then self.hide();return snapshot end
        return context_scope(snapshot.list,function(resource_context)
            return prepare(snapshot,context,dt,resource_context)
        end)
    end
    self.context_scope=context_scope
    return self
end
