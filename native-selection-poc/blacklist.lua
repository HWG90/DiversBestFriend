-- IDs are native stratagem kinds, never menu slots, names or direction codes.
local function stratagem_blacklist(values)
    local excluded={}
    if values.hide_sos==true then excluded[145]=true end
    for i=1,8 do
        local kind=values['blacklist_kind_'..i]
        if type(kind)=='number' and kind%1==0 and kind>=1 and kind<150 then excluded[kind]=true end
    end
    return excluded
end
local function blacklist_signature(excluded)
    local ids={}
    for kind=1,149 do if excluded[kind] then ids[#ids+1]=kind end end
    return table.concat(ids,',')
end
local function blacklist_snapshot(snapshot,excluded)
    if not snapshot or not snapshot.open then return snapshot end
    local filtered={}
    for key,value in pairs(snapshot) do filtered[key]=value end
    filtered.rows,filtered.excluded_rows={},{}
    for _,row in ipairs(snapshot.rows) do
        local target=excluded[row.kind] and filtered.excluded_rows or filtered.rows
        target[#target+1]=row
    end
    return filtered
end
-- Hide excluded stock rows only while DBF list mode is active. Do not touch
-- card membership, native availability, binding files or gameplay definitions.
local function blacklist_list_visibility(b)
    local saved={}
    local function same(a,c) return a and c and a[1]==c[1] and a[2]==c[2] end
    local function restore(item)
        if b.valid(item.identity) and same(b.get(item.address,'scale'),item.applied) then
            b.set(item.address,'scale',item.before)
        end
    end
    local self={}
    function self.restore()
        for _,item in pairs(saved) do restore(item) end
        saved={}
    end
    function self.step(snapshot)
        local active={}
        if snapshot and snapshot.open then
            for _,row in ipairs(snapshot.excluded_rows or {}) do active[row.address]=true end
        end
        for address,item in pairs(saved) do
            if not active[address] or item.identity~=snapshot.identity then restore(item);saved[address]=nil end
        end
        for address in pairs(active) do
            assert(b.valid(snapshot.identity),'Blacklist HUD changed')
            local current=assert(b.get(address,'scale'),'Excluded row scale unavailable')
            local item=saved[address]
            if not item then item={identity=snapshot.identity,address=address,before=current};saved[address]=item
            elseif not same(current,item.applied) then item.before=current end
            b.set(address,'scale',{0,0});item.applied={0,0}
        end
    end
    return self
end
