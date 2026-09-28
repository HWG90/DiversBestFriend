-- Temporarily give Display Stratagem List Press/toggle semantics. Unlike a
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
