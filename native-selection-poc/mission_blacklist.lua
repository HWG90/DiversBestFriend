local mission_blacklist_names={
    [5]='ORBITAL ILLUMINATION FLARE',
    [7]='EXTRACTION BEACON',
    [11]='RAISE FLAG',
    [17]='BUG THUMPER',
    [19]='SEISMIC PROBE',
    [28]='SEAF Artillery',
    [29]='DARK FLUID BACKPACK',
    [33]='Resupply',
    [36]='OIL RIG EXTRACT',
    [42]='HELLBOMB',
    [48]='DATA JACK',
    [49]='Eagle Rearm',
    [64]='TCS 03 THUMPER',
    [70]='PROSPECTING DRILL',
    [71]='CARGO CONTAINER',
    [72]='BUG PLUG',
    [76]='Cyborg Carry Data',
    [78]='SHOULDER MOUNTED CAMERA',
    [79]='Carry Data',
    [84]='JAMMED PINATA',
    [85]='RAISE FLAG NO CLEAR AREA',
    [86]='REMOTE EXPLOSIVES',
    [94]='POISON DRILL',
    [98]='EMERGENCY EXTRACTION BEACON',
    [102]='MOBILE COMMS RELAY',
    [103]='Carpet Bombing Run',
    [108]='Scrambler',
    [111]='IMMEDIATE EXTRACTION BEACON',
    [122]='SPIRE STERILIZER',
    [123]='CALL IN DESTROYER',
    [124]='Reinforce',
    [128]='Upload Discovery',
    [129]='DRILLING CHARGE',
    [132]='Nuke',
    [138]='CARGO CONTAINER',
    [145]='SOS Beacon',
    [148]='EXTRACTION',
}
local function mission_blacklist_settings(menu,state,available)
    local prefix='native_stratagem_radial.'
    local simple={{kind=145,id='hide_sos',label='Blacklist SOS Beacon'},{kind=49,id='hide_eagle_rearm',label='Blacklist Eagle Rearm'}}
    if not state.enabled then
        state.enabled={}
        local loader=rawget(_G,'CowboyBingusModLoader');local data=os.getenv('LOCALAPPDATA')
        local dir=loader and loader.log_directory or (data and data..'/CowboyBingus/Helldivers2/Logs')
        local function read_values(name)
            local values={};local file=dir and io.open(dir..'/'..name,'rb')
            if file then for id,value in file:read('*a'):gmatch('([^\t\r\n]+)\t([^\r\n]*)')do values[id]=value end;file:close()end
            return values
        end
        local saved=read_values('DiversBestFriendBlacklist.log');local legacy=read_values('ModOptionsMenu.values')
        if saved.version=='2' then
            for key,value in pairs(saved)do local kind=tonumber(key);if mission_blacklist_names[kind] and value=='true'then state.enabled[kind]=true end end
        elseif saved.version=='1' then
            for index=1,3 do local kind=tonumber(saved[tostring(index)]);if mission_blacklist_names[kind]then state.enabled[kind]=true end end
        else
            for index=1,8 do local kind=tonumber(legacy[prefix..'blacklist_kind_'..index]);if mission_blacklist_names[kind]then state.enabled[kind]=true end end
            if legacy[prefix..'hide_sos']=='true'then state.enabled[145]=true end
            if legacy[prefix..'hide_eagle_rearm']=='true'then state.enabled[49]=true end
        end
        state.save=function()
            local current=rawget(_G,'CowboyBingusModLoader')
            local file=current and type(current.open_log)=='function' and current.open_log('DiversBestFriendBlacklist.log')
            if not file then return false end
            local ids={};for kind,value in pairs(state.enabled)do if value and mission_blacklist_names[kind]then ids[#ids+1]=kind end end;table.sort(ids)
            local lines={'version\t2\n'};for _,kind in ipairs(ids)do lines[#lines+1]=kind..'\ttrue\n'end
            local ok=file:write(table.concat(lines));file:close();return ok~=nil
        end
    end
    state.registered=state.registered or {}
    local function changed(kind,value,from_native)
        state.enabled[kind]=value==true;state.save_pending=not state.save()
        if state.syncing then return end
        state.syncing=true
        for _,option in ipairs(simple)do if option.kind==kind and state.registered[kind]then menu.set(prefix..option.id,value==true)end end
        if not from_native and state.native then state.native.set('kind_'..kind,value==true)end
        state.syncing=false
    end
    if type(menu.set)=='function' and type(menu.on_change)=='function'then
        for _,option in ipairs(simple)do
            if not state.registered[option.kind]then
                local kind=option.kind
                local ok=menu.register_option(prefix..option.id,{mod="Diver's Best Friend",label=option.label,type='toggle',default=false,gap=kind==145,
                    description='Available on the ship. Excludes this stratagem when present in your mission. Use MCM for additional blacklist entries.'})
                if ok then
                    menu.set(prefix..option.id,state.enabled[kind]==true)
                    menu.on_change(prefix..option.id,function(value)if not state.syncing then changed(kind,value,false)end end)
                    state.registered[kind]=true
                end
            end
        end
    end
    local mcm=rawget(_G,'DBFMCM')
    if state.provider~=mcm then
        if state.native then pcall(state.native.unregister)end
        state.native=nil;state.provider=mcm
    end
    if mcm and mcm.api==1 and type(mcm.register)=='function' and not state.native then
        local ids={};for kind in pairs(mission_blacklist_names)do ids[#ids+1]=kind end;table.sort(ids)
        local controls={}
        for _,kind in ipairs(ids)do
            local target=kind
            controls[#controls+1]={id='kind_'..kind,type='toggle',label='Blacklist '..mission_blacklist_names[kind],default=state.enabled[kind]==true,
                description='Excludes this mission-provided stratagem when present. Equipped stratagems and unreadable mission data remain protected.',
                on_change=function(value)if not state.syncing then changed(target,value,true)end end}
        end
        local ok,handle=pcall(mcm.register,{id='dbf_ass_blacklist',name="Diver's Best Friend - Blacklist",description='Additional blacklist entries are available here. Confirm applies pending selections.',pages={{id='blacklist',name='Blacklist',require_confirmation=true,controls=controls}}})
        if ok then
            state.native=handle
            -- The shared blacklist file is authoritative across both menus.
            state.syncing=true;for _,kind in ipairs(ids)do handle.set('kind_'..kind,state.enabled[kind]==true)end;state.syncing=false
        end
    end
    if state.save_pending==nil then state.save_pending=true end
    if state.save_pending then state.save_pending=not state.save()end
    local excluded={}
    for _,kind in ipairs(available or {})do
        if mission_blacklist_names[kind] and state.enabled[kind] and
            ((kind==145 or kind==49) and state.registered[kind] or state.native~=nil)then excluded[kind]=true end
    end
    return excluded
end
