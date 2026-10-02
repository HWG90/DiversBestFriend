local function source(n) local f=assert(io.open('native-selection-poc/'..n));local s=f:read('*a');f:close();return s end
local filter,make=assert(loadstring(source('blacklist.lua')..'\nreturn blacklist_snapshot,blacklist_list_visibility'))()
local select=assert(loadstring(source('input.lua')..'\n'..source('selection.lua')..'\nreturn selection_controller'))()
local idle={next=false,previous=false,confirm=false}
local confirm={next=false,previous=false,confirm=true}
local kinds={124,145,33,126,136,25}
local cases={{},{1},{3},{6},{1,3,5},{1,2,3,4,5,6}}
for _,removed in ipairs(cases) do
    local rows,values,original,excluded={},{},{},{}
    for i,kind in ipairs(kinds) do
        local address=i*100
        rows[i]={address=address,kind=kind,entry=i+3,list_y=-(i-1)*68}
        values[address]={scale={0.9,0.8},position={7,-(i-1)*68},animation_a={8,-(i-1)*68},animation_b={9,-(i-1)*68}}
        original[address]={}
        for property,v in pairs(values[address]) do original[address][property]={v[1],v[2]} end
    end
    for _,i in ipairs(removed) do excluded[kinds[i]]=true end
    -- Storage order differs from visual order; native entry indices have gaps.
    local snap={identity=1,open=true,rows={rows[3],rows[6],rows[1],rows[5],rows[2],rows[4]}}
    local backend={valid=function(id) return id==1 end,
        get=function(address,property) return values[address][property] end,
        set=function(address,property,v) values[address][property]={v[1],v[2]} end}
    local controller=make(backend)
    local filtered=filter(snap,excluded)
    local function check()
        controller.step(filtered)
        local slot=0
        for i,row in ipairs(rows) do
            if excluded[row.kind] then
                assert(values[row.address].scale[1]==0,'excluded row is hidden')
            else
                slot=slot+1
                for _,property in ipairs({'position','animation_a','animation_b'}) do
                    local expected=#removed>0 and -(slot-1)*68 or -(i-1)*68
                    assert(values[row.address][property][2]==expected,'remaining rows occupy contiguous original slots')
                    assert(values[row.address][property][1]==original[row.address][property][1],'preserve each native X component')
                end
                assert(row.entry==i+3 and row.kind==kinds[i] and row.list_y==-(i-1)*68,'never mutate row identity or source geometry')
            end
        end
        assert(#filtered.rows==slot and #snap.rows==6)
    end
    check();check();check() -- no cumulative movement when native layout has not run
    -- Native animation/layout may overwrite DBF's changes each update.
    for address,properties in pairs(original) do
        for property,v in pairs(properties) do values[address][property]={v[1],v[2]} end
    end
    check()
    filtered.list_order=true
    local started
    local selection=select({begin=function(kind) started=kind;return {kind=kind} end},function() end)
    local now=0
    for _,row in ipairs(rows) do
        if not excluded[row.kind] then
            -- Navigate the actual compacted list, then Confirm the corresponding kind.
            if not selection.selected then selection.step(filtered,idle,now) end
            assert(selection.selected==row.address,'selection follows packed visual order')
            selection.step(filtered,confirm,now+1);assert(started==row.kind,'Confirm retains native kind after packing')
            selection.job=nil
            selection.step(filtered,idle,now+2)
            selection.step(filtered,{next=true,previous=false,confirm=false},now+3)
            selection.step(filtered,idle,now+4);now=now+5
        end
    end
    if #filtered.rows==0 then selection.step(filtered,idle,now);assert(not selection.selected and not started) end
    controller.step(filter(snap,{}))
    for address,properties in pairs(original) do
        for property,v in pairs(properties) do
            assert(values[address][property][1]==v[1] and values[address][property][2]==v[2],'clearing blacklist restores geometry and scale')
        end
    end
    controller.step(filtered)
    values[600].position={12,345};controller.restore()
    assert(values[600].position[2]==345,'preserve a newer native/user position')
end
print('Blacklist compaction passed: first/middle/last/multiple/all removals, visual/storage order, repeated frames, native refresh, Confirm mapping, restoration and newer changes.')
