-- Offline check of deferred native witnesses (game code pages the protection
-- runtime has not decrypted yet read as unavailable), in stock LuaJIT:
--   luajit offline_cold.lua <source tree>
-- Denied ranges in fake_win32.so make chosen pages unreadable. No game code is
-- ever called: a refused binding must raise before calling.
local tree=arg[1]
local ffi=require('ffi')
local here=arg[0]:match('^(.*)/[^/]*$') or '.'
local env=dofile(here..'/synthetic_image.lua')(tree..'/src/guards.lua')
local image,put=env.image,env.put
ffi.cdef[[
    void fake_deny_range(uintptr_t, uintptr_t);
    void fake_clear_denies(void);
    void fake_allow_writes(int);
]]
local fake=ffi.load(here..'/fake_win32.so')
local function slurp(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
local function load_tree()
    local scope=setmetatable({},{__index=_G});local cache={}
    local mod={dir=tree,config={},scope=scope};scope.mod=mod
    function mod.require(name)
        if cache[name]~=nil then return cache[name]end
        local chunk=assert(loadstring(slurp(tree..'/'..name),'@'..name));setfenv(chunk,scope)
        local value=chunk();if value==nil then value=true end;cache[name]=value;return value
    end
    for _,name in ipairs({'src/layout.lua','src/guards.lua','src/native.lua'})do
        for k,v in pairs(mod.require(name))do scope[k]=v end
    end
    return scope
end
local passed=0
local function check(label,cond)assert(cond,label);passed=passed+1;print('PASS '..label)end
local guards=load_tree().native_guards
local function guard(name)for _,g in ipairs(guards)do if g.name==name then return g end end;error(name)end

-- Stratagem card code (dock constructor/tick and their witnesses) and the HUD
-- root data witness page are cold; everything else is resident.
local cold={{0x16ba000,0x16bc000},{0xaf5000,0xaf6000}}
for _,r in ipairs(cold)do fake.fake_deny_range(image+r[1],image+r[2])end
local scope=load_tree()
local ok,b=pcall(scope.native_backend)
check('backend initializes with cold pages',ok)
local deferred=table.concat(b.deferred(),',')
check('cold witnesses are deferred ('..#b.deferred()..')',deferred:find('dock_card_constructor',1,true) and deferred:find('hud_root',1,true))
check('resident witnesses are not deferred',not deferred:find('widget_constructor',1,true))
check('widget setters are ready',b.widgets_ready())
local create=b.fn('void (*)(uintptr_t, uint64_t, uint64_t, uint64_t, int32_t, uint32_t)',0x16ba420)
local init=b.fn('void (*)(uintptr_t, uint32_t)',0x12de550)
check('resident function binds directly',type(init)=='cdata' and b.callable(init))
check('cold function is not callable',type(create)=='function' and not b.callable(create))
local called,why=pcall(create,0,0ULL,0ULL,0ULL,0,0)
check('cold function refuses before running',not called and tostring(why):find('Native code not resident yet',1,true))
fake.fake_allow_writes(1)
local target=env.state+0x100
local wrote,werr=pcall(b.pulse_byte,target,1)
check('writes wait for deferred data-layout witnesses',not wrote and tostring(werr):find('Native code not resident yet',1,true))
check('self-verified writes are allowed',pcall(b.pulse_byte,target,1,true) and ffi.cast('uint8_t *',target)[0]==1)

-- The game runs the code: pages become readable and the witnesses are checked.
fake.fake_clear_denies()
check('cold function becomes callable once resident',b.callable(create))
check('writes resume once the layout witness passes',pcall(b.pulse_byte,target,0))
check('nothing remains deferred',#b.deferred()==0)

-- A deferred witness that turns out different still refuses.
for _,r in ipairs(cold)do fake.fake_deny_range(image+r[1],image+r[2])end
local b2=load_tree().native_backend()
local tick=b2.fn('void (*)(uintptr_t, float, uint32_t, uintptr_t)',0x16baed0)
local g=guard('dock_card_tick');local at=image+g.rva
local saved=ffi.cast('uint8_t *',at)[0];ffi.cast('uint8_t *',at)[0]=bit.bxor(saved,0xff)
fake.fake_clear_denies()
local ok2,why2=pcall(b2.callable,tick)
check('changed deferred witness refuses',not ok2 and tostring(why2):find('Native signature changed: dock_card_tick',1,true))
ffi.cast('uint8_t *',at)[0]=saved

-- A readable mismatch at startup still refuses the build.
local h=guard('widget_constructor');local hat=image+h.rva
local hs=ffi.cast('uint8_t *',hat)[0];ffi.cast('uint8_t *',hat)[0]=bit.bxor(hs,0xff)
local ok3,why3=pcall(load_tree().native_backend)
check('readable mismatch still refuses at startup',not ok3 and tostring(why3):find('Native signature changed: widget_constructor',1,true))
ffi.cast('uint8_t *',hat)[0]=hs
print(string.format('PASS cold (%d checks)',passed))
