local api={api=1,revision=29,enabled=true,mode=1,experimental_layout=1,status='initializing',count=0}
local MOD_NAME = "Diver's Best Friend"
rawset(_G,'DiversBestFriend',api)
-- Compatibility alias for existing diagnostics and duplicate-load detection.
rawset(_G,'NativeStratagemRadial',api)
local controller,failed,registered,last_status
local frames=0
local backend,selection,input,duplicates,pointing,last_tick,list_controller,camera,active_mode
local wheel,expanded,release_selection,release_registered
local select_on_release=false
local interval_registered,input_interval_ms=nil,70
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
    file:write(MOD_NAME..' R29 - Completion Wait\n'..table.concat(native_events,'\n')..'\n')
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
local offset_registered,mode_registered,layout_registered,color_registered
local wedge_registered={}
local wedge_options={
    {key='wedge_darkness',label='Expanded wedge darkness (%)',default=70,
        description='Expanded wedges only. Darkens the unselected background; 0 keeps the original gray, 100 makes it black. The selected sector stays yellow.'},
    {key='wedge_opacity',label='Expanded wedge opacity (%)',default=75,
        description='Expanded wedges only. Background opacity: 0 is transparent, 100 is opaque. Empty sectors stay fainter and the selected sector stays visible. Original appearance: darkness 0, opacity 30.'},
}
local migration_checked,migrate_expanded
local mode_names={'Native wheel','Keybindings - list','Experimental'}
local function report(status,force)
    api.status=status
    if status==last_status and not force then return end
    last_status=status
    pcall(function()
        local loader=rawget(_G,'CowboyBingusModLoader')
        if not loader or type(loader.open_log)~='function' then return end
        local file=loader.open_log('DiversBestFriend.log')
        if file then
            file:write(MOD_NAME..' R29 - Completion Wait\nstatus='..status..'\ncount='..api.count..'\n')
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
local function options()
    local menu=rawget(_G,'ModOptionsMenu')
    if type(menu)~='table' or menu.api~=1 or type(menu.register_option)~='function' or type(menu.get)~='function' then return end
    if interval_registered~=menu then
        if menu.register_option('native_stratagem_radial.input_interval_ms',{
            type='slider',mod=MOD_NAME,label='Input interval (ms)',min=0,max=250,step=5,default=70,
            description='Delay between directions for Confirm and Select on Release. 0 sends one direction per frame. Changes apply to the next code.'}) then interval_registered=menu end
    end
    if interval_registered==menu then
        local value=menu.get('native_stratagem_radial.input_interval_ms')
        if type(value)=='number' and value==value and value>=0 and value<=250 then input_interval_ms=value end
    end
    if release_registered~=menu then
        if menu.register_option('native_stratagem_radial.select_on_release',{
            type='toggle',mod=MOD_NAME,label='Select on Release',default=false,
            description='Radial modes only: use a Hold stratagem-menu binding, point, then release to select. No separate Confirm binding required. Center the pointer to cancel. List mode still requires Confirm.'}) then release_registered=menu end
    end
    if release_registered==menu then
        select_on_release=menu.get('native_stratagem_radial.select_on_release')==true
    end
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
    if registered~=menu then
        local ok=menu.register_option('native_stratagem_radial.enabled',{
            type='toggle',mod=MOD_NAME,label='Enable Mod',default=true,
            description='Enable the selected menu mode. Confirm enters the highlighted stratagem code.'})
        if ok then registered=menu end
    end
    if mode_registered~=menu then
        if menu.register_option('native_stratagem_radial.selection_mode',{
            type='choice',mod=MOD_NAME,label='Selection mode',
            choices={'Native wheel','Keybindings - list','Experimental'},default=1,
            description='Native wheel: eight slots with mouse or stick selection. List: Next/Previous and Confirm with camera control. Experimental: choose Cards or Expanded wedges below.'}) then mode_registered=menu end
    end
    if mode_registered==menu then
        local value=menu.get('native_stratagem_radial.selection_mode')
        if value==1 or value==2 or value==3 then api.mode=value end
    end
    if layout_registered~=menu then
        if menu.register_option('native_stratagem_radial.experimental_layout',{
            type='choice',mod=MOD_NAME,label='Experimental layout',
            choices={'Cards - copied list rows','Expanded wedges'},default=1,
            description='Experimental mode: up to 16 Cards or Expanded wedges. Point with the mouse or stick, then Confirm or use Select on Release.'}) then layout_registered=menu end
    end
    if layout_registered==menu then
        local value=menu.get('native_stratagem_radial.experimental_layout')
        if value==1 or value==2 then api.experimental_layout=value end
    end
    if migrate_expanded and mode_registered==menu and layout_registered==menu then
        api.mode,api.experimental_layout=3,2
        if type(menu.set)=='function' then
            local layout_ok=menu.set('native_stratagem_radial.experimental_layout',2)
            if layout_ok and menu.set('native_stratagem_radial.selection_mode',3) then migrate_expanded=false end
        end
    end
    if color_registered~=menu then
        if menu.register_option('native_stratagem_radial.full_color_icons',{
            type='toggle',mod=MOD_NAME,label='Full-color stratagem icons',default=true,
            description='Use full-color icons on the wheels. Off shows the raw red/green icons. Cards keep their original colors; cooldown icons remain gray.'}) then color_registered=menu end
    end
    if color_registered==menu then
        local value=menu.get('native_stratagem_radial.full_color_icons')
        if type(value)=='boolean' then radial.full_color=value end
    end
    for _,spec in ipairs(wedge_options) do
        local id='native_stratagem_radial.'..spec.key
        if wedge_registered[id]~=menu then
            if menu.register_option(id,{type='slider',mod=MOD_NAME,
                label=spec.label,min=0,max=100,step=5,default=spec.default,
                description=spec.description}) then wedge_registered[id]=menu end
        end
        if wedge_registered[id]==menu then
            local value=menu.get(id)
            if type(value)=='number' and value>=0 and value<=100 then radial[spec.key]=value end
        end
    end
    if offset_registered~=menu then
        if menu.register_option('native_stratagem_radial.vertical_offset',{
            type='slider',mod=MOD_NAME,label='Radial vertical offset (down)',
            min=-600,max=600,step=25,default=0,
            description='Fine-tune automatic viewport centering. Leave at 0 for screen center; positive values move downward. Apply after adjusting.'}) then offset_registered=menu end
    end
    if offset_registered==menu then
        local value=menu.get('native_stratagem_radial.vertical_offset')
        if type(value)=='number' and value>=-600 and value<=600 then radial.vertical_offset=value end
    end
    if registered==menu then
        local value=menu.get('native_stratagem_radial.enabled')
        if type(value)=='boolean' then api.enabled=value end
    end
end
local function bindings()
    local menu=rawget(_G,'ModBindingsMenu')
    if type(menu)~='table' or menu.api~=1 or menu.version~=2 then
        api.selection_status='Requires Mod Bindings Menu v2'; return nil
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
            native_checkpoint('native adapter ready; menu not entered')
            controller=radial.controller(backend)
            list_controller=radial.list_controller(backend)
            camera=camera_capture(backend)
            input=input_backend(backend)
            selection=selection_controller(input,selection_report)
            release_selection=release_controller(input,selection_report)
            duplicates=duplicate_cards(backend)
            pointing=native_pointing(backend)
            wheel=emote_wheel(backend,duplicates,input)
            expanded=expanded_wheel(backend,duplicates,input)
        end
        local now=backend.milliseconds()
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
        local vector
        if snapshot and snapshot.open and api.mode~=2 and not (release_selection.job and release_selection.job.finished) then
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
                    snapshot,changed=wheel.prepare(snapshot,buttons,selection.job~=nil or release_selection.job~=nil)
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
        if api.mode==2 or not snapshot or not snapshot.open then
            duplicates.hide();wheel.hide();expanded.hide();pointing.reset();camera.release()
            if api.mode==2 then api.pointing_status='off; keybinding list mode' end
        end
        if snapshot and api.mode==2 then snapshot.list_order=true end
        if was_open and not buttons then api.last_block=api.selection_status end
        selection.interval_ms=input_interval_ms
        if not release_selection.job then selection.step(snapshot,buttons,now,vector) end
        release_selection.interval_ms=input_interval_ms
        release_selection.step(select_on_release and api.enabled and api.mode~=2 and buttons~=nil,
            snapshot,selection.selected,now,selection.job~=nil or (buttons and buttons.confirm))
        if release_selection.job then selection.selected=release_selection.job.address end
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
        if api.mode~=2 and snapshot and snapshot.open then
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
        display.step(api.enabled,snapshot or {open=false})
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
