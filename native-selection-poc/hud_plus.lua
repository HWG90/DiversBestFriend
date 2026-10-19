-- HUD+ 0.2.8 owns a second list and hides the vanilla group used by ASS.
-- Interpose at its feature boundary; never edit its settings or native memory.
local function hud_plus_compat(active)
    local self={status='HUD+ not detected',scans=0}
    local top,runtimes,seen_programs=nil,{},{}
    local pins={prepare='0f6d0b5c',observe='6eec2b6b',put='6be59f1a',
        vanilla='c5fd46ff',drop='057f16e2'}
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
        local ok,bytes=pcall(string.dump,fn,true) -- Strip chunk path/debug data.
        if not ok then return nil end
        local a,b=1,0
        for i=1,#bytes do a=(a+bytes:byte(i))%65521;b=(b+a)%65521 end
        return string.format('%08x',b*65536+a)
    end
    local function bind(program)
        local feature=member(member(program,'world_hud'),'stratagem')
        if not feature then return end
        for name,pin in pairs(pins) do
            if fingerprint(member(feature,name))~=pin then
                self.status='HUD+ stratagem adapter unsupported';return
            end
        end
        if type(member(feature,'inputs'))~='table' or type(member(feature,'list'))~='table' then return end
        local prepare,observe,put=feature.prepare,feature.observe,feature.put
        -- Instance methods only: no shared class mutation, per-frame discovery,
        -- option saves, or repeated opacity writes. HUD+ restores opacity and
        -- destroys its owned duplicate through its normal disabled path.
        feature.prepare=function(owner,enabled,...)
            if active() then enabled=false end
            return prepare(owner,enabled,...)
        end
        feature.observe=function(owner,enabled,...)
            if active() then enabled=false end
            return observe(owner,enabled,...)
        end
        feature.put=function(owner,...)
            if not active() then return put(owner,...) end
        end
        self.status='HUD+ 0.2.8 list/picker yield to ASS while enabled'
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
            if program and seen_programs[runtime]~=program then
                seen_programs[runtime]=program
                bind(program)
            end
        end
    end
    return self
end
