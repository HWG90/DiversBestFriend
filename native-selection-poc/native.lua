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
