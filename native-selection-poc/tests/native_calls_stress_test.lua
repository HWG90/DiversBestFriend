-- Production helper bodies with real LuaJIT type parsing; no game calls.
local ffi=require('ffi')
local f=assert(io.open('native-selection-poc/native.lua','rb'));local source=f:read('*a');f:close()
local first=assert(source:find("    local input_handler=",1,true))
local last=assert(source:find("    ffi.cdef 'unsigned long long GetTickCount64",first,true))
local base=0x10000000
local casts,calls=0,{}
local native={
 [0xa900d0]=function(c) assert(c==123);calls.input=(calls.input or 0)+1 end,
 [0xa8e850]=function(c) assert(c==123);calls.open=(calls.open or 0)+1;return 1 end,
 [0xa8fb50]=function(c) assert(c==123);calls.close=(calls.close or 0)+1 end,
 [0x1327f50]=function(z,event) assert(z==0 and (event==0x39425a55 or event==0xdd274583));calls.sound=(calls.sound or 0)+1 end,
 [0xa10820]=function(e,out,key,kind,z1,z2) assert(e==456 and key==7 and kind==136 and z1==0 and z2==0);out[0]=0xffffffff;calls.scramble=(calls.scramble or 0)+1 end,
 [0xa93e90]=function(w,slot) assert(w==789 and slot==5);calls.slot=(calls.slot or 0)+1 end,
}
local proxy=setmetatable({}, {__index=ffi})
proxy.cast=function(t,v)
    if type(t)=='string' and t:find('(*)',1,true) then
        ffi.cast(t,0) -- production ctype allocation only, never invoke the native address
        casts=casts+1
        return assert(native[v-base])
    end
    return ffi.cast(t,v)
end
local backend={}
local env=setmetatable({require=function() return proxy end,backend=backend,base=base,
    pointer=function() return 65536 end}, {__index=_G})
local chunk=assert(loadstring("local ffi=require('ffi')\n"..source:sub(first,last-1)))
setfenv(chunk,env);chunk()
assert(casts==6,'native input helpers bind exactly once')
for i=1,20000 do
    backend.invoke_input(123)
    assert(backend.open_input(123))
    backend.close_input(123)
    backend.ui_sound(i%2==0 and 'move' or 'confirm')
    assert(backend.scramble_effect(456,7,136)==4294967295)
    backend.request_stratagem_slot(789)
end
assert(casts==6,'callbacks must not parse more function types')
for _,name in ipairs({'input','open','close','sound','scramble','slot'}) do assert(calls[name]==20000,name) end
print('Native FFI stress passed: 120000 helper calls, six casts, original arguments/results preserved.')
