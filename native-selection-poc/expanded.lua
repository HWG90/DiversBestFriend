-- More than eight wedges without extending the native wheel's fixed arrays.
-- Each slot owns two transform containers, one native sector sprite and icon.
local function expanded_geometry(count,index)
    local sectors=math.max(8,count)
    assert(count>=0 and count<=16 and index>=1 and index<=sectors,'Expanded slot out of bounds')
    local angle=90-(index-1)*360/sectors
    -- Icon angles are mathematical (positive counterclockwise). Native widget
    -- rotation is clockwise. Center the sector on +X with a 67.5-degree
    -- native rotation before tangential scaling, then negate the icon angle.
    return angle,math.tan(math.pi/sectors*0.97)/math.tan(math.pi/8),
        {185*math.cos(math.rad(angle)),185*math.sin(math.rad(angle))}
end
local function expanded_index(rows,vector)
    if not vector or #rows==0 then return nil end
    local x,y=vector[1],vector[2]
    if x~=x or y~=y or x*x+y*y<0.2^2 then return nil end
    local n=math.max(8,#rows)
    local heading=(math.pi/2-math.atan2(y,x))%(2*math.pi)
    local slot=math.floor(heading*n/(2*math.pi)+0.5)%n+1
    if rows[slot] then return slot end
end
local function expanded_wheel(b,scope,input)
    local ffi=require('ffi')
    local init=ffi.cast('void (*)(uintptr_t, uint32_t)',b.base+0x1446840)
    local sprite=ffi.cast('void (*)(uintptr_t)',b.base+0x143eab0)
    local attach=ffi.cast('void (*)(uintptr_t, uintptr_t)',b.base+0x144c5c0)
    local finish=ffi.cast('void (*)(uintptr_t)',b.base+0x144c2c0)
    local visible=ffi.cast('void (*)(uintptr_t, uint8_t)',b.base+0x144cfb0)
    local opacity=ffi.cast('void (*)(uintptr_t, float)',b.base+0x1448ad0)
    local rotation=ffi.cast('void (*)(uintptr_t, float)',b.base+0x1448ef0)
    local rotation_pivot=ffi.cast('void (*)(uintptr_t, NSR_vec2)',b.base+0x14481a0)
    local order=ffi.cast('void (*)(uintptr_t, uint32_t)',b.base+0x14491f0)
    local color=ffi.cast('void (*)(uintptr_t, const float *)',b.base+0x1448690)
    local asset=ffi.cast('void (*)(uintptr_t, uint64_t, uint8_t)',b.base+0x144f800)
    local storage,address,identity,parent,signature
    local retired,content={},{}
    local SIZE,STRIDE=0x4f10,0x4e0
    local white=ffi.new('float[3]',{1,1,1})
    local yellow=ffi.new('float[3]',{1,0.9,0.35})
    local gray=ffi.new('float[3]',{0.5,0.55,0.6})
    local self={count=0,status='expanded wheel closed'}
    local function checkpoint(s) if b.checkpoint then b.checkpoint(s) end end
    local function owned() return address and b.valid(identity) and b.pointer(address+0xf0)==parent end
    local function bounds()
        assert(ffi.string(ffi.cast('char *',address-16),16)==string.rep('\165',16),'Expanded prefix overwritten')
        assert(ffi.string(ffi.cast('char *',address+SIZE),16)==string.rep('\165',16),'Expanded suffix overwritten')
    end
    local function link(p,c) attach(p,c);finish(p) end
    local function centered(p,size,pivot)
        b.set(p,'size',{size,size});b.set(p,'position',{0,0})
        b.set(p,'anchor',{0.5,0.5});b.set(p,'pivot',{pivot,pivot})
        rotation_pivot(p,ffi.new('NSR_vec2',{pivot,pivot}))
        opacity(p,1)
    end
    local function slot(i)
        local p=address+0x110+(i-1)*STRIDE
        return p,p+0x110,p+0x220,p+0x380
    end
    function self.hide()
        if owned() then visible(address,0) end
        self.count=0;signature=nil
    end
    self.restore=self.hide
    function self.prepare(snapshot)
        assert(snapshot.open and b.valid(snapshot.identity),'Expanded HUD changed')
        local rows,parts={},{}
        for _,row in ipairs(snapshot.rows) do if selectable_kind(row.kind) then rows[#rows+1]=row end end
        assert(#rows<=16,'Expanded wheel supports sixteen mission rows')
        table.sort(rows,function(a,c)
            if a.list_y~=c.list_y then return (a.list_y or 0)>(c.list_y or 0) end
            return a.entry<c.entry
        end)
        for _,row in ipairs(rows) do parts[#parts+1]=row.address..':'..row.kind end
        local current=table.concat(parts,',')
        local changed=signature~=current;signature=current
        scope.context_scope(snapshot.list,function(resource)
            if address and (identity~=snapshot.identity or parent~=snapshot.list or not owned()) then
                if b.read(address+0xf0,8)~=string.rep('\0',8) then
                    assert(#retired<8,'Too many expanded HUD generations; restart game')
                    retired[#retired+1]=storage
                end
                address,storage=nil,nil
            end
            if not address then
                storage=ffi.new('uint8_t[?]',SIZE+64)
                address=math.floor((tonumber(ffi.cast('uintptr_t',storage))+31)/16)*16
                ffi.fill(ffi.cast('void *',address-16),16,165)
                ffi.fill(ffi.cast('void *',address+SIZE),16,165)
                identity,parent=snapshot.identity,snapshot.list
                checkpoint('expanded root constructor enter')
                init(address,1);centered(address,600,0.5)
                assert(b.pointer(address+0xf8)==resource,'Expanded resource context mismatch')
                checkpoint('expanded root constructor returned')
                for i=1,16 do
                    local turn,stretch,wedge,icon=slot(i)
                    checkpoint('expanded slot '..i..' constructor enter')
                    init(turn,1);centered(turn,600,0.5)
                    init(stretch,1);centered(stretch,600,0.5)
                    sprite(wedge);centered(wedge,256,0)
                    asset(wedge,0x9c16bf1bb2d8de88ULL,0)
                    -- The stock -22.5-degree rotation points this texture UP,
                    -- not right. Its unrotated bisector is 67.5 degrees, and
                    -- native positive rotation is clockwise (r17/r18 captures).
                    rotation(wedge,67.5);order(wedge,0x228)
                    sprite(icon);centered(icon,64,0.5);order(icon,0x22b)
                    for _,p in ipairs({turn,stretch,wedge,icon}) do
                        assert(b.pointer(p+0xf8)==resource,'Expanded child context mismatch')
                    end
                    link(stretch,wedge);link(turn,stretch);link(address,turn);link(address,icon)
                    bounds()
                    checkpoint('expanded slot '..i..' constructor returned')
                end
                link(parent,address);content={}
                checkpoint('expanded root attached')
            end
            assert(owned(),'Expanded ownership mismatch')
            local center=snapshot.center or {0,0}
            b.set(address,'position',{center[1],center[2]-(radial.vertical_offset or 0)})
            for i=1,16 do
                local turn,stretch,wedge,icon=slot(i)
                assert(b.pointer(turn+0xf0)==address and b.pointer(stretch+0xf0)==turn and
                    b.pointer(wedge+0xf0)==stretch and b.pointer(icon+0xf0)==address,'Expanded child ownership changed')
                local active=i<=math.max(8,#rows)
                visible(turn,active and 1 or 0);visible(icon,rows[i] and 1 or 0)
                if active then
                    local angle,scale,pos=expanded_geometry(#rows,i)
                    rotation(turn,-angle);b.set(stretch,'scale',{1,scale});b.set(icon,'position',pos)
                end
                local row=rows[i]
                local content_key=row and (row.kind..':'..tostring(radial.full_color~=false)..':'..tostring(row.timer_kind))
                if row and content[i]~=content_key then
                    local info=input.presentation(row.kind)
                    checkpoint('expanded icon texture enter')
                    configure_stratagem_icon(b,icon,info,row.timer_seconds~=nil)
                    checkpoint('expanded icon texture returned')
                    content[i]=content_key
                end
            end
            bounds();visible(address,1)
        end)
        self.count=#rows
        self.status='expanded wedges: '..#rows..' stratagems / '..math.max(8,#rows)..' sectors'
        self.observation='separate native sprites; no paging; tangentially scaled 45-degree sectors'
        return {identity=snapshot.identity,open=true,rows=rows,pointer_only=true,pointing_index=expanded_index},changed
    end
    function self.draw(selected,rows)
        if not owned() then return nil end
        local kind
        -- Independent controls: darkness changes RGB, opacity changes coverage.
        -- Keep the selected sector conspicuous even with a transparent background.
        local brightness=1-(radial.wedge_darkness or 70)/100
        local alpha=(radial.wedge_opacity or 75)/100
        gray[0],gray[1],gray[2]=0.5*brightness,0.55*brightness,0.6*brightness
        scope.context_scope(parent,function()
            checkpoint('expanded highlight enter')
            for i=1,16 do
                local _,_,wedge,icon=slot(i)
                local row=rows[i]
                local chosen=row and row.address==selected
                color(wedge,chosen and yellow or gray)
                opacity(wedge,chosen and math.max(0.95,alpha) or (row and alpha or alpha*0.08/0.3))
                local timed=row and row.timer_seconds
                color(icon,(chosen and radial.full_color==false and not timed) and yellow or white)
                opacity(icon,timed and (chosen and 0.55 or 0.3) or (chosen and 1 or 0.8))
                if chosen then kind=row.kind end
            end
            bounds();checkpoint('expanded highlight returned')
        end)
        return kind
    end
    function self.step(enabled,snapshot)
        if not enabled or not snapshot or not snapshot.open then self.hide();self.status='expanded wheel closed' end
    end
    return self
end
