-- HD2-Addon: mods/EquippedStratagems/NativeStratagemRadial
-- Restart-only BSL bootstrap. Each embedded module compiles in its own chunk.
if rawget(_G,'NativeStratagemRadial') or rawget(_G,'DiversBestFriend') then return end
local sources={
["src/layout.lua"]=[=[-- Pure layout/controller. Native widgets retain their own content and input.
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

return {radial=radial}
]=],
["src/guards.lua"]=[=[-- Guard bytes from the supported in-process capture; see RESEARCH.md.
local native_guards = {
    {name='dock_charge_group_layout',rva=0x1839b15,bytes='\x4d\x8d\xbe\x20\x09\x00\x00'},
    {name='dock_charge_text_layout',rva=0x1839c8e,bytes='\x49\x8d\xbe\xe0\x0c\x00\x00'},
    {name='position',rva=0x14476a0,bytes='\x48\x89\x5c\x24\x18\x48\x89\x6c\x24\x20\x48\x89\x54\x24\x10\x56\x57\x41\x57\x48\x83\xec\x20\xf3\x0f\x10\x41\x04\x48\x8b\xda\x0f'},
    {name='size',rva=0x1447160,bytes='\x48\x89\x5c\x24\x18\x48\x89\x6c\x24\x20\x48\x89\x54\x24\x10\x56\x57\x41\x57\x48\x83\xec\x20\xf3\x0f\x10\x41\x0c\x48\x8b\xda\x0f'},
    {name='scale',rva=0x1447ed0,bytes='\x48\x89\x5c\x24\x18\x48\x89\x6c\x24\x20\x48\x89\x54\x24\x10\x56\x57\x41\x57\x48\x83\xec\x20\xf3\x0f\x10\x41\x14\x48\x8b\xda\x0f'},
    {name='anchor',rva=0x144f160,bytes='\x48\x83\xec\x28\xf3\x0f\x10\x41\x2c\x4c\x8b\xc9\x48\x89\x54\x24\x30\x0f\x2e\x44\x24\x30\x7a\x10\x75\x0e\xf3\x0f\x10\x41\x30\x0f'},
    {name='pivot',rva=0x144f0d0,bytes='\x48\x83\xec\x28\xf3\x0f\x10\x41\x3c\x4c\x8b\xc9\x48\x89\x54\x24\x30\x0f\x2e\x44\x24\x30\x7a\x10\x75\x0e\xf3\x0f\x10\x41\x40\x0f'},
    {name='hud_root',rva=0xad9d8e,bytes='\x48\x8b\x0d\xa3\x37\x99\x02\xe8\x86\x6b\x81\x00\xe8\x41\x17\x7c\x00\x48\x8b\x0d\x4a\x31\x9a\x02\x48\x8b\x81\xa8\xb3\x00\x00\x48'},
    {name='hud_panel',rva=0x12ea0df,bytes='\x44\x89\x75\xd0\x49\x8d\x8f\xc0\x6d\x14\x00\xc7\x45\xd4\x00\x00\x80\x3f\x49\x8b\xd6\x48\x8b\x45\xd0\x44\x89\x75\xc0\xc7\x45\xc4'},
    {name='hud_update',rva=0x12eb7d0,bytes='\x48\x8d\x8e\xc0\x6d\x14\x00\x48\x89\xac\x24\x80\x00\x00\x00\x44\x8b\xc3\xe8\x39\x7e\x54\x00\x48\x8d\x8e\x50\x60\x04\x00\x44\x8b'},
    {name='list_parent',rva=0x18334fe,bytes='\x48\x8b\xd3\x49\x8b\xcc\xe8\xb7\x90\xc1\xff\x49\x8b\xcc\xe8\xaf\x8d\xc1\xff\x48\x8b\x05\x20\xa0\xc3\x01\x49\x8b\xcf\x66\x41\xc7'},
    {name='row_layout',rva=0x1833440,bytes='\xf3\x0f\x11\x7d\xc4\x48\x8b\xce\xc7\x45\x30\x00\x00\x00\x00\xc7\x45\x34\x00\x00\x80\x3f\x4c\x8b\x4d\x30\xc7\x45\xc0\x00\x00\x00'},
    {name='open_state',rva=0x1833887,bytes='\x41\x0f\xb6\x8e\x69\x87\x03\x00\x0f\xb6\xc1\x84\xc9\x74\x20\x41\x38\xb6\x74\x87\x03\x00\x74\x17\x45\x3b\x27\x74\x12\xba\x7b\x44'},
    {name='card_animation',rva=0x183753f,bytes='\x0f\x28\xc6\x0f\x28\xcf\xf3\x41\x0f\x5f\x87\x34\x37\x00\x00\x49\x8b\xcf\xf3\x0f\x5c\xc8\x0f\x28\xd0\xf3\x41\x0f\x59\x97\x38\x37\x00\x00\x0f\x28\xd8\xf3\x41\x0f\x59\x9f\x3c\x37\x00\x00\x0f\x28\xc1\xf3\x41\x0f\x59\x8f\x44\x37\x00\x00\xf3\x41\x0f\x59\x87\x40\x37\x00\x00\xf3\x0f\x58\xcb\xf3\x0f\x58\xc2\xf3\x0f\x11\x4c\x24\x74\xf3\x0f\x11\x44\x24\x70\x48\x8b\x54\x24\x70\xe8\x00\x01\xc1\xff\x45'},
    {name='widget_transform',rva=0x144a40e,bytes='\xf3\x0f\x10\x79\x14\x48\x8b\xd9\xf3\x0f\x10\x51\x24\x0f\x57\x15\xce\x1b\xf8\x00\xf3\x0f\x10\x49\x28\x0f\x57\x0d\xc2\x1b\xf8\x00\xf3\x0f\x59\x51\x3c\x48\x8b\x81\xf0\x00\x00\x00\xf3\x0f\x59\x49\x40\x48\x89\x54\x24\x58\xf3\x0f\x10\x5c\x24\x58\xf3\x0f\x10\x64\x24\x5c\xf3\x0f\x59\x49\x18\xf3\x0f\x59\xd7\xf3\x0f\x11\x7c\x24\x54\xf3\x0f\x58\x59\x04\xf3\x0f\x58\x61\x08\xf3\x0f\x58\xda\xf3\x0f\x58\xe1\xf3\x0f\x11\x5c\x24\x24\xf3\x0f\x11\x64\x24\x44\x48\x85\xc0\x74\x33\x48\x8b\x40\x24\x48\x89\x44\x24\x58\xf3\x0f\x10\x44\x24\x58\xf3\x0f\x10\x4c\x24\x5c\xf3\x0f\x59\x41\x2c\xf3\x0f\x59\x49\x30\xf3\x0f\x58\xd8\xf3\x0f\x58\xe1\xf3\x0f\x11\x5c\x24\x24\xf3\x0f\x11\x64\x24\x44'},
    {name='widget_measure',rva=0x144bd60,bytes='\x48\x83\xec\x28\xf3\x0f\x10\x41\x0c\x4c\x8b\xc9\xf3\x0f\x10\x49\x10\xf3\x0f\x59\x41\x1c\x8b\x91\xb8\x00\x00\x00\xf3\x0f\x59\x49\x20\xf3\x0f\x11\x44\x24\x30\xf3\x0f\x11\x4c\x24\x34\x48\x8b\x44\x24\x30\x48\x89\x41\x24'},
    {name='viewport_parent',rva=0x12f0aa1,bytes='\x49\x8b\xd7\x48\x8b\xce\xe8\x14\xbb\x15\x00\x48\x8b\xce\xe8\x0c\xb8\x15\x00'},
    {name='scramble_query',rva=0xa10820,bytes='\x4c\x8b\xdc\x56\x41\x54\x41\x55\x41\x57\x48\x81\xec\x98\x00\x00\x00\x48\x8b\x05\xd8\xb7\xc2\x01\x48\x33\xc4\x48\x89\x44\x24\x48\x44\x3b\x05\x05\x34\xa7\x02\xbe\xff\xff\xff\xff\x89\x32\x4c\x8b\xe2\x44\x89\x4c\x24\x28\x4c\x8b\xe9\x48\x89\x54\x24\x20\x0f\x84'},
    {name='scramble_query_position',rva=0xa1092c,bytes='\x44\x3b\x05\xed\x32\xa7\x02\x4c\x8b\x1d\xce\x5b\x91\x02\x48\x89\x44\x24\x40\x74\x44\x45\x8b\x4b\x48\x41\x8b\xcf\x45\x8b\x53\x50\x45\x0f\xaf\xd0\x41\x8d\x69\xff\x45\x85\xc9\x74\x2c\x49\x8b\x5b\x40\x41\x8b\x7b\x4c\x8b\xc5\x42\x8d\x14\x11\x48\x23\xd0\x8b\x04\xd3\x3b\xc7\x0f\x84\x89\x02\x00\x00\x41\x3b\xc0\x0f\x84\x89\x02\x00\x00\xff\xc1\x41\x3b\xc9\x72\xdc\x8b\xc6\x48\x8b\x1d\x22\x5b\x91\x02\x8b\xc8\x49\x8b\x43\x68\x48\x69\xd1\x08\x03\x00\x00\xf2'},
    {name='scramble_match_shift',rva=0x66dd94,bytes='\x41\x83\xfd\xff\x74\x28\x8b\xc8\x48\x69\xc1\x38\x12\x00\x00\x46\x03\xb4\x38\x68\xea\x53\x00\xb8\xef\x61\xeb\xdb\x41\xf7\xe6\xc1\xea\x07\x69\xc2\x95\x00\x00\x00\x44\x2b\xf0\x41\xff\xc6'},
    {name='scramble_match_call',rva=0x66dcf0,bytes='\x48\x8b\x0d\xb9\x87\xcb\x02\x44\x8b\xc3\x8b\xee\x48\x89\x7c\x24\x28\x48\x89\x7c\x24\x20\x8b\x84\xac\xa0\x00\x00\x00\x48\x8d\x14\x40\x48\x03\xd2\x45\x8b\xb4\xd7\x88\x01\x00\x00\x45\x8b\xce\x48\x8d\x54\x24\x50\xe8\xf7\x2a\x3a\x00'},
    {name='ui_sound',rva=0x1327f50,bytes='\x48\x89\x5c\x24\x08\x48\x89\x74\x24\x10\x57\x48\x83\xec\x20\x48\x8b\x05\xb2\xe3\xff\x01\x8b\xda\x48\x8b\x0d\xd1\xe3\xff\x01\x48\x8b\x90\x88\x02\x00\x00\x48\x8b\x89\xf8\x10\x00\x00\x48\x8b\xb0\x38\x03\x00\x00\xff\xd2\x8b\xcb\x48\x8b\xf8\xe8\x50\xd7\xf2\xff\x48\x8b\x0d\xa9\xe3\xff\x01\x45\x33\xc9\x4c\x8b\xc7\x8b\xd0\x48\x8b\x89\xf8\x10\x00\x00\x48\x8b\xc6\x48\x8b\x5c\x24\x30\x48\x8b\x74\x24\x38\x48\x83\xc4\x20\x5f\x48\xff\xe0\xcc\xcc\xcc\xcc\xcc'},
    {name='wheel_move_sound',rva=0x182a908,bytes='\x3b\xd9\x0f\x84\x80\x04\x00\x00\x3b\xce\x0f\x84\x2f\x03\x00\x00\x41\x8b\x87\xe0\x1c\x00\x00\x48\x8d\x0d\xda\x56\x7d\xfe\x8b\x94\x81\x40\x75\x30\x02\xe8\x1e\xd6\xaf\xff'},
    {name='wheel_action_sound',rva=0x182a7d2,bytes='\x48\xb9\x00\x00\x00\x00\x09\x00\x00\x00\xe8\x9f\xb3\xd5\xfe\x44\x8b\xc8\x48\x8b\x05\x2d\x27\xc5\x01\x49\xc1\xe1\x05\x45\x38\xa4\x01\x28\x03\x00\x00\x74\x3d\x41\x8b\x87\xe0\x1c\x00\x00\x48\x8d\x0d\xf9\x57\x7d\xfe\x8b\x94\x81\x20\x75\x30\x02\xe8\x3d\xd7\xaf\xff'},
    {name='wheel_sound_ids',rva=0x2307520,bytes='\xf7\x31\x3c\x78\x83\x45\x27\xdd\x83\x45\x27\xdd\x00\x00\x00\x00\x1c\x8a\xb1\x93\xb2\xf7\xb3\x75\xb2\xf7\xb3\x75\x00\x00\x00\x00\x56\xe9\x82\x7e\x55\x5a\x42\x39\x55\x5a\x42\x39'},
}

-- Selection ABI and ownership witnesses from the supported code capture.
native_guards[#native_guards+1]={name='input_handler',rva=0xa900d0,bytes='\x40\x53\x55\x56\x57\x41\x54\x41\x55\x41\x56\x48\x83\xec\x40\x8b\x41\x28\x33\xff\x44\x8b\x05\x35\x3b\x9f\x02\x4c\x8b\xe1\x48\x8b'}
native_guards[#native_guards+1]={name='append_and_match',rva=0xa903ab,bytes='\x41\x8b\x04\x24\x83\xf8\x10\x0f\x83\x11\x07\x00\x00\x42\x88\x5c\x20\x04\x4d\x8b\xc4\x41\xff\x04\x24\x41\x8b\x94\x36\xbc\xe9\x53\x00\xe8\xef\xd4\xbd\xff'}
native_guards[#native_guards+1]={name='avatar_layout',rva=0x82a0a0,bytes='\x4d\x8b\xb4\xdd\x10\x01\x00\x00\x48\x69\xc3\xb8\x01\x00\x00\x4c\x69\xe3\x38\x12\x00\x00\x49\x8b\xce\x48\x89\x5d\xa8\x48\x89\x45\xb8\x48\x6b\xc3\x78\x49\x81\xc4\xb0\xd8\x53\x00\x4c\x89\x75\x90\x48\x89\x45\xb0\x4d\x03\xe5'}
native_guards[#native_guards+1]={name='input_component',rva=0xa3ea05,bytes='\x48\x8d\x8e\x80\x08\x00\x00\x0f\x28\xce\xe8\x0c\x02\x05\x00'}
native_guards[#native_guards+1]={name='owner_map',rva=0xfd9ba0,bytes='\x48\x83\xec\x08\x4c\x8b\x1d\xed\x23\x49\x02\x44\x8b\xc2\x4c\x8b\xc9\x81\xfa\xff\x7f\x00\x00\x75\x10\x8b\x05\xad\xa9\x4a\x02\x89'}
native_guards[#native_guards+1]={name='owner_map_value',rva=0xfd9c49,bytes='\x8b\x40\x04\x48\x8d\x04\x40\x48\x8d\x80\xe4\x65\x1e\x00\x49\x8d\x04\xc3\x8b\x00'}
native_guards[#native_guards+1]={name='context_to_peer',rva=0x606c90,bytes='\x48\x83\xec\x08\x3b\x15\x86\xcf\xe7\x02\x4c\x8b\x15\xc7\xf7\xd1\x02\x75\x18\xb8\xff\xff\xff\xff\x8b\xc8\x48\x6b\xc1\x38\x4a\x8b'}
native_guards[#native_guards+1]={name='card_payload_index',rva=0x1836582,bytes='\x45\x8b\xb7\x48\x37\x00\x00\x44\x3b\xb7\x88\x07\x00\x00\x0f\x82\x99\x00\x00\x00'}

-- r9 native pointing and independently constructed card widgets.
native_guards[#native_guards+1]={name='radial_direction_reader',rva=0x182b5c0,bytes='\x48\x8b\xc4\x53\x55\x56\x57\x48\x81\xec\x88\x00\x00\x00\x0f\x29\x70\xc8\x48\x8b\xf9\x0f\x29\x78\xb8\x48\xbe\x03\x00\x00\x00\x07'}
native_guards[#native_guards+1]={name='radial_direction_owner',rva=0x182a8e0,bytes='\xe8\xdb\x0c\x00\x00\x8b\x5d\x87\x41\x8b\x87\xd8\x1c\x00\x00\x8b\xc8\x3b\xc6\x74\x13\x46\x38\xa4\x38\xc8\x1c\x00\x00\x75\x09\x41'}
native_guards[#native_guards+1]={name='radial_binding_query',rva=0x12f9540,bytes='\x44\x88\x44\x24\x18\x48\x89\x4c\x24\x08\x53\x55\x56\x57\x41\x54\x41\x55\x41\x56\x41\x57\x48\x83\xec\x48\x48\x8b\xe9\x4c\x8b\xca'}
native_guards[#native_guards+1]={name='widget_constructor',rva=0x1446840,bytes='\x48\x89\x5c\x24\x10\x57\x48\x83\xec\x20\x0f\x28\x05\xaf\x3d\xf8\x00\x33\xff\x4c\x8b\x05\x36\x66\x03\x02\x48\x8b\xd9\x0f\x11\x41'}
native_guards[#native_guards+1]={name='radial_card_constructor',rva=0x18358d0,bytes='\x48\x8b\xc4\x48\x89\x58\x08\x48\x89\x70\x18\x48\x89\x78\x20\x48\x89\x50\x10\x55\x41\x54\x41\x55\x41\x56\x41\x57\x48\x8d\x68\xb1'}
native_guards[#native_guards+1]={name='radial_card_update',rva=0x1836510,bytes='\x4d\x85\xc9\x0f\x84\xad\x23\x00\x00\x4c\x8b\xdc\x55\x53\x57\x41\x57\x49\x8d\xab\xb8\xfe\xff\xff\x48\x81\xec\x28\x02\x00\x00\x45'}
native_guards[#native_guards+1]={name='widget_attach',rva=0x144c5c0,bytes='\x40\x53\x48\x83\xec\x20\x4c\x8b\xca\x48\x8b\xd9\x48\x8b\x91\xe0\x00\x00\x00\x48\x85\xd2\x74\x54\x33\xc9\x48\x8b\xc2\x49\x3b\xd1'}
native_guards[#native_guards+1]={name='widget_finish',rva=0x144c2c0,bytes='\x48\x8b\x81\xe0\x00\x00\x00\x45\x32\xc9\x4c\x8b\xc1\x48\x85\xc0\x74\x2f\x0f\x1f\x40\x00\x66\x66\x0f\x1f\x84\x00\x00\x00\x00\x00'}
native_guards[#native_guards+1]={name='widget_visible',rva=0x144cfb0,bytes='\x48\x83\xec\x28\x44\x8b\x01\x4c\x8b\xd1\x41\x8b\xc0\x45\x8b\xc8\x83\xe0\xef\x41\x83\xc9\x10\x84\xd2\x44\x0f\x44\xc8\x44\x89\x09'}
native_guards[#native_guards+1]={name='widget_release',rva=0x144dd70,bytes='\x40\x53\x48\x83\xec\x20\x48\x8b\xd9\xe8\xa2\x0b\x00\x00\x8b\x03\xc1\xe8\x12\x83\xe0\x0f\x83\xf8\x0d\x0f\x87\x4d\x01\x00\x00\x48'}
native_guards[#native_guards+1]={name='widget_release_children',rva=0x144cbc0,bytes='\x41\x54\x41\x56\x41\x57\x48\x83\xec\x30\x4c\x8b\xb9\xe0\x00\x00\x00\x44\x0f\xb6\xe2\x4c\x8b\xf1\x4d\x85\xff\x0f\x84\x53\x02\x00'}
native_guards[#native_guards+1]={name='widget_opacity',rva=0x1448ad0,bytes='\x40\x57\x48\x83\xec\x20\xf3\x0f\x10\x41\x44\x48\x8b\xf9\x0f\x2e\xc1\x7a\x23\x75\x21\xf7\x01\x00\x00\x00\x08\x0f\x84\x77\x01\x00'}
native_guards[#native_guards+1]={name='radial_input_flag_reset',rva=0x127a353,bytes='\xc6\x83\xa9\x01\x00\x00\x00\x45\x84\xed\x74\x35\x48\x8b\x05\xa2\xbf\x0a\x02\x48\x8b\x8b\x80\x01\x00\x00\x48\x8b\x50\x08\xff\x52'}

-- r10 UI resource context stack and native HUD construction scope.
native_guards[#native_guards+1]={name='widget_context_push',rva=0x12ef4b0,bytes='\x4c\x63\x81\xbc\xc5\x02\x00\x41\x8d\x40\x01\x89\x81\xbc\xc5\x02\x00\x41\x88\x94\x08\xb9\xc5\x02\x00'}
native_guards[#native_guards+1]={name='widget_context_pop',rva=0x12ef4d0,bytes='\x48\x8b\x05\xb9\xd9\x18\x02\xff\x88\xbc\xc5\x02\x00\xc3'}
native_guards[#native_guards+1]={name='widget_context_capture',rva=0x1446975,bytes='\x49\x63\x80\xbc\xc5\x02\x00\x85\xc0\x79\x04\x32\xc0\xeb\x09\x42\x0f\xb6\x84\x00\xb8\xc5\x02\x00\x48\x89\xbb\x00\x01\x00\x00\x81\xe2\x00\x00\x3c\x00\x48\x89\xbb\x08\x01\x00\x00\x0f\xb6\xc0\x48\x69\xc8\x98\x36\x00\x00\x49\x03\xc8\x48\x89\x8b\xf8\x00\x00\x00'}
native_guards[#native_guards+1]={name='hud_context_scope',rva=0x12f0974,bytes='\x49\x63\x90\xbc\xc5\x02\x00\x8d\x42\x01\x41\x89\x80\xbc\xc5\x02\x00\x42\xc6\x84\x02\xb9\xc5\x02\x00\x05'}
native_guards[#native_guards+1]={name='camera_radial_gate',rva=0x1286756,bytes='\x44\x38\xa0\xa9\x01\x00\x00\x74\x1a\xf3\x0f\x10\x05\x01\x6f\x54\x02\xf3\x0f\x10\x0d\xfd\x6e\x54\x02\xf3\x0f\x10\x35\xf9\x6e\x54\x02\xeb\x12\xf3\x0f\x10\x74\x24\x50\xf3\x0f\x10\x4c\x24\x4c\xf3\x0f\x10\x44\x24\x48'}
native_guards[#native_guards+1]={name='camera_radial_gate_secondary',rva=0x1289912,bytes='\x41\x80\xbe\xa9\x01\x00\x00\x00\x48\x8b\x05\xff\xd3\x09\x02\x4c\x8b\x0d\xf0\x35\x1f\x02\x48\x8b\x75\xc8\x4c\x89\x4d\x20\xf2\x0f\x10\x84\x01\x24\x7c\x0a\x00\x8b\x84\x01\x2c\x7c\x0a\x00\xf2\x0f\x11\x45\xa0\x89\x45\xa8\x75\x6d'}

-- r15 shared wheel presentation and native cursor witnesses.
native_guards[#native_guards+1]={name='wheel_constructor',rva=0x18298f0,bytes='\x48\x8b\xc4\x48\x89\x58\x08\x48\x89\x70\x10\x48\x89\x78\x18\x55\x41\x54\x41\x55\x41\x56\x41\x57\x48\x8d\x68\xa9\x48\x81\xec\xc0'}
native_guards[#native_guards+1]={name='wheel_static_mode',rva=0x182cd23,bytes='\x48\x8d\xb9\x88\x04\x00\x00\xc7\x81\xd4\x1c\x00\x00\x08\x00\x00\x00\x48\x8b\xcf\x48\xba\xb3\x3e\x5d\xce\x9f\x34\x25\xaa\x45\x33'}
native_guards[#native_guards+1]={name='wheel_static_content',rva=0x182bc6a,bytes='\x4c\x8b\x02\x45\x33\xc9\x49\x8b\xd6\x49\x8b\xcc\xe8\xb5\x45\xc2\xff\x49\x8b\xcc\xe8\x5d\x3a\xc2\xff\x48\x85\xc0\x0f\x84\xe8\x01\x00\x00\x4c\x8d\x05\xcd\x70\x9b'}
native_guards[#native_guards+1]={name='wheel_texture',rva=0x1450230,bytes='\x48\x89\x5c\x24\x10\x57\x48\x83\xec\x30\x49\x8b\xd8\x48\x8b\xf9\x45\x0f\xb6\xc1\xe8\xb7\xf5\xff\xff\x8b\x07\x25\x00\x00\x3c\x00'}
native_guards[#native_guards+1]={name='wheel_label',rva=0x1441720,bytes='\x48\x83\xec\x28\x4c\x8b\xd9\x39\x91\x10\x01\x00\x00\x0f\x84\x80\x00\x00\x00\x89\x91\x10\x01\x00\x00\x48\x8b\x91\x70\x02\x00\x00'}
native_guards[#native_guards+1]={name='wheel_rotation',rva=0x1448ef0,bytes='\x40\x57\x48\x83\xec\x20\xf3\x0f\x10\x81\xa4\x00\x00\x00\x48\x8b\xf9\x0f\x2e\xc1\x7a\x24\x75\x22\xf7\x01\x00\x00\x00\x10\x74\x12'}
native_guards[#native_guards+1]={name='wheel_cursor',rva=0x182adb8,bytes='\xf3\x41\x0f\x10\x87\xe8\x1c\x00\x00\x49\x8d\x8f\x40\x0b\x00\x00\xf3\x0f\x59\x05\xc8\xcb\xb9\x00\xf3\x0f\x11\x45\x87\xf3\x41\x0f\x10\x87\xec\x1c\x00\x00\xf3\x0f\x59\x05\xb2\xcb\xb9\x00\xf3\x0f\x11\x45\x8b\x48\x8b\x55\x87\xe8\xac\xc8\xc1\xff\xe9\x5a\xf9\xff\xff'}
native_guards[#native_guards+1]={name='wheel_icon_definition',rva=0x183a1e5,bytes='\x49\x8b\x96\xb0\x00\x00\x00\x48\x8d\xbe\x18\x05\x00\x00\x48\x8b\xcf\xe8\x65\x5f\xc1\xff'}
native_guards[#native_guards+1]={name='wheel_label_definition',rva=0x66d54c,bytes='\x4b\x8b\x84\xfd\x00\xb6\x7c\x03\x48\x89\x7c\x24\x28\x8b\x78\x28'}

-- r17 separately allocated wedge sprites and nested transforms.
native_guards[#native_guards+1]={name='expanded_sprite_constructor',rva=0x143eab0,bytes='\x40\x53\x48\x83\xec\x20\xba\x03\x00\x00\x00\x48\x8b\xd9\xe8\x7d\x7d\x00\x00\x48\xc7\x44\x24\x30\x00\x00\x00\x00\x48\x8b\x44\x24\x30\x48\x89\x83\x14\x01\x00\x00\xc7\x44\x24\x30\x00\x00\x80\x3f'}
native_guards[#native_guards+1]={name='expanded_sprite_asset',rva=0x144f800,bytes='\x48\x89\x5c\x24\x08\x57\x48\x83\xec\x20\x41\x0f\xb6\xf8\x48\x8b\xd9\x48\x85\xd2\x75\x0f\x48\x8b\x5c\x24\x30\x48\x83\xc4\x20\x5f'}
native_guards[#native_guards+1]={name='expanded_rotation_pivot',rva=0x14481a0,bytes='\x48\x89\x54\x24\x10\x48\x83\xec\x28\xf3\x0f\x10\x41\x34\x4c\x8b\xc9\x0f\x2e\x44\x24\x38\x7a\x10\x75\x0e\xf3\x0f\x10\x41\x38\x0f'}
native_guards[#native_guards+1]={name='expanded_sprite_order',rva=0x14491f0,bytes='\x48\x83\xec\x28\x4c\x8b\xc9\x66\x39\x91\xbc\x00\x00\x00\x75\x07\x32\xc0\x48\x83\xc4\x28\xc3\x66\x89\x91\xbc\x00\x00\x00\x8b\x91'}
native_guards[#native_guards+1]={name='expanded_sprite_color',rva=0x1448690,bytes='\x48\x89\x5c\x24\x10\x48\x89\x6c\x24\x18\x56\x57\x41\x57\x48\x83\xec\x20\xf3\x0f\x10\x41\x48\x48\x8b\xf2\x0f\x2e\x02\x48\x8b\xf9'}
native_guards[#native_guards+1]={name='expanded_parent_transform',rva=0x144a5e9,bytes='\x48\x8b\x83\xf0\x00\x00\x00\x0f\x29\x45\x70\x0f\x29\x8d\x80\x00\x00\x00\x48\x85\xc0\x0f\x84\xb5\x0d\x00\x00\xf3\x0f\x10\x6d\x10\xf3\x0f\x10\x55\x14\xf3\x0f\x10\x65\x18\xf3\x0f\x10\x5d\x1c\xf3\x0f\x10\x70\x64\xf3\x44\x0f\x10\x78\x74\xf3\x0f\x10\x88\x84\x00'}

-- r19 native stratagem material and channel-color parameters.
native_guards[#native_guards+1]={name='icon_material_get',rva=0x144f6e0,bytes='\x8b\x01\xc1\xe8\x12\x83\xe0\x0f\x83\xc0\xfd\x83\xf8\x0a\x77\x44\x4c\x8d\x05\x09\x09\xbb\xfe\x41\x8b\x94\x80\x38\xf7\x44\x01\x49'}
native_guards[#native_guards+1]={name='icon_material_parameter',rva=0x14498c0,bytes='\x48\x89\x5c\x24\x08\x48\x89\x74\x24\x10\x57\x48\x83\xec\x20\x49\x8b\xd8\x8b\xfa\x48\x8b\xf1\xe8\x04\x5e\x00\x00\x48\x8b\xd0\xe8'}
native_guards[#native_guards+1]={name='icon_material_source',rva=0x18398be,bytes='\xe8\xed\x51\xc0\xff\x45\x33\xc0\x48\x8b\xd3\x48\x8b\xcf\xe8\x2f\x5f\xc1\xff\xc7\x45\xc0\x00\x00'}
native_guards[#native_guards+1]={name='icon_channel_palette',rva=0x183a1fb,bytes='\x48\x8b\xcf\xe8\xdd\x54\xc1\xff\x48\x85\xc0\x74\x1f\x45\x8b\x86\xb8\x00\x00\x00\x48\x8d\x05\x2a\xde\xad\x01\x49\xc1\xe0\x04\xba\x4d\x3f\x72\x28\x4c\x03\xc0\xe8\x99\xf6\xc0\xff\x48\x8b\xcf\xe8\xb1\x54\xc1\xff\x48\x85\xc0\x74\x11\x4c\x8d\x05\xf5\x8a\x9a\x00\xba\xfd\xd4\x1f\x85\xe8\x7b\xf6\xc0\xff\x48\x8b\xcf\xe8\x93\x54\xc1\xff\x48\x85\xc0\x74\x11\x4c\x8d\x05\x07\x8b\x9a\x00\xba\xaf\x53\xc3\x10\xe8\x5d\xf6\xc0\xff'}

-- r24 native row timer fields and formatted-label setters.
native_guards[#native_guards+1]={name='cooldown_label',rva=0x143bf90,bytes='\x48\x83\xec\x28\x4c\x8b\xd9\x39\x91\x10\x01\x00\x00\x0f\x84\x80\x00\x00\x00\x89\x91\x10\x01\x00\x00\x48\x8b\x91\x70\x02\x00\x00'}
native_guards[#native_guards+1]={name='cooldown_number',rva=0x143c9d0,bytes='\x40\x53\x48\x83\xec\x20\x48\x8b\xd9\x48\x81\xc1\x10\x01\x00\x00\xe8\x1b\xd9\xff\xff\x84\xc0\x74\x5b\x8b\x93\xb8\x00\x00\x00\x8b'}
native_guards[#native_guards+1]={name='cooldown_field',rva=0x1836bea,bytes='\xf3\x41\x0f\x10\x87\x20\x37\x00\x00\x41\x0f\x2f\xc3\x76\x0a\xc7\x44\x24\x54\x04\x00\x00\x00'}
native_guards[#native_guards+1]={name='cooldown_format',rva=0x18377e2,bytes='\x49\x8d\x8f\xb8\x25\x00\x00\xf3\x0f\x5e\x05\x4f\xff\xb8\x00\x41\xb9\x20\x30\x00\x00\xba\x97\xe6\xd1\x51\xf3\x0f\x2c\xd8\x44\x8b\xc3\xe8\xc8\x51\xc0\xff\x66\x0f\x6e\xd3\x49\x8d\x8f\xb8\x25\x00\x00\x0f\x5b\xd2\xba\xd3\xb0\x83\x45\x41\xb9\x20\x30\x00\x00\xf3\x0f\x59\x15\x17\xff\xb8\x00\xf3\x0f\x5c\xe2\xf3\x44\x0f\x2c\xc4\xe8\x99\x51\xc0\xff'}
native_guards[#native_guards+1]={name='cooldown_hint_type',rva=0x182a1e4,bytes='\x49\x8d\x9f\x50\x0f\x00\x00\x48\x8b\xcb\xe8\xad\x0d\xc1\xff'}

-- Native Hold-release and guarded reopen witnesses.
native_guards[#native_guards+1]={name='release_guarded_open',rva=0xa8e850,bytes='\x40\x53\x48\x83\xec\x20\x48\x8b\xd9\xe8\x22\xff\xff\xff\x84\xc0\x75\x1c\x48\x8b\xcb\xe8\x56\x00\x00\x00\x84\xc0\x74\x10\x48\x8b\xcb\xe8\xfa\x0c\x00\x00\xb0\x01\x48\x83\xc4\x20\x5b\xc3\x32\xc0\x48\x83\xc4\x20\x5b\xc3'}
native_guards[#native_guards+1]={name='release_close',rva=0xa8fb50,bytes='\x48\x89\x5c\x24\x08\x48\x89\x6c\x24\x10\x48\x89\x74\x24\x18\x57\x41\x54\x41\x55\x41\x56\x41\x57\x48\x83\xec\x60\x48\x8b\x05\x9d'}
native_guards[#native_guards+1]={name='release_hold_test',rva=0xa8ed4e,bytes='\xb9\x05\x00\x00\x00\xe8\x28\x6e\xaf\xff\x44\x8b\xc8\x49\x8d\x81\xff\x01\x00\x00\x48\xc1\xe0\x05\x42\x8b\x8c\x38\x50\x01\x00\x00\x83\xf9\x02\x74\x26\x83\xf9\x09\x74\x21\x32\xc0\xeb\x1f\x3b\xc8\x0f\x85\x4c\xff\xff\xff\x43\x8b\x4c\xc3\x04\xe9\x44\xff\xff\xff\x3b\xc8\x75\x9e\x43\x8b\x44\xc3\x04\xeb\x99\xb0\x01\x49\xc1\xe1\x05\x43\x3a\x84\x39\x18\x41\x00\x00\x74\x05\x39\x75\x14\x74\x59'}
native_guards[#native_guards+1]={name='release_match_survives',rva=0xa8eda7,bytes='\x74\x05\x39\x75\x14\x74\x59'}
native_guards[#native_guards+1]={name='release_weapon_request',rva=0xa93e90,bytes='\x4c\x8b\xdc\x55\x57\x48\x8b\xec\x48\x83\xec\x78\x48\x8b\x05\x6d\x81\xba\x01\x48\x33\xc4\x48\x89\x45\xe0\x8b\x01\x48\x8b\xf9\x49\x89\x5b\x10\x33\xdb\x3b\x05\x65\xfd\x9e\x02\x49\x89\x73\x18\x8b'}
native_guards[#native_guards+1]={name='release_weapon_request_assignment',rva=0xa9401a,bytes='\x8b\x4f\x04\x8d\x41\xff\x83\xf8\x03\x77\x12\x3b\xce\x74\x0e\x8d\x41\xff\x89\x4f\x08\x83\xf8\x02\x77\x03\x89\x4f\x0c\x89\x77\x04\x83\xfe\x03\x75\x43\x44\x8b\x07'}
native_guards[#native_guards+1]={name='release_opener_slot_guard',rva=0xa8f828,bytes='\x41\x8b\x56\x08\xe8\x6f\x8c\xf1\xff\x83\xf8\x05\x74\x69\x45\x33'}
native_guards[#native_guards+1]={name='release_opener_slot_call',rva=0xa8f88f,bytes='\x49\x8d\x8d\xd0\xdc\x53\x00\x41\x8d\x52\x05\xe8\xf1\x45\x00\x00'}

-- Native stratagem row arrow atlas UV setter (1836DDA); verified live bytes.
native_guards[#native_guards+1]={name='expanded_arrow_uv',rva=0x143eef0,bytes='\x4c\x89\x44\x24\x18\x48\x89\x54\x24\x10\x48\x83\xec\x28\xf3\x0f\x10\x81\x14\x01\x00\x00'}

native_guards[#native_guards+1]={name='controller_active_binding',rva=0x12f95d2,bytes='\x44\x8b\x8d\x18\x7c\x0a\x00\x48\x8d\x15\x40\x40\x18\x02\x41\x83\xf9\xff\x74\x4c'}

native_guards[#native_guards+1]={name='controller_stick_binding',rva=0x182b6ce,bytes='\x8b\x08\x83\xe1\x0f\x83\xf9\x09\x77\x35\x48\x8d\x15\x21\x49\x7d\xfe\x8b\x8c\x8a\xc4\xba\x82\x01\x48\x03\xca\xff\xe1\xbd\x03\x00\x00\x00\xeb\x20\xbd\x01\x00\x00\x00\xeb\x19\x48\x8d\xb7\xe8\x1c\x00\x00\xbd\x02\x00\x00\x00\x48\x89\x1e\xe9\x86\x01\x00\x00\xbd\x04\x00\x00\x00\x41\x80\xbe'}

native_guards[#native_guards+1]={name='dock_card_constructor',rva=0x1839520,bytes=''}

native_guards[#native_guards+1]={name='dock_card_tick',rva=0x1839fd0,bytes=''}
-- Native cached charge count -> count label formatter, read-only witness.
native_guards[#native_guards+1]={name='dock_charge_count',rva=0x183aef1,bytes='\x44\x8b\x86\xbc\x14\x00\x00\x48\x8d\x8e\xe0\x0c\x00\x00\xba\x35\x7b\x2a\xab'}

native_guards[#native_guards+1]={name="list_text_colour",rva=0x1448690,bytes="\x48\x89\x5c\x24\x10\x48\x89\x6c\x24\x18\x56\x57\x41\x57\x48\x83\xec\x20\xf3\x0f\x10\x41\x48"}

return {native_guards=native_guards}
]=],
["src/native.lua"]=[=[-- Supported-build adapter. All drawing remains in the game's native HUD.
local function native_backend()
    local ffi = require('ffi')
    if not pcall(ffi.typeof,'NSR_vec2') then
        ffi.cdef 'typedef struct { float x, y; } NSR_vec2;'
    end
    ffi.cdef [[
        void *GetModuleHandleA(const char *name);
        void *GetCurrentProcess(void);
        int ReadProcessMemory(void *, const void *, void *, size_t, size_t *);
        int WriteProcessMemory(void *, void *, const void *, size_t, size_t *);
    ]]
    local kernel=ffi.load('kernel32')
    local process=kernel.GetCurrentProcess()
    local base=tonumber(ffi.cast('uintptr_t',kernel.GetModuleHandleA('game.dll')))
    assert(base and base>0,'game.dll unavailable')
    local buffer,received=ffi.new('uint8_t[512]'),ffi.new('size_t[1]')
    local function read(address,size)
        if type(address)~='number' or address<65536 or address>=2^47 or size>512 then return nil end
        if kernel.ReadProcessMemory(process,ffi.cast('const void *',address),buffer,size,received)==0
            or tonumber(received[0])~=size then return nil end
        return ffi.string(buffer,size)
    end
    local function u32(bytes,offset)
        if not bytes or #bytes<offset+4 then return nil end
        local a,b,c,d=bytes:byte(offset+1,offset+4)
        return a+b*256+c*65536+d*16777216
    end
    local function pointer(address)
        local bytes=read(address,8)
        if not bytes then return nil end
        local p=u32(bytes,0)+u32(bytes,4)*4294967296
        if p<65536 or p>=2^47 or p%8~=0 then return nil end
        return p
    end
    local header=assert(read(base,64),'Cannot read PE header')
    assert(header:sub(1,2)=='MZ','Invalid DOS header')
    local pe=u32(header,60)
    assert(pe>=64 and pe<4096,'Invalid PE offset')
    header=assert(read(base+pe,32))
    assert(header:sub(1,4)=='PE\0\0' and u32(header,8)==1790161983,'Unsupported game build')
    -- Signatures include the native constructor/update layout witnesses as
    -- well as every called entry point. No executable bytes are changed.
    for _, guard in ipairs(native_guards) do
        assert(read(base+guard.rva,#guard.bytes)==guard.bytes,'Native signature changed: '..guard.name)
    end
    local specs={
        position={offset=4,rva=0x14476a0}, size={offset=12,rva=0x1447160},
        scale={offset=20,rva=0x1447ed0}, anchor={offset=44,rva=0x144f160},
        pivot={offset=60,rva=0x144f0d0},
        animation_a={offset=0x3738}, animation_b={offset=0x3740},
    }
    for _,spec in pairs(specs) do
        if spec.rva then spec.call=ffi.cast('void (*)(uintptr_t, NSR_vec2)',base+spec.rva) end
    end
    local float_pair=ffi.new('float[2]')
    local vector=ffi.new('NSR_vec2')
    local function pair(bytes)
        if not bytes then return nil end
        ffi.copy(float_pair,bytes,8)
        local x,y=tonumber(float_pair[0]),tonumber(float_pair[1])
        if x~=x or y~=y or math.abs(x)>100000 or math.abs(y)>100000 then return nil end
        return {x,y}
    end
    local backend={}
    local endpoint_owner
    local function hud()
        local root=pointer(base+0x346d538)
        if not root or read(root+0x24e334,1)~='\1' then return nil end
        -- Only the gameplay HUD constructs this panel; frontend/ship layouts
        -- occupy the same larger owner and must not be interpreted as it.
        local state=pointer(base+0x3326340)
        if not state or u32(read(state+0xac21c,4),0)~=4 then return nil end
        return root
    end
    function backend.valid(identity)
        if hud()~=identity then return false,'HUD owner changed' end
        local panel=identity+0x24e340+0x146dc0
        local list=panel+0x1040
        local parents={{panel,identity+0x820,'panel'},
            {identity+0x820,identity+0x258,'HUD container'},
            {panel+0x110,panel,'fade container'},
            {panel+0x220,panel+0x110,'content container'},
            {list,panel+0x220,'list'}}
        for _,item in ipairs(parents) do
            if pointer(item[1]+0xf0)~=item[2] then return false,item[3]..' parent mismatch' end
        end
        for index=0,15 do
            if pointer(list+0x110+index*0x3760+0xf0)~=list then return false,'card '..index..' parent mismatch' end
        end
        return true
    end
    -- Guarded widget_opacity stores its scalar at +0x44 (signature above).
    local opacity_call=ffi.cast('void (*)(uintptr_t, float)',base+0x1448ad0)
    local opacity_value=ffi.new('float[1]')
    function backend.opacity_targets(card)
        -- These native containers own only the name, status and arrow strip.
        -- Native row ticks rewrite the children; inherited container tint survives.
        local targets={card+0x1f18,card+0x24a8,card+0x2870}
        for _,p in ipairs(targets)do
            local at=p;local valid=false
            for depth=1,8 do
                local parent=pointer(at+0xf0)
                if parent==card then valid=true;break end
                if not parent or parent<card or parent>=card+0x3760 or parent==at then break end
                at=parent
            end
            assert(valid,'List text container owner changed')
        end
        assert(pointer(card+0x2028+0xf0)==targets[1]and pointer(card+0x25b8+0xf0)==targets[2]
            and pointer(card+0x2980+0xf0)==targets[3],'List text container layout changed')
        return targets
    end
    function backend.get_opacity(address)
        local bytes=read(address+0x44,4)
        if not bytes then return nil end
        ffi.copy(opacity_value,bytes,4)
        local value=tonumber(opacity_value[0])
        assert(value==value and value>=0 and value<=1,'Invalid widget opacity')
        return value
    end
    function backend.set_opacity(address,value)
        assert(value==value and value>=0 and value<=1,'Invalid widget opacity')
        opacity_call(address,value)
    end
    local colour_value=ffi.new('float[3]')
    local colour_call=ffi.cast('void (*)(uintptr_t, const float *)',base+0x1448690)
    local style_value=ffi.new('float[4]')
    function backend.get_text_style(address)
        local bytes=assert(read(address+0x44,16),'List text style unavailable')
        ffi.copy(style_value,bytes,16)
        local result={}
        for i=0,3 do local v=tonumber(style_value[i]);assert(v==v and v>=0 and v<=1,'Invalid list text style');result[i+1]=v end
        return result
    end
    function backend.set_text_style(address,value)
        local current=backend.get_text_style(address)
        if current[1]~=value[1]then backend.set_opacity(address,value[1])end
        if current[2]~=value[2]or current[3]~=value[3]or current[4]~=value[4]then
            for i=1,3 do colour_value[i-1]=value[i+1]end
            colour_call(address,colour_value)
        end
    end
    function backend.dock_font(sr)
        if not sr.IdString64 or not sr.Application.can_get then return nil end
        local function id(at)
            local bytes=read(at,8);if not bytes then return nil end
            return string.format('%08x%08x',u32(bytes,4),u32(bytes,0))
        end
        -- This is a packed resource descriptor, not an aligned HUD widget.
        local raw=read(base+0x37c5478,8)
        local owner=raw and(u32(raw,0)+u32(raw,4)*4294967296)
        if owner and(owner<65536 or owner>=2^47-32)then owner=nil end
        local font,atlas,material=id(base+0x3772268),id(base+0x3772ee8),owner and id(owner+24)
        if not font or not atlas or not material then return nil end
        local I=sr.IdString64
        -- IdString64 values are frame-local engine temporaries. Retain only HEX
        -- strings; consumers must resolve each ID at the immediate API call.
        if not sr.Application.can_get('font',I.from_hex(font))or not sr.Application.can_get('texture',I.from_hex(atlas))or not sr.Application.can_get('material',I.from_hex(material))then return nil end
        return {font=font,atlas=atlas,material=material}
    end
    function backend.dock_text_position(s,x,y)
        local size=assert(pair(read(s.dock_parent+0x24,8)))
        local bytes=assert(read(s.dock_parent+0x64,64));local m=ffi.new('float[16]');ffi.copy(m,bytes,64)
        x=x+size[1]/2
        return tonumber(m[0])*x+tonumber(m[8])*y+tonumber(m[12]),tonumber(m[2])*x+tonumber(m[10])*y+tonumber(m[14])
    end
    function backend.get(address,property)
        return pair(read(address+specs[property].offset,8))
    end
    function backend.set(address,property,value)
        assert(value[1]==value[1] and value[2]==value[2]
            and math.abs(value[1])<=100000 and math.abs(value[2])<=100000,'Invalid vector')
        vector.x,vector.y=value[1],value[2]
        local spec=specs[property]
        if spec.call then
            spec.call(address,vector)
        else
            -- Exactly two 8-byte vectors in validated native card objects.
            -- These are layout data, not code, input, or gameplay payloads.
            local root=hud()
            assert(root and root==endpoint_owner,'Animation owner changed')
            local index=(address-(root+0x24e340+0x146dc0+0x1150))/0x3760
            local original_card=index>=0 and index<16 and index%1==0
                and pointer(address+0xf0)==root+0x24e340+0x146dc0+0x1040
            assert(original_card or (backend.radial_card and backend.radial_card(address)),
                'Invalid animation card')
            float_pair[0],float_pair[1]=value[1],value[2]
            assert(read(address+spec.offset,8),'Animation data unavailable')
            assert(kernel.WriteProcessMemory(process,ffi.cast('void *',address+spec.offset),
                float_pair,8,received)~=0 and tonumber(received[0])==8,'Animation write failed')
        end
    end
    function backend.snapshot(include_closed)
        local root=hud()
        if not root then return nil,'waiting for initialized gameplay HUD' end
        -- Read the native visibility bits through the existing HUD snapshot.
        -- Screen-GUI labels do not inherit these widget ancestors themselves.
        local function shown(address)
            local bytes=read(address,4)
            return bytes and math.floor(u32(bytes,0)/16)%2==1 or false
        end
        local hud_visible=shown(root+0x258) and shown(root+0x820)
        local panel=root+0x24e340+0x146dc0
        local open=read(panel+0x38769,1)
        if open=='\0' and not include_closed then return {identity=root,open=false,hud_visible=hud_visible},'native menu closed' end
        if open~='\1' and open~='\0' then return nil,'Invalid menu-open flag' end
        local valid,reason=backend.valid(root)
        if not valid then return nil,'HUD hierarchy not recognized: '..reason end
        endpoint_owner=root
        local list=panel+0x1040
        local function geometry(address)
            local size=pair(read(address+0x24,8))
            -- Native GUI matrices use X/Z for the two screen axes; Y is
            -- depth. Reading adjacent float pairs silently loses vertical
            -- scale/translation. Project both basis vectors and the origin.
            local bytes=read(address+0x64,64)
            assert(size and bytes,'Native transform unreadable')
            local transform=ffi.new('float[16]')
            ffi.copy(transform,bytes,64)
            local matrix={}
            for i,index in ipairs({0,2,8,10,12,14}) do
                local value=tonumber(transform[index])
                assert(value==value and math.abs(value)<=100000,'Invalid native transform')
                matrix[i]=value
            end
            assert(size[1]>=0 and size[2]>=0,'Invalid measured dimensions')
            return {width=size[1],height=size[2],matrix=matrix}
        end
        local viewport,container=geometry(root+0x258),geometry(list)
        if viewport.width<=0 or viewport.height<=0 then return nil,'Viewport dimensions not ready' end
        local dock_y=math.max(100,viewport.height*0.10)+32
        local dock_below_y=dock_y-62
        local dock_anchor='viewport fallback'
        local stamina=root+0x24e340+0x5778
        local bar=stamina+0x110
        if pointer(stamina+0xf0)==root+0x820 and pointer(bar+0xf0)==stamina then
            local good,g=pcall(geometry,bar)
            if good and g.width>0 and g.width<=1200 and g.height>0 and g.height<=100 then
                local m,v=g.matrix,viewport.matrix
                local x=m[1]*g.width/2+m[3]*g.height+m[5]-v[5]
                local y=m[2]*g.width/2+m[4]*g.height+m[6]-v[6]
                local det=v[1]*v[4]-v[2]*v[3]
                if math.abs(det)>0.000001 then
                    dock_y=(y*v[1]-x*v[2])/det+24+(radial.dock_gap or 6)
                    local bx=m[1]*g.width/2+m[5]-v[5]
                    local by=m[2]*g.width/2+m[6]-v[6]
                    dock_below_y=(by*v[1]-bx*v[2])/det-16-(radial.dock_gap or 6)
                    dock_anchor='native stamina bar'
                end
            end
        end
        local centered,center=pcall(radial.center,viewport,container)
        if not centered then return nil,'waiting for invertible list transform' end
        local rows={}
        for index=0,15 do
            local address=list+0x110+index*0x3760
            local active=read(address+0x36f0,1)
            if active~='\0' and active~='\1' then return nil,'Invalid native card state' end
            if active=='\1' then
                local size=backend.get(address,'size')
                if not size or size[1]<=0 or size[1]>1200 or size[2]<=0 or size[2]>500 then
                    return nil,'Invalid native card dimensions'
                end
                local target=backend.get(address,'animation_b')
                if not target then return nil,'Native row layout unavailable' end
                rows[#rows+1]={address=address,width=size[1],height=size[2],entry=u32(read(address+0x3748,4),0),list_y=target[2],dock_source=address+0x7c0}
            end
        end
        return {identity=root,hud_visible=hud_visible,panel=panel,list=list,rows=rows,open=open=='\1',dock_rows=include_closed,dock_parent=root+0x258,dock_y=dock_y,dock_below_y=dock_below_y,dock_anchor=dock_anchor,center=center,geometry=string.format('viewport=%.1fx%.1f matrix=%s list=%.1fx%.1f matrix=%s',viewport.width,viewport.height,table.concat(viewport.matrix,','),container.width,container.height,table.concat(container.matrix,','))}
    end
    local release_ui
    function backend.release_owned_ui(storage,address,identity,parent,retired)
        for _,old in ipairs(retired or {}) do
            local at=math.floor((tonumber(ffi.cast('uintptr_t',old))+31)/16)*16
            if read(at+0xf0,8)~=string.rep('\0',8) then return false,'Old HUD generation remains linked; restart required' end
        end
        if address then
            if backend.valid(identity) and pointer(address+0xf0)==parent then
                release_ui=release_ui or ffi.cast('void (*)(uintptr_t)',base+0x144dd70)
                release_ui(address)
            end
            if read(address+0xf0,8)~=string.rep('\0',8) then return false,'Native UI root did not detach; restart required' end
        end
        return true
    end
    backend.read=read; backend.pointer=pointer; backend.u32=u32; backend.base=base
    local input_handler=ffi.cast('void (*)(uintptr_t)',base+0xa900d0)
    -- Parse anonymous function types once: repeated ffi.cast strings exhaust LuaJIT's type table.
    local open_input=ffi.cast('uint8_t (*)(uintptr_t)',base+0xa8e850)
    local close_input=ffi.cast('void (*)(uintptr_t)',base+0xa8fb50)
    local ui_sound=ffi.cast('void (*)(uintptr_t, uint32_t)',base+0x1327f50)
    local scramble_effect=ffi.cast('uintptr_t (*)(uintptr_t, uint32_t *, uint32_t, uint32_t, uintptr_t, uintptr_t)',base+0xa10820)
    local request_slot=ffi.cast('void (*)(uintptr_t, uint32_t)',base+0xa93e90)
    local byte=ffi.new('uint8_t[1]')
    function backend.pulse_byte(address,value)
        byte[0]=value
        assert(kernel.WriteProcessMemory(process,ffi.cast('void *',address),byte,1,received)~=0
            and tonumber(received[0])==1,'Native action write failed')
    end
    function backend.invoke_input(component) input_handler(component) end
    function backend.replace_bytes(address,expected,replacement)
        assert((#expected==4 or #expected==20) and #replacement==#expected,'Invalid binding edit size')
        if read(address,#expected)~=expected then return false end
        assert(kernel.WriteProcessMemory(process,ffi.cast('void *',address),replacement,#replacement,received)~=0
            and tonumber(received[0])==#replacement,'Native binding edit failed')
        return true
    end
    function backend.open_input(component)
        return open_input(component)~=0
    end
    function backend.close_input(component)
        close_input(component)
    end
    function backend.ui_sound(event)
        local events={move=0x39425a55,confirm=0xdd274583}
        local sound=assert(events[event],'Unknown selection sound')
        local engine=assert(pointer(base+0x3326318),'Audio engine unavailable')
        local game=assert(pointer(base+0x3326340),'Game state unavailable')
        assert(pointer(engine+0x288) and pointer(engine+0x338) and pointer(game+0x10f8),'UI audio unavailable')
        ui_sound(0,sound)
    end
    function backend.scramble_effect(effects,key,kind)
        local result=ffi.new('uint32_t[1]',0xffffffff)
        -- Same six-argument query as the matcher; optional outputs are null.
        scramble_effect(effects,result,key,kind,0,0)
        return tonumber(result[0])
    end
    function backend.request_stratagem_slot(weapon)
        request_slot(weapon,5)
    end
    ffi.cdef 'unsigned long long GetTickCount64(void);'
    function backend.milliseconds() return tonumber(kernel.GetTickCount64()) end
    ffi.cdef [[
        void *GetForegroundWindow(void);
        unsigned long GetWindowThreadProcessId(void *, unsigned long *);
        unsigned long GetCurrentProcessId(void);
    ]]
    local user=ffi.load('user32')
    local foreground_pid=ffi.new('unsigned long[1]')
    function backend.focused()
        foreground_pid[0]=0
        user.GetWindowThreadProcessId(user.GetForegroundWindow(),foreground_pid)
        return foreground_pid[0]==kernel.GetCurrentProcessId()
    end
    return backend
end

return {native_backend=native_backend}
]=],
["src/menu_latch.lua"]=[=[-- Temporarily give Display Stratagem List Press/toggle semantics. Unlike a
-- transient evaluated button byte, its live mapping survives input evaluation.
-- Only the live map is edited; defaults and persisted bindings are untouched.
local function native_menu_latch(b)
    local ffi=require('ffi')
    local function read(at,n) local s=b.read(at,n);assert(s and #s==n,'Menu mapping unavailable');return s end
    local function num(at) return b.u32(read(at,4),0) end
    local function packed(value) local v=ffi.new('uint32_t[1]',value);return ffi.string(v,4) end
    local function bucket(owner)
        assert(b.pointer(b.base+0x347cf18)==owner,'Native controls owner changed')
        local map=owner+686800
        assert(num(map+8)==256,'Unexpected native binding map capacity')
        local table_address=assert(b.pointer(map),'Native binding map unavailable')
        for i=0,255 do
            local at=table_address+i*328
            if num(at)==0x50000 then
                local count=num(at+4);assert(count<=16,'Invalid Display Stratagem List mappings')
                return at,count
            end
        end
        error('Display Stratagem List mapping missing')
    end
    local self={}
    function self.acquire(owner,actions)
        local lease={owner=owner,actions=actions,records={},types={}}
        function lease.restore(avatar_valid)
            if b.pointer(b.base+0x347cf18)~=owner then return end
            local at,count=bucket(owner)
            -- Resolve the current map again: a config reload may relocate it.
            -- Restore only exact values we installed, never a user's new edit.
            for _,record in ipairs(lease.records) do
                local p=at+8+record.index*20
                if record.index<count and read(p,20)==record.patched then
                    assert(b.replace_bytes(p,record.patched,record.original),'Menu mapping restoration failed')
                end
            end
            for _,record in ipairs(lease.types) do
                if record.at==owner+808+32*(97*5)+24 or avatar_valid then
                    if b.read(record.at,4)==packed(0) then
                        assert(b.replace_bytes(record.at,packed(0),record.original),'Menu trigger restoration failed')
                    end
                end
            end
        end
        function lease.refresh()
            local at,count=bucket(owner)
            for _,record in ipairs(lease.records) do
                assert(record.index<count and read(at+8+record.index*20,20)==record.patched,
                    'Display Stratagem List binding changed during selection')
            end
            -- The current frame may still contain the old Hold trigger. Match
            -- the Press mapping now; future native evaluations derive it.
            for _,p in ipairs({owner+808+32*(97*5)+24,actions+24}) do
                local original=read(p,4);local trigger=b.u32(original,0)
                assert(trigger==0 or trigger==2 or trigger==9,'Unexpected menu trigger state')
                if trigger~=0 then
                    lease.types[#lease.types+1]={at=p,original=original}
                    assert(b.replace_bytes(p,original,packed(0)),'Menu trigger latch failed')
                end
            end
        end
        local ok,why=pcall(function()
            local at,count=bucket(owner)
            for i=0,count-1 do
                local p=at+8+i*20;local original=read(p,20)
                local trigger=b.u32(original,8)
                if trigger==2 or trigger==9 then
                    local flags=b.u32(original,0)
                    assert(math.floor(flags/16)%16==4 and math.floor(flags/65536)%16==trigger,
                        'Unexpected Hold mapping format')
                    local patched=packed(flags-trigger*65536)..original:sub(5,8)..packed(0)..original:sub(13)
                    lease.records[#lease.records+1]={index=i,original=original,patched=patched}
                    assert(b.replace_bytes(p,original,patched),'Menu mapping latch failed')
                end
            end
            assert(#lease.records>0,'No Hold mapping available for release selection')
            lease.refresh()
        end)
        if not ok then
            local restored,reason=pcall(lease.restore,true)
            assert(restored,'Menu latch rollback failed: '..tostring(reason))
            error(why)
        end
        return lease
    end
    return self
end

return {native_menu_latch=native_menu_latch}
]=],
["src/mission_blacklist.lua"]=[=[local mission_blacklist_names={
    [5]='ORBITAL ILLUMINATION FLARE',
    [7]='EXTRACTION BEACON',
    [11]='RAISE FLAG',
    [17]='BUG THUMPER',
    [19]='SEISMIC PROBE',
    [28]='SEAF Artillery',
    [29]='DARK FLUID BACKPACK',
    [33]='Resupply',
    [36]='OIL RIG EXTRACT',
    [42]='HELLBOMB',
    [48]='DATA JACK',
    [49]='Eagle Rearm',
    [64]='TCS 03 THUMPER',
    [70]='PROSPECTING DRILL',
    [71]='CARGO CONTAINER',
    [72]='BUG PLUG',
    [76]='Cyborg Carry Data',
    [78]='SHOULDER MOUNTED CAMERA',
    [79]='Carry Data',
    [84]='JAMMED PINATA',
    [85]='RAISE FLAG NO CLEAR AREA',
    [86]='REMOTE EXPLOSIVES',
    [94]='POISON DRILL',
    [98]='EMERGENCY EXTRACTION BEACON',
    [102]='MOBILE COMMS RELAY',
    [103]='Carpet Bombing Run',
    [108]='Scrambler',
    [111]='IMMEDIATE EXTRACTION BEACON',
    [122]='SPIRE STERILIZER',
    [123]='CALL IN DESTROYER',
    [124]='Reinforce',
    [128]='Upload Discovery',
    [129]='DRILLING CHARGE',
    [132]='Nuke',
    [138]='CARGO CONTAINER',
    [145]='SOS Beacon',
    [148]='EXTRACTION',
}
local function mission_blacklist_settings(menu,state,available)
    local mcm=rawget(_G,'DBFMCM')
    if state.excluded and not state.dirty and state.available_input==available
        and state.owner==menu and state.provider==mcm and state.ready then return state.excluded end
    state.dirty=false
    if state.owner and state.owner~=menu then
        if state.native then pcall(state.native.unregister) end
        state.native=nil;state.provider=nil;state.registered={}
    end
    state.owner=menu
    local prefix='native_stratagem_radial.'
    local simple={{kind=145,id='hide_sos',label='Blacklist SOS Beacon'},{kind=49,id='hide_eagle_rearm',label='Blacklist Eagle Rearm'}}
    if not state.enabled then
        state.enabled={}
        local loader=rawget(_G,'CowboyBingusModLoader');local data=os.getenv('LOCALAPPDATA')
        local dir=loader and loader.log_directory or (data and data..'/CowboyBingus/Helldivers2/Logs')
        local function read_values(name)
            local values={};local file=dir and io.open(dir..'/'..name,'rb')
            if file then for id,value in file:read('*a'):gmatch('([^\t\r\n]+)\t([^\r\n]*)')do values[id]=value end;file:close()end
            return values
        end
        local saved=read_values('DiversBestFriendBlacklist.log');local legacy=read_values('ModOptionsMenu.values')
        if saved.version=='2' then
            for key,value in pairs(saved)do local kind=tonumber(key);if mission_blacklist_names[kind] and value=='true'then state.enabled[kind]=true end end
        elseif saved.version=='1' then
            for index=1,3 do local kind=tonumber(saved[tostring(index)]);if mission_blacklist_names[kind]then state.enabled[kind]=true end end
        else
            for index=1,8 do local kind=tonumber(legacy[prefix..'blacklist_kind_'..index]);if mission_blacklist_names[kind]then state.enabled[kind]=true end end
            if legacy[prefix..'hide_sos']=='true'then state.enabled[145]=true end
            if legacy[prefix..'hide_eagle_rearm']=='true'then state.enabled[49]=true end
        end
        state.save=function()
            local current=rawget(_G,'CowboyBingusModLoader')
            local file=current and type(current.open_log)=='function' and current.open_log('DiversBestFriendBlacklist.log')
            if not file then return false end
            local ids={};for kind,value in pairs(state.enabled)do if value and mission_blacklist_names[kind]then ids[#ids+1]=kind end end;table.sort(ids)
            local lines={'version\t2\n'};for _,kind in ipairs(ids)do lines[#lines+1]=kind..'\ttrue\n'end
            local ok=file:write(table.concat(lines));file:close();return ok~=nil
        end
    end
    state.registered=state.registered or {}
    local function changed(kind,value,from_native)
        if state.owner~=menu then return end
        local next_value=value==true
        if (state.enabled[kind]==true)==next_value then return end
        state.enabled[kind]=next_value;state.dirty=true;state.save_pending=not state.save()
        if state.syncing then return end
        state.syncing=true
        for _,option in ipairs(simple)do if option.kind==kind and state.registered[kind]then menu.set(prefix..option.id,value==true)end end
        if not from_native and state.native then state.native.set('kind_'..kind,value==true)end
        state.syncing=false
    end
    if type(menu.set)=='function' and type(menu.on_change)=='function'then
        for _,option in ipairs(simple)do
            if not state.registered[option.kind]then
                local kind=option.kind
                local ok=menu.register_option(prefix..option.id,{mod="Diver's Best Friend",mod_id="hwg90.divers_best_friend",label=option.label,type='toggle',default=false,gap=kind==145,
                    description='Available on the ship. Prevents selection in List Select and hides it on wheels when present in your mission. Use MCM for additional blacklist entries.'})
                if ok then
                    menu.set(prefix..option.id,state.enabled[kind]==true)
                    local subscribe=dbf_menu_subscribe or function(m,id,fn)return m.on_change(id,fn)end
                    subscribe(menu,prefix..option.id,function(value)if not state.syncing then changed(kind,value,false)end end)
                    state.registered[kind]=true
                end
            end
        end
    end
    if state.provider~=mcm then
        if state.native then pcall(state.native.unregister)end
        state.native=nil;state.provider=mcm;state.registration_attempted=nil
    end
    if mcm and mcm.api==1 and type(mcm.register)=='function' and not state.native and not state.registration_attempted then
        state.registration_attempted=true
        local ids={};for kind in pairs(mission_blacklist_names)do ids[#ids+1]=kind end;table.sort(ids)
        local groups={
            {column=1,label='General',ids={49,145}},
            {column=1,label='Testing: support and extraction',ids={5,7,28,33,42,98,103,108,111,123,124,132,148}},
            {column=2,label='Testing: mission devices',ids={17,19,36,64,70,72,84,86,94,122,129}},
            {column=2,label='Testing: cargo, data and objectives',ids={11,29,48,71,76,78,79,85,102,128,138}},
        }
        local controls={}
        for _,group in ipairs(groups)do
          controls[#controls+1]={type='section',label=group.label,column=group.column}
          for _,kind in ipairs(group.ids)do
            local target=kind
            controls[#controls+1]={id='kind_'..kind,type='toggle',label=mission_blacklist_names[kind],column=group.column,default=state.enabled[kind]==true,
                description='Prevents selecting this mission-provided stratagem in List Select and hides it on wheels. Equipped stratagems and unreadable mission data remain protected.',
                on_change=function(value)if not state.syncing then changed(target,value,true)end end}
          end
        end
        local existing=type(mcm.mods)=='table' and mcm.mods.dbf_ass_blacklist
        local handle,ok
        if existing then
            local owned=existing.id=='dbf_ass_blacklist' and existing.name=="Diver's Best Friend - Blacklist"
                and existing.parent_name=="Diver's Best Friend" and type(existing.controls)=='table'
                and type(existing.handle)=='table' and type(existing.handle.set)=='function'
            local count=0
            if owned then
                for key,control in pairs(existing.controls) do
                    local kind=tonumber(key:match('^kind_(%d+)$'))
                    if not kind or not mission_blacklist_names[kind] or control.type~='toggle' then owned=false;break end
                    count=count+1
                end
                owned=owned and count==#ids
            end
            if owned then
                -- Reuse the exact DBF-owned schema after a provider/reload transition.
                -- Refresh callbacks in place; do not re-register or steal a foreign ID.
                for _,control in ipairs(controls) do if control.id then
                    existing.controls[control.id].on_change=control.on_change
                end end
                ok,handle=true,existing.handle
            else state.registration_error='MCM blacklist ID belongs to an unfamiliar owner' end
        else
            ok,handle=pcall(mcm.register,{id='dbf_ass_blacklist',name="Diver's Best Friend - Blacklist",parent_name="Diver's Best Friend",description='Additional blacklist entries are available here. Confirm applies pending selections.',pages={{id='blacklist',name='Blacklist',require_confirmation=true,controls=controls}}})
        end
        if ok and type(handle)=='table' and type(handle.set)=='function' then
            state.native=handle
            -- The shared blacklist file is authoritative across both menus.
            state.syncing=true;for _,kind in ipairs(ids)do handle.set('kind_'..kind,state.enabled[kind]==true)end;state.syncing=false
        end
    end
    if state.save_pending==nil then state.save_pending=true end
    if state.save_pending then state.save_pending=not state.save()end
    local excluded={}
    for _,kind in ipairs(available or {})do
        if mission_blacklist_names[kind] and state.enabled[kind] and
            ((kind==145 or kind==49) and state.registered[kind] or state.native~=nil)then excluded[kind]=true end
    end
    -- Keep the same exclusion object when availability was re-sampled unchanged.
    local prior=state.excluded
    local same=prior~=nil
    for kind in pairs(excluded) do if not prior or not prior[kind] then same=false;break end end
    if same then for kind in pairs(prior) do if not excluded[kind] then same=false;break end end end
    state.excluded=same and prior or excluded
    state.available_input=available
    state.ready=state.registered[145] and state.registered[49]
        and (not mcm or state.native~=nil or state.registration_attempted==true)
    return state.excluded
end

return {mission_blacklist_names=mission_blacklist_names,mission_blacklist_settings=mission_blacklist_settings}
]=],
["src/input.lua"]=[=[-- Native input adapter. Only one evaluated direction byte is temporarily
-- changed, restored synchronously after the normal input handler returns.
-- Descriptor bounds and mission membership are checked before activation.
local function selectable_kind(kind)
    return type(kind)=='number' and kind>0 and kind<150 and kind%1==0
end
-- Confirm and Select on Release share one bounded pacing policy.
local function input_interval(ms,default)
    if type(ms)~='number' or ms~=ms or ms<0 or ms>250 then return default end
    return ms
end
local function usage_interval(owner)
    return owner.randomize_delay and math.random(70,240)or input_interval(owner.interval_ms,70)
end
local function input_backend(b)
    local base=b.base
    local ffi=require('ffi')
    local timer_float=ffi.new('float[1]')
    local function decorate_timer(row)
        row.timer_seconds,row.timer_kind,row.unavailable=nil,nil,nil
        -- Read the same cached seconds/state the original HUD renders. This
        -- includes native special cases (shared Reinforce and Eagle timers).
        -- An unreadable or not-yet-updated card means unknown, never "ready".
        local bytes=b.read(row.address+0x3718,0x44)
        if not bytes or #bytes~=0x44 or b.u32(bytes,0x34)~=row.kind then return end
        local state=b.u32(bytes,0x40)
        row.unavailable=state==5
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
    local custom_module,custom_owned,custom_supported
    local function owned_code(address,count)
        -- Inspect only an already-loaded owner. Never start HD2Runtime or scan
        -- its registry. The shipped 0.40.0 calldown owner retains these arrays
        -- for this Lua state's lifetime and recognises exact pointer/count pairs.
        local loaded=package and package.loaded
        local module=type(loaded)=='table' and rawget(loaded,'hd2runtime/runtime/calldown_codes')
        local fn=type(module)=='table' and rawget(module,'owned')
        if module~=custom_module or fn~=custom_owned then
            custom_module,custom_owned,custom_supported=module,fn,false
            if type(fn)=='function' and rawget(module,'MAX')==9 and rawget(module,'CAPACITY')==10 then
                local ok,bytes=pcall(string.dump,fn,true)
                if ok then
                    local a,c=1,0
                    for i=1,#bytes do a=(a+bytes:byte(i))%65521;c=(c+a)%65521 end
                    custom_supported=string.format('%08x',c*65536+a)=='6b49047c'
                end
            end
        end
        assert(custom_supported,'Invalid code array: recognised HD2Runtime owner unavailable')
        assert(count<=9,'Invalid HD2Runtime code length')
        local values=fn(address,count)
        assert(type(values)=='table' and #values==count,'Invalid code array: HD2Runtime does not own pointer/count')
        return values
    end

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
            hud=hud,hud_open=hud_open,menu_active=menu_active,weapon=avatar+0x420,avatar=avatar}
    end
    local function code(kind,c)
        -- Match 66DD24/66DD94: affected kinds use a shifted definition.
        -- The seed alone does not imply that this particular kind is affected.
        assert(selectable_kind(kind),'Invalid stratagem kind')
        -- The query itself dereferences the original definition's category.
        local source_settings=ptr(base+0x348e8f8)
        local source_info=ptr(base+0x37cb600+kind*8,4)
        assert(source_info>=source_settings and source_info+400<=source_settings+80280
            and num(source_info)==kind,'Invalid definition')
        local positions=ptr(base+0x3326508)
        local position_index=lookup(positions,0x40,c.key,65536)
        read(ptr(positions+0x68)+position_index*0x308+0x2e0,12)
        local effects=ptr(base+0x33264b0)
        local effect=b.scramble_effect(effects,c.key,kind)
        assert(type(effect)=='number' and effect>=0 and effect<=4294967295 and effect%1==0,'Invalid scramble effect')
        if effect~=4294967295 then
            kind=((kind+num(c.avatar+0x11b8))%4294967296)%149+1
        end
        assert(selectable_kind(kind),'Invalid stratagem kind')
        local settings=ptr(base+0x348e8f8)
        -- Packed settings descriptors can be 4 mod 8 (live Maelstrom kind 50).
        -- Keep object-pointer alignment at 8; only this data record accepts 4.
        local info=ptr(base+0x37cb600+kind*8,4)
        assert(info>=settings and info+400<=settings+80280 and num(info)==kind,'Invalid definition')
        local n=num(info+0x48); local data=ptr(info+0x40,4)
        assert(n>=1 and n<=12,'Invalid code array')
        local external
        if data<settings or data+n*4>settings+80280 then external=owned_code(data,n) end
        local result={}
        for i=0,n-1 do
            local d=num(data+i*4); assert(d>=1 and d<=4,'Invalid direction')
            -- The owner proves allocation; readback proves the current bytes.
            -- advance() repeats this before each input, including scramble remaps.
            assert(not external or external[i+1]==d,'HD2Runtime code array changed')
            result[#result+1]=d
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
    function out.display_codes(rows)
        local c=context(false,true)
        local result={}
        for i,row in ipairs(rows) do result[i]=code(row.kind,c) end
        return result
    end
    function out.mission_blacklist_kinds()
        local c=context(false,true)
        local count=num(c.payload+0x788)
        assert(count<=32,'Invalid mission stratagem count')
        local result,seen={},{}
        for i=0,count-1 do
            local kind=num(c.payload+0x188+i*0x30)
            assert(kind<150,'Invalid mission stratagem kind')
            if mission_blacklist_names[kind] and not seen[kind] then
                -- Validate the same settings descriptor used by native UI.
                presentation(kind)
                seen[kind]=true;result[#result+1]=kind
            end
        end
        table.sort(result)
        return result
    end
    function out.decorate(snapshot)
        if not snapshot or (not snapshot.open and not snapshot.dock_rows) then return end
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
            row.timer_seconds,row.timer_kind,row.unavailable=nil,nil,nil
            if selectable_kind(row.kind) then decorate_timer(row);row.dock_payload=payload end
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
        return {identity=c.identity,component=c.component,kind=kind,code=code(kind,c),sent=0}
    end
    function out.advance(job)
        local c=context(true)
        assert(c.identity==job.identity and c.component==job.component,'Local avatar changed')
        local current_code=code(job.kind,c)
        assert(#current_code==#job.code,'Stratagem code changed; close and reopen the menu')
        for i,d in ipairs(current_code) do
            assert(d==job.code[i],'Stratagem code changed; close and reopen the menu')
        end
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
    local function begin_latched(kind,armed,shortcut)
        local c=out.release_state()
        assert(c.identity==armed.identity and c.component==armed.component and c.hud==armed.hud,
            'Release owner changed')
        assert((shortcut or c.hold)and not c.down and c.unobstructed,'Native menu input is held or obstructed')
        assert(num(c.component)==0 and num(c.component+0x14)==0 and num(c.component+0x2c)==0,
            'Manual input or completed selection cancels release')
        idle_actions(c)
        -- Revalidate membership/descriptor before asking the normal guarded
        -- native opener to resume a menu already closed by this frame's update.
        local n=num(c.payload+0x788);assert(n<=32,'Invalid stratagem entry count')
        local found=false
        for i=0,n-1 do if num(c.payload+0x188+i*0x30)==kind then found=true end end
        assert(found,'Released stratagem no longer belongs to the mission')
        code(kind,c)
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
            -- Closing on physical release queued the previous weapon. The
            -- native opener skips its slot-5 request when the beacon is still
            -- the current weapon, leaving that older request pending. Reissue
            -- the same native slot request, never a weapon ID or spawn call.
            local current=context(true)
            assert(current.identity==c.identity and current.component==c.component,'Release owner changed during reopen')
            assert(num(current.weapon)==c.key,'Weapon input owner mismatch')
            local requested=num(current.weapon+4)
            assert(requested>=1 and requested<=7,'Invalid requested weapon slot')
            if requested~=5 then
                if b.checkpoint then b.checkpoint('release beacon slot request enter') end
                b.request_stratagem_slot(current.weapon)
                assert(num(current.weapon+4)==5,'Native beacon slot request rejected')
                if b.checkpoint then b.checkpoint('release beacon slot request returned') end
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
    function out.begin_release(kind,armed)return begin_latched(kind,armed,false)end
    function out.begin_shortcut(slot)
        assert(type(slot)=='number'and slot%1==0 and slot>=1 and slot<=4,'Invalid equipped slot')
        local c=out.release_state()
        local n=num(c.payload+0x788);assert(n>=8 and n<=32,'Equipped stratagem slots unavailable')
        -- Native payload entries 0..3 are the shared mission slots; 4..7
        -- retain the four equipped slots independently of display sorting.
        local kind=num(c.payload+0x188+(slot+3)*0x30)
        assert(selectable_kind(kind),'Equipped slot is empty')
        return begin_latched(kind,c,true)
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

return {selectable_kind=selectable_kind,input_interval=input_interval,usage_interval=usage_interval,input_backend=input_backend}
]=],
["src/pointing.lua"]=[=[-- Native wheel binding kinds 1/2 use direct stick vectors; mouse kinds
-- integrate deltas. Require an active device so connected idle pads do not win.
local function controller_pointing(binding_kind,active_device)
    return active_device~=nil and active_device>=0 and active_device<32
        and (binding_kind==1 or binding_kind==2)
end

-- Point toward the visible card centers, including the ellipse's aspect ratio.
local function pointing_index(rows,vector,current)
    if not vector or #rows==0 then return nil end
    local x,y=vector[1],vector[2]
    if x~=x or y~=y or x*x+y*y<0.20^2 then return nil end
    local heading=math.atan2(y,x)
    local rx,ry=#rows>10 and 550 or 470,#rows>10 and 330 or 280
    local function distance(i)
        local a=math.pi/2-(i-1)*2*math.pi/#rows
        local target=math.atan2(math.sin(a)*ry,math.cos(a)*rx)
        return math.abs((heading-target+math.pi)%(2*math.pi)-math.pi)
    end
    local best,error_angle=1,math.huge
    for i=1,#rows do
        local d=distance(i)
        if d<error_angle then best,error_angle=i,d end
    end
    -- Three degrees of hysteresis keeps a boundary from flickering.
    if current and rows[current] and distance(current)<=error_angle+math.rad(3) then return current end
    return best
end

local function native_pointing(b)
    local ffi=require('ffi')
    local state=ffi.new('uint64_t[928]') -- 0x1d00, aligned; no native widget pointers
    local address=tonumber(ffi.cast('uintptr_t',state))
    local reader=ffi.cast('void (*)(uintptr_t, uintptr_t, float)',b.base+0x182b5c0)
    local binding=ffi.cast('uintptr_t (*)(uintptr_t, uint64_t, uint8_t)',b.base+0x12f9540)
    local owner
    local self={}
    function self.reset()
        ffi.fill(state,ffi.sizeof(state))
        -- One disabled wedge: native integration runs without native selection.
        ffi.cast('uint32_t *',address+0x1cd4)[0]=1
        owner=nil
    end
    function self.sample(context,dt,wheel)
        local reset=owner~=context.identity
        if reset then self.reset();owner=context.identity end
        local target=wheel or address
        if wheel then
            if reset then
                ffi.cast('float *',target+0x1ce8)[0]=0
                ffi.cast('float *',target+0x1ce8)[1]=0
                ffi.cast('float *',target+0x1cdc)[0]=0
            end
            -- A disabled/empty sector must not retain the previous selection.
            ffi.cast('uint32_t *',target+0x1cd8)[0]=0xffffffff
        end
        assert(b.pointer(b.base+0x346d560),'Native radial input state unavailable')
        local controls=assert(b.pointer(b.base+0x347cf18),'Native controls unavailable')
        if b.checkpoint then b.checkpoint('pointing binding query enter') end
        local bound=tonumber(binding(controls,0x700000003,1))
        if b.checkpoint then b.checkpoint('pointing binding query returned') end
        local bound_bytes=bound>=65536 and b.read(bound,4)
        assert(bound_bytes and #bound_bytes==4,'Native radial bindings unavailable')
        if b.checkpoint then b.checkpoint('pointing reader enter') end
        reader(target,context.input_owner,math.max(0.001,math.min(dt,0.05)))
        if b.checkpoint then b.checkpoint('pointing reader returned') end
        local v=ffi.cast('float *',target+0x1ce8)
        local x,y=tonumber(v[0]),tonumber(v[1])
        assert(x==x and y==y and math.abs(x)<=1.01 and math.abs(y)<=1.01,'Invalid radial direction')
        local active=b.read(controls+0xa7c18,4)
        local device=active and tonumber(ffi.cast('const int32_t *',active)[0])
        local kind=bound_bytes:byte(1)%16
        local result={x,y,controller=controller_pointing(kind,device)}
        if wheel then
            local index=tonumber(ffi.cast('uint32_t *',target+0x1cd8)[0])
            if index<8 and ffi.cast('uint8_t *',target+0x1cc8)[index]~=0 then result.slot=index+1 end
        end
        return result
    end
    self.reset()
    return self
end

return {controller_pointing=controller_pointing,pointing_index=pointing_index,native_pointing=native_pointing}
]=],
["src/camera.lua"]=[=[-- Use the same per-frame camera-input gate as the native radial reader.
-- Do not overwrite an existing capture owned by another native menu.
local function camera_capture(b)
    local owned
    local self={}
    function self.release()
        if owned and b.pointer(b.base+0x346d560)==owned then
            if b.read(owned+0x1a9,1)=='\1' then b.pulse_byte(owned+0x1a9,0) end
        end
        owned=nil
    end
    function self.capture()
        local owner=assert(b.pointer(b.base+0x346d560),'Camera input owner unavailable')
        if owned and owned~=owner then self.release() end
        local value=b.read(owner+0x1a9,1)
        assert(value=='\0' or value=='\1','Invalid camera input gate')
        if value=='\0' then
            b.pulse_byte(owner+0x1a9,1)
            owned=owner
        end
    end
    return self
end

return {camera_capture=camera_capture}
]=],
["src/icon_colors.lua"]=[=[-- Keep pointers per backend; parsing anonymous function types on each repaint leaks ctypes.
local icon_native_calls=setmetatable({}, {__mode='k'})
-- Called within the owner's HUD resource scope, only for separately owned icons.
local function configure_stratagem_icon(b,icon,info,cooling)
    local ffi=require('ffi')
    local calls=icon_native_calls[b]
    if not calls then
        calls={
            texture=ffi.cast('void (*)(uintptr_t, uint64_t, uint64_t, uint8_t)',b.base+0x1450230),
            material=ffi.cast('uintptr_t (*)(uintptr_t)',b.base+0x144f6e0),
            parameter=ffi.cast('void (*)(uintptr_t, uint32_t, const float *)',b.base+0x14498c0),
        }
        icon_native_calls[b]=calls
    end
    local texture,material,parameter=calls.texture,calls.material,calls.parameter
    local hash=ffi.new('uint64_t[1]');ffi.copy(hash,info.texture,8)
    if radial.full_color==false and not cooling then
        texture(icon,0x57fcf14ad069020bULL,hash[0],0)
        return
    end
    -- Native list sprite constructor 183398CC uses this material; its update
    -- 183A1E5..183A25E supplies the channel colors below. The texture is a mask,
    -- so displaying it with the generic emote material exposes red/green channels.
    local category=info.category
    assert(type(category)=='number' and category%1==0 and category>=0 and category<16,'Invalid icon color category')
    local function rgba(rva)
        local bytes=assert(b.read(b.base+rva,16),'Native icon palette unavailable')
        assert(#bytes==16,'Truncated icon palette')
        local v=ffi.new('float[4]');ffi.copy(v,bytes,16)
        for i=0,3 do assert(v[i]==v[i] and v[i]>=0 and v[i]<=1,'Invalid native icon palette') end
        return v
    end
    local accent=rgba(0x3318040+category*16)
    local foreground=rgba(0x21e2d30)
    local background=rgba(0x21e2d60)
    if cooling then
        -- Native palette vectors are A,R,G,B. Keep alpha and desaturate all
        -- three texture-mask channels, including raw-icon display mode.
        for _,v in ipairs({accent,foreground,background}) do
            local gray=0.2126*v[1]+0.7152*v[2]+0.0722*v[3]
            v[1],v[2],v[3]=gray,gray,gray
        end
    end
    texture(icon,0xaf73e09d6d725398ULL,hash[0],0)
    assert(tonumber(material(icon))~=0,'Stratagem icon material unavailable')
    parameter(icon,0x28723f4d,accent)
    parameter(icon,0x851fd4fd,foreground)
    parameter(icon,0x10c353af,background)
end

return {icon_native_calls=icon_native_calls,configure_stratagem_icon=configure_stratagem_icon}
]=],
["src/duplicate.lua"]=[=[-- Own new native widget storage. Never memcpy a live widget or its links.
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
        local ok,why=b.release_owned_ui(storage,address,identity,parent,retired)
        if not ok then return false,why end
        storage,address,identity,parent=nil,nil,nil,nil
        for i=#retired,1,-1 do retired[i]=nil end
        return true
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

return {duplicate_cards=duplicate_cards}
]=],
["src/emote.lua"]=[=[-- Separate instance of the shared native eight-sector wheel. Never run its
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
                local content_key=row and (row.kind..':'..tostring(radial.full_color~=false)..':'..tostring(row.timer_kind)..':'..tostring(row.unavailable))
                if row and content[i]~=content_key then
                    local info=input.presentation(row.kind)
                    checkpoint('wheel stratagem texture enter')
                    configure_stratagem_icon(b,icon,info,row.timer_seconds~=nil or row.unavailable)
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
                local timed=rows and rows[i+1] and (rows[i+1].timer_seconds or rows[i+1].unavailable)
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
    function self.close()
        self.hide()
        local ok,why=b.release_owned_ui(storage,address,identity,parent,retired)
        if not ok then return false,why end
        storage,address,identity,parent=nil,nil,nil,nil
        for i=#retired,1,-1 do retired[i]=nil end
        return true
    end
    return self
end

return {emote_wheel=emote_wheel}
]=],
["src/expanded.lua"]=[=[-- More than eight wedges without extending the native wheel's fixed arrays.
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
    local uv=ffi.cast('void (*)(uintptr_t, NSR_vec2, NSR_vec2)',b.base+0x143eef0)
    local storage,address,identity,parent,signature
    local retired,content={},{}
    local SIZE,STRIDE=0x15710,0x1560
    local white=ffi.new('float[3]',{1,1,1})
    local yellow=ffi.new('float[3]',{1,0.9,0.35})
    local arrow_ink=ffi.new('float[3]',{0.08,0.07,0.03})
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
    local function arrow(i,j) return address+0x110+(i-1)*STRIDE+0x4e0+(j-1)*0x160 end
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
        local codes=input.display_codes(rows)
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
                    for j=1,12 do
                        local p=arrow(i,j)
                        sprite(p);centered(p,16,0.5);order(p,0x300)
                        asset(p,0x84c0542299fb4884ULL,0)
                        assert(b.pointer(p+0xf8)==resource,'Expanded arrow context mismatch')
                        link(address,p);visible(p,0)
                    end
                    bounds()
                    checkpoint('expanded slot '..i..' constructor returned')
                end
                link(parent,address);content={}
                checkpoint('expanded root attached')
            end
            assert(owned(),'Expanded ownership mismatch')
            local center=snapshot.center or {0,0}
            b.set(address,'position',{center[1],center[2]-(radial.vertical_offset or 0)})
            local size=radial.wheel_scale or 1;b.set(address,'scale',{size,size})
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
                local size=radial.icon_scale or 1;b.set(icon,'scale',{size,size})
                local sequence=codes[i] or {}
                assert(#sequence<=12,'Expanded code exceeds arrow capacity')
                local _,_,pos=expanded_geometry(#rows,math.min(i,math.max(8,#rows)))
                local spacing=math.min(16,104/math.max(1,#sequence))*size
                local code_key=table.concat(sequence,',')..':'..size..':'..pos[1]..':'..pos[2]
                local previous=content['code'..i]
                if previous~=code_key then
                    for j=1,12 do
                        local p=arrow(i,j)
                        assert(b.pointer(p+0xf0)==address,'Expanded arrow ownership changed')
                        local direction=sequence[j]
                        visible(p,direction and 1 or 0)
                        if direction then
                            assert(direction>=1 and direction<=4 and direction%1==0,'Invalid expanded arrow direction')
                            uv(p,ffi.new('NSR_vec2',{direction/5,0}),ffi.new('NSR_vec2',{(direction+1)/5,1}))
                            b.set(p,'size',{spacing,spacing})
                            b.set(p,'position',{pos[1]+(j-(#sequence+1)/2)*spacing,pos[2]-42*size})
                        end
                    end
                    content['code'..i]=code_key
                end
                local row=rows[i]
                local content_key=row and (row.kind..':'..tostring(radial.full_color~=false)..':'..tostring(row.timer_kind)..':'..tostring(row.unavailable))
                if row and content[i]~=content_key then
                    local info=input.presentation(row.kind)
                    checkpoint('expanded icon texture enter')
                    configure_stratagem_icon(b,icon,info,row.timer_seconds~=nil or row.unavailable)
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
        local alpha=(radial.wedge_opacity or 50)/100
        gray[0],gray[1],gray[2]=0.5*brightness,0.55*brightness,0.6*brightness
        scope.context_scope(parent,function()
            checkpoint('expanded highlight enter')
            for i=1,16 do
                local _,_,wedge,icon=slot(i)
                local row=rows[i]
                local chosen=row and row.address==selected
                color(wedge,chosen and yellow or gray)
                opacity(wedge,chosen and math.max(0.95,alpha) or (row and alpha or alpha*0.08/0.3))
                local timed=row and (row.timer_seconds or row.unavailable)
                color(icon,(chosen and radial.full_color==false and not timed) and yellow or white)
                local alpha=timed and (chosen and 0.55 or 0.3) or (chosen and 1 or 0.8)
                opacity(icon,alpha)
                local arrow_state=tostring(chosen)..':'..tostring(not not timed)
                if content['highlight'..i]~=arrow_state then
                    for j=1,12 do
                        local p=arrow(i,j)
                        color(p,chosen and arrow_ink or white);opacity(p,chosen and 1 or alpha)
                    end
                    content['highlight'..i]=arrow_state
                end
                if chosen then kind=row.kind end
            end
            bounds();checkpoint('expanded highlight returned')
        end)
        return kind
    end
    function self.step(enabled,snapshot)
        if not enabled or not snapshot or not snapshot.open then self.hide();self.status='expanded wheel closed' end
    end
    function self.close()
        self.hide()
        local ok,why=b.release_owned_ui(storage,address,identity,parent,retired)
        if not ok then return false,why end
        storage,address,identity,parent=nil,nil,nil,nil
        for i=#retired,1,-1 do retired[i]=nil end
        return true
    end
    return self
end

return {expanded_geometry=expanded_geometry,expanded_index=expanded_index,expanded_wheel=expanded_wheel}
]=],
["src/cooldown_dock.lua"]=[=[-- State and geometry are independent of native ownership and rendering.
local function cooldown_dock_timed(row,track_unavailable)
    return (track_unavailable and row.unavailable==true) or not row.unavailable and (row.timer_kind=='incoming' or row.timer_kind=='cooldown')
        and type(row.timer_seconds)=='number' and row.timer_seconds>0
end
local function cooldown_dock_model()
    local self={items={},order={},identity=nil}
    function self.reset() self.items={};self.order={};self.identity=nil end
    function self.sample(snapshot,now,track_unavailable)
        if not snapshot then self.reset();return end
        if self.identity~=snapshot.identity then self.reset();self.identity=snapshot.identity end
        local wanted={}
        for _,row in ipairs(snapshot.rows or {}) do
            if cooldown_dock_timed(row,track_unavailable) then
                local key=tostring(row.entry)..':'..tostring(row.kind)
                wanted[key]=true
                local item=self.items[key]
                if not item then
                    item={key=key,kind=row.kind,born=now}
                    self.items[key]=item;self.order[#self.order+1]=key
                end
                -- Incoming -> cooldown updates the same docked icon, without a second flight.
                local phase=row.unavailable and 'unavailable' or row.timer_kind
                if item.phase~=phase then item.cooldown_span=nil end
                item.phase=phase;item.row=row
            end
        end
        for i=#self.order,1,-1 do
            local key=self.order[i]
            if not wanted[key] then self.items[key]=nil;table.remove(self.order,i) end
        end
    end
    function self.layout(now,y,overview,placement,brief_limit,below_y,balanced)
        local result={};local n=#self.order
        local split=not overview and placement and placement>1
        local short_n=0
        if split then for _,key in ipairs(self.order)do
            local item=self.items[key]
            -- Remaining charges survive a full Eagle rearm. They do not prove
            -- this is the brief between-run cooldown; classify by native time.
            item.short_status=item.phase=='incoming'or item.phase~='unavailable' and math.max(item.cooldown_span or 0,item.row.timer_seconds or 0)<=(brief_limit or 10)
            if item.short_status then short_n=short_n+1 end
        end end
        local main_n=n-short_n;local main_i,short_i=0,0
        local balance=balanced~=false and split and placement~=4 and main_n>0 and short_n>0 and (short_n*30+12)*(placement==2 and 1 or -1)or 0
        for i,key in ipairs(self.order) do
            local item=self.items[key]
            local x=overview and -70 or (i-(n+1)/2)*60
            local target_y=overview and y+(n-i)*38 or y
            item.below_stamina=false
            if split then
                if item.short_status then
                    short_i=short_i+1
                    if placement==4 then
                        x=(short_i-(short_n+1)/2)*60;target_y=below_y or y-62;item.below_stamina=true
                    elseif main_n==0 then x=(short_i-(short_n+1)/2)*60
                    elseif placement==2 then x=-(main_n*30+54)-(short_n-short_i)*60
                    else x=main_n*30+54+(short_i-1)*60 end
                else main_i=main_i+1;x=(main_i-(main_n+1)/2)*60 end
            end
            x=x+balance
            if item.target_x~=x or item.target_y~=target_y then
                item.start_x,item.start_y=item.x or x,item.y or target_y
                item.target_x,item.target_y=x,target_y;item.moved=now
            end
            local t=math.min(1,math.max(0,(now-item.moved)/350));local ease=1-(1-t)^3
            item.x=item.start_x+(x-item.start_x)*ease;item.y=item.start_y+(target_y-item.start_y)*ease
            item.alpha=math.min(1,math.max(0,(now-item.born)/140))
            result[i]=item
        end
        local divider
        if split and placement~=4 and main_n>0 and short_n>0 then
            local alpha=1;for _,item in ipairs(result)do alpha=math.min(alpha,item.alpha)end
            divider={x=(main_n*30+12)*(placement==2 and -1 or 1)+balance,y=y,alpha=alpha}
        end
        return result,divider
    end
    return self
end
-- Retained screen-GUI labels. No timer subscription exists; consume the dock's
-- existing timer updates and change retained text only when its value changes.
local function cooldown_dock_text(b)
    local self={};local gui,world,sr,font,identity,attempted;local labels={}
    local separator,separator_key
    local function destroy_label(label)
        if not label then return end
        sr.Gui.destroy_text(gui,label.id)
        sr.Gui.destroy_text(gui,label.shadow)
        if label.backdrop then sr.Gui.destroy_rect(gui,label.backdrop)end
    end
    local function world_live()
        if not world or not sr then return false end
        for _,candidate in pairs(sr.Application.worlds()or{})do if candidate==world then return true end end
        return false
    end
    function self.hide()
        -- A world destroys its GUI resources itself. Never pass a retired world
        -- or GUI to the engine; pcall cannot catch a native access violation.
        if gui and world_live() then pcall(sr.World.destroy_gui,world,gui)end
        gui,world,font,identity,attempted=nil,nil,nil,nil,nil;labels={};separator,separator_key=nil,nil
    end
    function self.draw(s,items,now,position,short_style,brief_limit,divider)
        local timers=position and position~=1
        local charges=false
        for _,item in ipairs(items)do if item.phase=='cooldown' and item.charge_count then charges=true;break end end
        if (not timers and not charges and not divider) or #items==0 then self.hide();return end
        local current=rawget(_G,'stingray');if not current or not b.dock_font then return end
        if sr~=current or identity~=s.identity then self.hide();sr=current;identity=s.identity end
        if gui and not world_live() then self.hide();identity=s.identity end
        if not gui then
            if attempted then return end;attempted=true
            font=b.dock_font(sr);if not font then return end
            local A,G=sr.Application,sr.Gui;world=A.main_world()
            for _,candidate in pairs(A.worlds()or{})do if candidate~=world then world=candidate;break end end
            if not world then return end
            gui=sr.World.create_screen_gui(world,'scale',1,1);if not gui then return end
            local ok,material=pcall(G.material,gui,sr.IdString64.from_hex(font.material))
            if not ok or not material then material=G.create_material(gui,sr.IdString64.from_hex(font.material))end
            if not material or sr.Material.set_texture(material,sr.IdString64.from_hex('88BAC99B00000000'),sr.IdString64.from_hex(font.atlas))==false then self.hide();attempted=true;return end
        end
        local G=sr.Gui;local width=G.resolution();local scale=(width or 1920)/1920
        for i=1,16 do
            local item,old=items[i],labels[i]
            if item and timers and item.phase~='unavailable' then
                local seconds=math.max(0,math.ceil(item.row.timer_seconds))
                local overview=position==5
                local incoming=item.phase=='incoming' or item.row.timer_kind=='incoming'
                local large=not overview and short_style==2 and (incoming or seconds<=(brief_limit or 10))
                local inside=large or position==4
                local size=math.max(14,(large and 36 or inside and 22 or 18)*scale)
                local text=large and tostring(seconds) or string.format('%d:%02d',math.floor(seconds/60),seconds%60)
                local above=position==2 and not item.below_stamina
                local x,y=b.dock_text_position(s,item.x,item.y+(inside and 0 or above and 30 or -42))
                if overview then
                    text=(incoming and 'INBOUND 'or 'COOLDOWN ')..text
                    x,y=b.dock_text_position(s,item.x+78,item.y-5)
                end
                if inside then y=y-size*.35 end
                local key=text..':'..x..':'..y..':'..item.alpha..':'..size..':'..tostring(overview)
                if not old or old.key~=key then
                    destroy_label(old)
                    local min,max=G.text_extents(gui,text,sr.IdString64.from_hex(font.font),size)
                    local extent=sr.Vector3.x(max)-sr.Vector3.x(min)
                    local backdrop
                    if overview then
                        local left,bottom=b.dock_text_position(s,item.x+22,item.y-12)
                        local right,top=b.dock_text_position(s,item.x+134,item.y+12)
                        backdrop=G.rect(gui,sr.Vector3(left,bottom,949),sr.Vector2(right-left,top-bottom),sr.Color(math.floor(item.alpha*150),0,0,0))
                    elseif inside then
                        local half=item.below_stamina and 16 or 24
                        local left,bottom=b.dock_text_position(s,item.x-half,item.y-half)
                        local right,top=b.dock_text_position(s,item.x+half,item.y+half)
                        backdrop=G.rect(gui,sr.Vector3(math.min(left,right),math.min(bottom,top),949),sr.Vector2(math.abs(right-left),math.abs(top-bottom)),sr.Color(math.floor(item.alpha*150),0,0,0))
                    end
                    local shadow_id=G.text(gui,text,sr.IdString64.from_hex(font.font),size,sr.IdString64.from_hex(font.material),sr.Vector3(x-extent/2+2*scale,y-2*scale,950),sr.Color(math.floor(item.alpha*210),0,0,0))
                    labels[i]={key=key,backdrop=backdrop,shadow=shadow_id,id=G.text(gui,text,sr.IdString64.from_hex(font.font),size,sr.IdString64.from_hex(font.material),sr.Vector3(x-extent/2,y,951),sr.Color(math.floor(item.alpha*255),255,255,255))}
                end
            elseif old then destroy_label(old);labels[i]=nil end
            local old_charge=labels[i+16]
            if item and item.phase=='cooldown' and item.charge_count then
                local text=tostring(item.charge_count);local size=18*scale
                local side=item.charge_side
                local x,y=b.dock_text_position(s,item.x+(side=='left'and -36 or 0),item.y+(side=='above'and 37 or side=='left'and 0 or -37))
                y=y-size*.35
                local key=text..':'..x..':'..y..':'..item.alpha..':'..size
                if not old_charge or old_charge.key~=key then
                    destroy_label(old_charge)
                    local min,max=G.text_extents(gui,text,sr.IdString64.from_hex(font.font),size)
                    local extent=sr.Vector3.x(max)-sr.Vector3.x(min)
                    local shadow=G.text(gui,text,sr.IdString64.from_hex(font.font),size,sr.IdString64.from_hex(font.material),sr.Vector3(x-extent/2+2*scale,y-2*scale,950),sr.Color(math.floor(item.alpha*210),0,0,0))
                    labels[i+16]={key=key,shadow=shadow,id=G.text(gui,text,sr.IdString64.from_hex(font.font),size,sr.IdString64.from_hex(font.material),sr.Vector3(x-extent/2,y,951),sr.Color(math.floor(item.alpha*255),255,255,255))}
                end
            elseif old_charge then destroy_label(old_charge);labels[i+16]=nil end
        end
        if divider then
            local left,bottom=b.dock_text_position(s,divider.x-1,divider.y-24)
            local right,top=b.dock_text_position(s,divider.x+1,divider.y+24)
            local key=left..':'..bottom..':'..right..':'..top..':'..divider.alpha
            if key~=separator_key then
                if separator then G.destroy_rect(gui,separator)end
                separator=G.rect(gui,sr.Vector3(left,bottom,952),sr.Vector2(right-left,top-bottom),sr.Color(math.floor(divider.alpha*210),255,255,255))
                separator_key=key
            end
        elseif separator then G.destroy_rect(gui,separator);separator,separator_key=nil,nil end
    end
    return self
end
-- Consume the dock's existing native snapshots; never start another reader.
local function cooldown_closed_notices(b)
    local self={};local saved
    function self.restore(open)
        if saved and b.valid(saved.identity)and b.get_opacity(saved.address)==saved.applied then
            -- Closed native lists can already have alpha zero. Replaying that
            -- value after the open transition makes the entire menu invisible.
            b.set_opacity(saved.address,open and saved.before==0 and 1 or saved.before)
        end
        saved=nil
    end
    function self.step(s)
        if not s or s.open~=false then self.restore(s and s.open==true);return end
        local address=s.identity+0x24e340+0x146dc0+0x1040
        if saved and saved.identity==s.identity then return end
        self.restore();assert(b.valid(s.identity),'Closed status HUD changed')
        local before=assert(b.get_opacity(address),'Closed status opacity unavailable')
        b.set_opacity(address,0)
        saved={identity=s.identity,address=address,before=before,applied=assert(b.get_opacity(address))}
    end
    return self
end
local function cooldown_dock(b,scope,input)
    local ffi=require('ffi')
    local init=ffi.cast('void (*)(uintptr_t, uint32_t)',b.base+0x1446840)
    local create=ffi.cast('void (*)(uintptr_t, uint64_t, uint64_t, uint64_t, int32_t, uint32_t)',b.base+0x1839520)
    local tick=ffi.cast('void (*)(uintptr_t, float, uint32_t, uintptr_t)',b.base+0x1839fd0)
    local attach=ffi.cast('void (*)(uintptr_t, uintptr_t)',b.base+0x144c5c0)
    local finish=ffi.cast('void (*)(uintptr_t)',b.base+0x144c2c0)
    local visible=ffi.cast('void (*)(uintptr_t, uint8_t)',b.base+0x144cfb0)
    local order=ffi.cast('void (*)(uintptr_t, uint32_t)',b.base+0x14491f0)
    local opacity=ffi.cast('void (*)(uintptr_t, float)',b.base+0x1448ad0)
    local model=cooldown_dock_model()
    local timer_text=cooldown_dock_text(b)
    local storage,address,identity,parent,snapshot
    local retired,drawn={},{}
    local self={}
    local sampled_signature,timer_text_key
    local function owned() return address and b.valid(identity) and b.pointer(address+0xf0)==parent end
    function self.hide()
        timer_text.hide()
        if not snapshot and not self.shown and #model.order==0 then return end
        if self.shown and owned() then
            for i=1,16 do if drawn[i] then visible(address+0x110+(i-1)*0x1500,0) end end
            visible(address,0)
        end
        model.reset();snapshot=nil;drawn={};self.shown=false;sampled_signature=nil
    end
    function self.sample(s,now)
        snapshot=s
        local parts={tostring(s and s.identity),tostring(s and s.dock_y),tostring(radial.full_color),tostring(radial.cooldown_timer),tostring(radial.cooldown_display)}
        for _,row in ipairs(s and s.rows or {}) do
            if cooldown_dock_timed(row,radial.track_unavailable) then
                parts[#parts+1]=tostring(row.entry)..':'..tostring(row.kind)..':'..tostring(row.unavailable and 'unavailable' or row.timer_kind)
            end
        end
        local signature=table.concat(parts,'|')
        if signature~=sampled_signature or not self.next_sample or now>=self.next_sample then
            model.sample(s,now,radial.track_unavailable);self.next_sample=now+250
        end
        if signature~=sampled_signature then
            sampled_signature=signature;self.animate_until=now+350;self.settled=false
        end
    end
    function self.draw(now,hud_visible)
        if hud_visible==false then
            timer_text.hide()
            if self.shown and owned() then visible(address,0)end
            self.shown=false;self.settled=false
            return
        end
        local timer_due=not self.next_tick or now>=self.next_tick
        if self.animate_until and now>self.animate_until and self.shown and self.settled and not timer_due then return end
        local s=snapshot
        if not s or not s.dock_parent then self.hide();return end
        if #model.order==0 then self.hide();return end
        if address and (identity~=s.identity or parent~=s.dock_parent or not owned()) then
            if b.read(address+0xf0,8)~=string.rep('\0',8) then
                assert(#retired<8,'Too many cooldown dock HUD generations; restart game')
                retired[#retired+1]=storage
            end
            address,storage=nil,nil;drawn={};self.shown=false
        end
        local overview=radial.cooldown_display==2
        local items,divider=model.layout(now,s.dock_y,overview,radial.short_status_placement,radial.brief_timer_limit,s.dock_below_y,radial.balance_separated_dock)
        local label_key=tostring(s.identity)..':'..tostring(radial.cooldown_timer)..':'..tostring(overview)
        if timer_text_key~=label_key then timer_text_key=label_key;self.timer_error=nil end
        local function draw_labels()
        if not self.timer_error then
            local ok,why=pcall(timer_text.draw,s,items,now,overview and 5 or radial.cooldown_timer,radial.short_timer_style,radial.brief_timer_limit,divider)
            if not ok then timer_text.hide();self.timer_error=tostring(why)end
        end
        end
        local changed=not self.shown or timer_due
        for i=1,16 do
            local item,old=items[i],drawn[i]
            if item then
                local signature=item.key..':'..item.phase..':'..tostring(overview)..':'..tostring(item.below_stamina)
                if not old or old.signature~=signature or old.x~=item.x or old.y~=item.y or old.alpha~=item.alpha then changed=true end
            elseif old then changed=true end
        end
        self.settled=true
        for _,item in ipairs(items) do
            if item.x~=item.target_x or item.y~=item.target_y or item.alpha<1 then self.settled=false end
        end
        if not changed then draw_labels();return end
        scope.context_scope(s.dock_parent,function(resource)
            if not address then
                storage=ffi.new('uint8_t[?]',0x15150)
                address=math.floor((tonumber(ffi.cast('uintptr_t',storage))+31)/16)*16
                identity,parent=s.identity,s.dock_parent
                init(address,1);b.set(address,'size',{0,0});b.set(address,'anchor',{0.5,0})
                b.set(address,'pivot',{0.5,0});b.set(address,'position',{0,0})
                assert(b.pointer(address+0xf8)==resource,'Dock resource context mismatch')
                for i=1,16 do
                    local icon=address+0x110+(i-1)*0x1500
                    create(icon,0ULL,0ULL,0ULL,0x22b,0)
                    local size=assert(b.get(icon,'size'),'Native tile size unavailable')
                    assert(size[1]>0 and size[2]>0,'Invalid native tile dimensions')
                    local pixels=overview and 32 or 48
                    b.set(icon,'scale',{pixels/size[1],pixels/size[2]});b.set(icon,'pivot',{0.5,0.5})
                    b.set(icon,'anchor',{0,0});order(icon,0x22b)
                    attach(address,icon);finish(address)
                end
                attach(parent,address);finish(parent)
            end
            assert(owned(),'Cooldown dock ownership mismatch')
            for i=1,16 do
                local icon=address+0x110+(i-1)*0x1500
                assert(b.pointer(icon+0xf0)==address,'Cooldown dock child ownership changed')
                local item=items[i];local old=drawn[i]
                if item then
                    local signature=item.key..':'..item.phase..':'..tostring(overview)..':'..tostring(item.below_stamina)
                    local denominator=old and old.denominator
                    local large=radial.short_timer_style==2 and(item.phase=='incoming'or (item.row.timer_seconds or math.huge)<=(radial.brief_timer_limit or 10))
                    local charge_side=(overview or item.below_stamina)and 'left'or(not large and radial.cooldown_timer==3 and 'above'or 'below')
                    local charge_key=signature..':'..charge_side
                    if (not old and item.below_stamina)or(old and old.signature~=signature)then
                        local size=assert(b.get(icon,'size'));local pixels=(overview or item.below_stamina)and 32 or 48
                        b.set(icon,'scale',{pixels/size[1],pixels/size[2]})
                    end
                    if timer_due or not old or old.signature~=signature then
                        local row=item.row
                        assert(row and row.dock_payload and row.entry,'Native dock record unavailable')
                        ffi.cast('uint32_t *',icon+0x14b8)[0]=row.entry
                        tick(icon,0.25,item.phase=='incoming' and 3 or item.phase=='unavailable' and 5 or 4,row.dock_payload)
                        -- Native initialization can reset the span. Restore the game's
                        -- original denominator afterwards, then refresh without elapsed time.
                        if item.phase~='unavailable' then
                        denominator=assert(b.read(row.dock_source+0x14c4,4),'Native tile timer span unavailable')
                        if not old or old.signature~=signature or old.denominator~=denominator then
                            ffi.copy(ffi.cast('void *',icon+0x14c4),denominator,4)
                            tick(icon,0,item.phase=='incoming' and 3 or item.phase=='unavailable' and 5 or 4,row.dock_payload)
                        end
                        local span=tonumber(ffi.cast('float *',icon+0x14c4)[0])
                        span=span==span and span>0 and span<=86400 and span or 0
                        item.cooldown_span=math.max(span,item.row.timer_seconds,item.cooldown_span or 0)
                        end
                    end
                    if timer_due or not old or old.charge_key~=charge_key then
                        -- Native tile constructor owns the count group at +920,
                        -- its two backing sprites and the count text at +CE0.
                        local badge=icon+0x920
                        assert(b.pointer(badge+0xf0)==icon,'Dock charge group ownership changed')
                        local count=tonumber(ffi.cast('uint32_t *',icon+0x14bc)[0])
                        if not old or old.charge_key~=charge_key or old.charge_count~=count then
                            b.set(badge,'anchor',{0.5,0.5});b.set(badge,'pivot',{0.5,0.5})
                            b.set(badge,'position',charge_side=='left'and{-36,0}or{0,charge_side=='above'and 37 or -37})
                        end
                        -- Native tick recolors/reveals these children. Suppress
                        -- AFTER it runs, at its existing bounded 4 Hz cadence.
                        opacity(icon+0xa30,0);opacity(icon+0xb88,0);opacity(icon+0xce0,0)
                        -- Native count cache, witnessed by 183AEF1's count-label
                        -- formatter. Read only our constructed/owned tile.
                        item.charge_count=item.phase=='cooldown' and count>0 and count<=99 and count or nil
                        item.charge_side=charge_side
                        if old then old.charge_count=count end
                    end
                    local position=timer_due and b.get(icon,'position') or nil
                    if not old or old.x~=item.x or old.y~=item.y or (position and (position[1]~=item.x or position[2]~=item.y)) then
                        b.set(icon,'position',{item.x,item.y})
                    end
                    if not old or old.alpha~=item.alpha then opacity(icon,item.alpha) end
                    if not old then visible(icon,1) end
                    local retained=old or {}
                    retained.signature,retained.x,retained.y=signature,item.x,item.y
                    retained.alpha,retained.denominator=item.alpha,denominator
                    retained.charge_key=charge_key
                    retained.charge_count=tonumber(ffi.cast('uint32_t *',icon+0x14bc)[0])
                    drawn[i]=retained
                elseif old then visible(icon,0);drawn[i]=nil
                elseif not drawn.initialized then visible(icon,0) end
            end
            self.next_tick=now+250
            drawn.initialized=true
            if not self.shown then visible(address,1);self.shown=true end
        end)
        draw_labels()
    end
    function self.close()
        self.hide()
        local ok,why=b.release_owned_ui(storage,address,identity,parent,retired)
        if not ok then return false,why end
        storage,address,identity,parent=nil,nil,nil,nil
        for i=#retired,1,-1 do retired[i]=nil end
        return true
    end
    return self
end

return {cooldown_dock_timed=cooldown_dock_timed,cooldown_dock_model=cooldown_dock_model,cooldown_dock_text=cooldown_dock_text,cooldown_closed_notices=cooldown_closed_notices,cooldown_dock=cooldown_dock}
]=],
["src/binding_warning.lua"]=[=[-- Read only the recognized MBM v3 registry/header, as the MCM binding page does.
local function dbf_binding_reader(host)
    local function up(fn,wanted)
        if type(fn)~='function' or not debug or not debug.getupvalue then return end
        for i=1,64 do local name,value=debug.getupvalue(fn,i);if not name then return end;if name==wanted then return value end end
    end
    if type(host)~='table' or host.api~=1 or type(host.version)~='number' or host.version<3 then return end
    local public=type(host.binding_info)=='function' and type(host.binding)=='function'
    local state=up(host.register_binding,'state')
    local header=up(host.is_down,'live_header')
    local read,words=up(header,'read_words'),up(header,'words')
    if type(state)~='table' or type(state.registry)~='table' or up(host.is_down,'state')~=state
        or up(header,'state')~=state or type(read)~='function' or (type(words)~='cdata' and type(words)~='table') then
        if public then return function(id)
            local info=host.binding_info(id)
            if info and info.backend=='extended' then local values=host.binding(id);if type(values)=='table' then return #values>0 end end
        end end
        return
    end
    return function(id)
        if public then local info=host.binding_info(id)
            if info and info.backend=='extended' then local values=host.binding(id);if type(values)=='table' then return #values>0 end;return end
        end
        if not state.build_rows then return end
        local record=state.registry[id];if type(record)~='table' then return end
        local bucket,count=header(record);count=tonumber(count)
        if not bucket or not count or count<0 or count>16 or count%1~=0 then return end
        if not read(bucket,8) or tonumber(words[0])~=record.code or tonumber(words[1])~=count then return end
        return count>0
    end
end
local function dbf_binding_warning_view()
    local gui,world,sr,text_id,background,signature
    local self={}
    local function live()
        if not sr or not world then return false end
        for _,w in pairs(sr.Application.worlds() or {}) do if w==world then return true end end
        return false
    end
    function self.hide()
        if gui and live() then pcall(sr.World.destroy_gui,world,gui) end
        gui,world,text_id,background,signature=nil,nil,nil,nil,nil
    end
    function self.show(text)
        if not text then self.hide();return end
        local current=rawget(_G,'stingray')
        if type(current)~='table' or not current.Gui or not current.World or not current.Application then return end
        if sr~=current or (gui and not live()) then self.hide();sr=current end
        sr=current
        local G,A=sr.Gui,sr.Application
        local w,h=G.resolution();if not w or not h or w<=0 or h<=0 then return end
        local next_signature=text..':'..w..':'..h
        if gui and signature==next_signature then return end
        if not gui then
            local main=A.main_world();world=main
            for _,candidate in pairs(A.worlds() or {}) do if candidate~=main then world=candidate;break end end
            if not world then return end
            gui=sr.World.create_screen_gui(world,'scale',1,1)
            if not gui then return end
        end
        if text_id then G.destroy_text(gui,text_id) end
        if background then G.destroy_rect(gui,background) end
        local font='core/performance_hud/debug'
        local size=math.max(14,math.min(20,w/75))
        local width=math.min(w-32,#text*size*0.62+28)
        local x=(w-width)/2
        background=G.rect(gui,sr.Vector3(x,16,950),sr.Vector2(width,size+20),sr.Color(210,15,15,15))
        text_id=G.text(gui,text,font,size,font,sr.Vector3(x+14,26,951),sr.Color(255,255,220,80))
        signature=next_signature
    end
    return self
end
local function dbf_binding_warning(view,reader_factory)
    view=view or dbf_binding_warning_view();reader_factory=reader_factory or dbf_binding_reader
    local owner,reader,next_check,requirements
    local self={}
    function self.hide() view.hide();next_check=nil end
    function self.step(enabled,host,ids,required,now)
        if not enabled then self.hide();return end
        local key=table.concat(required,',')
        if host~=owner or key~=requirements then
            owner,requirements=host,key;reader=reader_factory(host);next_check=nil
        end
        -- MBM exposes no mapping-change subscription. Check at most twice a second,
        -- reading only the three registered DBF action headers; unknown is not unbound.
        if next_check and now<next_check then return end
        next_check=now+500
        local missing={}
        for _,name in ipairs(required) do
            local ok,bound=pcall(function() return reader and reader(ids[name]) end)
            if ok and bound==false then missing[#missing+1]=({next='Next',previous='Previous',confirm='Confirm'})[name] end
        end
        local message=#missing>0 and ('DBF: Bind '..table.concat(missing,' / ')..' in MODS controls.') or nil
        local ok,why=pcall(view.show,message)
        self.status=ok and message or ('Binding warning unavailable: '..tostring(why))
    end
    return self
end

return {dbf_binding_reader=dbf_binding_reader,dbf_binding_warning_view=dbf_binding_warning_view,dbf_binding_warning=dbf_binding_warning}
]=],
["src/binding_defaults.lua"]=[=[-- Keep controls on MBM's native MODS page, including v4 providers.
-- Author defaults are extended-only; do not trade away native UI/input for them.
local function dbf_binding_options(menu,key)
    local options={category="Diver's Best Friend"}
    if menu.version>=4 then options.backend='native' end
    return options
end

return {dbf_binding_options=dbf_binding_options}
]=],
["src/selection.lua"]=[=[-- Pointing and discrete navigation share the proven explicit-confirm path.
local function selection_controller(input,report)
    local self={selected=nil,status='Open the native stratagem menu',job=nil,interval_ms=70}
    local previous,opened={},false
    local owner,next_at,last_vector,point_mode,selected_kind
    function self.step(snapshot,buttons,now,vector)
        local edges={}
        for _,key in ipairs({'next','previous','confirm'}) do
            edges[key]=buttons and buttons[key]==true and previous[key]==false
            if buttons then previous[key]=buttons[key] else previous[key]=nil end
        end
        local active=snapshot and snapshot.open and buttons~=nil
        if not active or (owner and snapshot.identity~=owner) then
            if self.job then report('Cancelled: menu closed, input unavailable, or HUD changed') end
            self.job=nil; self.selected=nil; opened=false
            owner=nil;last_vector=nil;point_mode=false;selected_kind=nil; return
        end
        owner=snapshot.identity
        local eligible={}
        for _,row in ipairs(snapshot.rows) do
            if selectable_kind(row.kind) and not row.blacklisted and(not snapshot.list_order or not row.timer_kind and not row.unavailable)then eligible[#eligible+1]=row end
        end
        if snapshot.list_order then
            -- Native payload/storage indices are not display indices. Use the
            -- native settled row positions (Y increases upward), so opening
            -- animations and the selected row's scale cannot change the order.
            table.sort(eligible,function(a,b)
                local ay,by=a.list_y or 0,b.list_y or 0
                if ay~=by then return ay>by end
                if a.entry~=b.entry then return (a.entry or 0)<(b.entry or 0) end
                return a.address<b.address
            end)
        end
        if not opened then
            self.selected=not snapshot.pointer_only and eligible[1] and eligible[1].address or nil
            opened=true
            -- Opening a menu with a held confirmation binding must not trigger it.
            edges.confirm=false
        end
        local chosen
        for i,row in ipairs(eligible) do
            if row.address==self.selected and (not selected_kind or row.kind==selected_kind) then chosen=i end
        end
        if not chosen and self.selected then
            self.job=nil; chosen=1; self.selected=eligible[1] and eligible[1].address
            edges.confirm=false
        end
        if self.job then
            if now>self.job.deadline then self.job=nil; report('Cancelled: input sequence timed out'); return end
            local row=eligible[chosen]
            if not row or row.kind~=self.job.kind then self.job=nil; report('Cancelled: card membership changed'); return end
            if now>=next_at then
                local ok,done,message=pcall(input.advance,self.job)
                if not ok then self.job=nil; report('Stopped: '..tostring(done)); return end
                report(message)
                if done then self.job=nil else next_at=now+self.job.interval_ms end
            end
            return
        end
        if #eligible==0 then self.status='No selectable stratagem cards are present'; return end
        if vector then
            local changed=not last_vector or math.abs(vector[1]-last_vector[1])+math.abs(vector[2]-last_vector[2])>0.001
            if changed or point_mode then
                local current
                for i,row in ipairs(snapshot.rows) do if row.address==self.selected then current=i end end
                local index=(snapshot.pointing_index or pointing_index)(snapshot.rows,vector,current)
                if index then
                    local address=snapshot.rows[index].address
                    for i,row in ipairs(eligible) do
                        if row.address==address then chosen=i;self.selected=address;point_mode=true end
                    end
                elseif point_mode then chosen=nil;self.selected=nil end
            end
            last_vector={vector[1],vector[2]}
        end
        if edges.next~=edges.previous then
            local delta=edges.next and 1 or -1
            chosen=chosen and (chosen-1+delta)%#eligible+1 or (delta==1 and 1 or #eligible)
            self.selected=eligible[chosen].address
            point_mode=false
        end
        if not chosen then self.status='Point at a card, then press Confirm';return end
        local row=eligible[chosen]
        selected_kind=row.kind
        self.status='Highlighted kind '..row.kind..'; press Confirm while keeping the menu open'
        if row.unavailable then self.status='Unavailable';return end
        if edges.confirm then
            local ok,result=pcall(input.begin,row.kind)
            if ok then
                local interval=usage_interval(self)
                self.job=result;self.job.interval_ms=interval
                self.job.deadline=now+math.max(3000,(self.job.code and #self.job.code or 12)*interval+1500)
                next_at=now;report('Started native input for kind '..row.kind..'; interval='..interval..'ms')
            else report('Not started: '..tostring(result)) end
        end
    end
    return self
end

return {selection_controller=selection_controller}
]=],
["src/release.lua"]=[=[-- Only a sampled Hold falling edge can confirm. A disappearing HUD alone
-- never confirms, and explicit Confirm suppresses release for this opening.
local function release_controller(input,report)
    local armed,blocked
    local self={status='Disabled',job=nil,interval_ms=70}
    function self.reset()
        if self.job then
            local ok,why=pcall(input.end_release,self.job,true)
            if not ok then report('Release cleanup failed: '..tostring(why)) end
        end
        self.job=nil;armed=nil;blocked=nil
    end
    function self.shortcut(slot,snapshot,now)
        if self.job or not snapshot then return false end
        local ok,job=pcall(input.begin_shortcut,slot)
        if not ok then report('Shortcut not started: '..tostring(job));return false end
        local interval=usage_interval(self)
        job.shortcut=true;job.interval_ms=interval;job.next_at=now;job.snapshot_identity=snapshot.identity
        job.deadline=now+math.max(3000,#job.code*interval+1500)
        self.job=job;armed=nil;blocked=true
        report('Equipped slot '..slot..'; interval='..interval..'ms')
        return true
    end
    function self.step(enabled,snapshot,selected,now,explicit)
        if not enabled or not snapshot then self.status='Disabled or no valid radial snapshot';self.reset();return end
        if self.job then
            local job=self.job
            if snapshot.identity~=job.snapshot_identity or now>job.deadline or explicit then
                self.status='Release cancelled: HUD changed, timeout or explicit input';report(self.status);self.reset();return
            end
            if job.finished then
                local checked,done,message=pcall(input.release_complete,job)
                if not checked then
                    self.status='Release completion cancelled: '..tostring(done);report(self.status);self.reset();return
                end
                if not done then
                    if self.status~=message then self.status=message;report(message) end
                    return
                end
                local ok,why=pcall(input.end_release,job,false)
                self.job=nil;blocked=true
                self.status=ok and (message..'; original menu trigger restored') or 'Release cleanup failed: '..tostring(why)
                report(self.status);return
            end
            local ok,why=pcall(function()
                input.hold_release(job)
                if now>=job.next_at then
                    local done,message=input.advance_release(job)
                    self.status=message;report('Release: '..message)
                    job.finished=done;job.next_at=now+job.interval_ms
                    if done then job.deadline=now+2000 end
                end
            end)
            if not ok then self.status='Release cancelled: '..tostring(why);report(self.status);self.reset() end
            return
        end
        local ok,state=pcall(input.release_state)
        if not ok then self.status=tostring(state);self.reset();return end
        if not state.unobstructed or not state.hold then
            self.status=not state.hold and 'Requires a Hold menu binding' or 'Blocked by native UI overlay'
            self.reset();return
        end
        self.status='Waiting for a highlighted Hold release'
        if not state.clean then blocked=true;armed=nil end
        if explicit then blocked=true;armed=nil end
        local previous=armed
        if previous and snapshot.rows then
            for _,row in ipairs(snapshot.rows) do
                if row.address==previous.address and row.unavailable then previous=nil;break end
            end
        end
        armed=nil
        if not state.down then
            local skip=blocked;blocked=nil
            if not skip and previous and now>=previous.time and now-previous.time<=250
                and snapshot.identity==previous.snapshot_identity
                and state.identity==previous.identity and state.component==previous.component
                and state.hud==previous.hud then
                local called,job=pcall(input.begin_release,previous.kind,previous)
                if called then
                    local interval=usage_interval(self)
                    job.interval_ms=interval;job.next_at=now;job.snapshot_identity=snapshot.identity;job.address=previous.address
                    job.deadline=now+math.max(3000,#job.code*interval+1500)
                    self.job=job
                    local held,why=pcall(input.hold_release,job)
                    if held then self.status='Latched native menu for kind '..previous.kind..'; interval='..interval..'ms'
                    else self.status='Release cancelled: '..tostring(why);self.reset() end
                else self.status='Release cancelled: '..tostring(job) end
                report(self.status)
            end
            return
        end
        if blocked or not snapshot.open or not state.menu_active then return end
        for _,row in ipairs(snapshot.rows) do
            if row.address==selected and selectable_kind(row.kind) and not row.unavailable then
                armed={kind=row.kind,address=row.address,time=now,snapshot_identity=snapshot.identity,
                    identity=state.identity,component=state.component,hud=state.hud}
                self.status='Armed kind '..row.kind
                return
            end
        end
    end
    return self
end

return {release_controller=release_controller}
]=],
["src/blacklist.lua"]=[=[-- IDs are native stratagem kinds, never menu slots, names or direction codes.
local function stratagem_blacklist(values)
    local excluded={}
    if values.hide_sos==true then excluded[145]=true end
    for i=1,8 do
        local kind=values['blacklist_kind_'..i]
        if type(kind)=='number' and kind%1==0 and kind>=1 and kind<150 then excluded[kind]=true end
    end
    return excluded
end
local function blacklist_signature(excluded)
    local ids={}
    for kind=1,149 do if excluded[kind] then ids[#ids+1]=kind end end
    return table.concat(ids,',')
end
local function blacklist_snapshot(snapshot,excluded,keep_visible,hide_cooldown)
    if not snapshot or not snapshot.open then return snapshot end
    local filtered={}
    for key,value in pairs(snapshot) do filtered[key]=value end
    filtered.rows,filtered.excluded_rows={},{}
    filtered.native_rows=snapshot.rows
    for _,row in ipairs(snapshot.rows) do
        if keep_visible and excluded[row.kind]then
            local copy={};for key,value in pairs(row)do copy[key]=value end
            copy.blacklisted=true;row=copy
        end
        local hidden=(excluded[row.kind]and not keep_visible)or(hide_cooldown and row.timer_kind=='cooldown')
        local target=hidden and filtered.excluded_rows or filtered.rows
        target[#target+1]=row
    end
    return filtered
end
-- Compact the displayed stock list without changing native entry/kind identity.
-- Restore only values still owned by DBF, including both native animation endpoints.
local function blacklist_list_visibility(b)
    local saved={}
    local function same(a,c) return a and c and a[1]==c[1] and a[2]==c[2] end
    local function restore(item)
        if b.valid(item.identity) and same(b.get(item.address,item.property),item.applied) then
            b.set(item.address,item.property,item.before)
        end
    end
    local function key(address,property) return address..':'..property end
    local function baseline(address,property,identity)
        local current=assert(b.get(address,property),'Blacklist row geometry unavailable')
        local item=saved[key(address,property)]
        if item and item.identity==identity and same(current,item.applied) then return item.before end
        return current
    end
    local self={}
    function self.restore()
        for _,item in pairs(saved) do restore(item) end
        saved={}
    end
    function self.step(snapshot)
        local plan={}
        local function add(address,property,value)
            plan[key(address,property)]={address=address,property=property,value=value}
        end
        if snapshot and snapshot.open and #(snapshot.excluded_rows or {})>0 then
            assert(b.valid(snapshot.identity),'Blacklist HUD changed')
            -- Include hidden cards when finding the original top-to-bottom slots.
            -- Use saved native endpoints if the previous frame still has our values.
            local ordered={}
            for _,group in ipairs({snapshot.rows,snapshot.excluded_rows}) do
                for _,row in ipairs(group) do
                    ordered[#ordered+1]={row=row,target=baseline(row.address,'animation_b',snapshot.identity),
                        position=baseline(row.address,'position',snapshot.identity),animation_a=baseline(row.address,'animation_a',snapshot.identity)}
                end
            end
            table.sort(ordered,function(a,c)
                if a.target[2]~=c.target[2] then return a.target[2]>c.target[2] end
                if a.row.entry~=c.row.entry then return (a.row.entry or 0)<(c.row.entry or 0) end
                return a.row.address<c.row.address
            end)
            local excluded={}
            for _,row in ipairs(snapshot.excluded_rows) do
                excluded[row.address]=true;add(row.address,'scale',{0,0})
            end
            -- Native rows can be inserted/reordered during a transition. Their
            -- old endpoints may temporarily coincide; never reuse those as a
            -- set of compacted slots. Construct unique slots from row height.
            local y=ordered[1]and ordered[1].target[2]or 0
            for _,item in ipairs(ordered) do
                if not excluded[item.row.address] then
                    add(item.row.address,'position',{item.position[1],y})
                    add(item.row.address,'animation_a',{item.animation_a[1],y})
                    add(item.row.address,'animation_b',{item.target[1],y})
                    local scale=b.get(item.row.address,'scale')or{1,1}
                    y=y-(item.row.height or 68)*math.max(1,scale[2])
                end
            end
        end
        for id,item in pairs(saved) do
            if not plan[id] or item.identity~=snapshot.identity then restore(item);saved[id]=nil end
        end
        for id,change in pairs(plan) do
            assert(b.valid(snapshot.identity),'Blacklist HUD changed')
            local current=assert(b.get(change.address,change.property),'Blacklist row geometry unavailable')
            local item=saved[id]
            if not item then
                item={identity=snapshot.identity,address=change.address,property=change.property,before=current};saved[id]=item
            elseif not same(current,item.applied) then item.before=current end
            if not same(current,change.value)then b.set(change.address,change.property,change.value)end
            item.applied=assert(b.get(change.address,change.property),'Blacklist row geometry unavailable')
        end
    end
    return self
end

return {stratagem_blacklist=stratagem_blacklist,blacklist_signature=blacklist_signature,blacklist_snapshot=blacklist_snapshot,blacklist_list_visibility=blacklist_list_visibility}
]=],
["src/settings.lua"]=[=[local function dbf_menu_subscribe(menu,id,fn)
    local broker=rawget(_G,'DBFMenuSubscriptions')
    if not broker then broker=setmetatable({}, {__mode='k'});rawset(_G,'DBFMenuSubscriptions',broker) end
    local rows=broker[menu]
    if not rows then rows={};broker[menu]=rows end
    local record=rows[id]
    if not record then
        record={}
        local callback=function(...) if record.fn then return record.fn(...) end end
        setfenv(callback,_G)
        if menu.on_change(id,callback)~=true then return false end
        rows[id]=record
    end
    record.fn=fn;record.owner=rawget(_G,'DiversBestFriend')
    return true
end
-- Original BSL Mod Options Menu strips unknown registration fields. Bind the
-- same DBF rules explicitly to MCM's authoritative imported handle as well.
local function dbf_mcm_conditions(menu,state)
    local mcm=rawget(_G,'DBFMCM')
    if not mcm or not mcm.mods or not state.condition_specs then return end
    if state.condition_mcm==mcm and state.condition_revision==mcm.revision then return end
    state.condition_mcm=mcm;state.condition_revision=mcm.revision
    local owner
    for _,mod in pairs(mcm.mods)do
        if mod.legacy and type(mod.name)=='string' and mod.name:upper()=="DIVER'S BEST FRIEND" then
            if owner then return end;owner=mod
        end
    end
    if not owner or not owner.handle or type(owner.handle.set_condition)~='function' then return end
    if state.condition_owner==owner then return end
    local keys={}
    for _,spec in ipairs(state.condition_specs)do
        for key,c in pairs(owner.controls)do
            if c.label==spec[3] or c.label==spec[2]..' / '..spec[3] then
                keys['native_stratagem_radial.'..spec[1]]=key
            end
        end
    end
    for id,rule in pairs(state.condition_rules)do
        local key=keys['native_stratagem_radial.'..id]
        if key then
            owner.handle.set_condition(key,{enabled_if=function(get)
                return rule(function(native_id)
                    local mapped=keys[native_id]
                    if mapped then return get(mapped)end
                    return menu.get(native_id)
                end)
            end})
        end
    end
    state.condition_owner=owner;state.condition_revision=mcm.revision
end
local function canary_settings(menu,api,radial,now)
    dbf_mcm_conditions(menu,api)
    if api.settings_menu==menu and api.cached and not api.dirty then
        if api.subscribed and not api.retry_registration then return api.cached end
        -- Old providers without notifications retain a bounded compatibility check.
        if now and now<(api.next_refresh or 0) then return api.cached end
    end
    if api.settings_menu~=menu then
        api.settings_menu=menu;api.subscriptions={};api.registered={};api.cached=nil
    end
    api.dirty=false;api.retry_registration=false
    api.next_refresh=(now or 0)+250
    local prefix='native_stratagem_radial.'
    local specs={
        {'enabled','Selection','Enable Mod','toggle',true},
        {'selection_mode_ordered','Appearance','Mode','choice',1,{'Wedge Wheel','List Select','Native wheel'}},
        {'selection_sounds','Selection','Sound feedback','toggle',true},
        {'experimental_layout','Appearance','Wedge Wheel layout','choice',2,{'Cards - copied list rows','Expanded wedges'},nil,nil,'Available while Wedge Wheel is selected.'},
        {'appearance_preset','Appearance','Preset','choice',1,{'Custom','Compact','Standard','Large'},nil,nil,'Custom uses the size sliders below. Other presets override sizes; opacity and colors stay independent.'},
        {'wheel_size','Appearance','Wheel size (%)','slider',100,70,130,5,'All radial layouts. Custom preset only.'},
        {'icon_size','Appearance','Icon size (%)','slider',100,70,130,5,'Native and expanded wheels. Relative to wheel size; Custom preset only.'},
        {'label_size','Appearance','Center label size (%)','slider',100,70,130,5,'Native and expanded wheels. Relative to wheel size; Custom preset only.'},
        {'native_opacity','Appearance','Native wheel opacity (%)','slider',100,0,100,5,'Native wheel only; background opacity. Selected highlight stays visible.'},
        {'wedge_darkness','Appearance','Expanded wedge darkness (%)','slider',70,0,100,5,'Expanded wedges only.'},
        {'wedge_opacity','Appearance','Wedge opacity (%)','slider',50,0,100,5,'Expanded wedges only; selected highlight stays visible.'},
        {'cooldown_timers','Appearance','Show cooldown timers','toggle',true,nil,nil,nil,'Show native remaining time on dock icons, using the game font.'},
        {'cooldown_timer','Appearance','Cooldown timer position','choice',2,{'Off','Above icon','Below icon','Inside icon'},nil,nil,'Position of regular cooldown timers. Short countdown style controls inbound, impact and brief cooldowns separately.'},
        {'short_timer_style','Appearance','Short countdown style','choice',2,{'Use cooldown position','Large inside icon'},nil,nil,'Separate style for inbound, impact and brief cooldown countdowns.'},
        {'dim_unselected','Appearance','Dim unselected stratagems','toggle',true,nil,nil,nil,'Dim unselected available entries in List Select. Native cooldown styling stays unchanged.'},
        {'hide_blacklisted_list','Appearance','Hide blacklisted stratagems','toggle',false,nil,nil,nil,'Hide blacklisted entries in List Select. Off keeps them visible but unselectable. Wheels always omit them.'},
        {'hide_cooldown_list','Appearance','Hide stratagems on cooldown','toggle',false,nil,nil,nil,'Hide cooldown entries in List Select. Inbound entries remain visible. Does not affect the cooldown dock or overview.'},
        {'brief_timer_limit','Appearance','Brief cooldown threshold','slider',10,1,30,1,'Cooldowns at or below this many seconds use the short countdown style.'},
        {'hide_closed_status','Appearance','Hide top-left status notices','toggle',true,nil,nil,nil,'Hide native inbound, impact and cooldown notices while the stratagem menu is closed. The open list stays complete.'},
        {'dock_gap','Appearance','Dock gap above stamina','slider',24,0,80,2,'Gap above the native stamina bar, in HUD units.'},
        {'cooldown_icons','Appearance','Show cooldown display','toggle',true,nil,nil,nil,'Show the chosen dock or overview. Off hides the display and stops its timer checks.'},
        {'cooldown_display','Appearance','Cooldown display style','choice',1,{'Icon dock','Compact overview'},nil,nil,'Use a compact vertical list of icons, status and native remaining times instead of the horizontal dock.'},
        {'short_status_placement','Appearance','Short status placement','choice',3,{'Together','Left of dock','Right of dock','Below stamina bar'},nil,nil,'Dock only. Separate inbound, impact, brief and per-charge cooldowns from longer cooldowns. Left/right adds a divider; below uses the stamina bar as the divider.'},
        {'track_unavailable','Appearance','Track unavailable / ineligible','toggle',false,nil,nil,nil,'Include native unavailable or ineligible stratagems in the cooldown display. No countdown is invented when the game supplies none.'},
        {'balance_separated_dock','Appearance','Center Cooldown Separator','toggle',true,nil,nil,nil,'Center the entire left/right separated bar. Off keeps the main cooldown group centered instead.'},
        {'release_selection_mode','Controller','Select on Release','choice',1,{'Automatic (controller)','On','Off'},nil,nil,'Automatic enables release selection for active controller input. On also enables mouse. Requires a Hold menu binding; center before releasing to cancel.'},
        {'input_interval_ms','Advanced','Input interval (ms)','slider',70,0,250,5,'Delay between directions. 0 sends one per frame; applies to the next code.'},
        {'randomize_input_delay','Advanced','Randomize input delay','toggle',false,nil,nil,nil,'Choose one delay between 70 and 240 ms for each stratagem use. Overrides the fixed delay.'},
        {'vertical_offset','Appearance','Radial vertical offset (down)','slider',0,-600,600,25,'Radial layouts: positive moves down. Leave at 0 for automatic centering.'},
    }
    -- DBF owns its dependencies; MCM evaluates them against draft values.
    -- Older options providers ignore this optional presentation metadata.
    local function value(get,key)return get('native_stratagem_radial.'..key)end
    local function wheel(get)return value(get,'selection_mode_ordered')~=2 end
    local function expanded(get)return value(get,'selection_mode_ordered')==1 and value(get,'experimental_layout')==2 end
    local function display(get)return value(get,'cooldown_icons')==true end
    local function dock(get)return display(get) and value(get,'cooldown_display')==1 end
    local function timers(get)return display(get) and value(get,'cooldown_timers')==true end
    local conditions={
        experimental_layout=function(get)return value(get,'selection_mode_ordered')==1 end,
        wedge_darkness=expanded,wedge_opacity=expanded,
        native_opacity=function(get)return value(get,'selection_mode_ordered')==3 end,
        wheel_size=function(get)return wheel(get) and value(get,'appearance_preset')==1 end,
        icon_size=function(get)return (expanded(get) or value(get,'selection_mode_ordered')==3) and value(get,'appearance_preset')==1 end,
        label_size=function(get)return (expanded(get) or value(get,'selection_mode_ordered')==3) and value(get,'appearance_preset')==1 end,
        vertical_offset=wheel,
        dim_unselected=function(get)return value(get,'selection_mode_ordered')==2 end,
        hide_blacklisted_list=function(get)return value(get,'selection_mode_ordered')==2 end,
        hide_cooldown_list=function(get)return value(get,'selection_mode_ordered')==2 end,
        input_interval_ms=function(get)return value(get,'randomize_input_delay')~=true end,
        cooldown_display=display,dock_gap=display,track_unavailable=display,cooldown_timers=display,
        short_status_placement=dock,
        balance_separated_dock=function(get)local position=value(get,'short_status_placement');return dock(get) and (position==2 or position==3) end,
        cooldown_timer=timers,short_timer_style=timers,brief_timer_limit=display,
    }
    api.condition_specs=specs;api.condition_rules=conditions
    local hidden={}
    -- Read the old toggle before registration; a saved On remains explicit On.
    if api.values==nil and menu.get(prefix..'release_selection_mode')==nil then
        api.values={release_selection_mode=menu.get(prefix..'select_on_release')==true and 2 or 1}
    end
    local values={}
    api.values=api.values or {}
    local previous
    local subscribed=type(menu.on_change)=='function'
    local previous_interval=api.values.input_interval_ms
    for _,s in ipairs(specs) do
        local spec={mod="Diver's Best Friend",mod_id="hwg90.divers_best_friend",label=s[2]..' / '..s[3],type=s[4],default=s[5],gap=previous~=s[2],description=s[9] or s[3]}
        spec.enabled_if=conditions[s[1]]
        if s[1]=='selection_mode_ordered' then
            local legacy=menu.get(prefix..'selection_mode')
            if legacy==1 or legacy==2 or legacy==3 then spec.default=4-legacy
            elseif legacy==4 then spec.default=1 end
        end
        if s[1]=='release_selection_mode' and api.values.release_selection_mode then spec.default=api.values.release_selection_mode end
        if s[4]=='choice' then spec.choices=s[6] end
        if s[4]=='slider' then spec.min=s[6];spec.max=s[7];spec.step=s[8] end
        if not hidden[s[1]] and not api.registered[s[1]] then api.registered[s[1]]=menu.register_option(prefix..s[1],spec)==true end
        if not hidden[s[1]] and not api.registered[s[1]] then api.retry_registration=true end
        local key=s[1]
        if subscribed and not hidden[key] and not api.subscriptions[key] then
            api.subscriptions[key]=dbf_menu_subscribe(menu,prefix..key,function()
                if api.settings_menu==menu then api.dirty=true end
            end)==true
        end
        if not hidden[key] then subscribed=subscribed and api.subscriptions[key]==true end
        local v=menu.get(prefix..s[1]);local valid=false
        if s[4]=='toggle' then valid=type(v)=='boolean'
        elseif type(v)=='number' and v==v then
            if s[4]=='choice' then valid=v%1==0 and v>=1 and v<=#s[6]
            else valid=v>=s[6] and v<=s[7]
                if s[1]:find('blacklist_kind_',1,true) then valid=valid and v%1==0 end
            end
        end
        if valid then api.values[s[1]]=v end
        if api.values[s[1]]==nil then api.values[s[1]]=spec.default end
        values[s[1]]=api.values[s[1]]
        if not hidden[s[1]] then previous=s[2] end
    end
    if previous_interval~=nil and previous_interval~=values.input_interval_ms and values.randomize_input_delay then
        if type(menu.set)=='function'then menu.set(prefix..'randomize_input_delay',false)end
        values.randomize_input_delay=false;api.values.randomize_input_delay=false
    end
    local presets={{values.wheel_size,values.icon_size,values.label_size},{85,100,95},{100,100,100},{115,110,110}}
    local sizes=presets[values.appearance_preset]
    radial.wheel_scale,radial.icon_scale,radial.label_scale=sizes[1]/100,sizes[2]/100,sizes[3]/100
    radial.native_opacity=values.native_opacity/100
    radial.full_color=true
    radial.wedge_darkness,radial.wedge_opacity=values.wedge_darkness,values.wedge_opacity
    radial.vertical_offset=values.vertical_offset
    values.selection_mode=4-values.selection_mode_ordered
    values.select_on_release=values.release_selection_mode==2
    values.controller_release_auto=values.release_selection_mode==1
    dbf_mcm_conditions(menu,api)
    api.cached=values;api.subscribed=subscribed
    return values
end

return {dbf_menu_subscribe=dbf_menu_subscribe,dbf_mcm_conditions=dbf_mcm_conditions,canary_settings=canary_settings}
]=],
["src/feedback.lua"]=[=[-- UI-only sounds: one tick per changed target, one cue per accepted job.
local function selection_feedback(b,report)
    local owner,last_target,last_job,last_tick=nil,nil,nil,-math.huge
    local failed=false
    local self={}
    local function play(event)
        if failed then return end
        local ok,why=pcall(b.ui_sound,event)
        if not ok then failed=true;report('Selection sound unavailable: '..tostring(why)) end
    end
    function self.step(enabled,snapshot,selected,job,now,list_mode,paged)
        if not enabled or not snapshot then owner=nil;last_target=nil;last_job=nil;return end
        local fresh=owner~=snapshot.identity
        if fresh then owner=snapshot.identity;last_target=nil;last_job=nil;last_tick=-math.huge end
        if job and job~=last_job then play('confirm');last_tick=now end
        -- A page flip is deliberate navigation; share the move-cue throttle so
        -- it never doubles with a target change in the same frame.
        if paged and not job and now-last_tick>=60 then play('move');last_tick=now end
        local target
        if snapshot.open then
            for _,row in ipairs(snapshot.rows or {}) do
                if row.address==selected then target=tostring(row.entry)..':'..tostring(row.kind);break end
            end
        end
        if target and target~=last_target and not job and not (fresh and list_mode) and now-last_tick>=60 then
            play('move');last_tick=now
        end
        last_target=target;last_job=job
    end
    return self
end

return {selection_feedback=selection_feedback}
]=],
["src/hud_plus.lua"]=[=[-- Recognize the selection ownership contract, never a HUD+ version string.
-- Future presentation changes may alter observe/put without changing handoff.
local function hud_plus_compat(active)
    local self={status='HUD+ not detected',scans=0}
    local top,runtimes,seen_programs,seen_features=nil,{},{},{}
    local installed=setmetatable({}, {__mode='k'})
    local bindings={}
    -- Only owner-provided lifecycle methods perform cleanup. Each contract
    -- fingerprints its Lua helper closures too, including held-input release.
    local lifecycle={prepare='0f6d0b5c',vanilla='c5fd46ff',drop='057f16e2',close='8b14074f'}
    local picker_contracts={
        {name='immediate-picker',methods={reset='594d0655'},absent={'frame','leave'}},
        {name='paced-picker',methods={reset='4dcd1a05',frame='ae220d38',leave='27a70348'},
            helpers={reset={start_cell='f0e31473'},frame={unblock_aim='789b2088'}}},
    }
    local function member(t,k)
        if type(t)~='table' then return nil end
        local v=rawget(t,k)
        if v~=nil then return v end
        local mt=getmetatable(t)
        local index=type(mt)=='table' and rawget(mt,'__index')
        return type(index)=='table' and rawget(index,k) or nil
    end
    local function fingerprint(fn)
        if type(fn)~='function' then return nil end
        local ok,bytes=pcall(string.dump,fn,true)
        if not ok then return nil end
        local a,b=1,0
        for i=1,#bytes do a=(a+bytes:byte(i))%65521;b=(b+a)%65521 end
        return string.format('%08x',b*65536+a)
    end
    local function helpers_match(fn,expected)
        local found={}
        if not debug or type(debug.getupvalue)~='function' then return false end
        for i=1,64 do
            local name,value=debug.getupvalue(fn,i)
            if not name then break end
            if type(value)=='function' then
                if not expected or expected[name]~=fingerprint(value) then return false end
                found[name]=true
            end
        end
        for name in pairs(expected or {}) do if not found[name] then return false end end
        return true
    end
    local function picker_contract(pick)
        if pick==nil then return {name='no-picker'} end
        if type(pick)~='table' then return end
        for _,contract in ipairs(picker_contracts) do
            local matches=true
            for method,pin in pairs(contract.methods) do
                local fn=member(pick,method)
                if fingerprint(fn)~=pin or not helpers_match(fn,contract.helpers and contract.helpers[method]) then matches=false;break end
            end
            for _,method in ipairs(contract.absent or {}) do if member(pick,method)~=nil then matches=false end end
            if matches then return contract end
        end
    end
    local function bind(program)
        local feature=member(member(program,'world_hud'),'stratagem')
        if not feature then return end
        if installed[feature] then self.status=installed[feature];return end
        local function unsupported(reason)
            self.status='HUD+ stratagem adapter unsupported: '..reason
        end
        for method,pin in pairs(lifecycle) do
            local fn=member(feature,method)
            if fingerprint(fn)~=pin or not helpers_match(fn) then unsupported('lifecycle '..method);return end
        end
        local pick=member(feature,'pick')
        local contract=picker_contract(pick)
        if not contract then unsupported('picker cleanup contract');return end
        for _,method in ipairs({'observe','put'}) do
            if type(member(feature,method))~='function' then unsupported('missing '..method);return end
        end
        local inputs=member(feature,'inputs')
        if type(inputs)~='table' or type(member(inputs,'observe'))~='function'
            or type(member(feature,'list'))~='table' or type(member(feature,'card'))~='table' then
            unsupported('selection feature shape');return
        end
        local originals={prepare=rawget(feature,'prepare'),observe=rawget(feature,'observe'),put=rawget(feature,'put')}
        local prepare,observe,put=feature.prepare,feature.observe,feature.put
        local vanilla,drop=feature.vanilla,feature.drop
        local reset=pick and member(pick,'reset')
        local frame=pick and member(pick,'frame')
        local yielding=false
        local function takeover(owner)
            if yielding then return end
            -- reset restores a held menu trigger; frame releases consumed aim.
            -- Capture the verified instance methods, not mutable global classes.
            if reset then reset(pick) end
            if frame then frame(pick,false) end
            vanilla(owner,false);drop(owner);owner.segment=false
            yielding=true
        end
        feature.prepare=function(owner,enabled,...)
            if active() then takeover(owner);enabled=false else yielding=false end
            return prepare(owner,enabled,...)
        end
        feature.observe=function(owner,enabled,world,player,players,arrow,cell,...)
            if not active() then
                yielding=false
                return observe(owner,enabled,world,player,players,arrow,cell,...)
            end
            takeover(owner)
            -- Preserve the extension's shared arrow input, while keeping the
            -- competing list/picker idle. No original observe/drop loop.
            if arrow then inputs:observe(owner.panel,world,player,players,cell) end
            owner.world=world
            return inputs.showing
        end
        feature.put=function(owner,...)
            if not active() then yielding=false;return put(owner,...) end
            takeover(owner)
        end
        bindings[#bindings+1]={feature=feature,originals=originals,wrappers={prepare=feature.prepare,observe=feature.observe,put=feature.put}}
        self.contract=contract.name
        self.status='HUD+ '..contract.name..' list/picker yield to ASS while enabled'
        installed[feature]=self.status
    end
    function self.close()
        for _,binding in ipairs(bindings) do
            for name,fn in pairs(binding.wrappers) do
                if rawget(binding.feature,name)~=fn then return false,'HUD+ handoff was replaced by another owner' end
            end
        end
        for _,binding in ipairs(bindings) do
            for name in pairs(binding.wrappers) do rawset(binding.feature,name,binding.originals[name]) end
        end
        bindings={}
        return true
    end
    function self.refresh(update)
        if update~=top and self.scans<8 and debug and debug.getupvalue then
            top=update;self.scans=self.scans+1
            local queue,seen,known={{fn=update,depth=0}},{},{}
            for _,runtime in ipairs(runtimes) do known[runtime]=true end
            local at=1
            while at<=#queue and at<=128 do
                local node=queue[at];at=at+1
                if type(node.fn)=='function' and not seen[node.fn] then
                    seen[node.fn]=true
                    for i=1,64 do
                        local name,value=debug.getupvalue(node.fn,i)
                        if not name then break end
                        if name=='runtime' and type(value)=='table' and rawget(value,'installed')==true
                            and type(rawget(value,'program'))=='table' and not known[value] and #runtimes<16 then
                            known[value]=true;runtimes[#runtimes+1]=value
                        elseif type(value)=='function' and node.depth<24 and #queue<128 then
                            queue[#queue+1]={fn=value,depth=node.depth+1}
                        end
                    end
                end
            end
        end
        for _,runtime in ipairs(runtimes) do
            local program=rawget(runtime,'program')
            local feature=member(member(program,'world_hud'),'stratagem')
            if program and (seen_programs[runtime]~=program or seen_features[runtime]~=feature) then
                seen_programs[runtime]=program;seen_features[runtime]=feature
                bind(program)
            end
        end
    end
    return self
end

return {hud_plus_compat=hud_plus_compat}
]=],
["src/foliage_compat.lua"]=[=[-- Recognise Foliage Pass-Through's sole reviewed ProjectileInfo variant.
-- No native writes, guard wrappers, masked fields or relaxed comparisons.
-- Update Runtime's Lua review snapshots only when the ENTIRE native row is
-- byte-identical to that snapshot except the owner's exact 0 -> 2 template.
local function foliage_compatibility(read,pointer,base,address,env)
    env=env or _G
    local done,frames=false,0
    local keys={'hd2runtime/domains/bombardment_payload','hd2runtime/domains/weapon_clone','hd2runtime/domains/custom_payloads'}
    local self={status='waiting for Foliage/HD2Runtime owners',changed=0}
    function self.refresh()
        if done then return end
        frames=frames+1
        local loaded=env.package and env.package.loaded or {}
        local runtime=rawget(env,'HD2RuntimeLibraryApi1')
        local owner=rawget(env,'FoliagePassThrough')
        if type(runtime)~='table' or type(owner)~='table' or not owner.applied or not rawget(loaded,keys[1]) or not rawget(loaded,keys[2]) or not rawget(loaded,keys[3]) then
            if frames>=3600 then done=true;self.done=true;self.status='owners not present; unchanged' end
            return
        end
        done=true;self.done=true
        local modules={loaded[keys[1]],loaded[keys[2]],loaded[keys[3]]}
        if runtime.version~='0.40.0' or owner.version~='1.0' or owner.patched~=true or type(owner.rows)~='table' or type(owner.rows.list)~='table'
            or #owner.rows.list>128 then self.status='unknown foliage owner; unchanged';return end
        for _,m in ipairs(modules) do
            if type(m)~='table' or type(m.source)~='table' or m.source.build~='F5FEE03DCFDB' then
                self.status='unknown Runtime schema; unchanged';return
            end
        end
        local owned={}
        for _,r in ipairs(owner.rows.list) do
            local t=r.target
            if type(t)=='table' and type(t[1])=='number' and r.template==2 then
                local at=pointer(base+0x37c7670+t[1]*8)
                if at and at==address(r.pointer) and read(at+0xf4,4)=='\2\0\0\0'
                    and address(owner.rows.base)+r.offset==at+0xf4 then owned[t[1]]=at end
            end
        end
        local function hex(bytes)
            return (bytes:gsub('.',function(c)return string.format('%02x',c:byte())end))
        end
        local seen,nodes={},0
        local changes={}
        local function visit(t,depth)
            if type(t)~='table' or seen[t] then return end
            assert(depth<=12,'Foliage schema depth exceeded')
            seen[t]=true;nodes=nodes+1;assert(nodes<=12000,'Foliage schema budget exceeded')
            for k,v in pairs(t) do
                if type(v)=='table' then visit(v,depth+1)
                elseif type(v)=='string' and #v==0x110*2 and not v:find('[^0-9a-f]') then
                    local a,b,c,d=tonumber(v:sub(1,2),16),tonumber(v:sub(3,4),16),tonumber(v:sub(5,6),16),tonumber(v:sub(7,8),16)
                    local id=a+b*256+c*65536+d*16777216
                    local at=owned[id]
                    if at and v:sub(0xf4*2+1,0xf4*2+8)=='00000000' then
                        local variant=v:sub(1,0xf4*2)..'02000000'..v:sub(0xf4*2+9)
                        local actual=read(at,0x110)
                        if actual and #actual==0x110 and hex(actual)==variant then
                            changes[#changes+1]={t,k,v,variant}
                        end
                    end
                end
            end
        end
        -- These schema roots contain the donor snapshots used by every family.
        local ok,why=pcall(function()visit(modules[1].shellRows,0);visit(modules[1].gasChainRows,0);visit(modules[2].rounds,0);visit(modules[3].explosionDonors,0) end)
        if not ok then self.status=tostring(why);return end
        for _,c in ipairs(changes) do assert(c[1][c[2]]==c[3],'Runtime schema changed during compatibility check') end
        for _,c in ipairs(changes) do c[1][c[2]]=c[4] end
        self.changed=#changes
        self.status='Foliage 1.0 / Runtime 0.40.0: '..#changes..' exact row variants registered; native memory unchanged'
    end
    return self
end

return {foliage_compatibility=foliage_compatibility}
]=],
["src/entry.lua"]=[=[local api={api=1,revision=46,enabled=true,mode=1,experimental_layout=1,status='initializing',count=0}
local MOD_NAME = "Diver's Best Friend"
rawset(_G,'DiversBestFriend',api)
-- Compatibility alias for existing diagnostics and duplicate-load detection.
rawset(_G,'NativeStratagemRadial',api)
local controller,failed,last_status
local initialized,recovering=false,false
local hud_compat=hud_plus_compat and hud_plus_compat(function()
    return api.enabled and initialized and not failed and not recovering
end)
local recovery_attempts=0
local backend,selection,input,duplicates,pointing,last_tick,list_controller,camera,active_mode
local auxiliary={}
local wheel,expanded,release_selection
local excluded,exclusion_signature,hidden_rows={},'',nil
local blacklist_release_blocked=false
local mission_blacklist_state={}
local next_blacklist_sample=0
local blacklist_menu_open,blacklist_hud,previous_excluded
local empty_excluded={}
local select_on_release=false
local controller_release_auto,controller_input=false,false
local input_interval_ms=70
local randomize_input_delay=false
local binding_owner={}
local selection_events={}
local native_events,native_seen={},{}
local function native_checkpoint(message)
    -- Persist first-pass call boundaries before entering native code. A CTD
    -- bypasses pcall and the ordinary end-of-frame status logger.
    if native_seen[message] then return end
    local loader=assert(rawget(_G,'CowboyBingusModLoader'),'Shared Loader unavailable')
    local file=assert(loader.open_log('DiversBestFriend-native.log'),'Cannot open native checkpoint log')
    native_events[#native_events+1]=message
    file:write(MOD_NAME..' R46 - Homecoming Update\n'..table.concat(native_events,'\n')..'\n')
    file:close()
    native_seen[message]=true
end
local binding_ids={next="native_stratagem_radial.next",previous="native_stratagem_radial.previous",confirm="native_stratagem_radial.confirm"}
for slot=1,4 do binding_ids['slot'..slot]='native_stratagem_radial.slot'..slot end
local function selection_report(message)
    -- Button telemetry must not overwrite the last actual confirmation result.
    if not message:find('; buttons=',1,true) then api.last_confirmation=message end
    selection_events[#selection_events+1]=message
    if #selection_events>12 then table.remove(selection_events,1) end
    api.last_selection=message
end
local migration_checked,migrate_expanded
local mode_names={'Native wheel','List Select','Wedge Wheel'}
local function report(status,force)
    api.status=status
    if status==last_status and not force then return end
    last_status=status
    pcall(function()
        local loader=rawget(_G,'CowboyBingusModLoader')
        if not loader or type(loader.open_log)~='function' then return end
        local file=loader.open_log('DiversBestFriend.log')
        if file then
            file:write(MOD_NAME..' R46 - Homecoming Update\nstatus='..status..'\ncount='..api.count..'\n')
            file:write('full_color_icons='..tostring(radial.full_color~=false)..'\n')
            file:write('wedge_darkness='..tostring(radial.wedge_darkness)..'; wedge_opacity='..tostring(radial.wedge_opacity)..'\n')
            file:write('centering='..tostring(api.centering or 'not sampled')..'; vertical_offset='..tostring(radial.vertical_offset)..'\n')
            file:write('pointing='..tostring(api.pointing_status)..'\n')
            file:write('mode='..mode_names[api.mode]..'; experimental_layout='..api.experimental_layout..'\n')
            file:write('before_latest_apply='..tostring(api.observation or 'not sampled')..'\n')
            file:write('selection='..tostring(api.selection_status)..'\nlast_result='..tostring(api.last_selection)..'\n')
            file:write('last_runtime_error='..tostring(api.last_runtime_error)..'; recovery_attempts='..recovery_attempts..'\n')
            file:write('last_confirmation='..tostring(api.last_confirmation)..'\n')
            file:write('select_on_release='..tostring(select_on_release)..'; release_status='..tostring(release_selection and release_selection.status)..'\n')
            file:write('input_interval_ms='..tostring(input_interval_ms)..'\n')
            file:write('last_open='..tostring(api.last_open)..'\nlast_block='..tostring(api.last_block)..'\n')
            file:write(table.concat(selection_events,'\n')..'\n')
            file:close()
        end
    end)
end
local settings_owner,settings_state
local sound_feedback,sounds_enabled
local function options(now)
    local menu=rawget(_G,'ModOptionsMenu')
    if type(menu)~='table' or menu.api~=1 or type(menu.register_option)~='function' or type(menu.get)~='function' then return end
    if migration_checked~=menu then
        migration_checked=menu
        migrate_expanded=menu.get('native_stratagem_radial.selection_mode')==4
        -- Registration rejects a saved choice 4 once the menu has only three
        -- choices. Read that one legacy value before registering, then migrate
        -- through the documented set API (which owns persistence).
        local loader=rawget(_G,'CowboyBingusModLoader')
        local directory=loader and loader.log_directory
        if not directory then
            local local_data=os.getenv('LOCALAPPDATA')
            if local_data then directory=local_data..'/CowboyBingus/Helldivers2/Logs' end
        end
        if directory then
            local file=io.open(directory..'/ModOptionsMenu.values','rb')
            if file then
                for id,value in file:read('*a'):gmatch('([^\t\r\n]+)\t([^\r\n]*)') do
                    if id=='native_stratagem_radial.selection_mode' and value=='4' then migrate_expanded=true end
                end
                file:close()
            end
        end
    end
    if settings_owner~=menu then settings_owner=menu;settings_state={registered={}} end
    local values=canary_settings(menu,settings_state,radial,now)
    api.enabled,api.mode,api.experimental_layout=values.enabled,values.selection_mode,values.experimental_layout
    api.cooldown_icons=values.cooldown_icons
    api.hide_blacklisted_list=values.hide_blacklisted_list
    api.hide_cooldown_list=values.hide_cooldown_list
    api.hide_closed_status=values.hide_closed_status
    radial.dock_gap=values.dock_gap
    radial.cooldown_display=values.cooldown_display
    radial.short_status_placement=values.short_status_placement
    radial.balance_separated_dock=values.balance_separated_dock
    radial.track_unavailable=values.track_unavailable
    radial.cooldown_timer=values.cooldown_timers and values.cooldown_timer or 1
    radial.short_timer_style=values.short_timer_style
    radial.dim_unselected=values.dim_unselected
    radial.brief_timer_limit=values.brief_timer_limit
    select_on_release,input_interval_ms,sounds_enabled=values.select_on_release,values.input_interval_ms,values.selection_sounds
    controller_release_auto=values.controller_release_auto
    randomize_input_delay=values.randomize_input_delay

    if migrate_expanded then
        api.mode,api.experimental_layout=3,2
        if type(menu.set)=='function' and menu.set('native_stratagem_radial.experimental_layout',2)
            and menu.set('native_stratagem_radial.selection_mode',3) and menu.set('native_stratagem_radial.selection_mode_ordered',1) then migrate_expanded=false end
    end
end

-- Programmatic owners that use a silent menu.set can invalidate explicitly.
function api.invalidate_settings()
    if settings_state then settings_state.dirty=true end
end

local function bindings()
    local menu=rawget(_G,'ModBindingsMenu')
    if type(menu)~='table' or menu.api~=1 or type(menu.version)~='number'
        or not (menu.version>=2) then
        api.selection_status='Requires Mod Bindings Menu v2 or newer'; return nil
    end
    local labels={next='Next stratagem',previous='Previous stratagem',confirm='Confirm stratagem',slot1='Equip stratagem slot 1',slot2='Equip stratagem slot 2',slot3='Equip stratagem slot 3',slot4='Equip stratagem slot 4'}
    local buttons={}
    auxiliary.binding_retry=auxiliary.binding_retry or {}
    local now=backend and backend.milliseconds() or 0
    api.hotkey_error=nil
    for _,key in ipairs({'next','previous','confirm','slot1','slot2','slot3','slot4'}) do
        local id=binding_ids[key]
        local optional=key:match('^slot')~=nil
        if binding_owner[id]~=menu then
            local retry=auxiliary.binding_retry[id]
            local ok,why
            if retry and retry.owner==menu and now<retry.at then why=retry.reason
            else
                ok,why=menu.register_binding(id,labels[key],nil,dbf_binding_options and dbf_binding_options(menu,key) or {category=MOD_NAME})
                if not ok then auxiliary.binding_retry[id]={owner=menu,at=now+1000,reason=why}end
            end
            if ok then binding_owner[id]=menu;auxiliary.binding_retry[id]=nil
            elseif not optional then api.selection_status='Binding unavailable: '..tostring(why);return nil
            else api.hotkey_error='Hotkey unavailable: '..tostring(why)end
        end
        if binding_owner[id]==menu then buttons[key]=menu.is_down(id) else buttons[key]=false end
        if key:match('^slot')then buttons[key]=buttons[key]==true end
        if type(buttons[key])~='boolean' then api.selection_status='Waiting for native bindings'; return nil end
    end
    return buttons
end
-- Only known transient HUD failures may retry. Memory guards, native ABI
-- failures and unknown errors remain fatal. Keep native allocations alive.
local transient_ui_errors={
    'Wheel HUD changed','Expanded HUD changed','HUD changed during radial construction',
    'Original list geometry unavailable','List row scale unavailable',
    'Widget became unreadable','Native transform unreadable','Degenerate list transform',
    'UI context manager unavailable','Original widget resource context unavailable',
    'HUD resource renderer unavailable','UI context stack is full','Animation owner changed',
}
local function transient_ui_error(message)
    for _,reason in ipairs(transient_ui_errors) do
        if message==reason or message:sub(-#reason-2)==': '..reason then return true end
    end
    return false
end
local function cleanup_ui()
    local errors={}
    local function clean(object,method,...)
        if not object then return end
        local ok,why=pcall(object[method],...)
        if not ok then errors[#errors+1]=method..': '..tostring(why) end
    end
    clean(release_selection,'reset')
    clean(selection,'step',nil,nil,0)
    clean(pointing,'reset')
    clean(camera,'release')
    clean(controller,'restore')
    clean(list_controller,'restore')
    clean(duplicates,'hide')
    clean(wheel,'hide')
    clean(expanded,'hide')
    clean(auxiliary.dock,'hide')
    clean(auxiliary.closed_notices,'restore')
    clean(hidden_rows,'restore')
    clean(auxiliary.binding_warning,'hide')
    radial.selected=nil;api.count=0
    return #errors==0,table.concat(errors,'; ')
end
-- Keep the assembled Lua 5.1 callback below its 60-upvalue limit.
local factories={native_backend=native_backend,blacklist_list_visibility=blacklist_list_visibility,camera_capture=camera_capture,input_backend=input_backend,selection_controller=selection_controller,selection_feedback=selection_feedback,release_controller=release_controller,duplicate_cards=duplicate_cards,native_pointing=native_pointing,emote_wheel=emote_wheel,expanded_wheel=expanded_wheel,cooldown_dock=cooldown_dock,cooldown_closed_notices=cooldown_closed_notices,dbf_binding_warning=dbf_binding_warning}
local function step()
    if failed then return end
    local ok,why=pcall(function()
        local now=backend and backend.milliseconds() or 0
        options(now)
        if not controller then
            backend=factories.native_backend()
            backend.checkpoint=native_checkpoint
            hidden_rows=factories.blacklist_list_visibility(backend)
            native_checkpoint('native adapter ready; menu not entered')
            controller=radial.controller(backend)
            list_controller=radial.list_controller(backend)
            camera=factories.camera_capture(backend)
            input=factories.input_backend(backend)
            selection=factories.selection_controller(input,selection_report)
            sound_feedback=factories.selection_feedback(backend,selection_report)
            release_selection=factories.release_controller(input,selection_report)
            duplicates=factories.duplicate_cards(backend)
            pointing=factories.native_pointing(backend)
            wheel=factories.emote_wheel(backend,duplicates,input)
            expanded=factories.expanded_wheel(backend,duplicates,input)
            if factories.cooldown_dock then auxiliary.dock=factories.cooldown_dock(backend,duplicates,input) end
            if factories.cooldown_closed_notices then auxiliary.closed_notices=factories.cooldown_closed_notices(backend)end
            if factories.dbf_binding_warning then auxiliary.binding_warning=factories.dbf_binding_warning() end
            initialized=true
        end
        if now==0 then now=backend.milliseconds() end
        if recovering then
            -- A missing/failed snapshot does not prove that the menu closed.
            -- Poll only; do not construct UI or replay the cancelled input.
            local sampled,current=pcall(backend.snapshot)
            if sampled and current and current.open==false then
                recovering=false;active_mode=nil;last_tick=nil
                blacklist_release_blocked=true
                report('UI recovered; reopen the stratagem menu',true)
            end
            return
        end
        local dt=last_tick and math.max(0.001,math.min((now-last_tick)/1000,0.05)) or 1/60
        last_tick=now
        local legacy=api.mode==3 and api.experimental_layout==1
        local expanded_layout=api.mode==3 and api.experimental_layout==2
        local active_key=api.mode..':'..(api.mode==3 and api.experimental_layout or 0)
        if active_mode~=active_key then
            controller.restore();list_controller.restore();duplicates.hide();wheel.hide();expanded.hide();pointing.reset();camera.release()
            selection.step(nil,nil,now)
            release_selection.reset()
            active_mode=active_key
        end
        local buttons=bindings()
        if not backend.focused() then buttons=nil; api.selection_status='Game is not foreground' end
        local snapshot=api.enabled and backend.snapshot() or nil
        if snapshot and snapshot.open and snapshot.center then
            api.centering=tostring(snapshot.geometry)..string.format(' local_center=%.2f,%.2f',snapshot.center[1],snapshot.center[2])
        end
        if snapshot and snapshot.open and (not blacklist_menu_open or blacklist_hud~=snapshot.identity) then
            api.invalidate_settings();options(now)
            local refreshed_key=api.mode..':'..(api.mode==3 and api.experimental_layout or 0)
            if refreshed_key~=active_mode then
                controller.restore();list_controller.restore();duplicates.hide();wheel.hide();expanded.hide();pointing.reset();camera.release()
                selection.step(nil,nil,now);release_selection.reset()
                active_mode=refreshed_key
                legacy=api.mode==3 and api.experimental_layout==1
                expanded_layout=api.mode==3 and api.experimental_layout==2
                snapshot=api.enabled and backend.snapshot() or nil
            end
        end
        if not api.enabled then snapshot=nil end
        local was_open=snapshot and snapshot.open
        local decorated,why=pcall(input.decorate,snapshot)
        if not decorated then snapshot=nil; buttons=nil; api.selection_status=tostring(why) end
        -- Release open-list geometry before the closed-menu dock takes row ownership.
        if snapshot and not snapshot.open then
            controller.restore();list_controller.restore();hidden_rows.restore()
        end
        if auxiliary.closed_notices then auxiliary.closed_notices.step(api.enabled and api.hide_closed_status and snapshot or nil)end
        if auxiliary.dock then
            if not api.enabled or not api.cooldown_icons or not snapshot then auxiliary.dock.hide();auxiliary.dock_snapshot=nil
            else
                -- Native cached timer changes expose no subscription here. Bound discovery
                -- to 4 Hz / 16 cards; animation runs only while positions are changing.
                if snapshot.open then auxiliary.dock_snapshot=snapshot;auxiliary.next_dock_sample=now+250
                elseif not auxiliary.next_dock_sample or now>=auxiliary.next_dock_sample or(auxiliary.dock_snapshot and auxiliary.dock_snapshot.open)then
                    auxiliary.next_dock_sample=now+250
                    local good,value=pcall(function()
                        local value=backend.snapshot(true)
                        input.decorate(value)
                        return value
                    end)
                    auxiliary.dock_snapshot=good and value or nil
                end
                if auxiliary.dock_snapshot then auxiliary.dock.sample(auxiliary.dock_snapshot,now);auxiliary.dock.draw(now,snapshot.hud_visible) else auxiliary.dock.hide() end
            end
        end
        if snapshot and snapshot.open and (not blacklist_menu_open or blacklist_hud~=snapshot.identity or now>=next_blacklist_sample) then
            next_blacklist_sample=now+1000
            local sampled,available=pcall(input.mission_blacklist_kinds)
            local menu=rawget(_G,'ModOptionsMenu')
            if menu and menu.api==1 then
                if mission_blacklist_state.menu~=menu then mission_blacklist_state={menu=menu} end
                mission_blacklist_state.available=sampled and available or nil
            end
        end
        blacklist_menu_open=snapshot and snapshot.open or false
        blacklist_hud=snapshot and snapshot.identity
        local menu=rawget(_G,'ModOptionsMenu')
        excluded=(menu and menu.api==1) and mission_blacklist_settings(menu,mission_blacklist_state,mission_blacklist_state.available) or empty_excluded
        local signature=exclusion_signature
        local filter_key=tostring(api.hide_blacklisted_list)..':'..tostring(api.hide_cooldown_list)
        if excluded~=previous_excluded or auxiliary.list_filter_key~=filter_key then
            signature=blacklist_signature(excluded)..':'..filter_key
            previous_excluded=excluded;auxiliary.list_filter_key=filter_key
        end
        if signature~=exclusion_signature then
            -- An applied edit cancels queued/armed input before any more pulses.
            selection.step(nil,nil,now);release_selection.reset()
            controller.restore();list_controller.restore();hidden_rows.restore()
            duplicates.hide();wheel.hide();expanded.hide();pointing.reset();camera.release()
            exclusion_signature=signature
            blacklist_release_blocked=true
        end
        snapshot=blacklist_snapshot(snapshot,excluded,api.mode==2 and not api.hide_blacklisted_list,api.mode==2 and api.hide_cooldown_list)
        local vector,paged
        local empty=snapshot and snapshot.open and #snapshot.rows==0
        if empty then selection.step(nil,nil,now);release_selection.reset() end
        if snapshot and snapshot.open and not empty and api.mode~=2 and not (release_selection.job and release_selection.job.finished) then
            native_checkpoint('first open snapshot accepted')
            local ready,context=pcall(input.view_context)
            if ready then
                if expanded_layout then
                    local original=snapshot
                    local changed
                    snapshot,changed=expanded.prepare(original)
                    wheel.prepare(original,nil,false)
                    if changed then pointing.reset();selection.step(nil,nil,now) end
                elseif legacy then
                    local original=snapshot
                    snapshot=duplicates.prepare(original,context,dt)
                    -- Reuse only the native wheel's cursor marker; the copied
                    -- rows are drawn by the original radial layout controller.
                    wheel.prepare(original,nil,false)
                else
                    local changed
                    snapshot,changed,paged=wheel.prepare(snapshot,buttons,selection.job~=nil or release_selection.job~=nil)
                    if changed then pointing.reset();selection.step(nil,nil,now) end
                end
                snapshot.pointer_only=true
                if buttons then
                    camera.capture()
                    -- Navigation edges were consumed as page changes by the wheel.
                    buttons.next,buttons.previous=false,false
                    local target
                    if not legacy and not expanded_layout then target=wheel.address end
                    local pointed,result=pcall(pointing.sample,context,dt,target)
                    if pointed then vector=result;controller_input=result.controller==true;api.controller_input=controller_input;api.pointing_status=string.format('x=%.3f y=%.3f',vector[1],vector[2])
                    else api.pointing_status=tostring(result);pointing.reset();camera.release();buttons=nil end
                else pointing.reset();camera.release() end
            else
                api.selection_status=tostring(context);buttons=nil;snapshot=nil
            end
        end
        if api.mode==2 or not snapshot or not snapshot.open or empty then
            duplicates.hide();wheel.hide();expanded.hide();pointing.reset();camera.release()
            if api.mode==2 then api.pointing_status='off; keybinding list mode' end
        end
        if snapshot and api.mode==2 then snapshot.list_order=true end
        if was_open and not buttons then api.last_block=api.selection_status end
        selection.interval_ms=input_interval_ms
        selection.randomize_delay=randomize_input_delay
        release_selection.randomize_delay=randomize_input_delay
        release_selection.interval_ms=input_interval_ms
        local previous=auxiliary.shortcut_buttons or {}
        for slot=1,4 do
            local key='slot'..slot;local down=buttons and buttons[key]==true
            if down and previous[key]==false and api.enabled and snapshot and not selection.job and not release_selection.job then
                local mcm=rawget(_G,'DBFMCM')
                if not(mcm and type(mcm.is_open)=='function'and mcm.is_open())then release_selection.shortcut(slot,snapshot,now)end
            end
            if buttons then previous[key]=down else previous[key]=nil end
        end
        auxiliary.shortcut_buttons=previous
        if not release_selection.job then selection.step(snapshot,buttons,now,vector) end
        release_selection.interval_ms=input_interval_ms
        release_selection.step(((select_on_release or (controller_release_auto and controller_input)) and api.mode~=2 or release_selection.job and release_selection.job.shortcut) and not blacklist_release_blocked and api.enabled and buttons~=nil,
            snapshot,selection.selected,now,selection.job~=nil or (buttons and buttons.confirm))
        if not was_open then blacklist_release_blocked=false end
        if release_selection.job then selection.selected=release_selection.job.address end
        sound_feedback.step(sounds_enabled and api.enabled and buttons~=nil,snapshot,selection.selected,
            release_selection.job or selection.job,now,api.mode==2,paged)
        if auxiliary.binding_warning then
            local required={}
            if api.mode==2 then required={'next','previous','confirm'}
            else
                if not (select_on_release or (controller_release_auto and controller_input)) then required={'confirm'} end
                if api.mode==1 and wheel.pages and wheel.pages>1 then
                    required[#required+1]='next';required[#required+1]='previous'
                end
            end
            auxiliary.binding_warning.step(api.enabled and snapshot~=nil and snapshot.hud_visible~=false,rawget(_G,'ModBindingsMenu'),binding_ids,required,now)
            api.binding_warning=auxiliary.binding_warning.status
        end
        radial.selected=selection.selected
        if buttons then api.selection_status=selection.status end
        if was_open then
            local rows={}
            for _,row in ipairs(snapshot and snapshot.rows or {}) do
                rows[#rows+1]=tostring(row.entry)..':'..tostring(row.kind)..':'..tostring(row.timer_kind or 'no-timer')..':'..tostring(row.unavailable)..':'..tostring(row.timer_seconds or '-')
            end
            api.last_open=api.selection_status..'; cards='..table.concat(rows,',')..
                '; selected='..tostring(selection.selected)..'; buttons='..
                (buttons and (tostring(buttons.next)..','..tostring(buttons.previous)..','..tostring(buttons.confirm)) or 'unavailable')
            if buttons and (buttons.next or buttons.previous or buttons.confirm) then
                if api.last_buttons~=api.last_open then selection_report(api.last_open) end
            end
            api.last_buttons=api.last_open
        end
        -- Never fall back to arranging the original list if preparation failed.
        if was_open then native_checkpoint('layout enter') end
        local display=api.mode==2 and list_controller or (expanded_layout and expanded or (legacy and controller or wheel))
        if api.mode~=2 and snapshot and snapshot.open and not empty then
            wheel.draw(selection.selected,vector,snapshot.rows,legacy or expanded_layout)
            if expanded_layout then wheel.caption(expanded.draw(selection.selected,snapshot.rows)) end
            local selected_row
            if not legacy then
                for _,row in ipairs(snapshot.rows) do
                    if row.address==selection.selected then selected_row=row;break end
                end
            end
            wheel.timer(selected_row)
        end
        display.step(api.enabled,empty and api.mode~=2 and {open=false} or snapshot or {open=false})
        if empty then api.selection_status='No selectable stratagems remain after filtering' end
        hidden_rows.step(api.enabled and api.mode==2 and snapshot or nil)
        if was_open then native_checkpoint('layout returned') end
        api.count=display.count
        api.observation=display.observation
        if snapshot and snapshot.open then recovery_attempts=0 end
        report(display.status,api.last_selection~=api.reported_selection)
        api.reported_selection=api.last_selection
    end)
    if not ok then
        api.last_runtime_error=tostring(why)
        local cleaned,cleanup_error=cleanup_ui()
        if initialized and cleaned and transient_ui_error(tostring(why)) and recovery_attempts<3 then
            recovery_attempts=recovery_attempts+1;recovering=true
            blacklist_release_blocked=true
            report('UI paused after transient error; close the stratagem menu to recover: '..tostring(why),true)
        else
            failed=true
            report('disabled after error: '..tostring(why)..(cleaned and '' or '; cleanup failed: '..cleanup_error),true)
        end
    end
end
local foliage_compat
local previous=rawget(_G,'update')
function api.shutdown()
    api.enabled=false
    local clean,why=cleanup_ui()
    if not clean then return false,why end
    if hud_compat then local ok,problem=hud_compat.close();if not ok then return false,problem end end
    for _,object in ipairs({wheel or false,expanded or false,auxiliary.dock or false,duplicates or false}) do
        if object and object.close then
            local ok,problem=object.close();if ok==false then return false,problem end
        end
    end
    if mission_blacklist_state.native then mission_blacklist_state.native.unregister();mission_blacklist_state.native=nil end
    local broker=rawget(_G,'DBFMenuSubscriptions') or {}
    for _,rows in pairs(broker) do for _,record in pairs(rows) do
        if record.owner==api then record.fn,record.owner=nil,nil end
    end end
    auxiliary.stopped=true
    if rawget(_G,'update')==auxiliary.wrapper then rawset(_G,'update',previous) end
    if rawget(_G,'DiversBestFriend')==api then rawset(_G,'DiversBestFriend',nil) end
    if rawget(_G,'NativeStratagemRadial')==api then rawset(_G,'NativeStratagemRadial',nil) end
    return true
end
local function after(...) step(); return ... end
update=function(...)
    if auxiliary.stopped then if type(previous)=='function' then return previous(...) end;return end
    if not foliage_compat and foliage_compatibility and backend then
        foliage_compat=foliage_compatibility(backend.read,function(at)
            local s=backend.read(at,8)
            if not s then return end
            local p=backend.u32(s,0)+backend.u32(s,4)*4294967296
            if p>=65536 and p<2^47 and p%4==0 then return p end
        end,backend.base,function(p) return tonumber(require('ffi').cast('uintptr_t',p)) end)
    end
    if foliage_compat and not foliage_compat.done then
        local ok,why=pcall(foliage_compat.refresh)
        api.foliage_compat=ok and foliage_compat.status or tostring(why)
    end
    -- Bind before the upstream HUD+ update; no unchanged-owner rescanning.
    if hud_compat then
        local ok,why=pcall(hud_compat.refresh,rawget(_G,'update'))
        api.hud_plus_compat=ok and hud_compat.status or tostring(why)
    end
    if type(previous)=='function' then return after(previous(...)) end
    return after()
end
auxiliary.wrapper=update
report('loaded; awaiting native HUD')

return {api=api,MOD_NAME=MOD_NAME,controller=controller,failed=failed,last_status=last_status,initialized=initialized,recovering=recovering,hud_compat=hud_compat,recovery_attempts=recovery_attempts,backend=backend,selection=selection,input=input,duplicates=duplicates,pointing=pointing,last_tick=last_tick,list_controller=list_controller,camera=camera,active_mode=active_mode,auxiliary=auxiliary,wheel=wheel,expanded=expanded,release_selection=release_selection,excluded=excluded,exclusion_signature=exclusion_signature,hidden_rows=hidden_rows,blacklist_release_blocked=blacklist_release_blocked,mission_blacklist_state=mission_blacklist_state,next_blacklist_sample=next_blacklist_sample,blacklist_menu_open=blacklist_menu_open,blacklist_hud=blacklist_hud,previous_excluded=previous_excluded,empty_excluded=empty_excluded,select_on_release=select_on_release,controller_release_auto=controller_release_auto,controller_input=controller_input,input_interval_ms=input_interval_ms,randomize_input_delay=randomize_input_delay,binding_owner=binding_owner,selection_events=selection_events,native_events=native_events,native_seen=native_seen,native_checkpoint=native_checkpoint,binding_ids=binding_ids,selection_report=selection_report,migration_checked=migration_checked,migrate_expanded=migrate_expanded,mode_names=mode_names,report=report,settings_owner=settings_owner,settings_state=settings_state,sound_feedback=sound_feedback,sounds_enabled=sounds_enabled,options=options,bindings=bindings,transient_ui_errors=transient_ui_errors,transient_ui_error=transient_ui_error,cleanup_ui=cleanup_ui,factories=factories,step=step,foliage_compat=foliage_compat,previous=previous,after=after}
]=],
}
local order={"src/layout.lua","src/guards.lua","src/native.lua","src/menu_latch.lua","src/mission_blacklist.lua","src/input.lua","src/pointing.lua","src/camera.lua","src/icon_colors.lua","src/duplicate.lua","src/emote.lua","src/expanded.lua","src/cooldown_dock.lua","src/binding_warning.lua","src/binding_defaults.lua","src/selection.lua","src/release.lua","src/blacklist.lua","src/settings.lua","src/feedback.lua","src/hud_plus.lua","src/foliage_compat.lua","src/entry.lua"
}
local scope=setmetatable({}, {__index=_G})
local cache={}
local function require_module(name)
    if cache[name] then return cache[name] end
    local source=assert(sources[name],'ASS module missing: '..tostring(name))
    local chunk=assert(loadstring(source,'@DiversBestFriend/'..name))
    setfenv(chunk,scope)
    local exports=chunk()
    assert(type(exports)=='table','ASS module must export a table: '..name)
    cache[name]=exports
    sources[name]=nil
    return exports
end
for _,name in ipairs(order) do
    for key,value in pairs(require_module(name)) do scope[key]=value end
end
assert(type(scope.update)=='function','ASS startup callback unavailable')
rawset(_G,'update',scope.update)
