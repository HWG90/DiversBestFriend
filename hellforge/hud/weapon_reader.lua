-- R50's bounded reader, rebound to the 25480438 weapon managers and stock HUD.
local Layout = {
    player=0x3326468, owner=0x346bf98, inventory=0x3326738, driver=0x3326660,
    selector=0x3326420, entity_map=0xf1aeb0, unit_map=0xf22ec8, records=0xf32f18,
}
local witnesses = {
    {0x607200, "488b0561f2d10283b88400000000"},
    {0x6066ed, "8b9410a8030000"},
    {0xfd9c93, "4c8b15fe224902"},
    {0xfd9cc5, "498b9ac82ef200"},
    {0xfd9d83, "498b9ab0aef100"},
    {0x9a83e0, "4c8b1551e39702"},
    {0x745db6, "488b1da308be02"},
    {0x744dc2, "4c8b0d271fbe02"},
    {0x744d02, "488b2d3f19be02"},
    {0x764efa, "4c8b15471ebc02"},
    {0x764f79, "8bc8498b4258488d1449807c9008000f94c0"},
    {0x75673a, "4c8b159f05bd02"},
    {0x617974, "488b1d5dedd002"},
    {0x1828099, "4c8b1540ecaf01458bc4458b5a38418b5a400fafd8458d"},
    {0x18280ea, "4c8b15cfe3af01458bc4458b5a38418b5a400fafd8458d"},
    {0x18281ee, "4869daf00300008b97d4bc000041b80200000049035a5849"},
    {0x1828220, "448b8358030000488d8424800000008b"},
    {0x182826c, "8b9358030000458bc348894c"},
    {0x182832c, "8b9350030000458bc348894c"},
    {0x18283ec, "8b9354030000458bc348894c"},
    {0x18284ac, "8b935c030000458bc348894c"},
    {0x759d00, "f30f108254010000488d442420f30f108a58010000f30f11442420f30f10825c0100008b"},
    {0x755c69, "488b43604b8d0c498b448804c1e804"},
    {0x755f3a, "83e003488b5c2448"},
    {0x12e97c6, "e895d25200498d5760498bcce8e92d1600"},
    -- Stock weapon row, curved backing and RGB-mask option sprite.
    {0x1816f0f, "41b001498d8fc0080000ba26020000e89df7ffff498d97c0080000498bcde88e56c3ff498bcde88653c3ff"},
    {0x181679b, "48b8bef4c41640c37e594084ed48ba585adabb3a489123488bcf480f45d04533c0e83f90"},
    {0x18167ce, "0f57d2ba900e684ce8352fc3ff"},
    {0x1818427, "498bd6498bcde88e41c3ff498bcde8863ec3ff"},
    {0x181855c, "ba28020000488bcbe8870cc3ff488bd3498bcee84c40c3ff"},
    {0x1828c26, "488d9f10010000488bcbe87b5ec1ff48ba7db4355ed81285354533c0488bcbe8b66bc2ff"},
    {0x1828cc8, "4c8d0591a09b00ba9e200177e8e70bc2ff"},
    {0x1828cfa, "4c8d05bfc69b00bace7737e14c8b4928488bc841ff5108"},
    {0x1829219, "ba7eb8a83a498bcf85c0740a4c"},
    {0x181aaa6, "4c8bc0ba7eb8a83af3410f1185cc560000e86456c3ff"},
    {0x14497d3, "4d8b512841ff5208"},
    {0x21e2d60, "cdcc4c3e000000000000000000000000"},
    {0x21e53c0, "0000803f000080bf"},
    {0x1817c38, "4d8db7f0270000498bcee8696ec2ff48bb33aea286a760f25a"},
    {0x181822c, "4d8db7602e0000498bcee87568c2ff"},
    {0x1818379, "498bd6498bcce83c42c3ff"},
    {0x181843a, "498d9fc8300000488bcbe86766c2ff4533c0488bd7488bcbe8a973c3ff"},
    {0x181984d, "488d8fc8300000c7452400000042488b5520"},
    {0x181aa9f, "498d8dc83000004c8bc0ba7eb8a83af3410f1185"},
    {0x12f0c17, "488d8f40e324004d8bc54c8d"},
}
local function bounded_memory(backend)
    local r={reads=0,bytes=0}
    function r.reset() r.reads,r.bytes=0,0 end
    function r.read(a,n)
        assert(type(a)=='number' and a==a and a%1==0 and a>=65536 and a+n<2^47,'invalid address')
        assert(n>0 and n<=4096,'invalid read size')
        r.reads,r.bytes=r.reads+1,r.bytes+n
        assert(r.reads<=512 and r.bytes<=65536,'read budget exceeded')
        local s=backend.read(a,n); assert(s and #s==n,'unreadable memory');return s
    end
    function r.u(s,o)
        local a,b,c,d=s:byte(o+1,o+4);assert(d,'short uint32');return a+b*256+c*65536+d*16777216
    end
    function r.i(s,o) local v=r.u(s,o);return v>=2^31 and v-2^32 or v end
    function r.f(s,o)
        local v=r.u(s,o);local sign=v>=2^31 and -1 or 1
        local e=math.floor(v/2^23)%256;local m=v%2^23
        assert(e~=255,'nonfinite float')
        return sign*(e==0 and m*2^-149 or (1+m/2^23)*2^(e-127))
    end
    function r.pointer(s,o)
        o=o or 0;local p=r.u(s,o)+r.u(s,o+4)*2^32
        assert(p>=65536 and p<2^47,'invalid pointer');return p
    end
    function r.p(a)return r.pointer(r.read(a,8),0)end
    function r.map(a,key,limit)
        local h=r.read(a,20);local n,empty,mult=r.u(h,8),r.u(h,12),r.u(h,16)
        if n==0 or key==empty or key==0xffffffff then return nil end
        assert(n<=limit and n>0,'invalid map capacity')
        local pow=n;while pow>1 and pow%2==0 do pow=pow/2 end
        assert(pow==1,'invalid map capacity')
        local p=r.p(a)
        -- Split multiplication keeps the low 32 bits exact under Lua doubles.
        local start=((key%65536)*(mult%65536)+((math.floor(key/65536)*(mult%65536)+(key%65536)*math.floor(mult/65536))%65536)*65536)%2^32
        for probe=0,math.min(n,128)-1 do
            local row=r.read(p+((start+probe)%n)*8,8);local k=r.u(row,0)
            if k==empty then return nil end
            if k==key then local index=r.u(row,4);if index~=0xffffffff then return index end;return nil end
        end
        error('map probe limit')
    end
    return r
end
local function selectable_fire_mode(control,choices)
    if not choices then return nil end
    local seen,count={},0
    for _,value in ipairs(choices) do
        if value>0 and value<=8 and not seen[value] then seen[value]=true;count=count+1 end
    end
    if count>1 and seen[control] then return ({[1]='AUTO',[2]='SEMI',[3]='BURST',[8]='ALT'})[control] end
end
local function flag(v,b) return math.floor(v/b)%2==1 end
local function weapon_reader(backend, bridge)
    local ffi = require('ffi')
    local buffer = ffi.new('uint8_t[4096]')
    local base = backend.base
    local checked = false
    local r = bounded_memory({read=function(address, size)
        if bridge.dbf_hud_read(address, buffer, size) == 1 then return ffi.string(buffer, size) end
    end})
    local self={status='starting'}
    local rpm_cache
    local function global(name) return r.p(base+Layout[name]) end
    local function component(m,map,registry,id,record)
        local index=r.map(m+map,id,65536)
        if not index then return nil end
        assert(index<4096,'component index')
        assert(r.read(r.p(r.p(m+registry)+index*8),24)==record,'component identity')
        return index
    end
    local function entity(owner,id)
        if not id or id==0 or id==0xffffffff then return nil end
        local index=r.map(owner+Layout.entity_map,id,1048576)
        if not index then return nil end
        assert(index<1048576,'entity index')
        local rec=r.read(owner+Layout.records+index*24,24)
        assert(r.u(rec,8)==id,'entity identity');return rec,owner+Layout.records+index*24
    end
    local function config(m,id,rec,owner)
        local i=r.map(m+0x70,id,65536)
        if i then
            assert(i<4096,'override index')
            return r.read(r.p(m+0xb0)+i*0x4d0,0x4d0)
        end
        local p=r.p(owner+0xf12bd8);local n=730;local key=rec:sub(1,8)
        local home=((r.u(rec,4)%n)*(2^32%n)+r.u(rec,0)%n)%n
        for probe=0,math.min(n,128)-1 do
            local row=r.read(p+((home+probe)%n)*16,16)
            if row:sub(1,8)==string.rep('\0',8) then return nil end
            if row:sub(1,8)==key then
                local i=r.u(row,8);assert(i<n and r.u(row,12)==0,'config index')
                return r.read(p+n*16+i*0x4d0,0x4d0)
            end
        end
        return nil
    end
    function self.validate()
        r.reset();assert(base == tonumber(bridge.dbf_hud_base()),'game module changed')
        local dos=r.read(base,64);assert(dos:sub(1,2)=='MZ','DOS signature')
        local pe=r.u(dos,0x3c);assert(pe<0x100000,'PE offset')
        local header=r.read(base+pe,0x80)
        assert(header:sub(1,4)=='PE\0\0','PE signature')
        assert(r.u(header,8)==0x6ab3b43f and r.u(header,0x50)==0x4744000,'unsupported game build')
        for _,s in ipairs(witnesses) do
            local bytes=s[2]:gsub('..',function(h) return string.char(tonumber(h,16)) end)
            assert(bridge.dbf_hud_guard(s[1],bytes,#bytes)==1, 'weapon layout mismatch at '..string.format('%x',s[1]))
        end
        checked=true;self.status='validated'
    end
    function self.snapshot()
        if not checked then self.validate() end
        r.reset()
        local pm=global('player');local n=r.read(pm+0x84,8)
        if r.u(n,0)==0 or r.u(n,4)==0 then return nil,'no local player' end
        local pl=r.read(r.p(pm+0xe8),24)
        assert(flag(pl:byte(21),1) and r.map(pm+0xd0,r.u(pl,8),64)==0,'local ownership')
        local unit=r.u(r.read(pm+0x3a8,4),0)
        if unit==0x7fff then return nil,'no avatar' end
        local owner=global('owner');local ai=r.map(owner+Layout.unit_map,unit,1048576)
        if not ai then return nil,'no avatar entity' end
        assert(ai<1048576,'avatar index')
        local avatar=r.read(owner+Layout.records+ai*24,24);local aid=r.u(avatar,8)
        assert(r.u(avatar,16)==unit and flag(avatar:byte(21),1),'avatar identity')
        local inv=global('inventory');local ii=component(inv,0x28,0x40,aid,avatar)
        if not ii then return nil,'no inventory' end
        assert(ii<r.u(r.read(inv+0x14,4),0),'inventory index')
        local inventory=r.read(r.p(inv+0x50)+ii*48,48);local slot=r.u(inventory,28)
        local offset=({[1]=0,[2]=4,[3]=8,[4]=16,[5]=16,[6]=12})[slot]
        local wid=offset and r.u(inventory,offset);local inventory_weapon=wid
        local lowered=false;local mounted=false
        local sm=global('selector');local si=r.map(sm+0x30,aid,1048576)
        if si then
            local live=r.u(r.read(sm+0x18,4),0);local cap=r.u(r.read(sm+0x10,4),0)
            assert(live<=cap and live<=262144 and si<live,'selector bounds')
            assert(r.read(r.p(r.p(sm+0x48)+si*8),24)==avatar,'selector identity')
            local at=r.p(sm+0x60)+si*0x1d0;local selected=r.u(r.read(at,4),0)
            -- Selector interpolation rates are NOT a reliable movement visibility signal.
            if selected~=0 and selected~=0xffffffff and selected~=aid then
                wid=selected;mounted=wid~=inventory_weapon
            end
        end
        local rec,record_address=entity(owner,wid);if not rec then return nil,'no selected weapon' end
        -- The machine gun uses the identity-checked magazine path below. Its
        -- inherited exclusion was removed after bounded live component checks.
        assert(mounted or flag(rec:byte(21),1),'weapon ownership')
        local main_rec,main_wid,main_address=rec,wid,record_address
        local control_address,active_mode
        local control_ok,address,mode=pcall(function()
            local control_manager=r.p(base+0x3326ce0)
            local control_index=component(control_manager,0x30,0x48,wid,rec)
            if not control_index then return nil end
            local count=r.u(r.read(control_manager+0x20,4),0)
            assert(count<=4096 and control_index<count,'weapon control bounds')
            local at=r.p(control_manager+0x60)+control_index*12
            return at,r.u(r.read(at,4),0)
        end)
        if control_ok then control_address,active_mode=address,mode end
        if active_mode==8 then
            local auxiliary=r.p(base+0x3326a38)
            local index=r.map(auxiliary+0x278,wid,4096)
            if not index or index>=4096 or not si then return nil,'alternate ammunition unavailable' end
            local state=r.read(r.p(auxiliary+0x2a0)+index*128,128)
            local ammo_id=r.u(state,0x64)
            local selector=r.read(r.p(sm+0x60)+si*0x1d0,5*0x50)
            local attached=false
            for slot=0,4 do
                if r.u(selector,slot*0x50)==wid and r.u(selector,slot*0x50+4)==ammo_id then attached=true end
            end
            if not attached then return nil,'alternate weapon attachment mismatch' end
            local ammo_rec,ammo_address=entity(owner,ammo_id)
            if not ammo_rec then return nil,'alternate weapon missing' end
            local owner_manager=r.p(base+0x3326730)
            local oi=component(owner_manager,0x18,0x30,ammo_id,ammo_rec)
            if not oi or r.u(r.read(r.p(owner_manager+0x38)+oi*4,4),0)~=aid then return nil,'alternate weapon owner mismatch' end
            wid,rec,record_address=ammo_id,ammo_rec,ammo_address
        end
        local driver=global('driver');local di=component(driver,0x28,0x40,wid,rec)
        if not di then return nil,'no weapon driver' end
        local driver_state=r.read(r.p(driver+0x50)+di*40,40)
        local flags=r.u(driver_state,0)
        local result={id=main_wid,unit_ref=r.u(main_rec,16),avatar_unit_ref=unit,resource_hex=string.format('%08x%08x',r.u(main_rec,4),r.u(main_rec,0)),lowered=lowered,alternate=mounted,reloadable=flag(flags,0x40)}
        if wid~=main_wid then result.ammo_resource_hex=string.format('%08x%08x',r.u(rec,4),r.u(rec,0));result.alternate_fire=true end
        -- Diagnostic values only. +0x0C is not yet a verified engine/Lua handle.
        -- All bytes below were already read for ownership and ammo selection.
        result.binding={module_base=base,record=main_address,candidate=r.u(main_rec,12),
            avatar_id=aid,avatar_record=owner+Layout.records+ai*24,avatar_candidate=r.u(avatar,12),driver_state=driver_state}

        result.changeable={}
        local options_ok,options=pcall(function()
            local settings
            for _,offset in ipairs({0x3326ce0,0x33264c0}) do
                local manager=r.p(base+offset)
                local index=component(manager,0x30,0x48,main_wid,main_rec)
                if index then settings=r.read(r.p(manager+0x58)+index*0x3f0,0x3f0);break end
            end
            if not settings then return {} end
            local kinds={}
            for _,offset in ipairs({0x350,0x354,0x358,0x35c}) do
                local kind=r.u(settings,offset);assert(kind<=12,'Unknown weapon option type')
                if kind>0 then kinds[kind]=true end
            end
            assert(r.read(main_address,24)==main_rec,'Weapon options entity changed')
            return {fire_mode=kinds[3]==true,rpm=kinds[2]==true,ammo_mode=kinds[11]==true,zoom=kinds[1]==true}
        end)
        if options_ok then result.changeable=options else result.options_error=tostring(options) end
        if not (result.changeable.fire_mode or result.changeable.rpm or result.changeable.ammo_mode or result.changeable.zoom)then self.status='ok';return result end
        do
            -- Optional mode metadata must not suppress otherwise valid ammunition.
            local ok,mode,fire_mode,safety_mode=pcall(function()
                local manager=r.p(base+0x3326ce0)
                local index=component(manager,0x30,0x48,main_wid,main_rec)
                if not index then return nil end
                local count=r.u(r.read(manager+0x20,4),0)
                assert(count<=4096 and index<count,'ammo control bounds')
                local controls=r.read(r.p(manager+0x60)+index*12,12)
                result.binding.ammo_controls=controls
                assert(r.read(main_address,24)==main_rec,'ammo control weapon changed')
                local selector=r.u(controls,4)
                if math.floor(selector/0x1000)%2==1 then selector=selector-0x1000 end
                local mode
                if result.resource_hex=='a8cffb316f0b5c5f' then
                    mode=({[0x50]='APHET',[0x54]='FLAK'})[selector]
                elseif result.resource_hex=='26e40437ea275296' and selector==0x50 then
                    mode='FLAK'
                end
                local settings=config(manager,main_wid,main_rec,owner)
                if result.changeable.zoom and settings then
                    local distinct={};local count=0
                    for i=0,2 do
                        local value=r.f(settings,0x154+i*4)
                        assert(value>=0 and value<=10000,'Zoom slot range')
                        if value>0 and not distinct[value]then distinct[value]=true;count=count+1 end
                    end
                    local selected=math.floor(r.u(controls,4)/16)%4
                    if count>1 and selected<3 then
                        local value=r.f(settings,0x154+selected*4)
                        if value>0 then result.zoom=value;result.zoom_index=selected end
                    end
                end
                local choices=settings and {r.u(settings,0x90),r.u(settings,0x94),r.u(settings,0x98)}
                local fire_mode=result.alternate_fire and 'ALT' or selectable_fire_mode(r.u(controls,0),choices)
                if (result.resource_hex=='72170a55a1f37ff1' or result.resource_hex=='2b28e17ffed05f7c') and r.u(controls,0)==4 then fire_mode='VOLLEY' end
                local safety_mode=result.resource_hex=='2e9d0bdc48b09e60' and ({[5]='SAFE',[6]='UNSAFE'})[r.u(controls,0)] or nil
                return mode,fire_mode,safety_mode
            end)
            if ok then result.ammo_mode=mode;result.fire_mode=fire_mode;result.safety_mode=safety_mode else result.mode_error=tostring(mode) end
        end
        do
            local ok,rpm=pcall(function()
                local manager=r.p(base+0x33266d8)
                local count=r.u(r.read(manager+0x38,4),0)
                assert(count>0 and count<=384,'RPM component bounds')
                local entities=r.p(manager+0x68)
                local index
                if rpm_cache and rpm_cache.manager==manager and rpm_cache.index<count and
                    r.p(entities+rpm_cache.index*8)==main_address then index=rpm_cache.index end
                if not index then
                    local pointers=r.read(entities,count*8)
                    for i=0,count-1 do
                        local ptr=r.u(pointers,i*8)+r.u(pointers,i*8+4)*2^32
                        if ptr==main_address then index=i;break end
                    end
                end
                if not index then return nil end
                rpm_cache={manager=manager,index=index}
                local data=r.read(r.p(manager+0x70)+index*0x20,0x20)
                local selected=r.u(data,0x1c);result.rpm_index=selected;assert(selected<3,'RPM selected index')
                local enabled=0;local distinct_rates={}
                for i=0,2 do local rate=r.f(data,0x10+i*4);assert(rate>=0 and rate<=10000,'RPM slot range');if rate>0 and not distinct_rates[rate] then distinct_rates[rate]=true;enabled=enabled+1 end end
                if enabled<2 then return nil end
                local rate=r.f(data,0x10+selected*4)
                assert(rate>0 and r.read(main_address,24)==main_rec,'RPM weapon changed')
                assert(r.read(r.p(manager+0x70)+index*0x20+0x1c,4)==data:sub(29,32),'RPM selection changed')
                return rate
            end)
            if ok and rpm then result.rpm=rpm;result.rpm_selectable=true elseif not ok then result.rpm_error=tostring(rpm) end
        end
        if control_address then assert(r.u(r.read(control_address,4),0)==active_mode,'fire mode changed during snapshot') end
        assert(r.read(main_address,24)==main_rec, 'weapon changed during snapshot')
        self.status='ok';return result
    end
    function self.poll()
        local ok,value,reason=pcall(self.snapshot)
        if not ok then self.status=tostring(value);return nil end
        self.status=reason or 'ok';return value
    end
    return self
end
return {weapon_reader=weapon_reader}
