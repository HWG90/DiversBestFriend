-- HD2-Addon: mods/EquippedStratagems/NativeStratagemRadial
if rawget(_G,'NativeStratagemRadial') then return end
-- Pure layout/controller. Native widgets retain their own content and input.
local radial = {vertical_offset=0,full_color=true,wedge_darkness=70,wedge_opacity=75}
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

-- List mode uses the original native list and only scales the selected row.
-- Its positions, arrows and parent hierarchy remain under native control.
function radial.list_controller(backend)
    local self={count=0,status='native menu closed'}
    local saved
    local function same(a,b) return a and b and a[1]==b[1] and a[2]==b[2] end
    function self.restore()
        if saved and backend.valid(saved.identity) then
            if same(backend.get(saved.address,'scale'),saved.applied) then
                backend.set(saved.address,'scale',saved.before)
            end
        end
        saved=nil;self.count=0
    end
    function self.step(enabled,snapshot)
        if not enabled or not snapshot or not snapshot.open then
            self.restore();self.status=enabled and 'native menu closed' or 'disabled';return
        end
        local selected
        for _,row in ipairs(snapshot.rows) do if row.address==radial.selected then selected=row.address end end
        if saved and (saved.identity~=snapshot.identity or saved.address~=selected) then self.restore() end
        if selected then
            local current=assert(backend.get(selected,'scale'),'List row scale unavailable')
            if not saved then saved={identity=snapshot.identity,address=selected,before=current}
            elseif not same(current,saved.applied) then saved.before=current end
            backend.set(selected,'scale',{saved.before[1]*1.10,saved.before[2]*1.10})
            saved.applied=assert(backend.get(selected,'scale'))
        end
        self.count=#snapshot.rows
        self.status='native list selection ('..self.count..' cards)'
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

-- Guard bytes from the supported in-process capture; see RESEARCH.md.
local native_guards = {
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

-- Supported-build adapter. All drawing remains in the game's native HUD.
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
            assert((backend.radial_card and backend.radial_card(address)) or
                (not backend.radial_card and index>=0 and index<16 and index%1==0),'Invalid animation card')
            float_pair[0],float_pair[1]=value[1],value[2]
            assert(read(address+spec.offset,8),'Animation data unavailable')
            assert(kernel.WriteProcessMemory(process,ffi.cast('void *',address+spec.offset),
                float_pair,8,received)~=0 and tonumber(received[0])==8,'Animation write failed')
        end
    end
    function backend.snapshot()
        local root=hud()
        if not root then return nil,'waiting for initialized gameplay HUD' end
        local panel=root+0x24e340+0x146dc0
        local open=read(panel+0x38769,1)
        if open=='\0' then return {identity=root,open=false},'native menu closed' end
        if open~='\1' then return nil,'Invalid menu-open flag' end
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
                rows[#rows+1]={address=address,width=size[1],height=size[2],entry=u32(read(address+0x3748,4),0),list_y=target[2]}
            end
        end
        return {identity=root,panel=panel,list=list,rows=rows,open=true,center=center,geometry=string.format('viewport=%.1fx%.1f matrix=%s list=%.1fx%.1f matrix=%s',viewport.width,viewport.height,table.concat(viewport.matrix,','),container.width,container.height,table.concat(container.matrix,','))}
    end
    backend.read=read; backend.pointer=pointer; backend.u32=u32; backend.base=base
    local input_handler=ffi.cast('void (*)(uintptr_t)',base+0xa900d0)
    local byte=ffi.new('uint8_t[1]')
    function backend.pulse_byte(address,value)
        byte[0]=value
        assert(kernel.WriteProcessMemory(process,ffi.cast('void *',address),byte,1,received)~=0
            and tonumber(received[0])==1,'Native action write failed')
    end
    function backend.invoke_input(component) input_handler(component) end
    function backend.open_input(component)
        return ffi.cast('uint8_t (*)(uintptr_t)',base+0xa8e850)(component)~=0
    end
    function backend.close_input(component)
        ffi.cast('void (*)(uintptr_t)',base+0xa8fb50)(component)
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
        local reopened=false
        if not c.menu_active then
            if b.checkpoint then b.checkpoint('release native opener enter') end
            assert(b.open_input(c.component),'Native game state rejected release selection')
            reopened=true
            if b.checkpoint then b.checkpoint('release native opener returned') end
        end
        local ok,result=pcall(out.begin,kind)
        if not ok then
            if reopened then b.close_input(c.component) end
            error(result)
        end
        result.hud=c.hud
        result.actions=c.actions
        result.controls=controls
        result.reopened=reopened
        return result
    end
    function out.hold_release(job)
        local c=out.release_state()
        assert(c.identity==job.identity and c.component==job.component and c.hud==job.hud,
            'Release owner changed')
        assert(c.unobstructed and c.hold,'Release interrupted by UI or changed menu binding')
        assert(c.menu_active,'Native menu closed before release code completed')
        assert(ptr(base+0x347cf18)==job.controls,'Native controls changed')
        -- Hold both evaluated copies: the controls owner and the local avatar.
        -- These transient bytes are not saved bindings or OS key events.
        local addresses={job.controls+808+32*(97*5),c.actions}
        job.held=job.held or {}
        for _,address in ipairs(addresses) do
            local value=read(address,1)
            assert(value=='\0' or value=='\1','Invalid native Hold action')
            if value=='\0' then
                job.held[address]=true
                b.pulse_byte(address,1)
            end
        end
    end
    function out.end_release(job,cancelled)
        -- Re-resolve owners before touching cached action addresses. Clean up
        -- the controls copy even when the avatar/HUD has gone away.
        local controls_ok,controls=pcall(ptr,base+0x347cf18)
        local current_ok,c=pcall(context,false,true)
        for address in pairs(job.held or {}) do
            local controls_owned=controls_ok and controls==job.controls and address==controls+808+32*(97*5)
            local avatar_owned=current_ok and c.identity==job.identity and c.component==job.component and address==c.actions
            if (controls_owned or avatar_owned) and b.read(address,1)=='\1' then b.pulse_byte(address,0) end
        end
        job.held=nil
        if cancelled and current_ok and c.identity==job.identity and c.component==job.component and c.menu_active then
            b.close_input(c.component)
        end
    end
    function out.advance_release(job)
        out.hold_release(job)
        return out.advance(job)
    end
    return out
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
        assert(bound>=65536 and b.read(bound,4),'Native radial bindings unavailable')
        if b.checkpoint then b.checkpoint('pointing reader enter') end
        reader(target,context.input_owner,math.max(0.001,math.min(dt,0.05)))
        if b.checkpoint then b.checkpoint('pointing reader returned') end
        local v=ffi.cast('float *',target+0x1ce8)
        local x,y=tonumber(v[0]),tonumber(v[1])
        assert(x==x and y==y and math.abs(x)<=1.01 and math.abs(y)<=1.01,'Invalid radial direction')
        local result={x,y}
        if wheel then
            local index=tonumber(ffi.cast('uint32_t *',target+0x1cd8)[0])
            if index<8 and ffi.cast('uint8_t *',target+0x1cc8)[index]~=0 then result.slot=index+1 end
        end
        return result
    end
    self.reset()
    return self
end

-- Use the same per-frame camera-input gate as the native radial reader.
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

-- Called within the owner's HUD resource scope, only for separately owned icons.
local function configure_stratagem_icon(b,icon,info,cooling)
    local ffi=require('ffi')
    local texture=ffi.cast('void (*)(uintptr_t, uint64_t, uint64_t, uint8_t)',b.base+0x1450230)
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
    local material=ffi.cast('uintptr_t (*)(uintptr_t)',b.base+0x144f6e0)
    local parameter=ffi.cast('void (*)(uintptr_t, uint32_t, const float *)',b.base+0x14498c0)
    assert(tonumber(material(icon))~=0,'Stratagem icon material unavailable')
    parameter(icon,0x28723f4d,accent)
    parameter(icon,0x851fd4fd,foreground)
    parameter(icon,0x10c353af,background)
end

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
        for _,original in ipairs(snapshot.rows) do
            assert(original.entry>=0 and original.entry<16,'Native card entry out of bounds')
            local card=address+0x110+original.entry*0x3760
            assert(self.owns(card),'Radial card ownership changed')
            rows[#rows+1]={address=card,entry=original.entry,kind=original.kind,width=original.width,height=original.height}
        end
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
        if not busy and next_edge~=prev_edge and (next_edge or prev_edge) then
            local page=(self.page-1+(next_edge and 1 or -1))%self.pages+1
            changed=changed or page~=self.page;self.page=page
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
            -- Original HUD remains visible; only independently owned icons change.
            for i=0,7 do
                local row=page_rows[i+1]
                local icon=address+0x1208+i*0x158
                ffi.cast('uint8_t *',address+0x1cc8)[i]=row and 1 or 0
                visible(icon,row and 1 or 0)
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
            pointing_index=function(_,vector) return vector.slot end},changed
    end
    function self.draw(selected,vector,rows,cursor_only)
        if not owned() then return end
        local index,row
        for i,item in ipairs(rows or {}) do if item.address==selected then index=i-1;row=item end end
        scope.context_scope(parent,function()
            local show=index~=nil and not cursor_only
            visible(address+0x488,cursor_only and 0 or 1)
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

-- Pointing and discrete navigation share the proven explicit-confirm path.
local function selection_controller(input,report)
    local self={selected=nil,status='Open the native stratagem menu',job=nil,interval_ms=70}
    local previous,opened={},false
    local owner,next_at,last_vector,point_mode
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
            owner=nil;last_vector=nil;point_mode=false; return
        end
        owner=snapshot.identity
        local eligible={}
        for _,row in ipairs(snapshot.rows) do
            if selectable_kind(row.kind) then eligible[#eligible+1]=row end
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
        for i,row in ipairs(eligible) do if row.address==self.selected then chosen=i end end
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
        self.status='Highlighted kind '..row.kind..'; press Confirm while keeping the menu open'
        if edges.confirm then
            local ok,result=pcall(input.begin,row.kind)
            if ok then
                local interval=self.interval_ms
                if type(interval)~='number' or interval~=interval or interval<0 or interval>250 then interval=70 end
                self.job=result;self.job.interval_ms=interval
                self.job.deadline=now+math.max(3000,(self.job.code and #self.job.code or 12)*interval+1500)
                next_at=now;report('Started native input for kind '..row.kind..'; interval='..interval..'ms')
            else report('Not started: '..tostring(result)) end
        end
    end
    return self
end

-- Only a sampled Hold falling edge can confirm. A disappearing HUD alone
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
    function self.step(enabled,snapshot,selected,now,explicit)
        if not enabled or not snapshot then self.status='Disabled or no valid radial snapshot';self.reset();return end
        if self.job then
            local job=self.job
            if snapshot.identity~=job.snapshot_identity or now>job.deadline or explicit then
                self.status='Release cancelled: HUD changed, timeout or explicit input';report(self.status);self.reset();return
            end
            if job.finished then
                local ok,why=pcall(input.end_release,job,false)
                self.job=nil;blocked=true
                self.status=ok and 'Release code complete; temporary Hold released' or 'Release cleanup failed: '..tostring(why)
                report(self.status);return
            end
            local ok,why=pcall(function()
                input.hold_release(job)
                if now>=job.next_at then
                    local done,message=input.advance_release(job)
                    self.status=message;report('Release: '..message)
                    job.finished=done;job.next_at=now+job.interval_ms
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
        armed=nil
        if not state.down then
            local skip=blocked;blocked=nil
            if not skip and previous and now>=previous.time and now-previous.time<=250
                and snapshot.identity==previous.snapshot_identity
                and state.identity==previous.identity and state.component==previous.component
                and state.hud==previous.hud then
                local called,job=pcall(input.begin_release,previous.kind,previous)
                if called then
                    local interval=self.interval_ms
                    if type(interval)~='number' or interval~=interval or interval<0 or interval>250 then interval=70 end
                    job.interval_ms=interval;job.next_at=now;job.snapshot_identity=snapshot.identity;job.address=previous.address
                    job.deadline=now+math.max(3000,#job.code*interval+1500)
                    self.job=job
                    local held,why=pcall(input.hold_release,job)
                    if held then self.status='Holding menu for kind '..previous.kind..'; interval='..interval..'ms'
                    else self.status='Release cancelled: '..tostring(why);self.reset() end
                else self.status='Release cancelled: '..tostring(job) end
                report(self.status)
            end
            return
        end
        if blocked or not snapshot.open or not state.menu_active then return end
        for _,row in ipairs(snapshot.rows) do
            if row.address==selected and selectable_kind(row.kind) then
                armed={kind=row.kind,address=row.address,time=now,snapshot_identity=snapshot.identity,
                    identity=state.identity,component=state.component,hud=state.hud}
                self.status='Armed kind '..row.kind
                return
            end
        end
    end
    return self
end

local api={api=1,revision=27,enabled=true,mode=1,experimental_layout=1,status='initializing',count=0}
local MOD_NAME = "Diver's Best Friend"
rawset(_G,'DiversBestFriend',api)
-- Compatibility alias for existing diagnostics and duplicate-load detection.
rawset(_G,'NativeStratagemRadial',api)
local controller,failed,registered,last_status
local frames=0
local backend,selection,input,duplicates,pointing,last_tick,list_controller,camera,active_mode
local wheel,expanded,release_selection,release_registered
local select_on_release=false
local interval_registered,input_interval_ms=nil,70
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
    file:write(MOD_NAME..' R27 - Release Hold\n'..table.concat(native_events,'\n')..'\n')
    file:close()
    native_seen[message]=true
end
local binding_ids={next="native_stratagem_radial.next",previous="native_stratagem_radial.previous",confirm="native_stratagem_radial.confirm"}
local function selection_report(message)
    -- Button telemetry must not overwrite the last actual confirmation result.
    if not message:find('; buttons=',1,true) then api.last_confirmation=message end
    selection_events[#selection_events+1]=message
    if #selection_events>12 then table.remove(selection_events,1) end
    api.last_selection=message
end
local offset_registered,mode_registered,layout_registered,color_registered
local wedge_registered={}
local wedge_options={
    {key='wedge_darkness',label='Expanded wedge darkness (%)',default=70,
        description='Expanded wedges only. Darkens the unselected background; 0 keeps the original gray, 100 makes it black. The selected sector stays yellow.'},
    {key='wedge_opacity',label='Expanded wedge opacity (%)',default=75,
        description='Expanded wedges only. Background opacity: 0 is transparent, 100 is opaque. Empty sectors stay fainter and the selected sector stays visible. Original appearance: darkness 0, opacity 30.'},
}
local migration_checked,migrate_expanded
local mode_names={'Native wheel','Keybindings - list','Experimental'}
local function report(status,force)
    api.status=status
    if status==last_status and not force then return end
    last_status=status
    pcall(function()
        local loader=rawget(_G,'CowboyBingusModLoader')
        if not loader or type(loader.open_log)~='function' then return end
        local file=loader.open_log('DiversBestFriend.log')
        if file then
            file:write(MOD_NAME..' R27 - Release Hold\nstatus='..status..'\ncount='..api.count..'\n')
            file:write('full_color_icons='..tostring(radial.full_color~=false)..'\n')
            file:write('wedge_darkness='..tostring(radial.wedge_darkness)..'; wedge_opacity='..tostring(radial.wedge_opacity)..'\n')
            file:write('centering='..tostring(api.centering or 'not sampled')..'; vertical_offset='..tostring(radial.vertical_offset)..'\n')
            file:write('pointing='..tostring(api.pointing_status)..'\n')
            file:write('mode='..mode_names[api.mode]..'; experimental_layout='..api.experimental_layout..'\n')
            file:write('before_latest_apply='..tostring(api.observation or 'not sampled')..'\n')
            file:write('selection='..tostring(api.selection_status)..'\nlast_result='..tostring(api.last_selection)..'\n')
            file:write('last_confirmation='..tostring(api.last_confirmation)..'\n')
            file:write('select_on_release='..tostring(select_on_release)..'; release_status='..tostring(release_selection and release_selection.status)..'\n')
            file:write('input_interval_ms='..tostring(input_interval_ms)..'\n')
            file:write('last_open='..tostring(api.last_open)..'\nlast_block='..tostring(api.last_block)..'\n')
            file:write(table.concat(selection_events,'\n')..'\n')
            file:close()
        end
    end)
end
local function options()
    local menu=rawget(_G,'ModOptionsMenu')
    if type(menu)~='table' or menu.api~=1 or type(menu.register_option)~='function' or type(menu.get)~='function' then return end
    if interval_registered~=menu then
        if menu.register_option('native_stratagem_radial.input_interval_ms',{
            type='slider',mod=MOD_NAME,label='Input interval (ms)',min=0,max=250,step=5,default=70,
            description='Delay between directions for Confirm and Select on Release. 0 sends one direction per frame. Changes apply to the next code.'}) then interval_registered=menu end
    end
    if interval_registered==menu then
        local value=menu.get('native_stratagem_radial.input_interval_ms')
        if type(value)=='number' and value==value and value>=0 and value<=250 then input_interval_ms=value end
    end
    if release_registered~=menu then
        if menu.register_option('native_stratagem_radial.select_on_release',{
            type='toggle',mod=MOD_NAME,label='Select on Release',default=false,
            description='Radial modes only: use a Hold stratagem-menu binding, point, then release to select. No separate Confirm binding required. Center the pointer to cancel. List mode still requires Confirm.'}) then release_registered=menu end
    end
    if release_registered==menu then
        select_on_release=menu.get('native_stratagem_radial.select_on_release')==true
    end
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
    if registered~=menu then
        local ok=menu.register_option('native_stratagem_radial.enabled',{
            type='toggle',mod=MOD_NAME,label='Enable Mod',default=true,
            description='Enable the selected menu mode. Confirm enters the highlighted stratagem code.'})
        if ok then registered=menu end
    end
    if mode_registered~=menu then
        if menu.register_option('native_stratagem_radial.selection_mode',{
            type='choice',mod=MOD_NAME,label='Selection mode',
            choices={'Native wheel','Keybindings - list','Experimental'},default=1,
            description='Native wheel: eight slots with mouse or stick selection. List: Next/Previous and Confirm with camera control. Experimental: choose Cards or Expanded wedges below.'}) then mode_registered=menu end
    end
    if mode_registered==menu then
        local value=menu.get('native_stratagem_radial.selection_mode')
        if value==1 or value==2 or value==3 then api.mode=value end
    end
    if layout_registered~=menu then
        if menu.register_option('native_stratagem_radial.experimental_layout',{
            type='choice',mod=MOD_NAME,label='Experimental layout',
            choices={'Cards - copied list rows','Expanded wedges'},default=1,
            description='Experimental mode: up to 16 Cards or Expanded wedges. Point with the mouse or stick, then Confirm or use Select on Release.'}) then layout_registered=menu end
    end
    if layout_registered==menu then
        local value=menu.get('native_stratagem_radial.experimental_layout')
        if value==1 or value==2 then api.experimental_layout=value end
    end
    if migrate_expanded and mode_registered==menu and layout_registered==menu then
        api.mode,api.experimental_layout=3,2
        if type(menu.set)=='function' then
            local layout_ok=menu.set('native_stratagem_radial.experimental_layout',2)
            if layout_ok and menu.set('native_stratagem_radial.selection_mode',3) then migrate_expanded=false end
        end
    end
    if color_registered~=menu then
        if menu.register_option('native_stratagem_radial.full_color_icons',{
            type='toggle',mod=MOD_NAME,label='Full-color stratagem icons',default=true,
            description='Use full-color icons on the wheels. Off shows the raw red/green icons. Cards keep their original colors; cooldown icons remain gray.'}) then color_registered=menu end
    end
    if color_registered==menu then
        local value=menu.get('native_stratagem_radial.full_color_icons')
        if type(value)=='boolean' then radial.full_color=value end
    end
    for _,spec in ipairs(wedge_options) do
        local id='native_stratagem_radial.'..spec.key
        if wedge_registered[id]~=menu then
            if menu.register_option(id,{type='slider',mod=MOD_NAME,
                label=spec.label,min=0,max=100,step=5,default=spec.default,
                description=spec.description}) then wedge_registered[id]=menu end
        end
        if wedge_registered[id]==menu then
            local value=menu.get(id)
            if type(value)=='number' and value>=0 and value<=100 then radial[spec.key]=value end
        end
    end
    if offset_registered~=menu then
        if menu.register_option('native_stratagem_radial.vertical_offset',{
            type='slider',mod=MOD_NAME,label='Radial vertical offset (down)',
            min=-600,max=600,step=25,default=0,
            description='Fine-tune automatic viewport centering. Leave at 0 for screen center; positive values move downward. Apply after adjusting.'}) then offset_registered=menu end
    end
    if offset_registered==menu then
        local value=menu.get('native_stratagem_radial.vertical_offset')
        if type(value)=='number' and value>=-600 and value<=600 then radial.vertical_offset=value end
    end
    if registered==menu then
        local value=menu.get('native_stratagem_radial.enabled')
        if type(value)=='boolean' then api.enabled=value end
    end
end
local function bindings()
    local menu=rawget(_G,'ModBindingsMenu')
    if type(menu)~='table' or menu.api~=1 or menu.version~=2 then
        api.selection_status='Requires Mod Bindings Menu v2'; return nil
    end
    local labels={next='Next stratagem',previous='Previous stratagem',confirm='Confirm stratagem'}
    local buttons={}
    for _,key in ipairs({'next','previous','confirm'}) do
        local id=binding_ids[key]
        if binding_owner[id]~=menu then
            local ok,why=menu.register_binding(id,labels[key],nil,{category=MOD_NAME})
            if not ok then api.selection_status='Binding unavailable: '..tostring(why); return nil end
            binding_owner[id]=menu
        end
        buttons[key]=menu.is_down(id)
        if type(buttons[key])~='boolean' then api.selection_status='Waiting for native bindings'; return nil end
    end
    return buttons
end
local function step()
    if failed then return end
    local ok,why=pcall(function()
        options()
        if not controller then
            backend=native_backend()
            backend.checkpoint=native_checkpoint
            native_checkpoint('native adapter ready; menu not entered')
            controller=radial.controller(backend)
            list_controller=radial.list_controller(backend)
            camera=camera_capture(backend)
            input=input_backend(backend)
            selection=selection_controller(input,selection_report)
            release_selection=release_controller(input,selection_report)
            duplicates=duplicate_cards(backend)
            pointing=native_pointing(backend)
            wheel=emote_wheel(backend,duplicates,input)
            expanded=expanded_wheel(backend,duplicates,input)
        end
        local now=backend.milliseconds()
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
        local was_open=snapshot and snapshot.open
        local decorated,why=pcall(input.decorate,snapshot)
        if not decorated then snapshot=nil; buttons=nil; api.selection_status=tostring(why) end
        local vector
        if snapshot and snapshot.open and api.mode~=2 then
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
                    snapshot,changed=wheel.prepare(snapshot,buttons,selection.job~=nil or release_selection.job~=nil)
                    if changed then pointing.reset();selection.step(nil,nil,now) end
                end
                snapshot.pointer_only=true
                if buttons then
                    camera.capture()
                    -- Navigation edges were consumed as page changes by the wheel.
                    buttons={next=false,previous=false,confirm=buttons.confirm}
                    local target
                    if not legacy and not expanded_layout then target=wheel.address end
                    local pointed,result=pcall(pointing.sample,context,dt,target)
                    if pointed then vector=result;api.pointing_status=string.format('x=%.3f y=%.3f',vector[1],vector[2])
                    else api.pointing_status=tostring(result);pointing.reset();camera.release();buttons=nil end
                else pointing.reset();camera.release() end
            else
                api.selection_status=tostring(context);buttons=nil;snapshot=nil
            end
        end
        if api.mode==2 or not snapshot or not snapshot.open then
            duplicates.hide();wheel.hide();expanded.hide();pointing.reset();camera.release()
            if api.mode==2 then api.pointing_status='off; keybinding list mode' end
        end
        if snapshot and api.mode==2 then snapshot.list_order=true end
        if was_open and not buttons then api.last_block=api.selection_status end
        selection.interval_ms=input_interval_ms
        if not release_selection.job then selection.step(snapshot,buttons,now,vector) end
        release_selection.interval_ms=input_interval_ms
        release_selection.step(select_on_release and api.enabled and api.mode~=2 and buttons~=nil,
            snapshot,selection.selected,now,selection.job~=nil or (buttons and buttons.confirm))
        if release_selection.job then selection.selected=release_selection.job.address end
        radial.selected=selection.selected
        if buttons then api.selection_status=selection.status end
        if was_open then
            local rows={}
            for _,row in ipairs(snapshot and snapshot.rows or {}) do
                rows[#rows+1]=tostring(row.entry)..':'..tostring(row.kind)..':'..tostring(row.timer_kind or 'no-timer')..':'..tostring(row.timer_seconds or '-')
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
        if api.mode~=2 and snapshot and snapshot.open then
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
        display.step(api.enabled,snapshot or {open=false})
        if was_open then native_checkpoint('layout returned') end
        api.count=display.count
        api.observation=display.observation
        frames=frames+1
        report(display.status,(api.count>0 and frames%120==0) or api.last_selection~=api.reported_selection)
        api.reported_selection=api.last_selection
    end)
    if not ok then
        failed=true
        if release_selection then pcall(release_selection.reset) end
        if controller then pcall(controller.restore) end
        if list_controller then pcall(list_controller.restore) end
        if camera then pcall(camera.release) end
        if duplicates then pcall(duplicates.hide) end
        if wheel then pcall(wheel.hide) end
        if expanded then pcall(expanded.hide) end
        api.count=0
        report('disabled after error: '..tostring(why))
    end
end
local previous=rawget(_G,'update')
local function after(...) step(); return ... end
update=function(...)
    if type(previous)=='function' then return after(previous(...)) end
    return after()
end
report('loaded; awaiting native HUD')
