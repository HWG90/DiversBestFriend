-- Synthetic build-26251122 game memory for offline DBF-ASS checks, plus the
-- fake_win32.so stand-in for kernel32/user32 (ffi.load is redirected to it).
-- dofile(...)(guards_path) returns the image layout.
return function(guards_path,layouts_path)
local ffi=require('ffi')
local function slurp(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
-- Data modules of the CFFI tree carry the PORT51 adapter line; it is not needed here.
local function data(path)return assert(loadstring((slurp(path):gsub("^local PORT51=mod%.require%('port51/compat51%.lua'%)\n",''))))()end
-- Synthetic memory: every simulated address is a real address of an owned buffer.
local regions={}
local function region(size)
    local storage=ffi.new('uint8_t[?]',size+16)
    local address=math.floor((tonumber(ffi.cast('uintptr_t',storage))+15)/16)*16
    regions[#regions+1]={storage=storage,first=address,last=address+size}
    return address
end
local function inside(address,size)
    for _,r in ipairs(regions)do if address>=r.first and address+size<=r.last then return true end end
    return false
end
local function put(address,ctype,value)ffi.cast(ctype..' *',address)[0]=value end
local function bytes(address,text)ffi.copy(ffi.cast('void *',address),text,#text)end
local function floats(address,list)for i,v in ipairs(list)do ffi.cast('float *',address)[i-1]=v end end

local image=region(0x3200000)
local root=region(0x400000)
local state=region(0xb0000)
bytes(image,'MZ');put(image+60,'uint32_t',0x100)
bytes(image+0x100,'PE\0\0');put(image+0x108,'uint32_t',1793123839)
put(image+0x150,'uint32_t',0x3382000) -- SizeOfImage, checked by the weapon status reader
if layouts_path then
    for _,s in ipairs(data(layouts_path).signatures)do
        bytes(image+s[1],(s[2]:gsub('..',function(h)return string.char(tonumber(h,16))end)))
    end
end
put(image+0x2e28788,'uint64_t',root);put(root+0x24e334,'uint8_t',1)
put(image+0x2ce1508,'uint64_t',state);put(state+0xac29c,'uint32_t',4)
put(root+0x258,'uint32_t',17);put(root+0x820,'uint32_t',17)
local panel=root+0x24e340+0x146940
local list=panel+0x1040
put(panel+0x38769,"uint8_t",1)
for _,link in ipairs({{panel,root+0x820},{root+0x820,root+0x258},{panel+0x110,panel},{panel+0x220,panel+0x110},{list,panel+0x220}})do
    put(link[1]+0xf0,'uint64_t',link[2])
end
local function geometry(address,w,h,m)floats(address+0x24,{w,h});floats(address+0x64,m)end
geometry(root+0x258,1920,1080,{1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1})
geometry(list,600,800,{1,0,0,0, 0,1,0,0, 0,0,1,0, 960,0,540,1})
local stamina=root+0x24e340+0x5778
put(stamina+0xf0,'uint64_t',root+0x820);put(stamina+0x110+0xf0,'uint64_t',stamina)
geometry(stamina+0x110,300,10,{1,0,0,0, 0,1,0,0, 0,0,1,0, 810,0,120,1})
for index=0,15 do
    local card=list+0x110+index*0x3760
    put(card+0xf0,'uint64_t',list)
    if index<5 then
        put(card+0x36f0,'uint8_t',1);floats(card+12,{280,60});floats(card+0x3740,{0,index*64})
        floats(card+4,{10+index,20+index});floats(card+20,{1,1});floats(card+44,{0.5,0.5});floats(card+60,{0.5,0.5})
        put(card+0x3748,'uint32_t',100+index)
    end
end

-- Fake Win32: fake_win32.so (C) stands in for kernel32/user32, so reads are
-- real FFI C calls as in the game. Build it with the command in fake_win32.c.
ffi.cdef[[
    void fake_add_range(uintptr_t, uintptr_t);
    void fake_set_module(void *);
    unsigned long long fake_reads(void);
]]
local here=arg[0]:match('^(.*)/[^/]*$') or '.'
local fake=ffi.load(here..'/fake_win32.so')
for _,r in ipairs(regions)do fake.fake_add_range(r.first,r.last)end
fake.fake_set_module(ffi.cast('void *',image))
local stats=setmetatable({},{__index=function(_,k)if k=='reads' then return tonumber(fake.fake_reads())end end})
for _,g in ipairs(data(guards_path).native_guards)do
    assert(g.rva+#g.bytes<0x3200000);bytes(image+g.rva,g.bytes)
end
local real_load=ffi.load
ffi.load=function(name)if name=='kernel32' or name=='user32' then return fake end;return real_load(name)end
package.preload.cffi=function()return ffi end

return {image=image,root=root,state=state,panel=panel,list=list,regions=regions,stats=stats,put=put}
end
