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
    if not state.kinds then
        state.kinds={0,0,0}
        local loader=rawget(_G,'CowboyBingusModLoader')
        local dir=loader and loader.log_directory
        local data=os.getenv('LOCALAPPDATA')
        dir=dir or (data and data..'/CowboyBingus/Helldivers2/Logs')
        local function read_values(name)
            local file=dir and io.open(dir..'/'..name,'rb')
            local values={}
            if file then
                for id,value in file:read('*a'):gmatch('([^\t\r\n]+)\t([^\r\n]*)') do values[id]=value end
                file:close()
            end
            return values
        end
        local saved=read_values('DiversBestFriendBlacklist.log')
        local legacy=read_values('ModOptionsMenu.values')
        local used={};local next_slot=1
        if saved.version=='1' then
            for i=1,3 do
                local kind=tonumber(saved[tostring(i)])
                state.kinds[i]=mission_blacklist_names[kind] and kind or 0
            end
        else
            for i=1,8 do
                local kind=tonumber(legacy[prefix..'blacklist_kind_'..i])
                if mission_blacklist_names[kind] and not used[kind] and next_slot<=3 then
                    state.kinds[next_slot]=kind;used[kind]=true;next_slot=next_slot+1
                end
            end
            if legacy[prefix..'hide_sos']=='true' and not used[145] and next_slot<=3 then state.kinds[next_slot]=145 end
        end
        state.save=function()
            if not loader or type(loader.open_log)~='function' then return false end
            local file=loader.open_log('DiversBestFriendBlacklist.log')
            if not file then return false end
            local ok=file:write('version\t1\n1\t'..state.kinds[1]..'\n2\t'..state.kinds[2]..'\n3\t'..state.kinds[3]..'\n')
            file:close();return ok~=nil
        end
    end
    -- Bingus does not support replacing an option schema. Freeze kind/index
    -- mapping for this process; IDs, not choice indices, persist across restarts.
    if not state.choices and available and #available>0 then
        state.choices={'None'};state.ids={0};state.index={[0]=1}
        for _,kind in ipairs(available) do
            if mission_blacklist_names[kind] and not state.index[kind] then
                if #state.choices>=16 then state.overflow=true;break end
                state.choices[#state.choices+1]=mission_blacklist_names[kind]
                state.ids[#state.ids+1]=kind;state.index[kind]=#state.ids
            end
        end
        if #state.choices<2 then state.choices=nil end
    end
    state.registered=state.registered or {}
    if state.choices and type(menu.set)=='function' and type(menu.on_change)=='function' then
        for i=1,3 do
            local id=prefix..'mission_blacklist_'..i
            if not state.registered[i] then
                local ok=menu.register_option(id,{mod="Diver's Best Friend",label='Blacklist / Entry '..i,
                    type='choice',choices=state.choices,default=1,gap=i==1,
                    description='Mission-provided stratagems only. None clears this entry. Apply saves the native ID. Choices come from the first mission this session; restart to refresh for another mission. Equipped stratagems cannot be excluded.'})
                if ok then
                    if not state.index[state.kinds[i]] then state.kinds[i]=0 end
                    menu.set(id,state.index[state.kinds[i]] or 1)
                    local slot=i
                    menu.on_change(id,function(value)
                        state.kinds[slot]=state.ids[value] or 0
                        state.save_pending=not state.save()
                    end)
                    state.registered[i]=true
                end
            end
        end
        state.save_pending=state.save_pending==nil and true or state.save_pending
        if state.save_pending then state.save_pending=not state.save() end
    end
    local allowed={}
    for _,kind in ipairs(available or {}) do allowed[kind]=true end
    local excluded={}
    for i=1,3 do
        local kind=state.kinds[i]
        -- Unknown/unreadable mission ownership always leaves automation usable.
        if state.registered[i] and allowed[kind] and mission_blacklist_names[kind] then excluded[kind]=true end
    end
    return excluded
end
