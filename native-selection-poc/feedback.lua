-- UI-only sounds: one tick per changed target, one cue per accepted job.
local function selection_feedback(b,report)
    local owner,last_target,last_job,last_tick=nil,nil,nil,-math.huge
    local failed=false
    local self={}
    local function play(event)
        if failed then return end
        local ok,why=pcall(b.ui_sound,event)
        if not ok then failed=true;report('Selection sound unavailable: '..tostring(why)) end
    end
    function self.step(enabled,snapshot,selected,job,now,list_mode)
        if not enabled or not snapshot then owner=nil;last_target=nil;last_job=nil;return end
        local fresh=owner~=snapshot.identity
        if fresh then owner=snapshot.identity;last_target=nil;last_job=nil;last_tick=-math.huge end
        if job and job~=last_job then play('confirm');last_tick=now end
        local target
        if snapshot.open then
            for _,row in ipairs(snapshot.rows or {}) do
                if row.address==selected then target=tostring(row.entry)..':'..tostring(row.kind);break end
            end
        end
        if target and target~=last_target and not job and not (fresh and list_mode) and now-last_tick>=60 then
            play('move');last_tick=now
        end
        last_target=target;last_job=job
    end
    return self
end
