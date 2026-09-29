local function source(name)
    local f=assert(io.open('native-selection-poc/'..name,'rb'));local s=f:read('*a');f:close();return s
end
local make=assert(loadstring(source('input.lua')..'\n'..source('selection.lua')..'\nreturn selection_controller'))()
local snapshot={open=true,identity=1,rows={{address=10,kind=33}}}
local neutral={next=false,previous=false,confirm=false}
for _,interval in ipairs({0,70,250}) do
    local calls=0
    local c=make({begin=function() return {kind=33,code={1,2,3},sent=0} end,
        advance=function(job) calls=calls+1;job.sent=job.sent+1;return job.sent==3,'input' end},function() end)
    c.interval_ms=interval;c.step(snapshot,neutral,0)
    c.step(snapshot,{confirm=true},1);c.step(snapshot,neutral,2);assert(calls==1)
    c.interval_ms=125 -- active job retains its starting interval
    if interval>0 then c.step(snapshot,neutral,2+interval-1);assert(calls==1) end
    c.step(snapshot,neutral,2+interval);assert(calls==2)
    c.step(snapshot,neutral,2+interval*2);assert(calls==3 and not c.job)
end
local c=make({begin=function() return {kind=33,code={1,2,3,4,1,2,3,4,1,2,3,4}} end},function() end)
c.interval_ms=250;c.step(snapshot,neutral,0);c.step(snapshot,{confirm=true},1)
assert(c.job.deadline==4501,'longest code gets enough time at the maximum interval')
for _,invalid in ipairs({'x',999,-5,0/0}) do
    local guarded=make({begin=function() return {kind=33,code={1,2,3},sent=0} end},function() end)
    guarded.interval_ms=invalid;guarded.step(snapshot,neutral,0);guarded.step(snapshot,{confirm=true},1)
    assert(guarded.job and guarded.job.interval_ms==70,'invalid intervals fall back to the default')
end
print('Input interval passed: 0/70/250 ms, no early inputs, active-job stability, long-code timeout and invalid-interval fallback.')
