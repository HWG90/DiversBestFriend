local function source(name)
    local f=assert(io.open('native-selection-poc/'..name,'rb'));local s=f:read('*a');f:close();return s
end
local make=assert(loadstring(source('input.lua')..'\n'..source('release.lua')..'\nreturn release_controller'))()
local state={identity='player',component=5,hud=9,hold=true,down=true,unobstructed=true,menu_active=true,clean=true}
local calls,logs=0,{}
local input={release_state=function() return state end,begin_release=function(kind,armed)
    assert(kind==33 and armed.component==5);calls=calls+1;return {code={1,2},kind=kind}
end,hold_release=function() end,end_release=function() end,advance_release=function() return true,'matched' end,
    release_complete=function() return true,'native finished' end}
local r=make(input,function(s) logs[#logs+1]=s end)
local open={identity=9,open=true,rows={{address=10,kind=33}}}
local closed={identity=9,open=false}
local function arm() r.reset();state.down=true;r.step(true,open,10,0,false) end
local function release(s,t) state.down=false;r.step(true,s or closed,nil,t or 16,false) end
arm();release();assert(calls==1,'Hold release confirms')
release();assert(calls==1,'only once')
arm();r.step(true,open,nil,8,false);release();assert(calls==1,'dead zone cancels')
arm();r.step(true,open,10,8,true);release();assert(calls==1,'explicit confirm suppresses duplicate')
arm();r.step(false,open,10,8,false);release();assert(calls==1,'disabled/focus loss cancels')
arm();release(closed,251);assert(calls==1,'stale frame cancels')
arm();release({identity=99,open=false});assert(calls==1,'HUD change cancels')
arm();state.identity='other';release();assert(calls==1,'player change cancels');state.identity='player'
arm();state.unobstructed=false;release();assert(calls==1,'overlay cancels');state.unobstructed=true
arm();state.hold=false;release();assert(calls==1,'toggle binding does not release-select');state.hold=true
arm();state.clean=false;r.step(true,open,10,8,false);state.clean=true;release();assert(calls==1,'manual input cancels session')
arm();release(open);assert(calls==2,'release also works before HUD closes')
arm();input.begin_release=function() error('native rejection') end;release();release()
assert(logs[#logs]:find('Release cancelled:',1,true),'failure is reported')
print('release controller checks passed')

local sent,holds,ends=0,0,0
input.begin_release=function() return {code={1,2},kind=33} end
input.hold_release=function() holds=holds+1 end
input.advance_release=function() sent=sent+1;return sent==2,'sent '..sent end
input.end_release=function() ends=ends+1 end
r.interval_ms=70;arm();release(closed,16)
assert(r.job and sent==0,'release starts a held job rather than an instant burst')
r.step(true,open,nil,17,false);assert(sent==1)
r.step(true,open,nil,86,false);assert(sent==1,'no early second direction')
r.step(true,open,nil,87,false);assert(sent==2 and r.job.finished and ends==0)
input.release_complete=function() return false,'native equip pending' end
r.step(true,open,nil,88,false);r.step(true,open,nil,188,false)
assert(r.job and ends==0,'do not restore while native equip is pending')
input.release_complete=function() return true,'native finished' end
r.step(true,closed,nil,200,false);assert(not r.job and ends==1,'restore only after native completion')
arm();release(closed,100);r.step(false,open,nil,101,false);assert(not r.job and ends==2,'disable releases owned hold')
print('Paced release checks passed: interval, final-frame hold and cancellation cleanup.')
arm();release(closed,100)
input.hold_release=function() error('native menu closed') end
r.step(true,closed,nil,101,false)
assert(not r.job and ends==3 and r.status:find('native menu closed',1,true),'early native closure cleans up without retry')
input.hold_release=function() end
arm();release(closed,100);r.step(true,open,nil,4000,false)
assert(not r.job and ends==4,'timeout restores Hold')
sent=1;arm();release(closed,100);r.step(true,open,nil,101,false)
input.release_complete=function() return false,'native still pending' end
r.step(true,open,nil,2101,false);assert(r.job,'completion wait allows its bounded deadline')
r.step(true,open,nil,2102,false);assert(not r.job and ends==5,'stuck post-match completion restores mapping')
