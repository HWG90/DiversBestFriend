-- Run from the repository root with luajit hellforge/tests/test_hud_runtime.lua.
local scope=setmetatable({}, {__index=_G})
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
    return {snapshot=function() return snapshot end,milliseconds=function() return now end}
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
scope.emote_wheel=function()
    local w=object()
    w.prepare=function(s) mutation();return s,false end
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
