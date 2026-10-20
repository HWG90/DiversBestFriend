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
    local mcm=rawget(_G,'DBFMCM')
    if state.excluded and not state.dirty and state.available_input==available
        and state.owner==menu and state.provider==mcm and state.ready then return state.excluded end
    state.dirty=false
    if state.owner and state.owner~=menu then
        if state.native then pcall(state.native.unregister) end
        state.native=nil;state.provider=nil;state.registered={}
    end
    state.owner=menu
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
        if state.owner~=menu then return end
        local next_value=value==true
        if (state.enabled[kind]==true)==next_value then return end
        state.enabled[kind]=next_value;state.dirty=true;state.save_pending=not state.save()
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
                local ok=menu.register_option(prefix..option.id,{mod="Diver's Best Friend",mod_id="hwg90.divers_best_friend",label=option.label,type='toggle',default=false,gap=kind==145,
                    description='Available on the ship. Prevents selection in List Select and hides it on wheels when present in your mission. Use MCM for additional blacklist entries.'})
                if ok then
                    menu.set(prefix..option.id,state.enabled[kind]==true)
                    local subscribe=dbf_menu_subscribe or function(m,id,fn)return m.on_change(id,fn)end
                    subscribe(menu,prefix..option.id,function(value)if not state.syncing then changed(kind,value,false)end end)
                    state.registered[kind]=true
                end
            end
        end
    end
    if state.provider~=mcm then
        if state.native then pcall(state.native.unregister)end
        state.native=nil;state.provider=mcm;state.registration_attempted=nil
    end
    if mcm and mcm.api==1 and type(mcm.register)=='function' and not state.native and not state.registration_attempted then
        state.registration_attempted=true
        local ids={};for kind in pairs(mission_blacklist_names)do ids[#ids+1]=kind end;table.sort(ids)
        local groups={
            {column=1,label='General',ids={49,145}},
            {column=1,label='Testing: support and extraction',ids={5,7,28,33,42,98,103,108,111,123,124,132,148}},
            {column=2,label='Testing: mission devices',ids={17,19,36,64,70,72,84,86,94,122,129}},
            {column=2,label='Testing: cargo, data and objectives',ids={11,29,48,71,76,78,79,85,102,128,138}},
        }
        local controls={}
        for _,group in ipairs(groups)do
          controls[#controls+1]={type='section',label=group.label,column=group.column}
          for _,kind in ipairs(group.ids)do
            local target=kind
            controls[#controls+1]={id='kind_'..kind,type='toggle',label=mission_blacklist_names[kind],column=group.column,default=state.enabled[kind]==true,
                description='Prevents selecting this mission-provided stratagem in List Select and hides it on wheels. Equipped stratagems and unreadable mission data remain protected.',
                on_change=function(value)if not state.syncing then changed(target,value,true)end end}
          end
        end
        local existing=type(mcm.mods)=='table' and mcm.mods.dbf_ass_blacklist
        local handle,ok
        if existing then
            local owned=existing.id=='dbf_ass_blacklist' and existing.name=="Diver's Best Friend - Blacklist"
                and existing.parent_name=="Diver's Best Friend" and type(existing.controls)=='table'
                and type(existing.handle)=='table' and type(existing.handle.set)=='function'
            local count=0
            if owned then
                for key,control in pairs(existing.controls) do
                    local kind=tonumber(key:match('^kind_(%d+)$'))
                    if not kind or not mission_blacklist_names[kind] or control.type~='toggle' then owned=false;break end
                    count=count+1
                end
                owned=owned and count==#ids
            end
            if owned then
                -- Reuse the exact DBF-owned schema after a provider/reload transition.
                -- Refresh callbacks in place; do not re-register or steal a foreign ID.
                for _,control in ipairs(controls) do if control.id then
                    existing.controls[control.id].on_change=control.on_change
                end end
                ok,handle=true,existing.handle
            else state.registration_error='MCM blacklist ID belongs to an unfamiliar owner' end
        else
            ok,handle=pcall(mcm.register,{id='dbf_ass_blacklist',name="Diver's Best Friend - Blacklist",parent_name="Diver's Best Friend",description='Additional blacklist entries are available here. Confirm applies pending selections.',pages={{id='blacklist',name='Blacklist',require_confirmation=true,controls=controls}}})
        end
        if ok and type(handle)=='table' and type(handle.set)=='function' then
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
    -- Keep the same exclusion object when availability was re-sampled unchanged.
    local prior=state.excluded
    local same=prior~=nil
    for kind in pairs(excluded) do if not prior or not prior[kind] then same=false;break end end
    if same then for kind in pairs(prior) do if not excluded[kind] then same=false;break end end end
    state.excluded=same and prior or excluded
    state.available_input=available
    state.ready=state.registered[145] and state.registered[49]
        and (not mcm or state.native~=nil or state.registration_attempted==true)
    return state.excluded
end
