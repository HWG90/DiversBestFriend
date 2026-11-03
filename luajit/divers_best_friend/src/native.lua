-- native_backend() is retried every second until the fingerprints pass, and
-- re-running cdef for a declared function still allocates C types that are
-- never freed (the shared table holds 65536). Each block runs once per load.
local bit=require('bit')
local declared={}
local function cdef_once(ffi,text)
    if not declared[text] then ffi.cdef(text);declared[text]=true end
end
-- Supported-build adapter. All drawing remains in the game's native HUD.
local function native_backend()
    local ffi = require('ffi')
    if not pcall(ffi.typeof,'NSR_vec2') then
        ffi.cdef 'typedef struct { float x, y; } NSR_vec2;'
    end
    cdef_once(ffi,[[
        void *GetModuleHandleA(const char *name);
        void *GetCurrentProcess(void);
        int ReadProcessMemory(void *, const void *, void *, size_t, size_t *);
        int WriteProcessMemory(void *, void *, const void *, size_t, size_t *);
    ]])
    local kernel=ffi.load('kernel32')
    local process=kernel.GetCurrentProcess()
    -- The runtime's shared memory API, when it provides version 1, does the reads
    -- and finds game.dll; kernel32 stays the fallback (and still does the writes).
    local has_runtime,runtime=pcall(require,'hd2.memory')
    local memory=has_runtime and type(runtime)=='table' and runtime.VERSION==1 and runtime or nil
    local runtime_read=memory and memory.read_into
    local base=memory and memory.module('game.dll')
        or tonumber(ffi.cast('uintptr_t',kernel.GetModuleHandleA('game.dll')))
    assert(base and base>0,'game.dll unavailable')
    local const_void_p=ffi.typeof('const void *')
    local buffer,received=ffi.new('uint8_t[512]'),ffi.new('size_t[1]')
    -- Scalar reads (pointers, u32 fields, flags) land here instead of in an
    -- interned Lua string; the per-frame HUD walk does dozens of them.
    local words=ffi.new('uint32_t[2]')
    local function fetch(address,size,into)
        if type(address)~='number' or address<65536 or address>=2^47 then return false end
        if runtime_read then return runtime_read(address,size,into) end
        return kernel.ReadProcessMemory(process,ffi.cast(const_void_p,address),into,size,received)~=0
            and tonumber(received[0])==size
    end
    local function read(address,size)
        if size>512 or not fetch(address,size,buffer) then return nil end
        return ffi.string(buffer,size)
    end
    local function u32(bytes,offset)
        if not bytes or #bytes<offset+4 then return nil end
        local a,b,c,d=bytes:byte(offset+1,offset+4)
        return a+b*256+c*65536+d*16777216
    end
    local function read_u32(address)
        if fetch(address,4,words) then return words[0] end
    end
    local function read_u64(address)
        if fetch(address,8,words) then return words[0]+words[1]*4294967296 end
    end
    local function read_u8(address)
        if fetch(address,1,buffer) then return buffer[0] end
    end
    local function pointer(address)
        if not fetch(address,8,words) then return nil end
        local p=words[0]+words[1]*4294967296
        if p<65536 or p>=2^47 or p%8~=0 then return nil end
        return p
    end
    local header=assert(read(base,64),'Cannot read PE header')
    assert(header:sub(1,2)=='MZ','Invalid DOS header')
    local pe=u32(header,60)
    assert(pe>=64 and pe<4096,'Invalid PE offset')
    header=assert(read(base+pe,32))
    assert(header:sub(1,4)=='PE\0\0' and u32(header,8)==1793123839,'Unsupported game build')
    -- Signatures include the native constructor/update layout witnesses as
    -- well as every called entry point. No executable bytes are changed.
    -- The protection runtime decrypts game code pages on first execution, so
    -- some witnesses read as unavailable until the game has run that code
    -- (e.g. stratagem list cards before the menu first opens). A readable
    -- mismatch still refuses the build; an unreadable witness is deferred and
    -- checked right before the first call that depends on it, never skipped.
    local pending={}
    for _, guard in ipairs(native_guards) do
        local bytes=read(base+guard.rva,#guard.bytes)
        if bytes==nil then pending[#pending+1]=guard
        else assert(bytes==guard.bytes,'Native signature changed: '..guard.name) end
    end
    -- A deferred witness belongs to the nearest bound entry point at or below
    -- it (its function body); witnesses with none within reach describe data
    -- layout and gate memory writes instead.
    local targets,reach={},0x4000
    local function owner(guard)
        local best
        for rva in pairs(targets) do
            if rva<=guard.rva and guard.rva-rva<reach and (not best or rva>best) then best=rva end
        end
        return best
    end
    local function settle(blocks)
        for i=#pending,1,-1 do
            local guard=pending[i]
            if blocks(guard) then
                local bytes=read(base+guard.rva,#guard.bytes)
                if bytes==nil then return false end
                assert(bytes==guard.bytes,'Native signature changed: '..guard.name)
                table.remove(pending,i)
            end
        end
        return true
    end
    local function code_ready(rva)
        if #pending==0 then return true end
        return settle(function(guard)return owner(guard)==rva end)
    end
    local function layout_ready()
        if #pending==0 then return true end
        return settle(function(guard)return owner(guard)==nil end)
    end
    local bound={}
    -- Every game function is bound here. Until its deferred witnesses pass,
    -- the binding is a guard that refuses the call instead of running it.
    local function bind(signature,rva)
        targets[rva]=true
        local ctype=ffi.typeof(signature)
        if code_ready(rva) then return ffi.cast(ctype,base+rva) end
        local fn
        local function call(...)
            if not fn then
                if not code_ready(rva) then error(string.format('0x%x: Native code not resident yet',rva)) end
                fn=ffi.cast(ctype,base+rva);bound[call]=nil
            end
            return fn(...)
        end
        bound[call]=rva
        return call
    end
    local specs={
        position={offset=4,rva=0x12df3b0}, size={offset=12,rva=0x12dee70},
        scale={offset=20,rva=0x12dfbe0}, anchor={offset=44,rva=0x12e6e70},
        pivot={offset=60,rva=0x12e6de0},
        animation_a={offset=0x3738}, animation_b={offset=0x3740},
    }
    for _,spec in pairs(specs) do
        if spec.rva then spec.call=bind('void (*)(uintptr_t, NSR_vec2)',spec.rva) end
    end
    local float_pair=ffi.new('float[2]')
    local vector=ffi.new('NSR_vec2')
    local read_pair=ffi.new('float[2]')
    local function pair_at(address)
        if not fetch(address,8,read_pair) then return nil end
        local x,y=read_pair[0],read_pair[1]
        if x~=x or y~=y or math.abs(x)>100000 or math.abs(y)>100000 then return nil end
        return {x,y}
    end
    local backend={}
    -- The path fetch reads through, named in the "native adapter ready" checkpoint.
    backend.memory=memory and 'hd2.memory v1' or 'kernel32'
    -- Writes rely on data-layout witnesses; refuse them while any is deferred.
    local function require_layout()
        if not layout_ready() then error('layout: Native code not resident yet') end
    end
    backend.fn=bind
    -- True when every given binding may run now (raw functions always may).
    function backend.callable(...)
        for i=1,select('#',...) do
            local rva=bound[select(i,...)]
            if rva and not code_ready(rva) then return false end
        end
        return true
    end
    function backend.deferred()
        local names={}
        for i,guard in ipairs(pending)do names[i]=guard.name end
        return names
    end
    local endpoint_owner
    local function hud()
        local root=pointer(base+0x2e28788)
        if not root or read_u8(root+0x24e334)~=1 then return nil end
        -- Only the gameplay HUD constructs this panel; frontend/ship layouts
        -- occupy the same larger owner and must not be interpreted as it.
        local state=pointer(base+0x2ce1508)
        if not state or read_u32(state+0xac29c)~=4 then return nil end
        return root
    end
    -- {child, parent, label} as offsets from the HUD root. valid() runs several
    -- times per frame, so the links are built once rather than per call.
    local panel_offset=0x24e340+0x146940
    local parent_links={{panel_offset,0x820,'panel'},
        {0x820,0x258,'HUD container'},
        {panel_offset+0x110,panel_offset,'fade container'},
        {panel_offset+0x220,panel_offset+0x110,'content container'},
        {panel_offset+0x1040,panel_offset+0x220,'list'}}
    function backend.valid(identity)
        if hud()~=identity then return false,'HUD owner changed' end
        local list=identity+panel_offset+0x1040
        for i=1,#parent_links do
            local link=parent_links[i]
            if pointer(identity+link[1]+0xf0)~=identity+link[2] then return false,link[3]..' parent mismatch' end
        end
        for index=0,15 do
            if pointer(list+0x110+index*0x3760+0xf0)~=list then return false,'card '..index..' parent mismatch' end
        end
        return true
    end
    -- Guarded widget_opacity stores its scalar at +0x44 (signature above).
    local opacity_call=bind('void (*)(uintptr_t, float)',0x12e07e0)
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
    local colour_call=bind('void (*)(uintptr_t, const float *)',0x12e03a0)
    -- The widget setters (position/size/scale/anchor/pivot, opacity, colour).
    function backend.widgets_ready()
        for _,spec in pairs(specs)do if spec.call and not backend.callable(spec.call)then return false end end
        return backend.callable(opacity_call,colour_call)
    end
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
        local raw=read(base+0x3180c08,8)
        local owner=raw and(u32(raw,0)+u32(raw,4)*4294967296)
        if owner and(owner<65536 or owner>=2^47-32)then owner=nil end
        local font,atlas,material=id(base+0x312d998),id(base+0x312e618),owner and id(owner+24)
        if not font or not atlas or not material then return nil end
        local I=sr.IdString64
        -- IdString64 values are frame-local engine temporaries. Retain only HEX
        -- strings; consumers must resolve each ID at the immediate API call.
        if not sr.Application.can_get('font',I.from_hex(font))or not sr.Application.can_get('texture',I.from_hex(atlas))or not sr.Application.can_get('material',I.from_hex(material))then return nil end
        return {font=font,atlas=atlas,material=material}
    end
    local transform=ffi.new('float[16]')
    function backend.dock_text_position(s,x,y)
        local size=assert(pair_at(s.dock_parent+0x24))
        assert(fetch(s.dock_parent+0x64,64,transform),'Dock transform unreadable');local m=transform
        x=x+size[1]/2
        return m[0]*x+m[8]*y+m[12],m[2]*x+m[10]*y+m[14]
    end
    function backend.get(address,property)
        return pair_at(address+specs[property].offset)
    end
    -- The list tweens a card's scale when its stratagem joins or leaves the
    -- list (0x16B96E3 -> 0x12E9B90). set_scale cancels that tween (flag
    -- 0x2000000, slot in +0xA8 bits 33..43, witness scale_tween_slot); a
    -- cancelled removal leaves the card drawn full size after it is gone.
    local function scale_tween(address)
        local flags=read_u32(address)
        if not flags or bit.band(flags,0x2000000)==0 then return false end
        local high=read_u32(address+0xac)
        return high~=nil and bit.band(bit.rshift(high,1),0x7ff)~=0
    end
    local function list_card(address)
        local root=hud()
        if not root then return false end
        local index=(address-(root+panel_offset+0x1150))/0x3760
        return index>=0 and index<16 and index%1==0
    end
    -- Returns false when a list card's scale is left to its running tween;
    -- callers read the scale back, so they follow it and apply once it ends.
    function backend.set(address,property,value)
        assert(value[1]==value[1] and value[2]==value[2]
            and math.abs(value[1])<=100000 and math.abs(value[2])<=100000,'Invalid vector')
        vector.x,vector.y=value[1],value[2]
        local spec=specs[property]
        if spec.call then
            if property=='scale' and list_card(address) and scale_tween(address) then return false end
            spec.call(address,vector)
        else
            -- Exactly two 8-byte vectors in validated native card objects.
            -- These are layout data, not code, input, or gameplay payloads.
            local root=hud()
            assert(root and root==endpoint_owner,'Animation owner changed')
            local index=(address-(root+0x24e340+0x146940+0x1150))/0x3760
            local original_card=index>=0 and index<16 and index%1==0
                and pointer(address+0xf0)==root+0x24e340+0x146940+0x1040
            assert(original_card or (backend.radial_card and backend.radial_card(address)),
                'Invalid animation card')
            float_pair[0],float_pair[1]=value[1],value[2]
            assert(read(address+spec.offset,8),'Animation data unavailable')
            require_layout()
            assert(kernel.WriteProcessMemory(process,ffi.cast('void *',address+spec.offset),
                float_pair,8,received)~=0 and tonumber(received[0])==8,'Animation write failed')
        end
    end
    -- Read the native visibility bits through the existing HUD snapshot.
    -- Screen-GUI labels do not inherit these widget ancestors themselves.
    local function shown(address)
        local flags=read_u32(address)
        return flags~=nil and bit.band(flags,16)~=0
    end
    -- A card whose stratagem left the list (+0x36F0 = 0, +0x3728 = 1) keeps its
    -- visible bit and ends its leave tween at scale height 0; a card reset for
    -- a new list has +0x3728 = 0 and is hidden. Removed, shown, taller than 0
    -- and not tweening means the leave tween was cancelled (see backend.set).
    function backend.removed_drawn_cards(identity)
        if not backend.valid(identity) then return nil end
        local list=identity+panel_offset+0x1040
        local found
        for index=0,15 do
            local card=list+0x110+index*0x3760
            if read_u8(card+0x36f0)==0 and read_u8(card+0x3728)==1 and shown(card) and not scale_tween(card) then
                local scale=backend.get(card,'scale')
                if scale and scale[2]~=0 then
                    found=found or {}
                    found[#found+1]={address=card,index=index,scale=scale}
                end
            end
        end
        return found
    end
    local matrix_lanes={0,2,8,10,12,14}
    function backend.snapshot(include_closed)
        local root=hud()
        if not root then return nil,'waiting for initialized gameplay HUD' end
        local hud_visible=shown(root+0x258) and shown(root+0x820)
        local panel=root+panel_offset
        local open=read_u8(panel+0x38769)
        if open==0 and not include_closed then return {identity=root,open=false,hud_visible=hud_visible},'native menu closed' end
        if open~=1 and open~=0 then return nil,'Invalid menu-open flag' end
        local valid,reason=backend.valid(root)
        if not valid then return nil,'HUD hierarchy not recognized: '..reason end
        endpoint_owner=root
        local list=panel+0x1040
        local function geometry(address)
            local size=pair_at(address+0x24)
            -- Native GUI matrices use X/Z for the two screen axes; Y is
            -- depth. Reading adjacent float pairs silently loses vertical
            -- scale/translation. Project both basis vectors and the origin.
            assert(size and fetch(address+0x64,64,transform),'Native transform unreadable')
            local matrix={}
            for i,index in ipairs(matrix_lanes) do
                local value=transform[index]
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
        local stamina_bounds
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
                    -- Transform the actual bar corners into the dock parent's
                    -- coordinates. Width comes from the live widget, including
                    -- booster expansion; never assume a centered fixed-width bar.
                    local left,right,bottom,top=math.huge,-math.huge,math.huge,-math.huge
                    for _,corner in ipairs({{0,0},{g.width,0},{0,g.height},{g.width,g.height}})do
                        local cx=m[1]*corner[1]+m[3]*corner[2]+m[5]-v[5]
                        local cy=m[2]*corner[1]+m[4]*corner[2]+m[6]-v[6]
                        local px=(cx*v[4]-cy*v[3])/det-viewport.width/2
                        local py=(cy*v[1]-cx*v[2])/det
                        left,right=math.min(left,px),math.max(right,px)
                        bottom,top=math.min(bottom,py),math.max(top,py)
                    end
                    stamina_bounds={left=left,right=right,bottom=bottom,top=top}
                    dock_anchor='native stamina bar'
                end
            end
        end
        -- Health row of the weapon panel (bottom-left): row box +24EED0 holds the
        -- health bar +252210; frame +24E3A0 under the weapon HUD container.
        -- Bounds in dock coordinates, as for the stamina bar; nil if the
        -- hierarchy differs, and the compact row then falls back to the dock.
        local health_bounds
        local frame,row_box,health=root+0x24e3a0,root+0x24eed0,root+0x252210
        if pointer(frame+0xf0)==root+0x820 and pointer(row_box+0xf0)==frame and pointer(health+0xf0)==row_box then
            local function bounds(node)
                local good,g=pcall(geometry,node)
                if not good or g.width<=0 or g.height<=0 or g.width>2000 or g.height>500 then return nil end
                local m,v=g.matrix,viewport.matrix
                local det=v[1]*v[4]-v[2]*v[3]
                if math.abs(det)<=0.000001 then return nil end
                local l,r,lo,hi=math.huge,-math.huge,math.huge,-math.huge
                for _,corner in ipairs({{0,0},{g.width,0},{0,g.height},{g.width,g.height}})do
                    local cx=m[1]*corner[1]+m[3]*corner[2]+m[5]-v[5]
                    local cy=m[2]*corner[1]+m[4]*corner[2]+m[6]-v[6]
                    local px=(cx*v[4]-cy*v[3])/det-viewport.width/2
                    local py=(cy*v[1]-cx*v[2])/det
                    l,r,lo,hi=math.min(l,px),math.max(r,px),math.min(lo,py),math.max(hi,py)
                end
                return {left=l,right=r,bottom=lo,top=hi}
            end
            local box,bar=bounds(row_box),bounds(health)
            if box and bar then health_bounds={left=bar.left,right=bar.right,bottom=box.bottom,top=box.top,box_left=box.left,box_right=box.right} end
        end
        local centered,center=pcall(radial.center,viewport,container)
        if not centered then return nil,'waiting for invertible list transform' end
        local rows={}
        for index=0,15 do
            local address=list+0x110+index*0x3760
            local active=read_u8(address+0x36f0)
            if active~=0 and active~=1 then return nil,'Invalid native card state' end
            if active==1 then
                local size=backend.get(address,'size')
                if not size or size[1]<=0 or size[1]>1200 or size[2]<=0 or size[2]>500 then
                    return nil,'Invalid native card dimensions'
                end
                local target=backend.get(address,'animation_b')
                if not target then return nil,'Native row layout unavailable' end
                rows[#rows+1]={address=address,width=size[1],height=size[2],entry=read_u32(address+0x3748),list_y=target[2],dock_source=address+0x7c0}
            end
        end
        -- Diagnostic text only; formatted when a status line asks for it.
        local geometry_text=setmetatable({},{__tostring=function()
            return string.format('viewport=%.1fx%.1f matrix=%s list=%.1fx%.1f matrix=%s',viewport.width,viewport.height,table.concat(viewport.matrix,','),container.width,container.height,table.concat(container.matrix,','))
        end})
        return {identity=root,hud_visible=hud_visible,panel=panel,list=list,rows=rows,open=open==1,dock_rows=include_closed,dock_parent=root+0x258,dock_y=dock_y,dock_below_y=dock_below_y,dock_anchor=dock_anchor,stamina_bounds=stamina_bounds,health_bounds=health_bounds,center=center,geometry=geometry_text}
    end
    local release_ui
    local function linked(address)
        return not fetch(address+0xf0,8,words) or words[0]~=0 or words[1]~=0
    end
    function backend.release_owned_ui(storage,address,identity,parent,retired)
        for _,old in ipairs(retired or {}) do
            local at=math.floor((tonumber(ffi.cast('uintptr_t',old))+31)/16)*16
            if linked(at) then return false,'Old HUD generation remains linked; restart required' end
        end
        if address then
            if backend.valid(identity) and pointer(address+0xf0)==parent then
                release_ui=release_ui or bind('void (*)(uintptr_t)',0x12e5a80)
                release_ui(address)
            end
            if linked(address) then return false,'Native UI root did not detach; restart required' end
        end
        return true
    end
    backend.read=read; backend.pointer=pointer; backend.u32=u32; backend.base=base
    backend.read_u32=read_u32; backend.read_u64=read_u64; backend.read_u8=read_u8
    local input_handler=bind('void (*)(uintptr_t)',0xaabb30)
    -- Parse anonymous function types once: repeated ffi.cast strings exhaust LuaJIT's type table.
    local open_input=bind('uint8_t (*)(uintptr_t)',0xaaa2b0)
    local close_input=bind('void (*)(uintptr_t)',0xaab5b0)
    local ui_sound=bind('void (*)(uintptr_t, uint32_t)',0x11bbaf0)
    local scramble_effect=bind('uintptr_t (*)(uintptr_t, uint32_t *, uint32_t, uint32_t, uintptr_t, uintptr_t)',0xa23710)
    local request_slot=bind('void (*)(uintptr_t, uint32_t)',0xaaf960)
    local byte=ffi.new('uint8_t[1]')
    -- verified: the caller checked its own witnesses for this address (terminal).
    function backend.pulse_byte(address,value,verified)
        if not verified then require_layout() end;byte[0]=value
        assert(kernel.WriteProcessMemory(process,ffi.cast('void *',address),byte,1,received)~=0
            and tonumber(received[0])==1,'Native action write failed')
    end
    function backend.invoke_input(component) input_handler(component) end
    function backend.replace_bytes(address,expected,replacement,verified)
        assert((#expected==4 or #expected==20) and #replacement==#expected,'Invalid binding edit size')
        if read(address,#expected)~=expected then return false end
        if not verified then require_layout() end
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
    local sound_events={move=0x39425a55,confirm=0xdd274583}
    function backend.ui_sound(event)
        local sound=assert(sound_events[event],'Unknown selection sound')
        local engine=assert(pointer(base+0x2ce14d8),'Audio engine unavailable')
        local game=assert(pointer(base+0x2ce1508),'Game state unavailable')
        assert(pointer(engine+0x290) and pointer(engine+0x340) and pointer(game+0x1178),'UI audio unavailable')
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
    cdef_once(ffi,'unsigned long long GetTickCount64(void);')
    function backend.milliseconds() return tonumber(kernel.GetTickCount64()) end
    cdef_once(ffi,[[
        void *GetForegroundWindow(void);
        unsigned long GetWindowThreadProcessId(void *, unsigned long *);
        unsigned long GetCurrentProcessId(void);
    ]])
    local user=ffi.load('user32')
    local foreground_pid=ffi.new('unsigned long[1]')
    local process_id=kernel.GetCurrentProcessId()
    function backend.focused()
        foreground_pid[0]=0
        user.GetWindowThreadProcessId(user.GetForegroundWindow(),foreground_pid)
        return foreground_pid[0]==process_id
    end
    return backend
end

return {native_backend=native_backend}
