-- Pure layout/controller. Native widgets retain their own content and input.
local radial = {vertical_offset=0,full_color=true,wedge_darkness=70,wedge_opacity=50}
-- Matrix columns follow the native widget transform at +0x64. Resolve the
-- viewport midpoint in list-local coordinates, then subtract the card anchor.
function radial.center(viewport,list)
    local v,m=viewport.matrix,list.matrix
    local x=v[1]*viewport.width/2+v[3]*viewport.height/2+v[5]
    local y=v[2]*viewport.width/2+v[4]*viewport.height/2+v[6]
    local dx,dy=x-m[5],y-m[6]
    local determinant=m[1]*m[4]-m[2]*m[3]
    assert(math.abs(determinant)>0.000001,'Degenerate list transform')
    return {(dx*m[4]-dy*m[3])/determinant-list.width/2,
            (dy*m[1]-dx*m[2])/determinant-list.height/2}
end

-- List mode highlights the selected native row and dims the other rows.
-- Its positions, arrows and parent hierarchy remain under native control.
function radial.list_controller(backend)
    local self={count=0,status='native menu closed'}
    local saved
    local dimmed,dim_identity={},nil
    local style_key
    local function same(a,b)
        if not a or not b or #a~=#b then return false end
        for i=1,#a do if a[i]~=b[i]then return false end end
        return true
    end
    local function get(address)
        if backend.get_text_style then return backend.get_text_style(address)end
        return {assert(backend.get_opacity(address))}
    end
    local function put(address,value)
        if backend.set_text_style then backend.set_text_style(address,value)
        else backend.set_opacity(address,value[1])end
    end
    local function blocked(row)return row.timer_kind~=nil or row.unavailable==true end
    local function owned_style(current,applied)
        if not current or not applied or #current~=#applied then return false end
        if #current~=4 then return same(current,applied)end
        for i=2,4 do if current[i]~=applied[i]then return false end end
        return true
    end
    local function restore_style(address,item)
        local current=get(address)
        if owned_style(current,item.applied)then
            local target={unpack(item.before)}
            if #target==4 then target[1]=current[1]end
            put(address,target)
        end
    end
    function self.restore()
        if saved and backend.valid(saved.identity) and same(backend.get(saved.address,'scale'),saved.applied)then
            backend.set(saved.address,'scale',saved.before)
        end
        if dim_identity and backend.valid(dim_identity)then
            for address,item in pairs(dimmed)do restore_style(address,item)end
        end
        dimmed,dim_identity={},nil;saved=nil;style_key=nil;self.count=0
    end
    function self.step(enabled,snapshot)
        if not enabled or not snapshot or not snapshot.open then
            self.restore();self.status=enabled and 'native menu closed'or'disabled';return
        end
        local selected
        for _,row in ipairs(snapshot.rows)do if row.address==radial.selected and not row.blacklisted and not blocked(row)then selected=row.address end end
        if (saved and(saved.identity~=snapshot.identity or saved.address~=selected))or
            (dim_identity and dim_identity~=snapshot.identity)then self.restore()end
        dim_identity=snapshot.identity
        local parts={tostring(selected),tostring(snapshot.identity),tostring(radial.dim_unselected)}
        for _,row in ipairs(snapshot.native_rows or snapshot.rows)do parts[#parts+1]=row.address..':'..tostring(row.timer_kind)..':'..tostring(row.unavailable)end
        local next_key=table.concat(parts,'|')
        if style_key==next_key then return end
        style_key=next_key
        local active={}
        for _,row in ipairs(snapshot.rows)do
            if radial.dim_unselected~=false and ((selected and row.address~=selected)or row.blacklisted)and not blocked(row)then
                local targets=backend.opacity_targets and backend.opacity_targets(row.address)or{}
                for index,address in ipairs(targets)do
                    active[address]=true
                    local current=get(address);local item=dimmed[address]
                    if not item then item={before=current};dimmed[address]=item
                    elseif not owned_style(current,item.applied)then item.before=current end
                    if #current==4 then item.before[1]=current[1]end
                    local target={unpack(item.before)}
                    if #target==4 then
                        -- Preserve native fade/visibility alpha, font, shadow and layout.
                        -- Tint only the text containers, never the blur or card art.
                        for channel=2,4 do target[channel]=item.before[channel]*0.35 end
                    else target[1]=item.before[1]*0.35 end
                    if not same(current,target)then put(address,target)end
                    item.applied=get(address)
                end
            end
        end
        for address,item in pairs(dimmed)do if not active[address]then
            restore_style(address,item)
            dimmed[address]=nil
        end end
        if selected then
            local current=assert(backend.get(selected,'scale'),'List row scale unavailable')
            if not saved then saved={identity=snapshot.identity,address=selected,before=current}
            elseif not same(current,saved.applied)then saved.before=current end
            local target={saved.before[1]*1.10,saved.before[2]*1.10}
            if not same(current,target)then backend.set(selected,'scale',target)end
            saved.applied=assert(backend.get(selected,'scale'))
        end
        self.count=#snapshot.rows;self.status='native list selection ('..self.count..' cards)'
    end
    return self
end
function radial.layout(rows,center)
    center=center or {0,0}
    local result, count = {}, #rows
    assert(count <= 16, 'Native HUD supports sixteen cards')
    for index, row in ipairs(rows) do
        local angle = math.pi / 2 - (index - 1) * 2 * math.pi / count
        local scale = count > 10 and 0.65 or 0.8
        local rx, ry = count > 10 and 550 or 470, count > 10 and 330 or 280
        local wheel=radial.wheel_scale or 1;rx,ry=rx*wheel,ry*wheel
        result[index] = {address=row.address, scale={scale,scale},
            position={center[1]+math.cos(angle)*rx, center[2]+math.sin(angle)*ry}}
    end
    return result
end

function radial.controller(backend)
    local self = {saved={}, identity=nil, status='waiting for HUD', count=0}
    local function same(a,b) return a and b and a[1]==b[1] and a[2]==b[2] end
    function self.restore()
        -- Never follow an old pointer after the game has torn down its HUD.
        if self.identity and backend.valid(self.identity) then
            for _, change in ipairs(self.saved) do
                local current = backend.get(change.address,change.property)
                if same(current,change.applied) then
                    backend.set(change.address,change.property,change.before)
                end
            end
        end
        self.saved, self.identity, self.count = {}, nil, 0
    end
    local function apply(address, property, value)
        local change
        for _, item in ipairs(self.saved) do
            if item.address==address and item.property==property then change=item; break end
        end
        local current = backend.get(address,property)
        assert(current,'Widget became unreadable')
        if not change then
            change={address=address,property=property,before=current}
            self.saved[#self.saved+1]=change
        elseif not same(current,change.applied) then
            -- Native animations/layout may have advanced since the last frame.
            change.before=current
        end
        backend.set(address,property,value)
        change.applied=assert(backend.get(address,property)) -- float32 round trip
    end
    function self.step(enabled,prepared)
        local snapshot, reason = prepared,nil
        if prepared==nil then snapshot,reason=backend.snapshot() end
        if not snapshot or not enabled or not snapshot.open then
            self.restore()
            self.status=not enabled and 'disabled' or reason or 'native menu closed'
            return
        end
        if self.identity and self.identity~=snapshot.identity then self.restore() end
        self.identity=snapshot.identity
        local drift,positions,checked=0,{},0
        for _,change in ipairs(self.saved) do
            if change.property=='animation_a' or change.property=='animation_b' or
                (change.property=='position' and change.address~=snapshot.panel and change.address~=snapshot.list) then
                local now=backend.get(change.address,change.property)
                checked=checked+1
                if not same(now,change.applied) then drift=drift+1 end
                if change.property=='position' and now and #positions<3 then
                    positions[#positions+1]=string.format('%.1f,%.1f',now[1],now[2])
                end
            end
        end
        self.observation='changed_since_previous_apply='..drift..'/'..checked..
            '; first_card_positions='..table.concat(positions,' | ')
        local original=snapshot.center or {0,0}
        local center={original[1],original[2]-(radial.vertical_offset or 0)}
        self.observation=self.observation..string.format('; local_center=%.1f,%.1f',center[1],center[2])
        self.observation=self.observation..'; geometry='..tostring(snapshot.geometry)
        -- Leave the entire parent hierarchy native. The cached transform
        -- accounts for its screen placement, safe-area offsets and HUD scale.
        local active={}
        for _, row in ipairs(radial.layout(snapshot.rows,center)) do
            active[row.address]=true
            apply(row.address,'anchor',{0.5,0.5})
            apply(row.address,'pivot',{0.5,0.5})
            if row.address==radial.selected then row.scale={1,1} end
            apply(row.address,'scale',row.scale)
            -- 0x183753F blends these endpoints and calls set_position again
            -- during the game's update, after the Lua callback may have run.
            -- Both ends must agree or native animation rebuilds the old list.
            apply(row.address,'animation_a',row.position)
            apply(row.address,'animation_b',row.position)
            apply(row.address,'position',row.position)
        end
        -- Restore cards that disappeared while the native menu stayed open.
        for i=#self.saved,1,-1 do
            local item=self.saved[i]
            if item.address~=snapshot.panel and item.address~=snapshot.list and not active[item.address] then
                if same(backend.get(item.address,item.property),item.applied) then
                    backend.set(item.address,item.property,item.before)
                end
                table.remove(self.saved,i)
            end
        end
        self.count=#snapshot.rows
        self.status='radial layout applied ('..self.count..' native cards)'
    end
    return self
end
