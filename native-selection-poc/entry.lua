local api={api=1,revision=46,enabled=true,mode=1,experimental_layout=1,status='initializing',count=0}
local MOD_NAME = "Diver's Best Friend"
rawset(_G,'DiversBestFriend',api)
-- Compatibility alias for existing diagnostics and duplicate-load detection.
rawset(_G,'NativeStratagemRadial',api)
local controller,failed,last_status
local initialized,recovering=false,false
local hud_compat=hud_plus_compat and hud_plus_compat(function()
    return api.enabled and initialized and not failed and not recovering
end)
local recovery_attempts=0
local backend,selection,input,duplicates,pointing,last_tick,list_controller,camera,active_mode
local auxiliary={}
local wheel,expanded,release_selection
local excluded,exclusion_signature,hidden_rows={},'',nil
local blacklist_release_blocked=false
local mission_blacklist_state={}
local next_blacklist_sample=0
local blacklist_menu_open,blacklist_hud,previous_excluded
local empty_excluded={}
local select_on_release=false
local controller_release_auto,controller_input=false,false
local input_interval_ms=70
local randomize_input_delay=false
local binding_owner={}
local selection_events={}
local native_events,native_seen={},{}
local function native_checkpoint(message)
    -- Persist first-pass call boundaries before entering native code. A CTD
    -- bypasses pcall and the ordinary end-of-frame status logger.
    if native_seen[message] then return end
    local loader=assert(rawget(_G,'CowboyBingusModLoader'),'Shared Loader unavailable')
    local file=assert(loader.open_log('DiversBestFriend-native.log'),'Cannot open native checkpoint log')
    native_events[#native_events+1]=message
    file:write(MOD_NAME..' R46 - Homecoming Update\n'..table.concat(native_events,'\n')..'\n')
    file:close()
    native_seen[message]=true
end
local binding_ids={next="native_stratagem_radial.next",previous="native_stratagem_radial.previous",confirm="native_stratagem_radial.confirm"}
for slot=1,4 do binding_ids['slot'..slot]='native_stratagem_radial.slot'..slot end
local function selection_report(message)
    -- Button telemetry must not overwrite the last actual confirmation result.
    if not message:find('; buttons=',1,true) then api.last_confirmation=message end
    selection_events[#selection_events+1]=message
    if #selection_events>12 then table.remove(selection_events,1) end
    api.last_selection=message
end
local migration_checked,migrate_expanded
local mode_names={'Native wheel','List Select','Wedge Wheel'}
local function report(status,force)
    api.status=status
    if status==last_status and not force then return end
    last_status=status
    pcall(function()
        local loader=rawget(_G,'CowboyBingusModLoader')
        if not loader or type(loader.open_log)~='function' then return end
        local file=loader.open_log('DiversBestFriend.log')
        if file then
            file:write(MOD_NAME..' R46 - Homecoming Update\nstatus='..status..'\ncount='..api.count..'\n')
            file:write('full_color_icons='..tostring(radial.full_color~=false)..'\n')
            file:write('wedge_darkness='..tostring(radial.wedge_darkness)..'; wedge_opacity='..tostring(radial.wedge_opacity)..'\n')
            file:write('centering='..tostring(api.centering or 'not sampled')..'; vertical_offset='..tostring(radial.vertical_offset)..'\n')
            file:write('pointing='..tostring(api.pointing_status)..'\n')
            file:write('mode='..mode_names[api.mode]..'; experimental_layout='..api.experimental_layout..'\n')
            file:write('before_latest_apply='..tostring(api.observation or 'not sampled')..'\n')
            file:write('selection='..tostring(api.selection_status)..'\nlast_result='..tostring(api.last_selection)..'\n')
            file:write('last_runtime_error='..tostring(api.last_runtime_error)..'; recovery_attempts='..recovery_attempts..'\n')
            file:write('last_confirmation='..tostring(api.last_confirmation)..'\n')
            file:write('select_on_release='..tostring(select_on_release)..'; release_status='..tostring(release_selection and release_selection.status)..'\n')
            file:write('input_interval_ms='..tostring(input_interval_ms)..'\n')
            file:write('last_open='..tostring(api.last_open)..'\nlast_block='..tostring(api.last_block)..'\n')
            file:write(table.concat(selection_events,'\n')..'\n')
            file:close()
        end
    end)
end
local settings_owner,settings_state
local sound_feedback,sounds_enabled
local function options(now)
    local menu=rawget(_G,'ModOptionsMenu')
    if type(menu)~='table' or menu.api~=1 or type(menu.register_option)~='function' or type(menu.get)~='function' then return end
    if migration_checked~=menu then
        migration_checked=menu
        migrate_expanded=menu.get('native_stratagem_radial.selection_mode')==4
        -- Registration rejects a saved choice 4 once the menu has only three
        -- choices. Read that one legacy value before registering, then migrate
        -- through the documented set API (which owns persistence).
        local loader=rawget(_G,'CowboyBingusModLoader')
        local directory=loader and loader.log_directory
        if not directory then
            local local_data=os.getenv('LOCALAPPDATA')
            if local_data then directory=local_data..'/CowboyBingus/Helldivers2/Logs' end
        end
        if directory then
            local file=io.open(directory..'/ModOptionsMenu.values','rb')
            if file then
                for id,value in file:read('*a'):gmatch('([^\t\r\n]+)\t([^\r\n]*)') do
                    if id=='native_stratagem_radial.selection_mode' and value=='4' then migrate_expanded=true end
                end
                file:close()
            end
        end
    end
    if settings_owner~=menu then settings_owner=menu;settings_state={registered={}} end
    local values=canary_settings(menu,settings_state,radial,now)
    api.enabled,api.mode,api.experimental_layout=values.enabled,values.selection_mode,values.experimental_layout
    api.cooldown_icons=values.cooldown_icons
    api.hide_blacklisted_list=values.hide_blacklisted_list
    api.hide_cooldown_list=values.hide_cooldown_list
    api.hide_closed_status=values.hide_closed_status
    radial.dock_gap=values.dock_gap
    radial.cooldown_display=values.cooldown_display
    radial.short_status_placement=values.short_status_placement
    radial.balance_separated_dock=values.balance_separated_dock
    radial.track_unavailable=values.track_unavailable
    radial.cooldown_timer=values.cooldown_timers and values.cooldown_timer or 1
    radial.short_timer_style=values.short_timer_style
    radial.dim_unselected=values.dim_unselected
    radial.brief_timer_limit=values.brief_timer_limit
    select_on_release,input_interval_ms,sounds_enabled=values.select_on_release,values.input_interval_ms,values.selection_sounds
    controller_release_auto=values.controller_release_auto
    randomize_input_delay=values.randomize_input_delay

    if migrate_expanded then
        api.mode,api.experimental_layout=3,2
        if type(menu.set)=='function' and menu.set('native_stratagem_radial.experimental_layout',2)
            and menu.set('native_stratagem_radial.selection_mode',3) and menu.set('native_stratagem_radial.selection_mode_ordered',1) then migrate_expanded=false end
    end
end

-- Programmatic owners that use a silent menu.set can invalidate explicitly.
function api.invalidate_settings()
    if settings_state then settings_state.dirty=true end
end

local function bindings()
    local menu=rawget(_G,'ModBindingsMenu')
    if type(menu)~='table' or menu.api~=1 or type(menu.version)~='number'
        or not (menu.version>=2) then
        api.selection_status='Requires Mod Bindings Menu v2 or newer'; return nil
    end
    local labels={next='Next stratagem',previous='Previous stratagem',confirm='Confirm stratagem',slot1='Equip stratagem slot 1',slot2='Equip stratagem slot 2',slot3='Equip stratagem slot 3',slot4='Equip stratagem slot 4'}
    local buttons={}
    auxiliary.binding_retry=auxiliary.binding_retry or {}
    local now=backend and backend.milliseconds() or 0
    api.hotkey_error=nil
    for _,key in ipairs({'next','previous','confirm','slot1','slot2','slot3','slot4'}) do
        local id=binding_ids[key]
        local optional=key:match('^slot')~=nil
        if binding_owner[id]~=menu then
            local retry=auxiliary.binding_retry[id]
            local ok,why
            if retry and retry.owner==menu and now<retry.at then why=retry.reason
            else
                ok,why=menu.register_binding(id,labels[key],nil,dbf_binding_options and dbf_binding_options(menu,key) or {category=MOD_NAME})
                if not ok then auxiliary.binding_retry[id]={owner=menu,at=now+1000,reason=why}end
            end
            if ok then binding_owner[id]=menu;auxiliary.binding_retry[id]=nil
            elseif not optional then api.selection_status='Binding unavailable: '..tostring(why);return nil
            else api.hotkey_error='Hotkey unavailable: '..tostring(why)end
        end
        if binding_owner[id]==menu then buttons[key]=menu.is_down(id) else buttons[key]=false end
        if key:match('^slot')then buttons[key]=buttons[key]==true end
        if type(buttons[key])~='boolean' then api.selection_status='Waiting for native bindings'; return nil end
    end
    return buttons
end
-- Only known transient HUD failures may retry. Memory guards, native ABI
-- failures and unknown errors remain fatal. Keep native allocations alive.
local transient_ui_errors={
    'Wheel HUD changed','Expanded HUD changed','HUD changed during radial construction',
    'Original list geometry unavailable','List row scale unavailable',
    'Widget became unreadable','Native transform unreadable','Degenerate list transform',
    'UI context manager unavailable','Original widget resource context unavailable',
    'HUD resource renderer unavailable','UI context stack is full','Animation owner changed',
}
local function transient_ui_error(message)
    for _,reason in ipairs(transient_ui_errors) do
        if message==reason or message:sub(-#reason-2)==': '..reason then return true end
    end
    return false
end
local function cleanup_ui()
    local errors={}
    local function clean(object,method,...)
        if not object then return end
        local ok,why=pcall(object[method],...)
        if not ok then errors[#errors+1]=method..': '..tostring(why) end
    end
    clean(release_selection,'reset')
    clean(selection,'step',nil,nil,0)
    clean(pointing,'reset')
    clean(camera,'release')
    clean(controller,'restore')
    clean(list_controller,'restore')
    clean(duplicates,'hide')
    clean(wheel,'hide')
    clean(expanded,'hide')
    clean(auxiliary.dock,'hide')
    clean(auxiliary.closed_notices,'restore')
    clean(hidden_rows,'restore')
    clean(auxiliary.binding_warning,'hide')
    radial.selected=nil;api.count=0
    return #errors==0,table.concat(errors,'; ')
end
-- Keep the assembled Lua 5.1 callback below its 60-upvalue limit.
local factories={native_backend=native_backend,blacklist_list_visibility=blacklist_list_visibility,camera_capture=camera_capture,input_backend=input_backend,selection_controller=selection_controller,selection_feedback=selection_feedback,release_controller=release_controller,duplicate_cards=duplicate_cards,native_pointing=native_pointing,emote_wheel=emote_wheel,expanded_wheel=expanded_wheel,cooldown_dock=cooldown_dock,cooldown_closed_notices=cooldown_closed_notices,dbf_binding_warning=dbf_binding_warning}
local function step()
    if failed then return end
    local ok,why=pcall(function()
        local now=backend and backend.milliseconds() or 0
        options(now)
        if not controller then
            backend=factories.native_backend()
            backend.checkpoint=native_checkpoint
            hidden_rows=factories.blacklist_list_visibility(backend)
            native_checkpoint('native adapter ready; menu not entered')
            controller=radial.controller(backend)
            list_controller=radial.list_controller(backend)
            camera=factories.camera_capture(backend)
            input=factories.input_backend(backend)
            selection=factories.selection_controller(input,selection_report)
            sound_feedback=factories.selection_feedback(backend,selection_report)
            release_selection=factories.release_controller(input,selection_report)
            duplicates=factories.duplicate_cards(backend)
            pointing=factories.native_pointing(backend)
            wheel=factories.emote_wheel(backend,duplicates,input)
            expanded=factories.expanded_wheel(backend,duplicates,input)
            if factories.cooldown_dock then auxiliary.dock=factories.cooldown_dock(backend,duplicates,input) end
            if factories.cooldown_closed_notices then auxiliary.closed_notices=factories.cooldown_closed_notices(backend)end
            if factories.dbf_binding_warning then auxiliary.binding_warning=factories.dbf_binding_warning() end
            initialized=true
        end
        if now==0 then now=backend.milliseconds() end
        if recovering then
            -- A missing/failed snapshot does not prove that the menu closed.
            -- Poll only; do not construct UI or replay the cancelled input.
            local sampled,current=pcall(backend.snapshot)
            if sampled and current and current.open==false then
                recovering=false;active_mode=nil;last_tick=nil
                blacklist_release_blocked=true
                report('UI recovered; reopen the stratagem menu',true)
            end
            return
        end
        local dt=last_tick and math.max(0.001,math.min((now-last_tick)/1000,0.05)) or 1/60
        last_tick=now
        local legacy=api.mode==3 and api.experimental_layout==1
        local expanded_layout=api.mode==3 and api.experimental_layout==2
        local active_key=api.mode..':'..(api.mode==3 and api.experimental_layout or 0)
        if active_mode~=active_key then
            controller.restore();list_controller.restore();duplicates.hide();wheel.hide();expanded.hide();pointing.reset();camera.release()
            selection.step(nil,nil,now)
            release_selection.reset()
            active_mode=active_key
        end
        local buttons=bindings()
        if not backend.focused() then buttons=nil; api.selection_status='Game is not foreground' end
        local snapshot=api.enabled and backend.snapshot() or nil
        if snapshot and snapshot.open and snapshot.center then
            api.centering=tostring(snapshot.geometry)..string.format(' local_center=%.2f,%.2f',snapshot.center[1],snapshot.center[2])
        end
        if snapshot and snapshot.open and (not blacklist_menu_open or blacklist_hud~=snapshot.identity) then
            api.invalidate_settings();options(now)
            local refreshed_key=api.mode..':'..(api.mode==3 and api.experimental_layout or 0)
            if refreshed_key~=active_mode then
                controller.restore();list_controller.restore();duplicates.hide();wheel.hide();expanded.hide();pointing.reset();camera.release()
                selection.step(nil,nil,now);release_selection.reset()
                active_mode=refreshed_key
                legacy=api.mode==3 and api.experimental_layout==1
                expanded_layout=api.mode==3 and api.experimental_layout==2
                snapshot=api.enabled and backend.snapshot() or nil
            end
        end
        if not api.enabled then snapshot=nil end
        local was_open=snapshot and snapshot.open
        local decorated,why=pcall(input.decorate,snapshot)
        if not decorated then snapshot=nil; buttons=nil; api.selection_status=tostring(why) end
        -- Release open-list geometry before the closed-menu dock takes row ownership.
        if snapshot and not snapshot.open then
            controller.restore();list_controller.restore();hidden_rows.restore()
        end
        if auxiliary.closed_notices then auxiliary.closed_notices.step(api.enabled and api.hide_closed_status and snapshot or nil)end
        if auxiliary.dock then
            if not api.enabled or not api.cooldown_icons or not snapshot then auxiliary.dock.hide();auxiliary.dock_snapshot=nil
            else
                -- Native cached timer changes expose no subscription here. Bound discovery
                -- to 4 Hz / 16 cards; animation runs only while positions are changing.
                if snapshot.open then auxiliary.dock_snapshot=snapshot;auxiliary.next_dock_sample=now+250
                elseif not auxiliary.next_dock_sample or now>=auxiliary.next_dock_sample or(auxiliary.dock_snapshot and auxiliary.dock_snapshot.open)then
                    auxiliary.next_dock_sample=now+250
                    local good,value=pcall(function()
                        local value=backend.snapshot(true)
                        input.decorate(value)
                        return value
                    end)
                    auxiliary.dock_snapshot=good and value or nil
                end
                if auxiliary.dock_snapshot then auxiliary.dock.sample(auxiliary.dock_snapshot,now);auxiliary.dock.draw(now,snapshot.hud_visible) else auxiliary.dock.hide() end
            end
        end
        if snapshot and snapshot.open and (not blacklist_menu_open or blacklist_hud~=snapshot.identity or now>=next_blacklist_sample) then
            next_blacklist_sample=now+1000
            local sampled,available=pcall(input.mission_blacklist_kinds)
            local menu=rawget(_G,'ModOptionsMenu')
            if menu and menu.api==1 then
                if mission_blacklist_state.menu~=menu then mission_blacklist_state={menu=menu} end
                mission_blacklist_state.available=sampled and available or nil
            end
        end
        blacklist_menu_open=snapshot and snapshot.open or false
        blacklist_hud=snapshot and snapshot.identity
        local menu=rawget(_G,'ModOptionsMenu')
        excluded=(menu and menu.api==1) and mission_blacklist_settings(menu,mission_blacklist_state,mission_blacklist_state.available) or empty_excluded
        local signature=exclusion_signature
        local filter_key=tostring(api.hide_blacklisted_list)..':'..tostring(api.hide_cooldown_list)
        if excluded~=previous_excluded or auxiliary.list_filter_key~=filter_key then
            signature=blacklist_signature(excluded)..':'..filter_key
            previous_excluded=excluded;auxiliary.list_filter_key=filter_key
        end
        if signature~=exclusion_signature then
            -- An applied edit cancels queued/armed input before any more pulses.
            selection.step(nil,nil,now);release_selection.reset()
            controller.restore();list_controller.restore();hidden_rows.restore()
            duplicates.hide();wheel.hide();expanded.hide();pointing.reset();camera.release()
            exclusion_signature=signature
            blacklist_release_blocked=true
        end
        snapshot=blacklist_snapshot(snapshot,excluded,api.mode==2 and not api.hide_blacklisted_list,api.mode==2 and api.hide_cooldown_list)
        local vector,paged
        local empty=snapshot and snapshot.open and #snapshot.rows==0
        if empty then selection.step(nil,nil,now);release_selection.reset() end
        if snapshot and snapshot.open and not empty and api.mode~=2 and not (release_selection.job and release_selection.job.finished) then
            native_checkpoint('first open snapshot accepted')
            local ready,context=pcall(input.view_context)
            if ready then
                if expanded_layout then
                    local original=snapshot
                    local changed
                    snapshot,changed=expanded.prepare(original)
                    wheel.prepare(original,nil,false)
                    if changed then pointing.reset();selection.step(nil,nil,now) end
                elseif legacy then
                    local original=snapshot
                    snapshot=duplicates.prepare(original,context,dt)
                    -- Reuse only the native wheel's cursor marker; the copied
                    -- rows are drawn by the original radial layout controller.
                    wheel.prepare(original,nil,false)
                else
                    local changed
                    snapshot,changed,paged=wheel.prepare(snapshot,buttons,selection.job~=nil or release_selection.job~=nil)
                    if changed then pointing.reset();selection.step(nil,nil,now) end
                end
                snapshot.pointer_only=true
                if buttons then
                    camera.capture()
                    -- Navigation edges were consumed as page changes by the wheel.
                    buttons.next,buttons.previous=false,false
                    local target
                    if not legacy and not expanded_layout then target=wheel.address end
                    local pointed,result=pcall(pointing.sample,context,dt,target)
                    if pointed then vector=result;controller_input=result.controller==true;api.controller_input=controller_input;api.pointing_status=string.format('x=%.3f y=%.3f',vector[1],vector[2])
                    else api.pointing_status=tostring(result);pointing.reset();camera.release();buttons=nil end
                else pointing.reset();camera.release() end
            else
                api.selection_status=tostring(context);buttons=nil;snapshot=nil
            end
        end
        if api.mode==2 or not snapshot or not snapshot.open or empty then
            duplicates.hide();wheel.hide();expanded.hide();pointing.reset();camera.release()
            if api.mode==2 then api.pointing_status='off; keybinding list mode' end
        end
        if snapshot and api.mode==2 then snapshot.list_order=true end
        if was_open and not buttons then api.last_block=api.selection_status end
        selection.interval_ms=input_interval_ms
        selection.randomize_delay=randomize_input_delay
        release_selection.randomize_delay=randomize_input_delay
        release_selection.interval_ms=input_interval_ms
        local previous=auxiliary.shortcut_buttons or {}
        for slot=1,4 do
            local key='slot'..slot;local down=buttons and buttons[key]==true
            if down and previous[key]==false and api.enabled and snapshot and not selection.job and not release_selection.job then
                local mcm=rawget(_G,'DBFMCM')
                if not(mcm and type(mcm.is_open)=='function'and mcm.is_open())then release_selection.shortcut(slot,snapshot,now)end
            end
            if buttons then previous[key]=down else previous[key]=nil end
        end
        auxiliary.shortcut_buttons=previous
        if not release_selection.job then selection.step(snapshot,buttons,now,vector) end
        release_selection.interval_ms=input_interval_ms
        release_selection.step(((select_on_release or (controller_release_auto and controller_input)) and api.mode~=2 or release_selection.job and release_selection.job.shortcut) and not blacklist_release_blocked and api.enabled and buttons~=nil,
            snapshot,selection.selected,now,selection.job~=nil or (buttons and buttons.confirm))
        if not was_open then blacklist_release_blocked=false end
        if release_selection.job then selection.selected=release_selection.job.address end
        sound_feedback.step(sounds_enabled and api.enabled and buttons~=nil,snapshot,selection.selected,
            release_selection.job or selection.job,now,api.mode==2,paged)
        if auxiliary.binding_warning then
            local required={}
            if api.mode==2 then required={'next','previous','confirm'}
            else
                if not (select_on_release or (controller_release_auto and controller_input)) then required={'confirm'} end
                if api.mode==1 and wheel.pages and wheel.pages>1 then
                    required[#required+1]='next';required[#required+1]='previous'
                end
            end
            auxiliary.binding_warning.step(api.enabled and snapshot~=nil and snapshot.hud_visible~=false,rawget(_G,'ModBindingsMenu'),binding_ids,required,now)
            api.binding_warning=auxiliary.binding_warning.status
        end
        radial.selected=selection.selected
        if buttons then api.selection_status=selection.status end
        if was_open then
            local rows={}
            for _,row in ipairs(snapshot and snapshot.rows or {}) do
                rows[#rows+1]=tostring(row.entry)..':'..tostring(row.kind)..':'..tostring(row.timer_kind or 'no-timer')..':'..tostring(row.unavailable)..':'..tostring(row.timer_seconds or '-')
            end
            api.last_open=api.selection_status..'; cards='..table.concat(rows,',')..
                '; selected='..tostring(selection.selected)..'; buttons='..
                (buttons and (tostring(buttons.next)..','..tostring(buttons.previous)..','..tostring(buttons.confirm)) or 'unavailable')
            if buttons and (buttons.next or buttons.previous or buttons.confirm) then
                if api.last_buttons~=api.last_open then selection_report(api.last_open) end
            end
            api.last_buttons=api.last_open
        end
        -- Never fall back to arranging the original list if preparation failed.
        if was_open then native_checkpoint('layout enter') end
        local display=api.mode==2 and list_controller or (expanded_layout and expanded or (legacy and controller or wheel))
        if api.mode~=2 and snapshot and snapshot.open and not empty then
            wheel.draw(selection.selected,vector,snapshot.rows,legacy or expanded_layout)
            if expanded_layout then wheel.caption(expanded.draw(selection.selected,snapshot.rows)) end
            local selected_row
            if not legacy then
                for _,row in ipairs(snapshot.rows) do
                    if row.address==selection.selected then selected_row=row;break end
                end
            end
            wheel.timer(selected_row)
        end
        display.step(api.enabled,empty and api.mode~=2 and {open=false} or snapshot or {open=false})
        if empty then api.selection_status='No selectable stratagems remain after filtering' end
        hidden_rows.step(api.enabled and api.mode==2 and snapshot or nil)
        if was_open then native_checkpoint('layout returned') end
        api.count=display.count
        api.observation=display.observation
        if snapshot and snapshot.open then recovery_attempts=0 end
        report(display.status,api.last_selection~=api.reported_selection)
        api.reported_selection=api.last_selection
    end)
    if not ok then
        api.last_runtime_error=tostring(why)
        local cleaned,cleanup_error=cleanup_ui()
        if initialized and cleaned and transient_ui_error(tostring(why)) and recovery_attempts<3 then
            recovery_attempts=recovery_attempts+1;recovering=true
            blacklist_release_blocked=true
            report('UI paused after transient error; close the stratagem menu to recover: '..tostring(why),true)
        else
            failed=true
            report('disabled after error: '..tostring(why)..(cleaned and '' or '; cleanup failed: '..cleanup_error),true)
        end
    end
end
local foliage_compat
local previous=rawget(_G,'update')
function api.shutdown()
    api.enabled=false
    local clean,why=cleanup_ui()
    if not clean then return false,why end
    if hud_compat then local ok,problem=hud_compat.close();if not ok then return false,problem end end
    for _,object in ipairs({wheel or false,expanded or false,auxiliary.dock or false,duplicates or false}) do
        if object and object.close then
            local ok,problem=object.close();if ok==false then return false,problem end
        end
    end
    if mission_blacklist_state.native then mission_blacklist_state.native.unregister();mission_blacklist_state.native=nil end
    local broker=rawget(_G,'DBFMenuSubscriptions') or {}
    for _,rows in pairs(broker) do for _,record in pairs(rows) do
        if record.owner==api then record.fn,record.owner=nil,nil end
    end end
    auxiliary.stopped=true
    if rawget(_G,'update')==auxiliary.wrapper then rawset(_G,'update',previous) end
    if rawget(_G,'DiversBestFriend')==api then rawset(_G,'DiversBestFriend',nil) end
    if rawget(_G,'NativeStratagemRadial')==api then rawset(_G,'NativeStratagemRadial',nil) end
    return true
end
local function after(...) step(); return ... end
update=function(...)
    if auxiliary.stopped then if type(previous)=='function' then return previous(...) end;return end
    if not foliage_compat and foliage_compatibility and backend then
        foliage_compat=foliage_compatibility(backend.read,function(at)
            local s=backend.read(at,8)
            if not s then return end
            local p=backend.u32(s,0)+backend.u32(s,4)*4294967296
            if p>=65536 and p<2^47 and p%4==0 then return p end
        end,backend.base,function(p) return tonumber(require('ffi').cast('uintptr_t',p)) end)
    end
    if foliage_compat and not foliage_compat.done then
        local ok,why=pcall(foliage_compat.refresh)
        api.foliage_compat=ok and foliage_compat.status or tostring(why)
    end
    -- Bind before the upstream HUD+ update; no unchanged-owner rescanning.
    if hud_compat then
        local ok,why=pcall(hud_compat.refresh,rawget(_G,'update'))
        api.hud_plus_compat=ok and hud_compat.status or tostring(why)
    end
    if type(previous)=='function' then return after(previous(...)) end
    return after()
end
auxiliary.wrapper=update
report('loaded; awaiting native HUD')
