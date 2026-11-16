local env=setmetatable({}, {__index=_G})
for _,name in ipairs({'wheel_input','wheel_selection','wheel_release'}) do
    local exports=setfenv(assert(loadfile((arg[1] or 'hellforge/hud')..'/'..name..'.lua')),env)()
    for k,v in pairs(exports) do env[k]=v end
end
local now,pulses=0,{}
local function advance(job)
    pulses[#pulses+1]=now
    job.sent=job.sent+1
    return job.sent==#job.code
end
local function job() return {kind=1,code={1,2,3,4,1,2,3,4,1},sent=0} end
local snapshot={identity=1,open=true,list_order=true,rows={{address=10,kind=1,list_y=0,entry=0}}}
local buttons={next=false,previous=false,confirm=false}
local function selection()
    local s=env.selection_controller({begin=job,advance=advance},function() end)
    s.step(snapshot,buttons,-1)
    buttons.confirm=true;s.step(snapshot,buttons,0);buttons.confirm=false
    return s
end
local s=selection()
for frame=1,50 do now=frame*1000/60;s.step(snapshot,buttons,now) end
print(string.format('Nine-arrow confirm at 60 Hz / 70 ms: %.1f ms from confirm',pulses[9]))
if arg[2]=='baseline' then return end
assert(#pulses==9 and pulses[9]<=9*70,'normal cadence must not accumulate one frame per direction')
-- The same cadence drives shortcuts and Hold-release jobs.
pulses={}
local release=env.release_controller({begin_shortcut=job,hold_release=function() end,
    advance_release=advance,end_release=function() end},function() end)
assert(release.shortcut(1,snapshot,0))
for frame=1,34 do now=frame*1000/60;release.step(true,snapshot,10,now,false) end
assert(#pulses==9 and release.job.finished and pulses[9]<=9*70)
-- A stall discards missed beats and never emits a catch-up burst.
pulses={};s=selection()
now=17;s.step(snapshot,buttons,now)
now=400;s.step(snapshot,buttons,now)
now=401;s.step(snapshot,buttons,now)
assert(#pulses==2)
now=470;s.step(snapshot,buttons,now);assert(#pulses==3)
snapshot.identity=2;now=480;s.step(snapshot,buttons,now)
assert(not s.job and #pulses==3,'HUD replacement cancels before another pulse')
snapshot.identity=1
-- Instant final-arrow settle remains tied to physical button release.
pulses={};local j=job();j.instant=true;j.trigger_down=true
now=0;assert(not env.advance_all(advance,j,now) and #pulses==8)
j.trigger_down=false;now=10;assert(not env.advance_all(advance,j,now))
now=109;assert(not env.advance_all(advance,j,now) and #pulses==8)
now=110;assert(env.advance_all(advance,j,now) and #pulses==9)
assert(env.next_input_at(0,17,0)==17)
print('Confirm/shortcut cadence, stall recovery, HUD replacement and instant settle passed')
