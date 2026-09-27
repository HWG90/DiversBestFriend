-- Only a sampled Hold falling edge can confirm. A disappearing HUD alone
-- never confirms, and explicit Confirm suppresses release for this opening.
local function release_controller(input,report)
    local armed,blocked
    local self={status='Disabled'}
    function self.reset() armed=nil;blocked=nil end
    function self.step(enabled,snapshot,selected,now,explicit)
        if not enabled or not snapshot then self.status='Disabled or no valid radial snapshot';self.reset();return end
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
                local called,message=pcall(input.select_released,previous.kind,previous)
                self.status=tostring(message)
                report((called and 'Release: ' or 'Release cancelled: ')..tostring(message))
            end
            return
        end
        if blocked or not snapshot.open or not state.menu_active then return end
        for _,row in ipairs(snapshot.rows) do
            if row.address==selected and selectable_kind(row.kind) then
                armed={kind=row.kind,time=now,snapshot_identity=snapshot.identity,
                    identity=state.identity,component=state.component,hud=state.hud}
                self.status='Armed kind '..row.kind
                return
            end
        end
    end
    return self
end
