-- Offline check of DBF-ASS's native backend in stock LuaJIT (no game).
-- Loads a source tree the way the archive does (scope + mod.require), replaces
-- kernel32/user32 with a fake that reads a synthetic build-26251122 image, then
-- runs native_backend(), snapshot() and the scalar readers.
--   luajit offline_backend.lua <tree> <out.txt> [iterations]
-- The CFFI tree runs through its own PORT51 adapter (cffi aliased to ffi), so
-- both trees can be compared on identical memory.
local tree,out_path,iterations=arg[1],arg[2],tonumber(arg[3] or 0)
local ffi=require('ffi')
local function slurp(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end

local here=arg[0]:match('^(.*)/[^/]*$') or '.'
local env=dofile(here..'/synthetic_image.lua')(tree..'/src/guards.lua')
local image,root,state,panel,list,stats,put=env.image,env.root,env.state,env.panel,env.list,env.stats,env.put
-- Archive-style loader.
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

local lines={}
local function emit(...)local t={};for i=1,select('#',...)do t[i]=tostring((select(i,...)))end;lines[#lines+1]=table.concat(t,' ')end
local function dump(v,indent)
    indent=indent or ''
    if type(v)~='table' then return type(v)=='number' and string.format('%.6g',v) or tostring(v) end
    local keys={};for k in pairs(v)do keys[#keys+1]=k end
    table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
    local parts={}
    for _,k in ipairs(keys)do
        local value=v[k]
        if k=='identity' or k=='panel' or k=='list' or k=='dock_parent' or k=='address' or k=='dock_source' then value=value-root end
        parts[#parts+1]=indent..'  '..tostring(k)..'='..(k=='geometry' and tostring(value) or dump(value,indent..'  '))
    end
    return '{\n'..table.concat(parts,'\n')..'\n'..indent..'}'
end

local b=scope.native_backend()
emit('base_ok',b.base==image)
-- The read path (this tree only; the CFFI and mechanical trees have no such field and print no line).
if b.memory~=nil then emit('memory',b.memory) end
emit('valid',b.valid(root))
local s,why=b.snapshot()
emit('snapshot_open',dump(s),why)
for _,p in ipairs({'position','size','scale','anchor','pivot','animation_a','animation_b'})do
    emit('get',p,dump(b.get(list+0x110,p)))
end
emit("dock_text_position",pcall(b.dock_text_position,s,10,20))
emit('focused',b.focused())
emit('pointer_unaligned',b.pointer(image+1))
emit('u32_of_read',b.u32(b.read(state+0xac29c,4),0))
emit('release_clean',b.release_owned_ui(nil,nil,nil,nil,{}))
put(panel+0x38769,'uint8_t',0)
local closed,closed_why=b.snapshot()
emit('snapshot_closed',dump(closed),closed_why)
local docked=b.snapshot(true)
emit('snapshot_dock',dump(docked))
put(panel+0x38769,'uint8_t',7)
emit('snapshot_badflag',b.snapshot())
put(panel+0x38769,'uint8_t',1)
put(list+0x110+0xf0,'uint64_t',0)
emit('valid_broken',b.valid(root))
put(list+0x110+0xf0,'uint64_t',list)
emit('reads_for_checks',stats.reads)

-- Bytes of garbage one snapshot leaves for the collector (GC stopped while measured).
local function garbage(n)
    collectgarbage('collect');collectgarbage('stop')
    local before=collectgarbage('count')
    for _=1,n do assert(b.snapshot())end
    local used=(collectgarbage('count')-before)*1024/n
    collectgarbage('restart');return used
end
if iterations>0 then
    local open_garbage=garbage(200)
    put(panel+0x38769,'uint8_t',0);local closed_garbage=garbage(200);put(panel+0x38769,'uint8_t',1)
    emit(string.format('GARBAGE open: %.0f B/snapshot; closed: %.0f B/snapshot',open_garbage,closed_garbage))
    local before=stats.reads
    local t=os.clock()
    for _=1,iterations do assert(b.snapshot())end
    local open_time=os.clock()-t
    local open_reads=(stats.reads-before)/iterations
    put(panel+0x38769,'uint8_t',0)
    before=stats.reads;t=os.clock()
    for _=1,iterations do assert(b.snapshot())end
    local closed_time=os.clock()-t
    put(panel+0x38769,'uint8_t',1)
    emit(string.format('BENCH open: %.2f us/snapshot, %.1f reads; closed: %.2f us/snapshot, %.1f reads',
        open_time/iterations*1e6,open_reads,closed_time/iterations*1e6,(stats.reads-before)/iterations))
end
local f=assert(io.open(out_path,'w'));f:write(table.concat(lines,'\n'),'\n');f:close()
for _,l in ipairs(lines)do if l:match('^BENCH')or l:match('^GARBAGE')then print(l)end end
