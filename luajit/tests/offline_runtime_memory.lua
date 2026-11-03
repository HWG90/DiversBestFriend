-- Offline check that DBF-ASS prefers the runtime's hd2.memory (version 1) and
-- that it changes nothing the mod reports. offline_backend.lua's flow runs on
-- one tree in one process, twice:
--   1. as is, with no hd2.memory anywhere: DBF-ASS reads through kernel32;
--   2. with package.preload['hd2.memory'] set to a stand-in whose read_into and
--      module sit over the same fake kernel32 ReadProcessMemory, counting calls.
-- The backend names its read path (backend.memory, printed by offline_backend
-- as a "memory" line): kernel32 in run 1, hd2.memory v1 in run 2. Apart from
-- that line the two output texts must be identical, and the stand-in must have
-- served every read (count > 0, and equal to the fake's ReadProcessMemory calls).
-- A stand-in that reports another VERSION, or a module that is not a table, is
-- ignored; a module() that finds no game.dll falls back to GetModuleHandleA.
--   luajit offline_runtime_memory.lua <tree> <out>
-- <out> is a path prefix: it writes <out>.kernel32.txt and <out>.hd2memory.txt.
local tree,out_prefix=arg[1],arg[2]
assert(tree and out_prefix,'usage: luajit offline_runtime_memory.lua <tree> <out>')
local ffi=require('ffi')
local here=arg[0]:match('^(.*)/[^/]*$') or '.'
local function slurp(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
-- Each flow builds a 55 MB synthetic image that the fake keeps a range for; a
-- collection would free the first one under it.
collectgarbage('stop')

ffi.cdef[[
    void *GetModuleHandleA(const char *name);
    void *GetCurrentProcess(void);
    int ReadProcessMemory(void *, const void *, void *, size_t, size_t *);
    unsigned long long fake_reads(void);
]]
local fake=ffi.load(here..'/fake_win32.so')

-- hd2.memory as the runtime ships it (hd2_memory.lua, spec section 2), for the
-- calls DBF-ASS makes. Addresses are numbers or cdata, bad memory gives false
-- or nil, wrong argument types raise, and n over 16 MiB or an address at or
-- above 2^47 is refused. The fake cannot tell modules apart, so only game.dll
-- exists. Reads go through the fake ReadProcessMemory, so its counter sees them.
local MAX_READ,MAX_ADDRESS=16*1024*1024,2^47
local const_void_p=ffi.typeof('const void *')
local function standin(version)
    local process,got=fake.GetCurrentProcess(),ffi.new('size_t[1]')
    local counts={read_into=0,module=0}
    local mem={VERSION=version}
    local function address(value,name)
        if type(value)=='number' then return value end
        if type(value)=='cdata' then return tonumber(ffi.cast('uintptr_t',value)) end
        error('hd2.memory: '..name..' expects a number or cdata address',3)
    end
    function mem.read_into(addr,n,buf)
        counts.read_into=counts.read_into+1
        local at=address(addr,'read_into')
        if type(n)~='number' then error('hd2.memory: read_into expects a number size',2) end
        if type(buf)~='cdata' or not (n>=1 and n<=MAX_READ) or not (at<MAX_ADDRESS) then return false end
        return fake.ReadProcessMemory(process,ffi.cast(const_void_p,at),buf,n,got)~=0 and tonumber(got[0])==n
    end
    function mem.module(name)
        counts.module=counts.module+1
        if name~=nil and type(name)~='string' then error('hd2.memory: module expects a module name or nil',2) end
        if name~='game.dll' then return nil end
        local base=tonumber(ffi.cast('uintptr_t',fake.GetModuleHandleA(name)))
        if not base or base==0 then return nil end
        -- SizeOfImage, from the PE header the synthetic image carries
        local bytes=ffi.cast('uint8_t *',base)
        local pe=ffi.cast('uint32_t *',bytes+60)[0]
        return base,ffi.cast('uint32_t *',bytes+pe+0x50)[0]
    end
    return mem,counts
end

-- The stand-in itself, so a drifting stand-in cannot make the comparison pass.
do
    local mem=standin(1)
    local buf=ffi.new('uint8_t[8]')
    assert(mem.VERSION==1)
    assert(mem.read_into(0x10,4,buf)==false,'unmapped memory must give false')
    assert(mem.read_into(2^47,1,buf)==false and mem.read_into(2^47+4096,1,buf)==false,'2^47 and up must give false')
    assert(mem.read_into(0x10000,MAX_READ+1,buf)==false,'over 16 MiB must give false')
    assert(mem.read_into(ffi.cast('void *',0x10),4,buf)==false,'cdata address must be accepted')
    assert(not pcall(mem.read_into,'x',4,buf) and not pcall(mem.read_into,0x10000,'4',buf),'wrong types must raise')
    assert(mem.module('no_such.dll')==nil)
    assert(not pcall(mem.module,12))
end

-- One run of offline_backend.lua's flow. Its reads_for_checks line is the fake's
-- process-wide counter; made per-run here (and in the file) so the texts compare.
local function flow(label)
    local saved=arg
    local path=out_prefix..'.'..label..'.txt'
    _G.arg={[0]=here..'/offline_backend.lua',tree,path}
    local before=tonumber(fake.fake_reads())
    local ok,why=pcall(dofile,here..'/offline_backend.lua')
    _G.arg=saved
    assert(ok,why)
    local reads=tonumber(fake.fake_reads())-before
    local text=slurp(path):gsub('reads_for_checks (%d+)',function(n)return 'reads_for_checks '..(tonumber(n)-before)end)
    local f=assert(io.open(path,'wb'));f:write(text);f:close()
    return text,reads
end
-- The "memory" line, and the text with that line's value masked.
local function read_path(text) return text:match('\nmemory ([^\n]*)\n') end
local function without_read_path(text) return (text:gsub('\nmemory [^\n]*\n','\nmemory <path>\n')) end
local function first_difference(a,b)
    local la,lb={},{}
    for l in (a..'\n'):gmatch('(.-)\n')do la[#la+1]=l end
    for l in (b..'\n'):gmatch('(.-)\n')do lb[#lb+1]=l end
    for i=1,math.max(#la,#lb)do
        if la[i]~=lb[i] then return string.format('line %d: %q vs %q',i,tostring(la[i]),tostring(lb[i])) end
    end
end

-- Run 1: the kernel32 path. Nothing may provide hd2.memory.
package.loaded['hd2.memory']=nil;package.preload['hd2.memory']=nil
local text1,reads1=flow('kernel32')
assert(package.loaded['hd2.memory']==nil,'run 1 must not have loaded hd2.memory')
assert(reads1>0,'run 1 made no ReadProcessMemory calls')

-- Run 2: the same flow with the runtime's module present.
local mem,counts=standin(1)
package.loaded['hd2.memory']=nil;package.preload['hd2.memory']=function()return mem end
local text2,reads2=flow('hd2memory')
package.loaded['hd2.memory']=nil;package.preload['hd2.memory']=nil

print(string.format('kernel32 run: %d ReadProcessMemory calls; hd2.memory run: %d read_into, %d module, %d ReadProcessMemory calls',
    reads1,counts.read_into,counts.module,reads2))
print(string.format('read path: run 1 %q, run 2 %q',tostring(read_path(text1)),tostring(read_path(text2))))
assert(read_path(text1)=='kernel32','run 1 must name kernel32 as its read path, got '..tostring(read_path(text1)))
assert(read_path(text2)=='hd2.memory v1','run 2 must name hd2.memory v1 as its read path, got '..tostring(read_path(text2)))
text1,text2=without_read_path(text1),without_read_path(text2)
if text1~=text2 then error('output differs between the kernel32 and hd2.memory runs: '..first_difference(text1,text2),0) end
assert(counts.read_into>0,'hd2.memory stand-in saw 0 read_into calls: DBF-ASS did not use it')
assert(counts.module>0,'hd2.memory stand-in saw 0 module calls: DBF-ASS did not ask for game.dll')
assert(counts.read_into==reads2,'some reads bypassed hd2.memory: '..counts.read_into..' read_into vs '..reads2..' ReadProcessMemory')
assert(reads2==reads1,'the two runs made different numbers of reads: '..reads1..' vs '..reads2)

-- The remaining branches, each built by hand on run 2's image (still
-- registered with the fake): another flow would need another synthetic image,
-- and the fake holds ranges for two. module_value is what require gives.
local function backend_with(module_value)
    local scope=setmetatable({},{__index=_G})
    local cache={}
    local mod={dir=tree,config={},scope=scope}
    scope.mod=mod
    function mod.require(name)
        if cache[name]~=nil then return cache[name]end
        local chunk=assert(loadstring(slurp(tree..'/'..name),'@'..name));setfenv(chunk,scope)
        local value=chunk();if value==nil then value=true end;cache[name]=value;return value
    end
    for _,name in ipairs({'src/layout.lua','src/guards.lua','src/native.lua'})do
        for k,v in pairs(mod.require(name))do scope[k]=v end
    end
    package.loaded['hd2.memory']=nil;package.preload['hd2.memory']=function()return module_value end
    local ok,backend=pcall(scope.native_backend)
    package.loaded['hd2.memory']=nil;package.preload['hd2.memory']=nil
    assert(ok,backend)
    return backend
end
local game_dll=tonumber(ffi.cast('uintptr_t',fake.GetModuleHandleA('game.dll')))
-- A runtime that is not version 1 is ignored: the kernel32 path again.
do
    local other,other_counts=standin(2)
    local backend=backend_with(other)
    assert(backend and backend.base>0)
    assert(other_counts.read_into==0 and other_counts.module==0,'a version 2 hd2.memory must be ignored')
    assert(backend.memory=='kernel32','a version 2 hd2.memory must leave the kernel32 path, got '..tostring(backend.memory))
end
-- A module that loads but is not a table (a loader returning true) is ignored.
do
    local backend=backend_with(true)
    assert(backend and backend.base==game_dll,'a non-table hd2.memory: base must come from GetModuleHandleA')
    assert(backend.memory=='kernel32','a non-table hd2.memory must leave the kernel32 path, got '..tostring(backend.memory))
end
-- module() finding no game.dll: base falls back to GetModuleHandleA, and the
-- reads still go through hd2.memory.
do
    local mem,nil_counts=standin(1)
    function mem.module(name) nil_counts.module=nil_counts.module+1;return nil end
    local backend=backend_with(mem)
    assert(backend and backend.base==game_dll,'module() nil: base must come from GetModuleHandleA')
    assert(nil_counts.module==1,'module() must be asked once, got '..nil_counts.module)
    assert(nil_counts.read_into>0,'module() nil: the reads must still go through hd2.memory')
    assert(backend.memory=='hd2.memory v1','module() nil keeps the hd2.memory path, got '..tostring(backend.memory))
end
print('PASS runtime memory: identical output apart from the read path, '..counts.read_into..' reads through hd2.memory; '..
    'version 2, non-table and module() nil branches as expected')
