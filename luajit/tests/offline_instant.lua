-- Offline check of input.lua's advance_all: instant jobs send all but the last
-- arrow at once, and hold the last one until the trigger has been up 100 ms.
--   luajit offline_instant.lua <source tree>
local tree=arg[1] or '../divers_best_friend'
local function slurp(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
local scope=setmetatable({},{__index=_G})
scope.mod={require=function(name)return assert(loadstring(slurp(tree..'/'..name)))()end}
local chunk=assert(loadstring(slurp(tree..'/src/input.lua'),'@src/input.lua'));setfenv(chunk,scope)
local advance_all=chunk().advance_all
local function job(code,instant)
    return {code=code,sent=0,instant=instant}
end
local calls=0
local function advance(j)
    calls=calls+1;j.sent=j.sent+1
    return j.sent==#j.code,'sent '..j.sent
end
local failures=0
local function check(name,ok)print((ok and 'PASS ' or 'FAIL ')..name);if not ok then failures=failures+1 end end

local j=job({1,2,3,4},true);j.trigger_down=true
local done,message=advance_all(advance,j,1000)
check('held Confirm: all but the last arrow at once',not done and message==nil and j.sent==3)
done=advance_all(advance,j,1200)
check('still held: last arrow waits',not done and j.sent==3)
j.trigger_down=false
done=advance_all(advance,j,1300)
check('released: settling starts',not done and j.sent==3 and j.settle_at==1400)
done=advance_all(advance,j,1350)
check('released 50 ms: still settling',not done and j.sent==3)
j.trigger_down=true
done=advance_all(advance,j,1360)
check('pressed again: settle resets',not done and j.settle_at==nil)
j.trigger_down=false
advance_all(advance,j,1370)
done,message=advance_all(advance,j,1470)
check('released 100 ms: last arrow sent',done and j.sent==4 and message=='sent 4')

j=job({1,2,3},true)
done=advance_all(advance,j,0)
check('no trigger known (release/shortcut): settles from first call',not done and j.sent==2 and j.settle_at==100)
done=advance_all(advance,j,100)
check('then completes',done and j.sent==3)

j=job({1,2,3},false);calls=0
done,message=advance_all(advance,j,0)
check('paced job: one arrow per call',not done and j.sent==1 and calls==1 and message=='sent 1')

j=job({3},true);j.trigger_down=true
done=advance_all(advance,j,0)
check('one-arrow code waits for release',not done and j.sent==0)
print(failures==0 and 'PASS instant' or ('FAIL instant: '..failures))
os.exit(failures==0 and 0 or 1)
