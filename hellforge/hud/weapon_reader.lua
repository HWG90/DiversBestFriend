-- R50's bounded reader, rebound to the 25480438 weapon managers and stock HUD.
local Layout = {
    player=0x3326468, owner=0x346bf98, inventory=0x3326738, driver=0x3326660,
    selector=0x3326420, entity_map=0xf1aeb0, unit_map=0xf22ec8, records=0xf32f18,
}
local witnesses = {
    {0x755d50, "488b1d990fbd02"},
    {0x755dff, "488b4358488d14898b449004e92d010000"},
    {0x759f4c, "83fe020f8338fdffff4c8b0594cdbc02"},
    {0x759fb7, "498b4840488b0cc1e85c3ddaff85f6750e8b4040498904248bc6e9bcfcffff8b4044498904248bc6e9aefcffff"},
    {0x4fdd42, "4c8b1da78fe202"},
    {0x4fdd5b, "458b4b70418b5b78"},
    {0x4fdd74, "498b7b68418b7374"},
    {0x4fddc2, "4869c088000000490383a8000000"},
    {0x4fd8ef, "4c8b902028f10048b815ae47e17a14ae4748f7e1488bc1482bc248d1e84803c248c1e8056bc032442bc045"},
    {0x4fd95c, "4869c1880000004805200300004903c2c3"},
    -- Programmable option selectors and native definition-driven icon paths.
    {0x755f58, "695c75007d5c7500405d7500505d7500105e7500775e7500ea5e7500f85e7500095f75001a5f7500d95e75002b5f7500"},
    {0x755ed9, "488b43604b8d0c498b448804c1e80aeb50488b43604b8d0c498b448804eb42488b43604b8d0c498b448804c1e802eb31488b43604b8d0c498b448804c1e806eb20488b43604b8d0c498b448804c1e808eb0f488b43604b8d0c498b448804c1e80e83e003"},
    {0x75a4b4, "02a1750057a175008da275006ea3750038a2750001a27500aca175006ea375001da4750047a4750031a3750071a47500"},
    {0x75a0a0, "009d7500b79d7500659d75004c9f7500419f7500389f7500839e7500e49f750086a0750086a0750086a0750086a07500"},
    {0x759fe4, "83fe020f83a0fcffff4c8b05e4c6bc02"},
    {0x75a057, "498b4868488b0cc1e89cb0dbff85f6750d8b00498904248bc6e91dfcffff8b8040020000498904248bc6e90cfcffff"},
    {0x75a331, "488b8c2460010000e832f2daff85db7516488b80a0000000498903498bc34881c4300100005bc3488b80a8000000498903498bc34881c4300100005bc3"},
    {0x75a36e, "488b842460010000483d5f0100000f831f01000085c07509488d05d3d10603eb0a8bc0488b84c170767c03"},
    {0x75a409, "488b442430498903"},
    {0x75a41d, "488b8c2460010000e8363fdbff488bc8488d43084803c0488b04c1498903498bc34881c4300100005bc3488b8c2460010000e86c3edbff8bcb83e101488d0c89488b44c818498903498bc34881c4300100005bc3488b8c2460010000e8a222dbff8bcb83e1014869c978010000488b840858010000498903498bc34881c4300100005bc3"},
    {0x515122, "4c8b1daf15e102"},
    {0x51513b, "458b8b98000000418b9ba0000000"},
    {0x51515a, "498bbb90000000"},
    {0x5151b2, "4869c068020000490383d0000000"},
    {0x514c1f, "4c8b90802ef10048b8fb99d3e0ce8bd4f148f7e148c1ea0969c21e020000"},
    {0x514c91, "4869c1680200004805e02100004903c2"},
    {0x50e36f, "4c8b90d82cf10048b8a38b2ebae8a28b2e48f7e148c1ea026bc216442bc0"},
    {0x50e3cc, "488d044948c1e0064805600100004903c2c3"},
    {0x50e2cf, "4c8b90d02cf10048b88fe3388ee3388ee348f7e148c1ea048d04d203c044"},
    {0x50e33c, "486bc1584805200100004903c2c3"},
    {0x50c72f, "4c8b90882cf10048b8cdcccccccccccccc48f7e148c1ea038d049203c044"},
    {0x50c79c, "4869c1f00200004805a00000004903c2c3"},
    {0x50957f, "4c8b90d82bf10048b8379f711660f3196748f7e1488bc1482bc248d1e84803c248c1e80969c0da020000442bc045"},
    {0x5095f1, "4869c1d00400004805a02d00004903c2c3"},
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
    -- Native definition maps: 16-byte hash slots followed by fixed-size rows.
    -- Keys stay as eight bytes; no uint64 resource ID is rounded through a double.
    local function definition(owner,rec,offset,n,stride)
        local p=r.p(owner+offset);local key=rec:sub(1,8)
        local home=((r.u(rec,4)%n)*(2^32%n)+r.u(rec,0)%n)%n
        for probe=0,math.min(n,128)-1 do
            local row=r.read(p+((home+probe)%n)*16,16)
            if row:sub(1,8)==string.rep('\0',8) then return nil end
            if row:sub(1,8)==key then
                local i=r.u(row,8);assert(i<n and r.u(row,12)==0,'programmable definition index')
                return r.read(p+n*16+i*stride,stride),p+n*16+i*stride
            end
        end
        error('programmable definition probe limit')
    end
    local shifts={[8]=2,[9]=6,[10]=8,[11]=10,[12]=14}
    local specs={ [9]={0xf12cd8,22,0xc0},[10]={0xf12cd0,18,0x58},
        [11]={0xf12bd8,730,0x4d0},[12]={0xf12c88,10,0x2f0} }
    local function programmable(kind,word,owner,id,rec,checks)
        local selected=kind~=4 and math.floor(word/2^shifts[kind])%4 or nil
        local data,offset,projectile,data_at,source
        if kind==4 or kind==8 then
            local rounds=kind==4
            local global=rounds and 0x3326cf0 or 0x33266d8
            local m=r.p(base+global)
            local map,registry=rounds and 0x28 or 0x50,rounds and 0x40 or 0x68
            local component_index=component(m,map,registry,id,rec)
            assert(component_index,'programmable projectile component missing')
            local selector_at
            if rounds then
                selector_at=r.p(m+0x58)+component_index*20+4
                selected=r.u(r.read(selector_at,4),0)
            end
            assert(selected<2,'programmable selection outside native choices')
            local index=r.map(m+(rounds and 0x68 or 0x90),id,65536)
            local stride=rounds and 0x88 or 0x268
            if index then
                assert(index<4096,'programmable override index')
                data_at=r.p(m+(rounds and 0xa8 or 0xd0))+index*stride
                data=r.read(data_at,stride)
            else
                data,data_at=definition(owner,rec,rounds and 0xf12820 or 0xf12e80,rounds and 50 or 542,stride)
            end
            assert(data,'programmable projectile definition missing')
            projectile=r.u(data,rounds and (0x40+selected*4) or (selected==0 and 0 or 0x240))
            assert(projectile<0x15f,'programmable projectile out of range')
            local at=projectile==0 and base+0x37c7560 or r.p(base+0x37c7670+projectile*8)
            data=r.read(at+0x10,8);offset=0
            assert(r.p(base+global)==m and component(m,map,registry,id,rec)==component_index,
                'programmable projectile component changed')
            source=table.concat({m,component_index,tostring(index),data_at,at,tostring(selector_at)},':')
        else
            assert(selected<2,'programmable selection outside native choices')
            local spec=specs[kind]
            data,data_at=definition(owner,rec,spec[1],spec[2],spec[3])
            assert(data,'programmable icon definition missing')
            offset=kind==9 and (0x80+selected*16) or kind==10 and (0x18+selected*40)
                or kind==11 and (0xa0+selected*8) or (0x158+selected*0x178)
            source=tostring(data_at)
        end
        local lo,hi=r.u(data,offset),r.u(data,offset+4)
        assert(lo~=0 or hi~=0,'programmable icon missing')
        local item={kind=kind,index=selected,projectile=projectile,asset=string.format('%08x%08x',hi,lo)}
        -- Re-resolve the entire source before publication, including absent-to-
        -- present overrides, moved arrays, changed projectile IDs/catalog entries.
        if checks then checks[#checks+1]={kind=kind,word=word,item=item,source=source} end
        return item,source
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
        local ammo_checks={}
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
            local programmable_kinds={}
            if kinds[4] then programmable_kinds[#programmable_kinds+1]=4 end
            for kind=8,12 do if kinds[kind] then programmable_kinds[#programmable_kinds+1]=kind end end
            return {fire_mode=kinds[3]==true,rpm=kinds[2]==true,ammo_mode=#programmable_kinds>0,
                programmable_kinds=programmable_kinds,zoom=kinds[1]==true}
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
                local mode
                local ammo_options,errors={},{}
                for _,kind in ipairs(result.changeable.programmable_kinds or {}) do
                    local valid,item=pcall(programmable,kind,r.u(controls,4),owner,main_wid,main_rec,ammo_checks)
                    if valid then ammo_options[#ammo_options+1]=item else errors[#errors+1]=tostring(item) end
                end
                -- A mid-read selection change must never publish a stale glyph.
                assert(r.read(r.p(manager+0x60)+index*12,12)==controls,'programmable selection changed')
                assert(r.p(base+0x3326ce0)==manager and component(manager,0x30,0x48,main_wid,main_rec)==index,
                    'programmable control component changed')
                result.ammo_options=ammo_options
                if #errors>0 then result.ammo_error=table.concat(errors,'; ') end
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
        for _,check in ipairs(ammo_checks) do
            local current,source=programmable(check.kind,check.word,owner,main_wid,main_rec)
            assert(source==check.source and current.index==check.item.index and
                current.projectile==check.item.projectile and current.asset==check.item.asset,
                'programmable source changed during snapshot')
        end
        if control_address then
            local manager=r.p(base+0x3326ce0)
            local index=component(manager,0x30,0x48,main_wid,main_rec)
            assert(index and r.p(manager+0x60)+index*12==control_address,'weapon control component changed')
            local controls=r.read(control_address,12)
            assert(r.u(controls,0)==active_mode,'fire mode changed during snapshot')
            if result.binding.ammo_controls then
                assert(controls==result.binding.ammo_controls,'programmable selection changed during snapshot')
            end
        end
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
