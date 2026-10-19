-- Recognise Foliage Pass-Through's sole reviewed ProjectileInfo variant.
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
