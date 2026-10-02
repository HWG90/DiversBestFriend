local api={api=1,revision=36,enabled=true,mode=1,experimental_layout=1,status='initializing',count=0}
local MOD_NAME = "Diver's Best Friend"
rawset(_G,'DiversBestFriend',api)
-- Compatibility alias for existing diagnostics and duplicate-load detection.
rawset(_G,'NativeStratagemRadial',api)
local controller,failed,last_status
local frames=0
local backend,selection,input,duplicates,pointing,last_tick,list_controller,camera,active_mode
local wheel,expanded,release_selection
local excluded,exclusion_signature,hidden_rows={},'',nil
local blacklist_release_blocked=false
local select_on_release=false
local input_interval_ms=70
local binding_owner={}
local selection_events={}
local native_events,native_seen={},{}
local function native_checkpoint(message)
    -- Persist first-pass call boundaries before entering native code. A CTD
    -- bypasses pcall and the ordinary end-of-frame status logger.
    if native_seen[message] then return end
    local loader=assert(rawget(_G,'CowboyBingusModLoader'),'Shared Loader unavailable')
    local file=assert(loader.open_log('DiversBestFriendCanary-native.log'),'Cannot open native checkpoint log')
    native_events[#native_events+1]=message
    file:write(MOD_NAME..' Canary R36 - Blacklist\n'..table.concat(native_events,'\n')..'\n')
    file:close()
    native_seen[message]=true
end
local binding_ids={next="native_stratagem_radial.next",previous="native_stratagem_radial.previous",confirm="native_stratagem_radial.confirm"}
local function selection_report(message)
    -- Button telemetry must not overwrite the last actual confirmation result.
    if not message:find('; buttons=',1,true) then api.last_confirmation=message end
    selection_events[#selection_events+1]=message
    if #selection_events>12 then table.remove(selection_events,1) end
    api.last_selection=message
end
local migration_checked,migrate_expanded
local mode_names={'Native wheel','Keybindings - list','Experimental'}
local function report(status,force)
    api.status=status
    if status==last_status and not force then return end
    last_status=status
    pcall(function()
        local loader=rawget(_G,'CowboyBingusModLoader')
        if not loader or type(loader.open_log)~='function' then return end
        local file=loader.open_log('DiversBestFriendCanary.log')
        if file then
            file:write(MOD_NAME..' Canary R36 - Blacklist\nstatus='..status..'\ncount='..api.count..'\n')
            file:write('full_color_icons='..tostring(radial.full_color~=false)..'\n')
            file:write('wedge_darkness='..tostring(radial.wedge_darkness)..'; wedge_opacity='..tostring(radial.wedge_opacity)..'\n')
            file:write('centering='..tostring(api.centering or 'not sampled')..'; vertical_offset='..tostring(radial.vertical_offset)..'\n')
            file:write('pointing='..tostring(api.pointing_status)..'\n')
            file:write('mode='..mode_names[api.mode]..'; experimental_layout='..api.experimental_layout..'\n')
            file:write('before_latest_apply='..tostring(api.observation or 'not sampled')..'\n')
            file:write('selection='..tostring(api.selection_status)..'\nlast_result='..tostring(api.last_selection)..'\n')
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
local function options()
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
    local values=canary_settings(menu,settings_state,radial)
    api.enabled,api.mode,api.experimental_layout=values.enabled,values.selection_mode,values.experimental_layout
    select_on_release,input_interval_ms,sounds_enabled=values.select_on_release,values.input_interval_ms,values.selection_sounds
    excluded=stratagem_blacklist(values)
    if migrate_expanded then
        api.mode,api.experimental_layout=3,2
        if type(menu.set)=='function' and menu.set('native_stratagem_radial.experimental_layout',2)
            and menu.set('native_stratagem_radial.selection_mode',3) then migrate_expanded=false end
    end
end

local function bindings()
    local menu=rawget(_G,'ModBindingsMenu')
    if type(menu)~='table' or menu.api~=1 or type(menu.version)~='number'
        or not (menu.version>=2) then
        api.selection_status='Requires Mod Bindings Menu v2 or newer'; return nil
    end
    local labels={next='Next stratagem',previous='Previous stratagem',confirm='Confirm stratagem'}
    local buttons={}
    for _,key in ipairs({'next','previous','confirm'}) do
        local id=binding_ids[key]
        if binding_owner[id]~=menu then
            local ok,why=menu.register_binding(id,labels[key],nil,{category=MOD_NAME})
            if not ok then api.selection_status='Binding unavailable: '..tostring(why); return nil end
            binding_owner[id]=menu
        end
        buttons[key]=menu.is_down(id)
        if type(buttons[key])~='boolean' then api.selection_status='Waiting for native bindings'; return nil end
    end
    return buttons
end
local function step()
    if failed then return end
    local ok,why=pcall(function()
        options()
        if not controller then
            backend=native_backend()
            backend.checkpoint=native_checkpoint
            hidden_rows=blacklist_list_visibility(backend)
            native_checkpoint('native adapter ready; menu not entered')
            controller=radial.controller(backend)
            list_controller=radial.list_controller(backend)
            camera=camera_capture(backend)
            input=input_backend(backend)
            selection=selection_controller(input,selection_report)
            sound_feedback=selection_feedback(backend,selection_report)
            release_selection=release_controller(input,selection_report)
            duplicates=duplicate_cards(backend)
            pointing=native_pointing(backend)
            wheel=emote_wheel(backend,duplicates,input)
            expanded=expanded_wheel(backend,duplicates,input)
        end
        local now=backend.milliseconds()
        local signature=blacklist_signature(excluded)
        if signature~=exclusion_signature then
            -- An applied edit cancels queued/armed input before any more pulses.
            selection.step(nil,nil,now);release_selection.reset()
            controller.restore();list_controller.restore();hidden_rows.restore()
            duplicates.hide();wheel.hide();expanded.hide();pointing.reset();camera.release()
            exclusion_signature=signature
            blacklist_release_blocked=true
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
        local was_open=snapshot and snapshot.open
        local decorated,why=pcall(input.decorate,snapshot)
        if not decorated then snapshot=nil; buttons=nil; api.selection_status=tostring(why) end
        snapshot=blacklist_snapshot(snapshot,excluded)
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
                    buttons={next=false,previous=false,confirm=buttons.confirm}
                    local target
                    if not legacy and not expanded_layout then target=wheel.address end
                    local pointed,result=pcall(pointing.sample,context,dt,target)
                    if pointed then vector=result;api.pointing_status=string.format('x=%.3f y=%.3f',vector[1],vector[2])
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
        if not release_selection.job then selection.step(snapshot,buttons,now,vector) end
        release_selection.interval_ms=input_interval_ms
        release_selection.step(select_on_release and not blacklist_release_blocked and api.enabled and api.mode~=2 and buttons~=nil,
            snapshot,selection.selected,now,selection.job~=nil or (buttons and buttons.confirm))
        if not was_open then blacklist_release_blocked=false end
        if release_selection.job then selection.selected=release_selection.job.address end
        sound_feedback.step(sounds_enabled and api.enabled and buttons~=nil,snapshot,selection.selected,
            release_selection.job or selection.job,now,api.mode==2,paged)
        radial.selected=selection.selected
        if buttons then api.selection_status=selection.status end
        if was_open then
            local rows={}
            for _,row in ipairs(snapshot and snapshot.rows or {}) do
                rows[#rows+1]=tostring(row.entry)..':'..tostring(row.kind)..':'..tostring(row.timer_kind or 'no-timer')..':'..tostring(row.timer_seconds or '-')
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
        frames=frames+1
        report(display.status,(api.count>0 and frames%120==0) or api.last_selection~=api.reported_selection)
        api.reported_selection=api.last_selection
    end)
    if not ok then
        failed=true
        if release_selection then pcall(release_selection.reset) end
        if controller then pcall(controller.restore) end
        if list_controller then pcall(list_controller.restore) end
        if camera then pcall(camera.release) end
        if duplicates then pcall(duplicates.hide) end
        if wheel then pcall(wheel.hide) end
        if expanded then pcall(expanded.hide) end
        if hidden_rows then pcall(hidden_rows.restore) end
        api.count=0
        report('disabled after error: '..tostring(why))
    end
end
local previous=rawget(_G,'update')
local function after(...) step(); return ... end
update=function(...)
    if type(previous)=='function' then return after(previous(...)) end
    return after()
end
report('loaded; awaiting native HUD')
