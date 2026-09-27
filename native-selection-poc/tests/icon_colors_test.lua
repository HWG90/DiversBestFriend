local ffi=require('ffi')
local function source(n) local f=assert(io.open('native-selection-poc/'..n,'rb'));local s=f:read('*a');f:close();return s end
local base=0x10000000
local uniforms,material,texture,calls={},nil,nil,0
local native={
 [0x1450230]=function(icon,m,t,flag) assert(icon==12345 and flag==0);material=m;texture=t;calls=calls+1 end,
 [0x144f6e0]=function(icon) assert(icon==12345);return 65536 end,
 [0x14498c0]=function(icon,key,v) assert(icon==12345);uniforms[key]={v[0],v[1],v[2],v[3]} end,
}
local proxy=setmetatable({}, {__index=ffi})
proxy.cast=function(t,v) if t:find('(*)',1,true) then return assert(native[v-base]) end;return ffi.cast(t,v) end
local env=setmetatable({require=function() return proxy end,radial={full_color=true}},{__index=_G})
local chunk=assert(loadstring(source('icon_colors.lua')..'\nreturn configure_stratagem_icon'));setfenv(chunk,env);local apply=chunk()
local palette={}
palette[0x3318040+3*16]={1,0.2,0.6,0.8}
palette[0x21e2d30]={1,1,1,0.9333333}
palette[0x21e2d60]={0.2,0,0,0}
local b={base=base,read=function(p,n) assert(n==16);return ffi.string(ffi.new('float[4]',assert(palette[p-base])),16) end}
local info={category=3,texture=ffi.string(ffi.new('uint64_t[1]',999),8)}
apply(b,12345,info)
assert(material==0xaf73e09d6d725398ULL and texture==999)
assert(math.abs(uniforms[0x28723f4d][3]-0.6)<1e-6)
assert(uniforms[0x851fd4fd][2]==1 and uniforms[0x10c353af][2]==0)
env.radial.full_color=false;uniforms={};apply(b,12345,info)
assert(material==0x57fcf14ad069020bULL and next(uniforms)==nil,'off restores raw material')
env.radial.full_color=true;apply(b,12345,info)
assert(material==0xaf73e09d6d725398ULL and uniforms[0x28723f4d],'reenable restores channel colors')
info.category=16;local before=calls;assert(not pcall(apply,b,12345,info) and calls==before,'reject invalid category before native assignment')
info.category=3;palette[0x3318040+48][1]=0/0
assert(not pcall(apply,b,12345,info) and calls==before,'reject invalid palette before native assignment')
print('Icon colors passed: native mask material, exact palette channels, toggle restore and invalid-data guards.')
