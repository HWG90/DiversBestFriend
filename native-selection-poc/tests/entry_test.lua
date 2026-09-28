local function source(name)
    local f=assert(io.open('native-selection-poc/'..name,'rb'));local s=f:read('*a');f:close();return s
end
local make_selection=assert(loadstring(source('input.lua')..'\n'..source('pointing.lua')..'\n'..source('selection.lua')..'\nreturn selection_controller'))()
local make_release=assert(loadstring(source('input.lua')..'\n'..source('release.lua')..'\nreturn release_controller'))()
local now,focus,draws,starts,advances=0,true,0,0,0
local buttons={next=false,previous=false,confirm=false}
local snapshot={identity=1,open=true,rows={{address=10,kind=3},{address=20,kind=33}}}
local logs={}
local mode,enabled,experimental_layout=2,true,1
local full_color=true
local release_enabled=false
local release_down,release_calls=true,0
local wedge_darkness,wedge_opacity=70,75
local wedge_registrations=0
local copies,cursor_only,last_target=0,false,nil
local expanded_prepares,caption=0,nil
local timer_row
local prepares,samples,captured=0,0,false
local vector={0,0}
local env=setmetatable({}, {__index=_G});env._G=env
env.radial={}
env.release_controller=make_release
env.radial.controller=function()
    return {step=function() draws=draws+1 end,restore=function() end,count=2,status='drawing'}
end
env.radial.list_controller=env.radial.controller
env.camera_capture=function() return {capture=function() captured=true end,release=function() captured=false end} end
env.ModOptionsMenu={api=1,register_option=function(id,spec)
    if id:find('input_interval_ms',1,true) then assert(spec.default==70 and spec.min==0 and spec.max==250 and spec.step==5) end
    if id:find('select_on_release',1,true) then assert(spec.default==false and spec.type=='toggle') end
    if id:find('.wedge_',1,true) then
        assert(spec.type=='slider' and spec.min==0 and spec.max==100 and spec.step==5)
        assert(spec.default==(id:find('darkness',1,true) and 70 or 75))
        wedge_registrations=wedge_registrations+1
    end
    if id:find('selection_mode',1,true) then assert(spec.type=='choice' and #spec.choices==3 and spec.default==1) end
    return true
end,get=function(id)
    if id:find('select_on_release',1,true) then return release_enabled end
    if id:find('selection_mode',1,true) then return mode end
    if id:find('enabled',1,true) then return enabled end
    if id:find('full_color_icons',1,true) then return full_color end
    if id:find('experimental_layout',1,true) then return experimental_layout end
    if id:find('wedge_darkness',1,true) then return wedge_darkness end
    if id:find('wedge_opacity',1,true) then return wedge_opacity end
    return 575
end}
env.native_backend=function()
    return {snapshot=function() return snapshot end,focused=function() return focus end,milliseconds=function() return now end}
end
env.input_backend=function()
    return {view_context=function() return {} end,decorate=function() end,begin=function(kind) starts=starts+1;return {kind=kind} end,
        release_state=function() return {identity=1,component=2,hud=3,hold=true,down=release_down,unobstructed=true,menu_active=true,clean=true} end,
        begin_release=function() release_calls=release_calls+1;return {code={1},kind=33} end,
        hold_release=function() end,end_release=function() end,advance_release=function() return true,'matched' end,
        advance=function() advances=advances+1;return true,'Native matched; equip pending' end}
end
env.duplicate_cards=function() return {prepare=function(s)
    prepares=prepares+1;copies=copies+1
    local rows={};for i,row in ipairs(s.rows) do rows[i]={address=row.address+100,kind=row.kind} end
    return {identity=s.identity,open=s.open,rows=rows}
end,hide=function() end} end
env.emote_wheel=function()
    return {prepare=function(s)
        prepares=prepares+1;return {identity=s.identity,open=s.open,rows=s.rows,pointer_only=true},false
    end,caption=function(kind) caption=kind end,timer=function(row) timer_row=row end,address=12345,draw=function(_,_,_,only) cursor_only=only==true end,hide=function() end,step=function() draws=draws+1 end,count=2,status='drawing'}
end
env.expanded_wheel=function()
    return {prepare=function(s)
        expanded_prepares=expanded_prepares+1
        return {identity=s.identity,open=true,rows=s.rows,pointer_only=true,
            pointing_index=function(rows,v) if v[1]^2+v[2]^2>0.04 then return #rows end end},false
    end,draw=function(selected,rows)
        for _,row in ipairs(rows) do if row.address==selected then return row.kind end end
    end,hide=function() end,step=function() draws=draws+1 end,count=2,status='expanded'}
end
env.native_pointing=function() return {sample=function(_,_,target) samples=samples+1;last_target=target;return vector end,reset=function() end} end
env.selection_controller=make_selection
env.CowboyBingusModLoader={log_directory='native-selection-poc/tests/no-saved-settings',open_log=function()
    return {write=function(_,s) logs[#logs+1]=s;return true end,close=function() return true end}
end}
local registered={}
env.ModBindingsMenu={api=1,version=2,register_binding=function(id,label,slot,options)
    assert(slot==nil and options.category=="Diver's Best Friend");registered[id]=label;return true
end,is_down=function(id) return buttons[id:match('%.([^%.]+)$')] end}
env.update=function(a,b) assert(a=='a' and b=='b');return 1,nil,3 end
local chunk=assert(loadstring(source('entry.lua')));setfenv(chunk,env);chunk()
local function tick()
    now=now+100;local a,b,c=env.update('a','b');assert(a==1 and b==nil and c==3)
end
tick();assert(env.radial.selected==10 and draws==1 and starts==0)
buttons.next=true;tick();assert(env.radial.selected==20)
buttons.next=false;tick();buttons.confirm=true;tick();assert(starts==1)
buttons.confirm=false;tick();assert(advances==1)
buttons.confirm=true;tick();assert(starts==2)
focus=false;tick();assert(advances==1 and not env.radial.selected,'focus loss cancels')
focus=true;tick();assert(starts==2,'held confirmation on focus return is ignored')
env.ModBindingsMenu.version=1;tick();assert(env.NativeStratagemRadial.selection_status=='Requires Mod Bindings Menu v2')
assert(draws==9,'drawing survives missing binding dependency')
assert(table.concat(logs):find('Native matched; equip pending',1,true))
assert(prepares==0 and samples==0 and not captured,'list mode must not create a radial or consume pointing/camera')
env.ModBindingsMenu.version=2
mode=1;tick();assert(not env.radial.selected and starts==2 and captured,'mouse mode starts with no pointed card; held confirm ignored')
buttons.confirm=false;vector={0,1};tick();assert(env.radial.selected==10)
buttons.next=true;tick();assert(env.radial.selected==10,'mouse mode ignores navigation bindings')
buttons.next=false;buttons.confirm=true;tick();assert(starts==3)
mode=2;tick();assert(starts==3 and advances==1 and not captured,'mode change cancels job, releases camera and gates held confirm')
local old_samples=samples;tick();assert(samples==old_samples,'list never samples pointer')
mode=1;buttons.confirm=false;tick();assert(captured)
focus=false;tick();assert(not captured,'focus loss releases camera')
focus=true;tick();assert(captured)
snapshot.open=false;tick();assert(not captured,'menu close releases camera')
snapshot.open=true;tick();assert(captured)
enabled=false;tick();assert(not captured and not env.radial.selected,'disable releases camera and clears selection')
print('Entry integration passed: both modes, switching cancels/gates confirm, list avoids radial/input capture, pointer-only mouse selection, close/disable/focus cleanup and callback returns.')

-- Third mode restores copied-row drawing, preserves native input integration,
-- and switches layouts without accidentally confirming a held binding.
enabled=true;mode=3;vector={0,1};buttons.confirm=true;tick()
assert(copies==1 and cursor_only and last_target==nil and captured)
assert(env.radial.selected==110 and starts==3,'old radial uses duplicate addresses; held Confirm gated')
buttons.confirm=false;tick();buttons.confirm=true;tick();assert(starts==4)
experimental_layout=2;tick()
assert(cursor_only and last_target==nil and starts==4 and advances==1,'style change cancels sequence and gates held Confirm')
local old_copies=copies
buttons.confirm=false;tick();assert(copies==old_copies,'native baseline does not update copied rows')
mode=1;experimental_layout=1;tick()
assert(not cursor_only and last_target==12345 and copies==old_copies,'experimental setting cannot alter native mode')
mode=3;tick();assert(cursor_only and copies>old_copies)
mode=2;tick();assert(not captured,'experimental-to-list releases capture')
print('Experimental modes passed: copied-row routing, cursor-only native wheel, independent style option, job cancellation and held-confirm gating.')

mode=3;experimental_layout=2;buttons.confirm=true;local before=starts;local previous_expanded=expanded_prepares;tick()
assert(expanded_prepares==previous_expanded+1 and captured and cursor_only and last_target==nil)
assert(env.radial.selected==20 and caption==33 and starts==before,'expanded layout routes independent expanded selection and caption; held Confirm gated')
assert(timer_row==snapshot.rows[2],'expanded selected row also feeds native timer hint')
buttons.confirm=false;tick();buttons.confirm=true;tick();assert(starts==before+1)
mode=1;tick();assert(starts==before+1 and not cursor_only and last_target==12345,'return to native mode cancels expanded job and restores native input state')
print('Expanded layout passed: expanded routing, cursor/caption reuse, held Confirm and return to native mode.')

full_color=false;tick();assert(env.radial.full_color==false)
full_color=true;tick();assert(env.radial.full_color==true)
print('Icon option routing passed: live off/on setting reaches render configuration.')

assert(env.radial.wedge_darkness==70 and env.radial.wedge_opacity==75 and wedge_registrations==2)
wedge_darkness,wedge_opacity=0,100;tick()
assert(env.radial.wedge_darkness==0 and env.radial.wedge_opacity==100,'valid appearance endpoints apply')
wedge_darkness,wedge_opacity=101,-1;tick()
assert(env.radial.wedge_darkness==0 and env.radial.wedge_opacity==100,'out-of-range values rejected')
wedge_darkness,wedge_opacity=0/0,'75';tick()
assert(env.radial.wedge_darkness==0 and env.radial.wedge_opacity==100,'NaN and nonnumeric settings rejected')
wedge_darkness,wedge_opacity=70,75;tick()
assert(wedge_registrations==2,'settings are registered once per options menu instance')
print('Wedge option routing passed: defaults, live changes, endpoints and invalid values.')

-- A saved legacy mode 4 migrates using set after both choices register.
mode=4;experimental_layout=1
local old_menu=env.ModOptionsMenu
local migrated={}
env.ModOptionsMenu={api=1,register_option=old_menu.register_option,get=old_menu.get,
 set=function(id,value)
    migrated[id]=value
    if id:find('experimental_layout',1,true) then experimental_layout=value else mode=value end
    return true
 end}
tick()
assert(mode==3 and experimental_layout==2 and env.NativeStratagemRadial.mode==3)
assert(migrated['native_stratagem_radial.selection_mode']==3 and migrated['native_stratagem_radial.experimental_layout']==2)
experimental_layout=1;tick();assert(env.NativeStratagemRadial.experimental_layout==1,'migration must not override later edits')
print('Legacy mode migration passed: mode 4 becomes Experimental/Expanded once, then respects edits.')
mode=3;experimental_layout=2;enabled=true;focus=true;buttons.confirm=false;vector={1,0}
snapshot.open=true;release_down=true;tick();release_down=false;snapshot.open=false;tick()
assert(release_calls==0,'release remains disabled by default')
release_enabled=true;release_down=true;snapshot.open=true;tick()
release_down=false;snapshot.open=false;tick()
assert(release_calls==1,'opt-in survives closed snapshot and cleared selection')
tick();assert(release_calls==1,'no repeated selection on closed frames')
mode=2;release_down=true;snapshot.open=true;tick();release_down=false;snapshot.open=false;tick()
assert(release_calls==1,'list mode never confirms on release')
print('Select on Release integration passed: opt-in default, closed-frame delivery, once-only and list exclusion.')
