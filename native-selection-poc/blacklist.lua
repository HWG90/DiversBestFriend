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
local function blacklist_snapshot(snapshot,excluded,keep_visible,hide_cooldown)
    if not snapshot or not snapshot.open then return snapshot end
    local filtered={}
    for key,value in pairs(snapshot) do filtered[key]=value end
    filtered.rows,filtered.excluded_rows={},{}
    filtered.native_rows=snapshot.rows
    for _,row in ipairs(snapshot.rows) do
        if keep_visible and excluded[row.kind]then
            local copy={};for key,value in pairs(row)do copy[key]=value end
            copy.blacklisted=true;row=copy
        end
        local hidden=(excluded[row.kind]and not keep_visible)or(hide_cooldown and row.timer_kind=='cooldown')
        local target=hidden and filtered.excluded_rows or filtered.rows
        target[#target+1]=row
    end
    return filtered
end
-- Compact the displayed stock list without changing native entry/kind identity.
-- Restore only values still owned by DBF, including both native animation endpoints.
local function blacklist_list_visibility(b)
    local saved={}
    local function same(a,c) return a and c and a[1]==c[1] and a[2]==c[2] end
    local function restore(item)
        if b.valid(item.identity) and same(b.get(item.address,item.property),item.applied) then
            b.set(item.address,item.property,item.before)
        end
    end
    local function key(address,property) return address..':'..property end
    local function baseline(address,property,identity)
        local current=assert(b.get(address,property),'Blacklist row geometry unavailable')
        local item=saved[key(address,property)]
        if item and item.identity==identity and same(current,item.applied) then return item.before end
        return current
    end
    local self={}
    function self.restore()
        for _,item in pairs(saved) do restore(item) end
        saved={}
    end
    function self.step(snapshot)
        local plan={}
        local function add(address,property,value)
            plan[key(address,property)]={address=address,property=property,value=value}
        end
        if snapshot and snapshot.open and #(snapshot.excluded_rows or {})>0 then
            assert(b.valid(snapshot.identity),'Blacklist HUD changed')
            -- Include hidden cards when finding the original top-to-bottom slots.
            -- Use saved native endpoints if the previous frame still has our values.
            local ordered={}
            for _,group in ipairs({snapshot.rows,snapshot.excluded_rows}) do
                for _,row in ipairs(group) do
                    ordered[#ordered+1]={row=row,target=baseline(row.address,'animation_b',snapshot.identity),
                        position=baseline(row.address,'position',snapshot.identity),animation_a=baseline(row.address,'animation_a',snapshot.identity)}
                end
            end
            table.sort(ordered,function(a,c)
                if a.target[2]~=c.target[2] then return a.target[2]>c.target[2] end
                if a.row.entry~=c.row.entry then return (a.row.entry or 0)<(c.row.entry or 0) end
                return a.row.address<c.row.address
            end)
            local excluded={}
            for _,row in ipairs(snapshot.excluded_rows) do
                excluded[row.address]=true;add(row.address,'scale',{0,0})
            end
            -- Native rows can be inserted/reordered during a transition. Their
            -- old endpoints may temporarily coincide; never reuse those as a
            -- set of compacted slots. Construct unique slots from row height.
            local y=ordered[1]and ordered[1].target[2]or 0
            for _,item in ipairs(ordered) do
                if not excluded[item.row.address] then
                    add(item.row.address,'position',{item.position[1],y})
                    add(item.row.address,'animation_a',{item.animation_a[1],y})
                    add(item.row.address,'animation_b',{item.target[1],y})
                    local scale=b.get(item.row.address,'scale')or{1,1}
                    y=y-(item.row.height or 68)*math.max(1,scale[2])
                end
            end
        end
        for id,item in pairs(saved) do
            if not plan[id] or item.identity~=snapshot.identity then restore(item);saved[id]=nil end
        end
        for id,change in pairs(plan) do
            assert(b.valid(snapshot.identity),'Blacklist HUD changed')
            local current=assert(b.get(change.address,change.property),'Blacklist row geometry unavailable')
            local item=saved[id]
            if not item then
                item={identity=snapshot.identity,address=change.address,property=change.property,before=current};saved[id]=item
            elseif not same(current,item.applied) then item.before=current end
            if not same(current,change.value)then b.set(change.address,change.property,change.value)end
            item.applied=assert(b.get(change.address,change.property),'Blacklist row geometry unavailable')
        end
    end
    return self
end
