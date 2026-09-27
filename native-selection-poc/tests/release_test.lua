local function source(name)
    local f=assert(io.open('native-selection-poc/'..name,'rb'));local s=f:read('*a');f:close();return s
end
local make=assert(loadstring(source('input.lua')..'\n'..source('release.lua')..'\nreturn release_controller'))()
local state={identity='player',component=5,hud=9,hold=true,down=true,unobstructed=true,menu_active=true,clean=true}
local calls,logs=0,{}
local input={release_state=function() return state end,select_released=function(kind,armed)
    assert(kind==33 and armed.component==5);calls=calls+1;return 'matched'
end}
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
arm();input.select_released=function() error('native rejection') end;release();release()
assert(#logs==3 and logs[3]:find('Release cancelled:',1,true),'failure is reported once')
print('release controller checks passed')
