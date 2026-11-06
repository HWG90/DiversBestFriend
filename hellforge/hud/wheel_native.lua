-- Supported-build adapter. All drawing remains in the game's native HUD.
-- 25480438: set_scale's cancellation slot and the card updater's removed
-- flag, zero-height target and native tween call (18365EA..1836620).
native_guards[#native_guards+1]={name='scale_tween_slot',rva=0x1447f8e,bytes='\xf7\x01\x00\x00\x00\x02\x74\x72\x48\x8b\x81\xa8\x00\x00\x00\x48\xc1\xe8\x21\x25\xff\x07\x00\x00\x74\x60\x8d\x68\xff\x4c\x89\x74'}
native_guards[#native_guards+1]={name='card_leave_tween',rva=0x18365ea,bytes='\x48\xc7\x45\xc0\x00\x00\x80\x3f\x48\x8b\x55\xc0\xf3\x0f\x11\x44\x24\x20\x45\x89\xa7\x4c\x37\x00\x00\x66\x41\xc7\x87\xf0\x36\x00\x00\x00\x01\x41\xc6\x87\x28\x37\x00\x00\x01\x66\x0f\x7f\x4c\x24\x70\xe8\x60\xb8\xc1\xff'}
-- Cache successful witnesses for this module lifetime. A zero from guard can
-- mean an encrypted/not-yet-resident page. Retry that group before first use.
local function wheel_admission(bridge)
    -- R46 left these two prologues empty. The 25480438 mapped capture
    -- supplies both; use the bridge's original-code check for them too.
    local dock_guards={
        [0x1839520]="\x48\x89\x5c\x24\x08\x48\x89\x74\x24\x10\x48\x89\x7c\x24\x18\x4c\x89\x6c\x24\x20\x55\x41\x56\x41",
        [0x1839fd0]="\x4d\x85\xc9\x0f\x84\x81\x0a\x00\x00\x4c\x8b\xdc\x55\x56\x41\x55\x41\x57\x49\x8d\x6b\xa1\x48\x81",
    }
    local groups={}
    local names={
        companion='scramble_query scramble_query_position scramble_match_shift scramble_match_call',
        removed='card_leave_tween',
        cards='radial_card_constructor radial_card_update',
        wheel='radial_direction_reader radial_direction_owner radial_binding_query radial_input_flag_reset camera_radial_gate camera_radial_gate_secondary wheel_constructor wheel_static_mode wheel_static_content wheel_label wheel_rotation wheel_cursor wheel_label_definition cooldown_label cooldown_number cooldown_hint_type controller_active_binding controller_stick_binding',
        icons='wheel_texture wheel_icon_definition icon_material_get icon_material_parameter icon_material_source icon_channel_palette',
        sprite='expanded_sprite_constructor expanded_sprite_asset expanded_arrow_uv',
        expanded='expanded_rotation_pivot expanded_sprite_color expanded_parent_transform',
        order='expanded_sprite_order',
        sound='ui_sound wheel_move_sound wheel_action_sound wheel_sound_ids',
        dock='dock_charge_group_layout dock_charge_text_layout dock_card_constructor dock_card_tick dock_charge_count',
        release='release_guarded_open release_close release_hold_test release_match_survives release_weapon_request release_weapon_request_assignment release_opener_slot_guard release_opener_slot_call',
    }
    local group_of={}
    for group,list in pairs(names) do
        for name in list:gmatch('%S+') do group_of[name]=group end
    end
    for _,g in ipairs(native_guards) do
        local group=group_of[g.name] or 'core'
        groups[group]=groups[group] or {}
        groups[group][#groups[group]+1]=g
    end
    local next_try,reasons={},{}
    return function(group,now)
        local pending=groups[group]
        if not pending then return true end
        if now<(next_try[group] or 0) then return false,reasons[group] end
        for i=#pending,1,-1 do
            local g=pending[i]
            local bytes=dock_guards[g.rva] or g.bytes
            if #bytes==0 or bridge.dbf_hud_guard(g.rva,bytes,#bytes)~=1 then
                reasons[group]=g.name
                next_try[group]=now+500
                return false,g.name
            end
            table.remove(pending,i)
        end
        groups[group]=nil
        return true
    end
end
local function native_backend(bridge,token)
    local ffi = require('ffi')
    if not pcall(ffi.typeof,'NSR_vec2') then
        ffi.cdef 'typedef struct { float x, y; } NSR_vec2;'
    end
    ffi.cdef [[
        void *GetCurrentProcess(void);
        int WriteProcessMemory(void *, void *, const void *, size_t, size_t *);
    ]]
    local kernel=ffi.load('kernel32')
    local process=kernel.GetCurrentProcess()
    local base=tonumber(bridge.dbf_hud_base())
    assert(base and base>0,'game.dll unavailable')
    local buffer,received=ffi.new('uint8_t[512]'),ffi.new('size_t[1]')
    local function read(address,size)
        if type(address)~='number' or address<65536 or address>=2^47 or size>512 then return nil end
        if bridge.dbf_hud_read(address,buffer,size)~=1 then return nil end
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
    local function tweening(card)
        local flags=u32(read(card,4),0)
        if not flags then return nil end
        if math.floor(flags/0x2000000)%2==0 then return false end
        local high=u32(read(card+0xac,4),0)
        if high then return math.floor(high/2)%0x800~=0 end
    end
    local function stock_card(address)
        local root=hud()
        if not root then return false end
        local list=root+0x395100+0x1040
        local index=(address-list-0x110)/0x3760
        return index>=0 and index<16 and index%1==0 and pointer(address+0xf0)==list
    end
    function backend.finish_removed(identity)
        if not backend.valid(identity) then return end
        local first=identity+0x395100+0x1150
        for i=0,15 do
            local card=first+i*0x3760
            if read(card+0x36f0,1)=='\0' and read(card+0x3728,1)=='\1' then
                local flags=u32(read(card,4),0)
                if flags and math.floor(flags/16)%2==1 and tweening(card)==false then
                    local scale=backend.get(card,'scale')
                    if scale and scale[2]~=0 then backend.set(card,'scale',{scale[1],0}) end
                end
            end
        end
    end
    function backend.set(address,property,value)
        assert(value[1]==value[1] and value[2]==value[2]
            and math.abs(value[1])<=100000 and math.abs(value[2])<=100000,'Invalid vector')
        if property=='scale' and stock_card(address) and tweening(address)~=false then return false end
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
        if open=='\0' and not include_closed then
            if not backend.valid(root) then return nil,'waiting for gameplay HUD hierarchy' end
            return {identity=root,open=false,hud_visible=hud_visible},'native menu closed'
        end
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
        local stamina_bounds,health_bounds=cooldown_bounds(root,pointer,geometry,viewport)
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
        return {identity=root,hud_visible=hud_visible,panel=panel,list=list,rows=rows,open=open=='\1',list_geometry=container,dock_rows=include_closed,dock_parent=root+0x258,stamina_bounds=stamina_bounds,health_bounds=health_bounds,dock_y=dock_y,dock_below_y=dock_below_y,dock_anchor=dock_anchor,center=center,geometry=string.format('viewport=%.1fx%.1f matrix=%s list=%.1fx%.1f matrix=%s',viewport.width,viewport.height,table.concat(viewport.matrix,','),container.width,container.height,table.concat(container.matrix,','))}
    end
    function backend.alloc_widget(bytes)
        local p=bridge.dbf_hud_widget_alloc(token,bytes)
        if p==nil then
            collectgarbage('collect')
            p=bridge.dbf_hud_widget_alloc(token,bytes)
        end
        assert(p~=nil,'Native HUD widget storage unavailable')
        return ffi.gc(p,bridge.dbf_hud_widget_drop)
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

return {native_backend=native_backend,wheel_admission=wheel_admission}
