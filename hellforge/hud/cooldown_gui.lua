-- One retained GUI per live world, with ownership outside reloadable render
-- closures. Every primitive is registered before another native call can fail.
-- A style switch/unload clears and parks the GUI; only the engine retires it
-- with its world. No native handles are reconstructed or used after retirement.
-- name selects an independent pool (one owner per world each); default is the dock's.
local function cooldown_gui_pool(sr,name)
    name=name or 'DBFCooldownGuiPool'
    local registry=rawget(_G,name)
    if type(registry)~='table' then registry={version=1,records={}};rawset(_G,name,registry)end
    assert(registry.version==1,'Unsupported cooldown GUI pool version')
    local G=sr.Gui
    local function live(world)
        for _,candidate in pairs(sr.Application.worlds()or{})do if candidate==world then return true end end
        return false
    end
    local function clear(record)
        if not live(record.world)then
            registry.records[record.world]=nil
            record.owner=nil;record.primitives={};return true
        end
        -- Hide first; a failing destroy must retain both the handle and ledger.
        record.failed=true
        G.set_visible(record.gui,false);record.visible=false
        for key,primitive in pairs(record.primitives)do
            G['destroy_'..primitive.kind](record.gui,primitive.id)
            record.primitives[key]=nil
        end
        G.reset(record.gui);record.failed=false
        return true
    end
    local function prune()
        for world,record in pairs(registry.records)do
            if not live(world)then
                record.owner=nil
                registry.records[world]=nil
            end
        end
    end
    local self={}
    function self.acquire(world,owner)
        assert(not owner.retired,'Retired cooldown GUI owner')
        prune();assert(live(world),'Cooldown GUI world retired')
        local record=registry.records[world]
        if record then
            if record.owner and record.owner~=owner then record.owner.retired=true end
            if record.owner or record.visible or record.failed or next(record.primitives)then clear(record)end
        else
            record={world=world,gui=assert(sr.World.create_screen_gui(world,'scale',1,1)),primitives={},visible=false,failed=true}
            -- Publish immediately, before font/material/primitive setup.
            registry.records[world]=record
            G.set_visible(record.gui,false);record.failed=false
        end
        record.owner=owner
        local api=setmetatable({},{__index=G})
        local function owned()return not owner.retired and record.owner==owner and registry.records[world]==record end
        for _,kind in ipairs({'text','rect','bitmap'})do
            api[kind]=function(gui,...)
                assert(owned() and not record.failed and gui==record.gui,'Cooldown GUI ownership changed')
                local id=G[kind](gui,...)
                if id~=nil and id~=false then record.primitives[kind..':'..tostring(id)]={kind=kind,id=id}end
                return id
            end
            api['destroy_'..kind]=function(gui,id)
                assert(owned() and gui==record.gui,'Cooldown GUI ownership changed')
                if id==nil then return end
                local key=kind..':'..tostring(id)
                if record.primitives[key]then
                    G['destroy_'..kind](gui,id);record.primitives[key]=nil
                end
            end
        end
        local lease={gui=record.gui,api=api,world=world}
        function lease.valid()return owned() and not record.failed and live(world)end
        function lease.show()
            assert(lease.valid(),'Cooldown GUI lease retired')
            if not record.visible then G.set_visible(record.gui,true);record.visible=true end
        end
        function lease.release()
            if not owned()then return true end
            clear(record);record.owner=nil;return true
        end
        return lease
    end
    function self.purge()
        prune()
        for _,record in pairs(registry.records)do
            if record.owner then record.owner.retired=true end
            clear(record);record.owner=nil
        end
        return true
    end
    registry.purge=self.purge
    return self
end

return {cooldown_gui_pool=cooldown_gui_pool}
