local f=assert(io.open('native-selection-poc/foliage_compat.lua','rb'));local s=f:read('*a');f:close()
local make=assert(loadstring(s..'\nreturn foliage_compatibility'))()
local keys={'hd2runtime/domains/bombardment_payload','hd2runtime/domains/weapon_clone','hd2runtime/domains/custom_payloads'}
local raw=string.char(197,0,0,0)..string.rep('\0',0x110-4)
local actual=raw:sub(1,0xf4)..'\2\0\0\0'..raw:sub(0xf4+5)
local function hex(s)return(s:gsub('.',function(c)return string.format('%02x',c:byte())end))end
local function fixture()
 local loaded={};for _,key in ipairs(keys)do loaded[key]={source={build='F5FEE03DCFDB'}} end
 local m=loaded[keys[1]];m.shellRows={['197']=hex(raw)}
 local env={HD2RuntimeLibraryApi1={version='0.40.0'},package={loaded=loaded},FoliagePassThrough={version='1.0',applied=true,patched=true,
 rows={base=100000,list={{target={197},pointer=100004,offset=248,template=2}}}}}
 local reads=0
 local c=make(function(at,n)reads=reads+1;if at==100004+0xf4 and n==4 then return actual:sub(0xf4+1,0xf4+4)end;if at==100004 then return actual end end,
 function()return 100004 end,0,function(p)return p end,env)
 return c,env,m,function()return reads end
end
local c,e,m,reads=fixture();c.refresh();assert(c.changed==1 and m.shellRows['197']==hex(actual))
local n=reads();for i=1,10000 do c.refresh()end;assert(reads()==n,'unchanged owner is idle')
c,e,m=fixture();actual=actual:sub(1,30)..'X'..actual:sub(32);c.refresh();assert(c.changed==0 and m.shellRows['197']==hex(raw),'unrelated donor edit remains refused')
actual=raw:sub(1,0xf4)..'\2\0\0\0'..raw:sub(0xf4+5)
c,e,m=fixture();e.FoliagePassThrough.rows.list[1].pointer=100008;c.refresh();assert(c.changed==0,'wrong owner pointer refused')
c,e,m=fixture();e.FoliagePassThrough.version='2.0';c.refresh();assert(c.changed==0,'unknown owner unchanged')
c,e,m=fixture();e.package.loaded[keys[2]].source.build='unknown';c.refresh();assert(c.changed==0,'unknown build unchanged')
c,e,m=fixture();e.FoliagePassThrough.applied=false;c.refresh();assert(c.changed==0);e.FoliagePassThrough.applied=true;c.refresh();assert(c.changed==1,'deferred owner supported')
print('Foliage compatibility: exact variant, foreign edits, ownership, build/version, deferred startup and 10000 idle frames passed')
