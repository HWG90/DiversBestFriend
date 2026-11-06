-- Temporary, data-only diagnostic. No file contents are executed.
local function blur_probe(bridge, deps)
    deps=deps or {}
    local root
    if os and type(os.getenv)=='function' then
        local ok,value=pcall(os.getenv,'LOCALAPPDATA')
        if ok and type(value)=='string' and value~='' then root=value end
    end
    local path=root and (root..'/DBF/HellForge/blur-probe.txt')
    local read=deps.read or function()
        if not path or not io or type(io.open)~='function' then return end
        local opened,f=pcall(io.open,path,'rb');if not opened or not f then return end
        local ok,value=pcall(function() return f:read(64) end)
        local closed=pcall(function() f:close() end)
        if ok and closed then return value end
    end
    -- Keep expiry across orderly HUD module reloads; never extend a command's TTL.
    local state=deps.state or rawget(_G,'DBFBlurProbeCommand')
    if not state then state={};rawset(_G,'DBFBlurProbeCommand',state) end
    local lease,next_poll,chosen,signature
    local self={}
    local message
    local function log(value)
        if message~=value then message=value;bridge.dbf_hud_log('Blur probe: '..value) end
    end
    function self.hide()
        if lease then lease.release();lease=nil end
        signature=nil
    end
    local function step(now)
        if now<(next_poll or 0) then return end
        next_poll=now+250
        local command=read()
        local phase,index
        if type(command)=='string' and #command<64 then
            phase,index=command:match('^([0-3]) ([0-8])\n?$')
        end
        local canonical=phase and (phase..' '..index) or nil
        if canonical~=state.last then
            self.hide();state.last=canonical;chosen=nil;state.deadline=now+60000
        end
        if not canonical or phase=='0' or now>=state.deadline then
            self.hide();log(not canonical and 'off (missing/invalid command)' or phase=='0' and 'off' or 'expired');return
        end
        local sr=deps.sr or rawget(_G,'stingray')
        assert(sr and sr.Application and sr.Gui,'engine GUI unavailable')
        local app,G=sr.Application,sr.Gui
        local main=app.main_world()
        local worlds=app.worlds() or {}
        local live,others,keys={}, {}, {}
        for key in pairs(worlds) do keys[#keys+1]=key end
        table.sort(keys,function(a,b) if type(a)=='number' and type(b)=='number' then return a<b end return tostring(a)<tostring(b) end)
        for _,key in ipairs(keys) do
            local world=worlds[key]
            if not live[world] then
                live[world]=true
                if world~=main then others[#others+1]=world end
            end
        end
        local world=tonumber(index)==0 and main or others[tonumber(index)]
        if not world or not live[world] or chosen and chosen~=world then
            self.hide();log('world unavailable/changed; change command to rearm');return
        end
        chosen=world
        local w,h=G.resolution()
        assert(w and h and w>=320 and h>=320,'invalid resolution')
        if lease and (not lease.valid() or lease.world~=world) then self.hide() end
        local key=canonical..':'..w..':'..h
        if lease and signature==key then return end
        self.hide()
        lease=cooldown_gui_pool(sr,'DBFBlurProbeGuiPool').acquire(world,{})
        local gui,api=lease.gui,lease.api
        local c=style.tokens.colors.text
        local ink=sr.Color(c[4],c[1],c[2],c[3])
        local x,y=w/2-128,h/2-128
        local material='content/ui/shared/material/blur_background'
        -- Identical 256px square, same layer; bitmap uses XY plus layer,
        -- triangle uses XZ positions with a separate layer argument.
        if phase=='3' then
            assert(app.can_get('material',material),'blur material unavailable')
            assert(api.bitmap(gui,material,sr.Vector3(x,y,950),sr.Vector2(256,256),ink),'bitmap refused')
        else
            local a,b,c1,d=sr.Vector3(x,0,y),sr.Vector3(x+256,0,y),sr.Vector3(x+256,0,y+256),sr.Vector3(x,0,y+256)
            local function triangle(p,q,r,u,v,t)
                if phase=='1' then return api.triangle(gui,p,q,r,950,ink) end
                return api.triangle(gui,p,q,r,950,ink,material,u,v,t)
            end
            if phase=='2' then assert(app.can_get('material',material),'blur material unavailable') end
            local u,v,t,z=sr.Vector2(0,0),sr.Vector2(1,0),sr.Vector2(1,1),sr.Vector2(0,1)
            assert(triangle(a,b,c1,u,v,t),'triangle refused')
            assert(triangle(a,c1,d,u,t,z),'triangle refused')
        end
        if phase~='1' then
            local handle=assert(api.material(gui,material),'material binding refused')
            assert(sr.Material.set_scalar(handle,'desaturate',0)~=false,'scalar refused')
        end
        -- Separate solid reference outside sample bounds, never under the blur.
        assert(api.rect(gui,sr.Vector3(x-16,y,950),sr.Vector2(8,256),ink),'reference refused')
        lease.show();signature=key
        log('phase '..phase..' world '..index..' '..tostring(world)..' bounds '..x..','..y..',256,256 layer 950')
    end
    function self.step(now)
        local ok,why=pcall(step,now)
        if not ok then
            local cleaned,problem=pcall(self.hide)
            log('failed: '..tostring(why)..(cleaned and '' or '; cleanup pending: '..tostring(problem)))
        end
    end
    return self
end
return {blur_probe=blur_probe}
