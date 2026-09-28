local f=assert(io.open('native-selection-poc/menu_latch.lua','rb'));local source=f:read('*a');f:close()
local make=assert(loadstring(source..'\nreturn native_menu_latch'))()
local ffi=require('ffi')
local function u(n) local v=ffi.new('uint32_t[1]',n);return ffi.string(v,4) end
local mem,table_at,owner,actions={},0x300000,0x200000,0x400000
local function put(at,s) for i=1,#s do mem[at+i-1]=s:sub(i,i) end end
local function read(at,n) local t={};for i=0,n-1 do if not mem[at+i] then return nil end;t[#t+1]=mem[at+i] end;return table.concat(t) end
local function num(s,o) if not s then return nil end;local a,b,c,d=s:byte(o+1,o+4);return a+b*256+c*65536+d*16777216 end
local source_type=owner+808+32*(97*5)+24
local hold=u(0x2ff41)..u(10)..u(2)..u(0)..u(0)
local press=u(0xff41)..u(10)..u(0)..u(0)..u(0)
local fail_at,writes
local b={base=0,read=read,u32=num,pointer=function(at)
    if at==0x347cf18 then return owner elseif at==owner+686800 then return table_at end
end,replace_bytes=function(at,old,new)
    if at==fail_at then error('simulated write failure') end
    assert(read(at,#old)==old);put(at,new);writes=writes+1;return true
end}
local function reset()
    mem={};writes=0;fail_at=nil;table_at=0x300000
    put(owner+686808,u(256));put(table_at,u(0x50000)..u(2)..hold..press)
    put(source_type,u(2));put(actions+24,u(2))
end
reset();local lease=make(b).acquire(owner,actions)
assert(read(table_at+8,20)==press and read(table_at+28,20)==press)
assert(read(source_type,4)==u(0) and read(actions+24,4)==u(0))
-- Emulate fresh native input evaluation reading the patched mapping.
put(source_type,read(table_at+16,4));put(actions+24,read(source_type,4));lease.refresh()
lease.restore(true)
assert(read(table_at+8,20)==hold and read(table_at+28,20)==press,'original Press row must stay Press')
assert(read(source_type,4)==u(2) and read(actions+24,4)==u(2))
reset();fail_at=actions+24
assert(not pcall(make(b).acquire,owner,actions));fail_at=nil
assert(read(table_at+8,20)==hold and read(source_type,4)==u(2),'partial acquisition rolls back')
reset();lease=make(b).acquire(owner,actions)
local edit=u(0xff41)..u(11)..u(0)..u(0)..u(0)
put(table_at+8,edit);assert(not pcall(lease.refresh));lease.restore(true)
assert(read(table_at+8,20)==edit,'new user mapping is not overwritten')
reset();lease=make(b).acquire(owner,actions)
local old_table=table_at;table_at=0x500000;put(table_at,read(old_table,48));lease.restore(false)
assert(read(table_at+8,20)==hold and read(actions+24,4)==u(0),'relocated map restored, stale avatar untouched')
reset();put(owner+686808,u(128));assert(not pcall(make(b).acquire,owner,actions) and writes==0)
print('Menu latch passed: native re-evaluation, exact restoration, partial rollback, existing Press, user edits, map relocation and bounds.')
