-- Separate instance of the shared native eight-sector wheel. Never run its
-- gameplay update/activation: those dispatch emotes rather than stratagems.
local function emote_wheel(b,scope,input)
    local ffi=require('ffi')
    local ctor=ffi.cast('void (*)(uintptr_t, uintptr_t, uint32_t, uint32_t, uint8_t)',b.base+0x18298f0)
    local attach=ffi.cast('void (*)(uintptr_t, uintptr_t)',b.base+0x144c5c0)
    local finish=ffi.cast('void (*)(uintptr_t)',b.base+0x144c2c0)
    local visible=ffi.cast('void (*)(uintptr_t, uint8_t)',b.base+0x144cfb0)
    local opacity=ffi.cast('void (*)(uintptr_t, float)',b.base+0x1448ad0)
    local rotation=ffi.cast('void (*)(uintptr_t, float)',b.base+0x1448ef0)
    local label=ffi.cast('void (*)(uintptr_t, uint32_t)',b.base+0x1441720)
    local timer_label=ffi.cast('void (*)(uintptr_t, uint32_t)',b.base+0x143bf90)
    local timer_number=ffi.cast('void (*)(uintptr_t, uint32_t, int32_t, uint32_t)',b.base+0x143c9d0)
    local storage,address,identity,parent,signature
    local retired,content={},{}
    local previous={}
    local self={page=1,pages=1,count=0,status='native wheel closed'}
    local function checkpoint(s) if b.checkpoint then b.checkpoint(s) end end
    local function owned()
        return address and b.valid(identity) and b.pointer(address+0xf0)==parent
    end
    local function bounds()
        assert(ffi.string(ffi.cast('char *',address-16),16)==string.rep('\165',16),'Wheel prefix overwritten')
        assert(ffi.string(ffi.cast('char *',address+0x1d00),16)==string.rep('\165',16),'Wheel suffix overwritten')
    end
    function self.hide()
        if owned() then visible(address,0) end
        self.page=1;previous={};signature=nil;self.count=0
    end
    self.restore=self.hide
    function self.prepare(snapshot,buttons,busy)
        assert(snapshot.open and b.valid(snapshot.identity),'Wheel HUD changed')
        local rows,parts={},{}
        for _,row in ipairs(snapshot.rows) do
            if selectable_kind(row.kind) then rows[#rows+1]=row end
        end
        table.sort(rows,function(a,c)
            if a.list_y~=c.list_y then return (a.list_y or 0)>(c.list_y or 0) end
            return a.entry<c.entry
        end)
        for _,row in ipairs(rows) do parts[#parts+1]=row.address..':'..row.kind end
        local current=table.concat(parts,',')
        local changed=current~=signature
        if changed then self.page=1;signature=current end
        self.pages=math.max(1,math.ceil(#rows/8))
        local next_edge=buttons and buttons.next and previous.next==false
        local prev_edge=buttons and buttons.previous and previous.previous==false
        local paged=false
        if not busy and next_edge~=prev_edge and (next_edge or prev_edge) then
            local page=(self.page-1+(next_edge and 1 or -1))%self.pages+1
            if page~=self.page then changed=true;self.page=page;paged=true end
        end
        previous=buttons and {next=buttons.next,previous=buttons.previous} or {}
        local page_rows={}
        for i=(self.page-1)*8+1,math.min(self.page*8,#rows) do page_rows[#page_rows+1]=rows[i] end
        scope.context_scope(snapshot.list,function(resource)
            if address and (identity~=snapshot.identity or parent~=snapshot.list or not owned()) then
                if b.read(address+0xf0,8)~=string.rep('\0',8) then
                    assert(#retired<8,'Too many wheel HUD generations; restart game')
                    retired[#retired+1]=storage
                end
                storage,address=nil,nil
            end
            if not address then
                storage=ffi.new('uint8_t[?]',0x1d00+64)
                address=math.floor((tonumber(ffi.cast('uintptr_t',storage))+31)/16)*16
                ffi.fill(ffi.cast('void *',address-16),16,165)
                ffi.fill(ffi.cast('void *',address+0x1d00),16,165)
                identity,parent=snapshot.identity,snapshot.list
                checkpoint('shared wheel constructor enter')
                -- Mode 1 has the SAME eight-sector resources/rotation as emote
                -- mode 2, but initializes static icons instead of reading loadout.
                ctor(address,0,0x226,1,0)
                checkpoint('shared wheel constructor returned')
                bounds()
                assert(b.pointer(address+0xf8)==resource,'Wheel resource context mismatch')
                checkpoint('shared wheel attach enter')
                attach(parent,address);finish(parent)
                checkpoint('shared wheel attach returned')
                content={}
            end
            assert(owned(),'Wheel ownership mismatch')
            opacity(address,1);opacity(address+0x110,1);opacity(address+0x220,1)
            visible(address+0xf50,0) -- native emote-action hint does not apply
            local center=snapshot.center or {0,0}
            b.set(address,'position',{center[1],center[2]-(radial.vertical_offset or 0)})
            local size=radial.wheel_scale or 1
            b.set(address,'scale',{size,size})
            local text=radial.label_scale or 1
            b.set(address+0xc98,'scale',{text,text})
            b.set(address+0xf50,'scale',{text,text})
            -- Original HUD remains visible; only independently owned icons change.
            for i=0,7 do
                local row=page_rows[i+1]
                local icon=address+0x1208+i*0x158
                ffi.cast('uint8_t *',address+0x1cc8)[i]=row and 1 or 0
                visible(icon,row and 1 or 0)
                local size=radial.icon_scale or 1;b.set(icon,'scale',{size,size})
                local content_key=row and (row.kind..':'..tostring(radial.full_color~=false)..':'..tostring(row.timer_kind))
                if row and content[i]~=content_key then
                    local info=input.presentation(row.kind)
                    checkpoint('wheel stratagem texture enter')
                    configure_stratagem_icon(b,icon,info,row.timer_seconds~=nil)
                    checkpoint('wheel stratagem texture returned')
                    content[i]=content_key
                end
            end
            bounds();visible(address,1)
        end)
        self.address=address
        self.count=#page_rows
        self.status='native emote-style wheel; page '..self.page..'/'..self.pages
        self.observation='8 native sectors; native cursor radius 240; '..self.status
        return {identity=snapshot.identity,open=true,rows=page_rows,pointer_only=true,
            pointing_index=function(_,vector) return vector.slot end},changed,paged
    end
    function self.draw(selected,vector,rows,cursor_only)
        if not owned() then return end
        local index,row
        for i,item in ipairs(rows or {}) do if item.address==selected then index=i-1;row=item end end
        scope.context_scope(parent,function()
            local show=index~=nil and not cursor_only
            visible(address+0x488,cursor_only and 0 or 1)
            opacity(address+0x488,radial.native_opacity or 1)
            visible(address+0x5e0,show and 1 or 0)
            visible(address+0x890,show and 1 or 0)
            visible(address+0x738,(show or cursor_only) and 0 or 1)
            visible(address+0xc98,show and 1 or 0)
            if show then
                -- Native rotations are DEGREES, not radians. Mode 1/2 offset -22.5.
                checkpoint('wheel highlight rotation enter')
                rotation(address+0x5e0,index*45-22.5)
                rotation(address+0x890,index*45-22.5)
                checkpoint('wheel highlight rotation returned')
                checkpoint('wheel label enter')
                label(address+0xc98,input.presentation(row.kind).label)
                checkpoint('wheel label returned')
            end
            for i=0,7 do
                local timed=rows and rows[i+1] and rows[i+1].timer_seconds
                opacity(address+0x1208+i*0x158,cursor_only and 0 or
                    (timed and (i==index and 0.55 or 0.3) or (i==index and 1 or 0.65)))
            end
            -- Same widget, vector and radius as native update 182ADA[A..EF].
            visible(address+0xb40,vector and 1 or 0)
            if vector then b.set(address+0xb40,'position',{vector[1]*240,vector[2]*240}) end
            bounds()
        end)
    end
    -- The owned native emote hint is a type-7 formatted label. Reuse it for
    -- the list's minute/second template; no new widget or raw text allocation.
    function self.timer(row)
        if not owned() then return end
        scope.context_scope(parent,function()
            local seconds=row and row.timer_seconds
            local hint=address+0xf50
            visible(hint,seconds and 1 or 0)
            if seconds then
                checkpoint('wheel cooldown timer enter')
                timer_label(hint,0xa851371b)
                timer_number(hint,0x51d1e697,math.floor(seconds/60),0x3020)
                timer_number(hint,0x4583b0d3,seconds%60,0x3020)
                b.set(hint,'position',{0,-75})
                opacity(hint,1)
                checkpoint('wheel cooldown timer returned')
            end
            bounds()
        end)
    end
    -- Expanded mode reuses the native center caption without any slot indexing.
    function self.caption(kind)
        if not owned() then return end
        scope.context_scope(parent,function()
            visible(address+0xc98,kind and 1 or 0)
            if kind then
                checkpoint('expanded native caption enter')
                label(address+0xc98,input.presentation(kind).label)
                checkpoint('expanded native caption returned')
            end
        end)
    end
    function self.step(enabled,snapshot)
        if not enabled or not snapshot or not snapshot.open then self.hide();self.status='native wheel closed' end
    end
    return self
end
