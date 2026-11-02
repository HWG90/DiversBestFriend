-- Offline check of a source tree against a real game.dll capture (a mapped image
-- from a live session, RVA = file offset), in stock LuaJIT:
--   luajit offline_capture.lua <tree> <game-<stamp>.merged.bin> [expect]
-- expect: 'pass' (default) or 'refuse' (a tree for another build must refuse).
-- The capture is the module image behind fake_win32.so; its all-zero pages read
-- as unavailable, like game code the protection runtime has not decrypted yet.
-- Runs the tree's own checks: native_backend() (PE stamp gate and the 92 code
-- witnesses), the 15 terminal witnesses, and the icon palette reads of
-- icon_colors.lua. Only reads; no game code is called.
local tree,capture,expect=arg[1],arg[2],arg[3] or 'pass'
local ffi=require('ffi')
local here=arg[0]:match('^(.*)/[^/]*$') or '.'
local function slurp(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
ffi.cdef[[
    void fake_add_range(uintptr_t, uintptr_t);
    void fake_set_module(void *);
    void fake_deny_zero_pages(uintptr_t, const unsigned char *, size_t);
]]
local fake=ffi.load(here..'/fake_win32.so')
local raw=slurp(capture)
local pages=math.ceil(#raw/4096)
local storage=ffi.new('uint8_t[?]',pages*4096+4096)
local image=math.floor((tonumber(ffi.cast('uintptr_t',storage))+4095)/4096)*4096
ffi.copy(ffi.cast('void *',image),raw,#raw)
local zero=ffi.new('unsigned char[?]',pages)
local cold=0
for p=0,pages-1 do
    if not raw:sub(p*4096+1,p*4096+4096):find('[^%z]') then zero[p]=1;cold=cold+1 end
end
raw=nil;collectgarbage()
fake.fake_add_range(image,image+pages*4096)
fake.fake_set_module(ffi.cast('void *',image))
fake.fake_deny_zero_pages(image,zero,pages)
local real_load=ffi.load
ffi.load=function(name)if name=='kernel32' or name=='user32' then return fake end;return real_load(name)end

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
local passed=0
local function check(label,cond)assert(cond,label);passed=passed+1;print('PASS '..label)end
print(string.format('capture %s: %d pages, %d unavailable',capture:match('[^/]*$'),pages,cold))

local ok,b=pcall(scope.native_backend)
if expect=='refuse' then
    check('tree refuses this build ('..tostring(b)..')',not ok and tostring(b):find('Unsupported game build',1,true))
    print('PASS refuse ('..passed..' checks)');return
end
check('native_backend passes the stamp gate and every readable witness'..(ok and '' or ': '..tostring(b)),ok)
local deferred=b.deferred()
for _,name in ipairs(deferred)do print('deferred (page not captured): '..name)end
check(string.format('%d of %d witnesses checked now, %d deferred',#scope.native_guards-#deferred,#scope.native_guards,#deferred),true)
check('widget setters ready',b.widgets_ready())

local terminal=mod.require('src/terminal_guards.lua')
local good,missing=0,{}
for _,g in ipairs(terminal)do
    local bytes=b.read(b.base+g.rva,#g.bytes)
    if bytes==nil then missing[#missing+1]=g.name else assert(bytes==g.bytes,'terminal witness changed: '..g.name);good=good+1 end
end
check(string.format('terminal witnesses: %d match, %d not captured %s',good,#missing,table.concat(missing,',')),good+#missing==#terminal)

-- icon_colors.lua palette: same reads and range checks as rgba().
local source=slurp(tree..'/src/icon_colors.lua')
local rvas={}
for rva in source:gmatch('rgba%((0x%x+)%)')do rvas[#rvas+1]=tonumber(rva)end
-- Stratagem categories 0..4 (stratagem-catalog-live.json); the table ends there.
for category=0,4 do rvas[#rvas+1]=0x2cd0c40+category*16 end
local v=ffi.new('float[4]')
for _,rva in ipairs(rvas)do
    local bytes=assert(b.read(b.base+rva,16),'palette unreadable')
    ffi.copy(v,bytes,16)
    for i=0,3 do assert(v[i]==v[i] and v[i]>=0 and v[i]<=1,string.format('invalid palette at 0x%x',rva))end
end
check(string.format('icon palette: %d vectors in range (%s)',#rvas,table.concat({source:match('foreground=rgba%((0x%x+)%)'),source:match('background=rgba%((0x%x+)%)')},', ')),true)
-- The palette vectors are the ones the native icon code loads: the
-- icon_channel_palette witness holds two lea r8,[rip+disp32] to them.
local palette
for _,g in ipairs(scope.native_guards)do if g.name=='icon_channel_palette' then palette=g end end
local targets={}
for at in palette.bytes:gmatch('()\76\141\5')do
    local d=ffi.new('int32_t[1]');ffi.copy(d,palette.bytes:sub(at+3,at+6),4)
    targets[#targets+1]=palette.rva+at-1+7+d[0]
end
local fg,bg=tonumber(source:match('foreground=rgba%((0x%x+)%)')),tonumber(source:match('background=rgba%((0x%x+)%)'))
check(string.format('icon palette rvas are the witness lea targets (%s)',table.concat({string.format('0x%x',targets[1] or 0),string.format('0x%x',targets[2] or 0)},', ')),
    #targets==2 and targets[1]==fg and targets[2]==bg)
print('PASS capture ('..passed..' checks)')
