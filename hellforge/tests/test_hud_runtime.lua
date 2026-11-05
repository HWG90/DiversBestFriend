-- Run from the repository root with luajit hellforge/tests/test_hud_runtime.lua.
local scope=setmetatable({native_guards={}}, {__index=_G})
local function module(name)
    local f=assert(loadfile('hellforge/hud/'..name..'.lua'))
    setfenv(f,scope)
    for key,value in pairs(f()) do scope[key]=value end
end
module('wheel_native');module('wheel_input');module('wheel_selection');module('wheel_release');module('runtime')
local now=0
local ready_page,granted,capacity,blacklisted=false,false,true,false
local token,requests,releases,mask=nil,0,0,0
local bridge={
    dbf_hud_base=function() return 0x10000 end,
    dbf_hud_option=function(k)
        if k=='selection_mode_ordered' then return 3 end
        if k=='release_selection_mode' then return 2 end
        return -2147483648
    end,
    dbf_hud_guard=function(rva,bytes,length)
        assert(#bytes==length and length>0)
        return (rva~=123 or ready_page) and 1 or 0
    end,
    dbf_hud_acquire=function(t)
        requests=requests+1
        if token and token~=t then return 0 end
        token=t
        return granted and 1 or 0
    end,
    dbf_hud_release=function(t)
        if token==t then token=nil;releases=releases+1 end
    end,
    dbf_hud_buttons=function() return mask end,
    dbf_hud_blacklisted=function(kind) return kind==154 and blacklisted and 1 or 0 end,
    dbf_hud_log=function() end,
}
local function noop() end
local function object()
    return {reset=noop,restore=noop,step=noop,hide=noop,close=function() return true end}
end
local function mutation() assert(token and granted,'mutation without lease') end
local snapshot={identity=7,open=true,hud_visible=true,rows={{kind=154,address=300,entry=0}}}
scope.native_guards={{name='wheel_constructor',rva=123,bytes='expected'}}
scope.native_backend=function()
    return {finish_removed=noop,snapshot=function() return snapshot end,milliseconds=function() return now end}
end
scope.radial={list_controller=object,controller=object}
scope.blacklist_list_visibility=object
scope.blacklist_snapshot=function(s,excluded)
    if excluded[154] then return {identity=7,open=true,rows={}} end
    return s
end
local down,started,pointing_fails,captured=true,0,false,false
scope.camera_capture=function()
    return {release=function() mutation();captured=false end,capture=function() mutation();captured=true end}
end
scope.native_pointing=function()
    return {sample=function()
        if pointing_fails then error('pointer temporary unavailable') end
        return {0,1,slot=1,controller=true}
    end,reset=noop}
end
scope.pointing_index=function() return 1 end
scope.input_backend=function() return {
    decorate=noop,retry_cleanup=noop,view_context=function() return {} end,
    release_state=function() return {identity=1,hud=7,component=4,hold=true,down=down,
        menu_active=true,clean=true,unobstructed=true} end,
    begin_release=function() started=started+1;return {code={1,2}} end,
    hold_release=noop,end_release=noop,
} end
scope.duplicate_cards=object
scope.expanded_wheel=object
local row_missing=false
local transient_error=false
local wheels=0
scope.emote_wheel=function()
    wheels=wheels+1
    local w=object()
    w.prepare=function(s)
        mutation()
        if row_missing then error('HUD row withdrawn') end
        if transient_error then error('Wheel HUD changed') end
        return s,false
    end
    w.draw=mutation;w.timer=noop
    w.close=function() return capacity,'widget still linked' end
    return w
end
scope.selection_feedback=object
local dock_broken=true
scope.cooldown_dock=function()
    local d=object()
    d.sample=noop
    d.draw=function() mutation();assert(not dock_broken,'Native dock record unavailable') end
    return d
end
scope.cooldown_closed_notices=object
scope.binding_warning=object
scope.weapon_strip=function() error('isolated strip guard mismatch') end
local function tick(r,ms)
    now=now+ms;r:update(ms/1000)
end
local r=scope.dbf_hud_runtime(bridge)
tick(r,20);assert(requests==0 and not r:ready(),'unreadable wheel page waits without claiming')
ready_page=true
tick(r,501);assert(requests==1 and not r:ready(),'C has one tick to undo list ownership')
assert(r:shutdown() and releases==1 and not token,'cancel pending token')
r=scope.dbf_hud_runtime(bridge);granted=true
tick(r,20);assert(r:ready() and captured,'weapon mismatch must not stop wheel')
assert(r.dock_error and r.strip_error,'independent optional modules reported their failures')
dock_broken=false
local another=scope.dbf_hud_runtime(bridge);tick(another,20)
assert(not another:ready() and another:shutdown() and token==r.token,'second token cannot release the first')
pointing_fails=true;tick(r,20);assert(r:ready() and not captured)
pointing_fails=false;tick(r,20);assert(captured)
r.release.job={finished=true,code={1},snapshot_identity=7,deadline=now+1000}
mask=-1;tick(r,20);assert(not captured and not r.release.job)
mask=0;tick(r,20)
blacklisted=true;down=false;tick(r,20)
assert(started==0 and r.block_release,'filtered Hold release cancelled')
blacklisted=false;down=true;tick(r,20);down=false;tick(r,20)
assert(started==0,'no rearming until menu closes')
snapshot.open=false;tick(r,20);snapshot.open=true;down=true;tick(r,20);down=false;tick(r,20)
assert(started==1,'subsequent fresh Hold release works')
capacity=false
assert(not r:shutdown() and token==r.token,'retain token after failed close')
capacity=true
assert(r:shutdown() and token==nil and releases==2,'release only after successful cleanup')
assert(r:shutdown() and releases==2,'idempotent shutdown')
print('HUD admission, handoff, strip isolation, pointing, filter changes, Hold release and cleanup passed')

-- Rebuild during an open menu: release the lease, wait with no claim, then
-- construct new controllers only after the next positively observed closure.
local recovering=scope.dbf_hud_runtime(bridge)
transient_error=true
tick(recovering,20)
assert(not recovering:ready() and not token and not captured)
local before=wheels
tick(recovering,1000)
assert(wheels==before and not token,'open menu cannot rearm after transient failure')
transient_error=false;snapshot.open=false
tick(recovering,500)
assert(recovering:ready() and wheels==before+1 and token==recovering.token)
snapshot.open=true;tick(recovering,16);assert(captured,'fresh owner draws the wheel')
transient_error=true;tick(recovering,16)
assert(not token and not recovering:ready())
assert(recovering:shutdown())
snapshot.open=false;tick(recovering,1000)
assert(wheels==before+1 and not token,'manager disable permanently cancels recovery')
print('Transient rebuild recovery released the lease and manager disable cancelled reinitialization')

local row_owner=scope.dbf_hud_runtime(bridge)
transient_error=false;row_missing=true;snapshot.open=true;mask=0
tick(row_owner,20)
assert(row_owner:ready() and token==row_owner.token and not captured)
row_missing=false;tick(row_owner,20)
assert(captured and row_owner:ready(),'row withdrawal must permit a fresh next frame')
assert(row_owner:shutdown())

-- A terminal can own the game's UI while the selector mask is blocked.
local allow_terminal,restore_terminal,terminal_ticks=true,true,0
local get=bridge.dbf_hud_option
bridge.dbf_hud_option=function(key)
    if key=='auto_terminal_complete' then return 1 end
    return get(key)
end
bridge.dbf_hud_terminal_active=function(t) return t==token and allow_terminal and 1 or 0 end
scope.terminal_controller=function(_,b)
    assert(b==bridge)
    return {
        retry_cleanup=function() return restore_terminal,'terminal byte still held' end,
        update=function() terminal_ticks=terminal_ticks+1 end,
    }
end
mask=-1;transient_error=false
local terminal_owner=scope.dbf_hud_runtime(bridge)
tick(terminal_owner,16);assert(terminal_ticks==1 and terminal_owner:ready())
allow_terminal=false;tick(terminal_owner,16);assert(terminal_ticks==1)
restore_terminal=false
assert(not terminal_owner:shutdown() and token==terminal_owner.token)
restore_terminal=true
assert(terminal_owner:shutdown() and not token)
print('Independent terminal gate and pending-byte release passed')

-- Release completion can take several ticks with the stock menu still open.
-- Copied-card layout must never fall through to applying transforms to it.
local old_get=bridge.dbf_hud_option
bridge.dbf_hud_option=function(key)
    if key=='selection_mode_ordered' or key=='experimental_layout' then return 1 end
    if key=='auto_terminal_complete' then return 0 end
    return old_get(key)
end
scope.duplicate_cards=function()
    local d=object()
    d.prepare=function(s)
        return {identity=s.identity,open=true,rows={{address=999,kind=154,entry=0}}}
    end
    return d
end
local layouts=0
scope.radial.controller=function()
    local ctrl=object()
    ctrl.step=function(_,s)
        assert(s.rows[1].address==999,'copy controller attempted to move a stock card')
        layouts=layouts+1
    end
    return ctrl
end
snapshot.open=true;mask=0
local copied=scope.dbf_hud_runtime(bridge)
tick(copied,20);assert(layouts==1)
copied.release.job={finished=true,code={1},snapshot_identity=7,deadline=now+1000}
tick(copied,20);assert(copied:ready() and layouts==1,'only prepared duplicate addresses can be laid out')
assert(copied:shutdown())
print('Open stock menu protected during copied-card release completion')
