-- Only a sampled Hold falling edge can confirm. A disappearing HUD alone
-- never confirms, and explicit Confirm suppresses release for this opening.
local function release_controller(input,report)
    local armed,blocked
    local self={status='Disabled',job=nil,interval_ms=70}
    function self.reset()
        if self.job then
            local ok,why=pcall(input.end_release,self.job,true)
            if not ok then report('Release cleanup failed: '..tostring(why)) end
        end
        self.job=nil;armed=nil;blocked=nil
    end
    function self.step(enabled,snapshot,selected,now,explicit)
        if not enabled or not snapshot then self.status='Disabled or no valid radial snapshot';self.reset();return end
        if self.job then
            local job=self.job
            if snapshot.identity~=job.snapshot_identity or now>job.deadline or explicit then
                self.status='Release cancelled: HUD changed, timeout or explicit input';report(self.status);self.reset();return
            end
            if job.finished then
                local checked,done,message=pcall(input.release_complete,job)
                if not checked then
                    self.status='Release completion cancelled: '..tostring(done);report(self.status);self.reset();return
                end
                if not done then
                    if self.status~=message then self.status=message;report(message) end
                    return
                end
                local ok,why=pcall(input.end_release,job,false)
                self.job=nil;blocked=true
                self.status=ok and (message..'; original menu trigger restored') or 'Release cleanup failed: '..tostring(why)
                report(self.status);return
            end
            local ok,why=pcall(function()
                input.hold_release(job)
                if now>=job.next_at then
                    local done,message=input.advance_release(job)
                    self.status=message;report('Release: '..message)
                    job.finished=done;job.next_at=now+job.interval_ms
                    if done then job.deadline=now+2000 end
                end
            end)
            if not ok then self.status='Release cancelled: '..tostring(why);report(self.status);self.reset() end
            return
        end
        local ok,state=pcall(input.release_state)
        if not ok then self.status=tostring(state);self.reset();return end
        if not state.unobstructed or not state.hold then
            self.status=not state.hold and 'Requires a Hold menu binding' or 'Blocked by native UI overlay'
            self.reset();return
        end
        self.status='Waiting for a highlighted Hold release'
        if not state.clean then blocked=true;armed=nil end
        if explicit then blocked=true;armed=nil end
        local previous=armed
        armed=nil
        if not state.down then
            local skip=blocked;blocked=nil
            if not skip and previous and now>=previous.time and now-previous.time<=250
                and snapshot.identity==previous.snapshot_identity
                and state.identity==previous.identity and state.component==previous.component
                and state.hud==previous.hud then
                local called,job=pcall(input.begin_release,previous.kind,previous)
                if called then
                    local interval=self.interval_ms
                    if type(interval)~='number' or interval~=interval or interval<0 or interval>250 then interval=70 end
                    job.interval_ms=interval;job.next_at=now;job.snapshot_identity=snapshot.identity;job.address=previous.address
                    job.deadline=now+math.max(3000,#job.code*interval+1500)
                    self.job=job
                    local held,why=pcall(input.hold_release,job)
                    if held then self.status='Latched native menu for kind '..previous.kind..'; interval='..interval..'ms'
                    else self.status='Release cancelled: '..tostring(why);self.reset() end
                else self.status='Release cancelled: '..tostring(job) end
                report(self.status)
            end
            return
        end
        if blocked or not snapshot.open or not state.menu_active then return end
        for _,row in ipairs(snapshot.rows) do
            if row.address==selected and selectable_kind(row.kind) then
                armed={kind=row.kind,address=row.address,time=now,snapshot_identity=snapshot.identity,
                    identity=state.identity,component=state.component,hud=state.hud}
                self.status='Armed kind '..row.kind
                return
            end
        end
    end
    return self
end
