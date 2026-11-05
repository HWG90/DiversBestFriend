-- Engine VM owner. The host drives update after the game's HUD tick and retains
-- this object (including every FFI allocation) until shutdown returns true.
local ffi=require('ffi')
ffi.cdef[[
    void *GetModuleHandleA(const char *name);
    unsigned long GetModuleFileNameA(void *module,char *path,unsigned long size);
    int dbf_hud_acquire(const void *token);
    void dbf_hud_release(const void *token);
    uint64_t dbf_hud_base(void);
    int dbf_hud_read(uint64_t address,void *out,uint32_t bytes);
    int dbf_hud_guard(unsigned rva,const void *expected,unsigned bytes);
    int dbf_hud_option(const char *key);
    int dbf_hud_buttons(void);
    int dbf_hud_bound(unsigned action);
    int dbf_hud_blacklisted(unsigned kind);
    int dbf_hud_code(unsigned kind,unsigned char *dirs,unsigned capacity);
    uint64_t dbf_hud_row(unsigned kind);
    void dbf_hud_log(const char *message);
]]

-- Only pin the companion already mapped by this HellForge session. An
-- absolute path from its HMODULE avoids searching the process DLL path.
local function loaded_companion()
    local k=ffi.load('kernel32')
    if k.GetModuleHandleA('hellforge_modloader.dll')==nil then return end
    local handle=k.GetModuleHandleA('divers_best_friend.dll')
    if handle==nil then return end
    local path=ffi.new('char[32768]')
    local n=k.GetModuleFileNameA(handle,path,32768)
    if n==0 or n>=32768 then return end
    return ffi.load(ffi.string(path,n))
end

local defaults={
    selection_mode_ordered=1,experimental_layout=2,appearance_preset=1,
    wheel_size=100,icon_size=100,label_size=100,vertical_offset=0,
    wedge_darkness=70,wedge_opacity=50,native_opacity=100,dim_unselected=true,
    hide_blacklisted_list=false,hide_cooldown_list=false,selection_sounds=true,
    release_selection_mode=1,input_interval_ms=70,randomize_input_delay=false,
    instant_stratagems=false,cooldown_icons=true,hide_closed_status=true,
    cooldown_timers=true,cooldown_timer=2,short_timer_style=2,brief_timer_limit=10,
    balance_separated_dock=true,short_status_placement=3,track_unavailable=false,
    dock_gap=24,cooldown_display=1,weapon_status_strip=true,auto_terminal_complete=false,terminal_input=1,
}
local actions={'next','previous','confirm','slot1','slot2','slot3','slot4'}
local presets={{},{85,100,95},{100,100,100},{115,110,110}}
local function options(bridge)
    local s={}
    for key,default in pairs(defaults) do
        local value=bridge.dbf_hud_option(key)
        if value==-2147483648 then value=default
        elseif type(default)=='boolean' then value=value==1 end
        s[key]=value
        radial[key]=value
    end
    local sizes=presets[s.appearance_preset]
    radial.wheel_scale=(sizes[1] or s.wheel_size)/100
    radial.icon_scale=(sizes[2] or s.icon_size)/100
    radial.label_scale=(sizes[3] or s.label_size)/100
    radial.native_opacity=s.native_opacity/100
    radial.cooldown_timer=s.cooldown_timers and s.cooldown_timer or 1
    return s
end

local function dbf_hud_runtime(bridge)
    local r={status='waiting for companion',token=ffi.new('uint8_t[1]')}
    local function report(message)
        if r.status~=message then
            r.status=message
            if bridge then bridge.dbf_hud_log(message) end
        end
    end
    local function initialize()
        r.list=radial.list_controller(r.b)
        r.cards=radial.controller(r.b)
        r.hidden=blacklist_list_visibility(r.b)
        r.input=input_backend(r.b,bridge)
        r.selection=selection_controller(r.input,report)
        r.release=release_controller(r.input,report)
        r.sound=selection_feedback(r.b,report)
        r.camera=camera_capture(r.b)
        r.point=native_pointing(r.b)
        r.dupes=duplicate_cards(r.b)
        r.wheel=emote_wheel(r.b,r.dupes,r.input)
        r.expanded=expanded_wheel(r.b,r.dupes,r.input)
        r.dock=cooldown_dock(r.b,r.dupes,r.input)
        r.notices=cooldown_closed_notices(r.b)
        r.warning=binding_warning(bridge)
        r.initialized=true
        report('engine HUD owner ready')
    end
    local function reset(wait_for_list)
        local errors={}
        local function clean(key,method,...)
            if r[key] then
                local ok,why=pcall(r[key][method],...)
                if not ok then errors[#errors+1]=key..': '..tostring(why) end
            end
        end
        clean('input','retry_cleanup')
        clean('release','reset')
        clean('selection','step',nil,nil,0)
        clean('camera','release')
        clean('point','reset')
        clean('cards','restore')
        if wait_for_list and r.list_open then
            local ok,snapshot=pcall(r.b.snapshot)
            if not ok or snapshot and snapshot.open then
                errors[#errors+1]='Close the stratagem list to restore its animated rows'
            else r.list_open=false end
        end
        if not wait_for_list or not r.list_open then
            clean('list','restore')
            clean('hidden','restore')
        end
        clean('wheel','hide')
        clean('expanded','hide')
        clean('dupes','hide')
        clean('dock','hide')
        clean('notices','restore',true)
        clean('strip','hide')
        clean('warning','hide')
        r.slots,r.controller,r.dock_sample,r.next_sample=nil,false,nil,nil
        radial.selected=nil
        assert(#errors==0,table.concat(errors,'; '))
    end
    local function stop()
        if r.owned then
            reset(true)
            for _,key in ipairs({'strip','wheel','expanded','dock','dupes'}) do
                if r[key] then
                    local ok,why=r[key].close()
                    assert(ok~=false,why)
                    r[key]=nil
                end
            end
        end
        if r.requested then
            bridge.dbf_hud_release(r.token)
            r.owned,r.requested=false,false
        end
        r.terminal=nil
        r.initialized=false
    end
    function r:ready() return self.initialized==true and not self.stopping end
    function r:shutdown()
        self.stopping=true
        local ok,why=pcall(stop)
        if not ok then report('HUD cleanup pending: '..tostring(why)) end
        return ok,why
    end
    local function dock(snapshot,s,now)
        if not s.cooldown_icons or not snapshot then
            r.dock.hide()
            r.dock_sample,r.next_sample=nil,nil
            return
        end
        if snapshot.open then
            r.dock_sample=snapshot
            r.next_sample=now+250
        elseif not r.next_sample or now>=r.next_sample or
            (r.dock_sample and (r.dock_sample.open or r.dock_sample.identity~=snapshot.identity)) then
            r.next_sample=now+250
            local full=r.b.snapshot(true)
            if full and full.identity==snapshot.identity then
                local ok=pcall(r.input.decorate,full)
                r.dock_sample=ok and full or nil
            else r.dock_sample=nil end
        end
        if r.dock_sample then
            r.dock.sample(r.dock_sample,now)
            r.dock.draw(now,snapshot.hud_visible)
        else r.dock.hide() end
    end
    local function surface_ready(mode,layout,now)
        if mode==2 then return true end
        local ok,why=r.admit('wheel',now)
        if not ok then return false,why end
        ok,why=r.admit('icons',now)
        if not ok or mode==3 then return ok,why end
        if layout==1 then return r.admit('cards',now) end
        ok,why=r.admit('order',now)
        if not ok then return false,why end
        ok,why=r.admit('sprite',now)
        if not ok then return false,why end
        return r.admit('expanded',now)
    end
    local function weapon(snapshot,dt,now)
        if not snapshot or not r.settings.weapon_status_strip or not snapshot.hud_visible then
            if r.strip then r.strip.hide() end
            return
        end
        if not r.admit('sprite',now) or not r.admit('order',now) then return end
        if not r.strip then r.strip=weapon_strip(r.b,r.dupes,bridge) end
        r.strip.update(snapshot,dt)
    end
    local function frame(dt)
        r.input.retry_cleanup()
        local now=r.b.milliseconds()
        if bridge.dbf_hud_option('enabled')==0 then
            if r.active~=false then reset() end
            r.active=false
            return
        end
        r.active=true
        if not r.next_options or now>=r.next_options then
            r.settings=options(bridge)
            r.next_options=now+150
        end
        local s=r.settings
        local mode=s.selection_mode_ordered
        local copied=mode==1 and s.experimental_layout==1
        local mode_key=mode..':'..s.experimental_layout
        if mode_key~=r.mode then reset();r.mode=mode_key end
        local mask=bridge.dbf_hud_buttons()
        local buttons
        if mask>=0 then
            buttons={}
            for i,name in ipairs(actions) do buttons[name]=math.floor(mask/2^(i-1))%2==1 end
        end
        if buttons and s.auto_terminal_complete and terminal_controller then
            if not r.terminal then r.terminal=terminal_controller(r.b) end
            r.terminal.update(dt,s)
        end
        local snapshot=r.b.snapshot()
        local hud_visible=snapshot and snapshot.hud_visible
        if snapshot and not pcall(r.input.decorate,snapshot) then snapshot=nil end
        if not snapshot or not snapshot.open then
            r.cards.restore();r.list.restore();r.hidden.restore()
        end
        if not r.strip_retry or now>=r.strip_retry then
            local ok,why=pcall(weapon,snapshot,dt,now)
            if not ok then
                if r.strip then pcall(r.strip.hide) end
                r.strip_retry=now+1000
                if r.strip_error~=tostring(why) then
                    r.strip_error=tostring(why)
                    bridge.dbf_hud_log('Weapon strip paused: '..r.strip_error)
                end
            end
        end
        r.notices.step(s.hide_closed_status and snapshot or nil)
        if (not r.dock_retry or now>=r.dock_retry) and r.admit('dock',now)
            and r.admit('order',now) and r.admit('icons',now) then
            local ok,why=pcall(dock,snapshot,s,now)
            if not ok then
                pcall(r.dock.hide)
                r.dock_sample,r.next_sample=nil,nil
                r.dock_retry=now+1000
                if tostring(why)~=r.dock_error then
                    r.dock_error=tostring(why)
                    bridge.dbf_hud_log('Cooldown display paused: '..r.dock_error)
                end
            end
        end
        local surface,missing=surface_ready(mode,s.experimental_layout,now)
        if not surface then report('Waiting for HUD witness: '..missing);return end
        local excluded={}
        for _,row in ipairs(snapshot and snapshot.rows or {}) do
            if row.kind and bridge.dbf_hud_blacklisted(row.kind)~=0 then excluded[row.kind]=true end
        end
        -- Retain the last open-menu kinds across the release frame (closed
        -- snapshots have no rows). An edit on that frame must disarm the latch.
        if snapshot and snapshot.open then
            r.filter_kinds={}
            for _,row in ipairs(snapshot.rows) do
                if row.kind then r.filter_kinds[row.kind]=true end
            end
        end
        local filters={'blacklist='..tostring(s.hide_blacklisted_list),'cooldown='..tostring(s.hide_cooldown_list)}
        for kind in pairs(r.filter_kinds or {}) do
            if excluded[kind] or bridge.dbf_hud_blacklisted(kind)~=0 then filters[#filters+1]=tostring(kind) end
        end
        table.sort(filters)
        local signature=table.concat(filters,',')
        if r.filters and r.filters~=signature then
            r.selection.step(nil,nil,now)
            r.release.reset()
            r.block_release=true
        end
        r.filters=signature
        snapshot=blacklist_snapshot(snapshot,excluded,mode==2 and not s.hide_blacklisted_list,
            mode==2 and s.hide_cooldown_list)
        local selected=r.selection
        local release=r.release
        for _,control in ipairs({selected,release}) do
            control.interval_ms=s.input_interval_ms
            control.randomize_delay=s.randomize_input_delay
            control.instant=s.instant_stratagems
        end
        if snapshot and snapshot.open and #snapshot.rows==0 then
            r.block_release=true
            release.reset()
        end
        local vector,paged
        local open=snapshot and snapshot.open and #snapshot.rows>0
        if open and mode~=2 and not (release.job and release.job.finished) then
            local ok,context=pcall(r.input.view_context)
            if ok then
                local original=snapshot
                local changed
                if copied then
                    snapshot=r.dupes.prepare(original,context,dt)
                    -- The copied widgets have new addresses; eligibility still belongs to their source rows.
                    for i,row in ipairs(snapshot.rows) do
                        row.timer_kind=original.rows[i].timer_kind
                        row.unavailable=original.rows[i].unavailable
                    end
                elseif mode==1 then snapshot,changed=r.expanded.prepare(original)
                else snapshot,changed,paged=r.wheel.prepare(original,buttons,selected.job~=nil or release.job~=nil) end
                if mode==1 then r.wheel.prepare(original,nil,false) end
                if changed then selected.step(nil,nil,now);r.point.reset() end
                snapshot.pointer_only=true
                if buttons then
                    r.camera.capture()
                    buttons.next,buttons.previous=false,false
                    local pointed,value=pcall(r.point.sample,context,dt,mode==3 and r.wheel.address or nil)
                    if pointed then vector=value;r.controller=vector.controller
                    else buttons=nil;r.controller=false end
                else r.point.reset();r.camera.release() end
            else snapshot=nil;buttons=nil;open=false end
        end
        if not buttons then r.point.reset();r.camera.release() end
        if not open or mode==2 then
            r.dupes.hide();r.wheel.hide();r.expanded.hide();r.point.reset();r.camera.release()
        end
        if mode==2 and snapshot then snapshot.list_order=true end
        local can_release=r.admit('release',now)
        for slot=1,4 do
            local key='slot'..slot
            if not r.block_release and can_release and buttons and buttons[key] and r.slots and r.slots[key]==false and
                snapshot and not selected.job and not release.job then
                release.shortcut(slot,snapshot,now)
            end
        end
        r.slots=buttons
        if release.job and release.job.slot then
            release.job.trigger_down=buttons and buttons['slot'..release.job.slot]
        end
        if not release.job then selected.step(snapshot,buttons,now,vector) end
        local on_release=s.release_selection_mode==2 or (s.release_selection_mode==1 and r.controller)
        r.warning.step(hud_visible,mode,on_release,r.wheel.pages or 1,now)
        release.step(not r.block_release and can_release and buttons~=nil and ((mode~=2 and on_release) or (release.job and release.job.shortcut)),
            snapshot,selected.selected,now,selected.job~=nil or (buttons and buttons.confirm))
        if snapshot and not snapshot.open then r.block_release=false end
        local address=release.job and release.job.address or selected.selected
        r.sound.step(s.selection_sounds and r.admit('sound',now) and buttons~=nil,snapshot,address,release.job or selected.job,now,mode==2,paged)
        radial.selected=address
        if open and mode~=2 then
            r.wheel.draw(address,vector,snapshot.rows,mode==1)
            if mode==1 and not copied then r.wheel.caption(r.expanded.draw(address,snapshot.rows)) end
            local timer
            for _,row in ipairs(snapshot.rows) do if row.address==address then timer=row end end
            r.wheel.timer(timer)
        end
        local display=mode==2 and r.list or (copied and r.cards or (mode==1 and r.expanded or r.wheel))
        r.list_open=mode==2 and open
        display.step(true,snapshot or {open=false})
        r.hidden.step(mode==2 and snapshot or nil)
    end
    function r:update(dt)
        if self.stopping then
            if self.requested then self:shutdown() end
            return
        end
        self.elapsed=(self.elapsed or 0)+math.max(1,(tonumber(dt) or 1/60)*1000)
        if self.elapsed<(self.retry_at or 0) then return end
        if not bridge then
            local ok,dll=pcall(loaded_companion)
            if not ok or not dll then self.retry_at=self.elapsed+500;return end
            bridge=dll
        end
        local ok,why=pcall(function()
            if not self.owned then
                if bridge.dbf_hud_base()==0 or bridge.dbf_hud_option('enabled')==0 then
                    if self.requested then stop() end
                    self.retry_at=self.elapsed+500
                    return
                end
                self.admit=self.admit or wheel_admission(bridge)
                local admitted,reason=self.admit('core',self.elapsed)
                if admitted then
                    local s=options(bridge)
                    admitted,reason=surface_ready(s.selection_mode_ordered,s.experimental_layout,self.elapsed)
                end
                if not admitted then
                    if self.requested then stop() end
                    report('Waiting for HUD witness: '..tostring(reason))
                    self.retry_at=self.elapsed+500
                    return
                end
                if not self.b then
                    local prepared,b=pcall(native_backend,bridge)
                    if not prepared then
                        report('Waiting for game image: '..tostring(b))
                        self.retry_at=self.elapsed+500
                        return
                    end
                    self.b=b
                end
                self.requested=true
                if bridge.dbf_hud_acquire(self.token)~=1 then return end
                self.owned=true
                initialize()
            end
            frame(math.max(0.001,math.min(tonumber(dt) or 1/60,0.05)))
        end)
        if not ok then
            report('HUD stopped: '..tostring(why))
            self:shutdown()
        end
    end
    return r
end

return {dbf_hud_runtime=dbf_hud_runtime}
