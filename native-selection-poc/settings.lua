local function dbf_menu_subscribe(menu,id,fn)
    local broker=rawget(_G,'DBFMenuSubscriptions')
    if not broker then broker=setmetatable({}, {__mode='k'});rawset(_G,'DBFMenuSubscriptions',broker) end
    local rows=broker[menu]
    if not rows then rows={};broker[menu]=rows end
    local record=rows[id]
    if not record then
        record={}
        local callback=function(...) if record.fn then return record.fn(...) end end
        setfenv(callback,_G)
        if menu.on_change(id,callback)~=true then return false end
        rows[id]=record
    end
    record.fn=fn;record.owner=rawget(_G,'DiversBestFriend')
    return true
end
-- Original BSL Mod Options Menu strips unknown registration fields. Bind the
-- same DBF rules explicitly to MCM's authoritative imported handle as well.
local function dbf_mcm_conditions(menu,state)
    local mcm=rawget(_G,'DBFMCM')
    if not mcm or not mcm.mods or not state.condition_specs then return end
    if state.condition_mcm==mcm and state.condition_revision==mcm.revision then return end
    state.condition_mcm=mcm;state.condition_revision=mcm.revision
    local owner
    for _,mod in pairs(mcm.mods)do
        if mod.legacy and type(mod.name)=='string' and mod.name:upper()=="DIVER'S BEST FRIEND" then
            if owner then return end;owner=mod
        end
    end
    if not owner or not owner.handle or type(owner.handle.set_condition)~='function' then return end
    if state.condition_owner==owner then return end
    local keys={}
    for _,spec in ipairs(state.condition_specs)do
        for key,c in pairs(owner.controls)do
            if c.label==spec[3] or c.label==spec[2]..' / '..spec[3] then
                keys['native_stratagem_radial.'..spec[1]]=key
            end
        end
    end
    for id,rule in pairs(state.condition_rules)do
        local key=keys['native_stratagem_radial.'..id]
        if key then
            owner.handle.set_condition(key,{enabled_if=function(get)
                return rule(function(native_id)
                    local mapped=keys[native_id]
                    if mapped then return get(mapped)end
                    return menu.get(native_id)
                end)
            end})
        end
    end
    state.condition_owner=owner;state.condition_revision=mcm.revision
end
local function canary_settings(menu,api,radial,now)
    dbf_mcm_conditions(menu,api)
    if api.settings_menu==menu and api.cached and not api.dirty then
        if api.subscribed and not api.retry_registration then return api.cached end
        -- Old providers without notifications retain a bounded compatibility check.
        if now and now<(api.next_refresh or 0) then return api.cached end
    end
    if api.settings_menu~=menu then
        api.settings_menu=menu;api.subscriptions={};api.registered={};api.cached=nil
    end
    api.dirty=false;api.retry_registration=false
    api.next_refresh=(now or 0)+250
    local prefix='native_stratagem_radial.'
    local specs={
        {'enabled','Selection','Enable Mod','toggle',true},
        {'selection_mode_ordered','Appearance','Mode','choice',1,{'Wedge Wheel','List Select','Native wheel'}},
        {'selection_sounds','Selection','Sound feedback','toggle',true},
        {'experimental_layout','Appearance','Wedge Wheel layout','choice',2,{'Cards - copied list rows','Expanded wedges'},nil,nil,'Available while Wedge Wheel is selected.'},
        {'appearance_preset','Appearance','Preset','choice',1,{'Custom','Compact','Standard','Large'},nil,nil,'Custom uses the size sliders below. Other presets override sizes; opacity and colors stay independent.'},
        {'wheel_size','Appearance','Wheel size (%)','slider',100,70,130,5,'All radial layouts. Custom preset only.'},
        {'icon_size','Appearance','Icon size (%)','slider',100,70,130,5,'Native and expanded wheels. Relative to wheel size; Custom preset only.'},
        {'label_size','Appearance','Center label size (%)','slider',100,70,130,5,'Native and expanded wheels. Relative to wheel size; Custom preset only.'},
        {'native_opacity','Appearance','Native wheel opacity (%)','slider',100,0,100,5,'Native wheel only; background opacity. Selected highlight stays visible.'},
        {'wedge_darkness','Appearance','Expanded wedge darkness (%)','slider',70,0,100,5,'Expanded wedges only.'},
        {'wedge_opacity','Appearance','Wedge opacity (%)','slider',50,0,100,5,'Expanded wedges only; selected highlight stays visible.'},
        {'cooldown_timers','Appearance','Show cooldown timers','toggle',true,nil,nil,nil,'Show native remaining time on dock icons, using the game font.'},
        {'cooldown_timer','Appearance','Cooldown timer position','choice',2,{'Off','Above icon','Below icon','Inside icon'},nil,nil,'Position of regular cooldown timers. Short countdown style controls inbound, impact and brief cooldowns separately.'},
        {'short_timer_style','Appearance','Short countdown style','choice',2,{'Use cooldown position','Large inside icon'},nil,nil,'Separate style for inbound, impact and brief cooldown countdowns.'},
        {'dim_unselected','Appearance','Dim unselected stratagems','toggle',true,nil,nil,nil,'Dim unselected available entries in List Select. Native cooldown styling stays unchanged.'},
        {'hide_blacklisted_list','Appearance','Hide blacklisted stratagems','toggle',false,nil,nil,nil,'Hide blacklisted entries in List Select. Off keeps them visible but unselectable. Wheels always omit them.'},
        {'hide_cooldown_list','Appearance','Hide stratagems on cooldown','toggle',false,nil,nil,nil,'Hide cooldown entries in List Select. Inbound entries remain visible. Does not affect the cooldown dock or overview.'},
        {'brief_timer_limit','Appearance','Brief cooldown threshold','slider',10,1,30,1,'Cooldowns at or below this many seconds use the short countdown style.'},
        {'hide_closed_status','Appearance','Hide top-left status notices','toggle',true,nil,nil,nil,'Hide native inbound, impact and cooldown notices while the stratagem menu is closed. The open list stays complete.'},
        {'dock_gap','Appearance','Dock gap above stamina','slider',24,0,80,2,'Gap above the native stamina bar, in HUD units.'},
        {'cooldown_icons','Appearance','Show cooldown display','toggle',true,nil,nil,nil,'Show the chosen dock or overview. Off hides the display and stops its timer checks.'},
        {'cooldown_display','Appearance','Cooldown display style','choice',1,{'Icon dock','Compact overview'},nil,nil,'Use a compact vertical list of icons, status and native remaining times instead of the horizontal dock.'},
        {'short_status_placement','Appearance','Short status placement','choice',3,{'Together','Left of dock','Right of dock','Below stamina bar'},nil,nil,'Dock only. Separate inbound, impact, brief and per-charge cooldowns from longer cooldowns. Left/right adds a divider; below uses the stamina bar as the divider.'},
        {'track_unavailable','Appearance','Track unavailable / ineligible','toggle',false,nil,nil,nil,'Include native unavailable or ineligible stratagems in the cooldown display. No countdown is invented when the game supplies none.'},
        {'balance_separated_dock','Appearance','Center Cooldown Separator','toggle',true,nil,nil,nil,'Center the entire left/right separated bar. Off keeps the main cooldown group centered instead.'},
        {'release_selection_mode','Controller','Select on Release','choice',1,{'Automatic (controller)','On','Off'},nil,nil,'Automatic enables release selection for active controller input. On also enables mouse. Requires a Hold menu binding; center before releasing to cancel.'},
        {'input_interval_ms','Advanced','Input interval (ms)','slider',70,0,250,5,'Delay between directions. 0 sends one per frame; applies to the next code.'},
        {'randomize_input_delay','Advanced','Randomize input delay','toggle',false,nil,nil,nil,'Choose one delay between 70 and 240 ms for each stratagem use. Overrides the fixed delay.'},
        {'vertical_offset','Appearance','Radial vertical offset (down)','slider',0,-600,600,25,'Radial layouts: positive moves down. Leave at 0 for automatic centering.'},
    }
    -- DBF owns its dependencies; MCM evaluates them against draft values.
    -- Older options providers ignore this optional presentation metadata.
    local function value(get,key)return get('native_stratagem_radial.'..key)end
    local function wheel(get)return value(get,'selection_mode_ordered')~=2 end
    local function expanded(get)return value(get,'selection_mode_ordered')==1 and value(get,'experimental_layout')==2 end
    local function display(get)return value(get,'cooldown_icons')==true end
    local function dock(get)return display(get) and value(get,'cooldown_display')==1 end
    local function timers(get)return display(get) and value(get,'cooldown_timers')==true end
    local conditions={
        experimental_layout=function(get)return value(get,'selection_mode_ordered')==1 end,
        wedge_darkness=expanded,wedge_opacity=expanded,
        native_opacity=function(get)return value(get,'selection_mode_ordered')==3 end,
        wheel_size=function(get)return wheel(get) and value(get,'appearance_preset')==1 end,
        icon_size=function(get)return (expanded(get) or value(get,'selection_mode_ordered')==3) and value(get,'appearance_preset')==1 end,
        label_size=function(get)return (expanded(get) or value(get,'selection_mode_ordered')==3) and value(get,'appearance_preset')==1 end,
        vertical_offset=wheel,
        dim_unselected=function(get)return value(get,'selection_mode_ordered')==2 end,
        hide_blacklisted_list=function(get)return value(get,'selection_mode_ordered')==2 end,
        hide_cooldown_list=function(get)return value(get,'selection_mode_ordered')==2 end,
        input_interval_ms=function(get)return value(get,'randomize_input_delay')~=true end,
        cooldown_display=display,dock_gap=display,track_unavailable=display,cooldown_timers=display,
        short_status_placement=dock,
        balance_separated_dock=function(get)local position=value(get,'short_status_placement');return dock(get) and (position==2 or position==3) end,
        cooldown_timer=timers,short_timer_style=timers,brief_timer_limit=display,
    }
    api.condition_specs=specs;api.condition_rules=conditions
    local hidden={}
    -- Read the old toggle before registration; a saved On remains explicit On.
    if api.values==nil and menu.get(prefix..'release_selection_mode')==nil then
        api.values={release_selection_mode=menu.get(prefix..'select_on_release')==true and 2 or 1}
    end
    local values={}
    api.values=api.values or {}
    local previous
    local subscribed=type(menu.on_change)=='function'
    local previous_interval=api.values.input_interval_ms
    for _,s in ipairs(specs) do
        local spec={mod="Diver's Best Friend",mod_id="hwg90.divers_best_friend",label=s[2]..' / '..s[3],type=s[4],default=s[5],gap=previous~=s[2],description=s[9] or s[3]}
        spec.enabled_if=conditions[s[1]]
        if s[1]=='selection_mode_ordered' then
            local legacy=menu.get(prefix..'selection_mode')
            if legacy==1 or legacy==2 or legacy==3 then spec.default=4-legacy
            elseif legacy==4 then spec.default=1 end
        end
        if s[1]=='release_selection_mode' and api.values.release_selection_mode then spec.default=api.values.release_selection_mode end
        if s[4]=='choice' then spec.choices=s[6] end
        if s[4]=='slider' then spec.min=s[6];spec.max=s[7];spec.step=s[8] end
        if not hidden[s[1]] and not api.registered[s[1]] then api.registered[s[1]]=menu.register_option(prefix..s[1],spec)==true end
        if not hidden[s[1]] and not api.registered[s[1]] then api.retry_registration=true end
        local key=s[1]
        if subscribed and not hidden[key] and not api.subscriptions[key] then
            api.subscriptions[key]=dbf_menu_subscribe(menu,prefix..key,function()
                if api.settings_menu==menu then api.dirty=true end
            end)==true
        end
        if not hidden[key] then subscribed=subscribed and api.subscriptions[key]==true end
        local v=menu.get(prefix..s[1]);local valid=false
        if s[4]=='toggle' then valid=type(v)=='boolean'
        elseif type(v)=='number' and v==v then
            if s[4]=='choice' then valid=v%1==0 and v>=1 and v<=#s[6]
            else valid=v>=s[6] and v<=s[7]
                if s[1]:find('blacklist_kind_',1,true) then valid=valid and v%1==0 end
            end
        end
        if valid then api.values[s[1]]=v end
        if api.values[s[1]]==nil then api.values[s[1]]=spec.default end
        values[s[1]]=api.values[s[1]]
        if not hidden[s[1]] then previous=s[2] end
    end
    if previous_interval~=nil and previous_interval~=values.input_interval_ms and values.randomize_input_delay then
        if type(menu.set)=='function'then menu.set(prefix..'randomize_input_delay',false)end
        values.randomize_input_delay=false;api.values.randomize_input_delay=false
    end
    local presets={{values.wheel_size,values.icon_size,values.label_size},{85,100,95},{100,100,100},{115,110,110}}
    local sizes=presets[values.appearance_preset]
    radial.wheel_scale,radial.icon_scale,radial.label_scale=sizes[1]/100,sizes[2]/100,sizes[3]/100
    radial.native_opacity=values.native_opacity/100
    radial.full_color=true
    radial.wedge_darkness,radial.wedge_opacity=values.wedge_darkness,values.wedge_opacity
    radial.vertical_offset=values.vertical_offset
    values.selection_mode=4-values.selection_mode_ordered
    values.select_on_release=values.release_selection_mode==2
    values.controller_release_auto=values.release_selection_mode==1
    dbf_mcm_conditions(menu,api)
    api.cached=values;api.subscribed=subscribed
    return values
end
