-- Native wheel binding kinds 1/2 use direct stick vectors; mouse kinds
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
    local reader=b.fn('void (*)(uintptr_t, uintptr_t, float)',0x16ac4b0)
    local binding=b.fn('uintptr_t (*)(uintptr_t, uint64_t, uint8_t)',0x118c4e0)
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
        assert(b.pointer(b.base+0x2e287d0),'Native radial input state unavailable')
        local controls=assert(b.pointer(b.base+0x2e38250),'Native controls unavailable')
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
