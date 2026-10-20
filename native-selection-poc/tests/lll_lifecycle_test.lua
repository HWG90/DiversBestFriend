local f=assert(io.open('adapters/main.lua'));local text=f:read('*a');f:close()
local env=setmetatable({}, {__index=_G});env._G=env
local original=function()return 7,nil,9 end;env.update=original
local closes=0
for generation=1,100 do
 local refuse=false
 local scope={}
 env.mod={scope=scope,config={preferences={}},expose=function()end,require=function(name)
  if name=='src/entry.lua' then
   local previous=env.update
   local api={shutdown=function()
    if refuse then return false,'owned root still linked' end
    closes=closes+1;env.DiversBestFriend=nil;env.NativeStratagemRadial=nil;env.update=previous;return true
   end}
   env.DiversBestFriend=api;env.NativeStratagemRadial=api
   scope.update=function(...)return previous(...)end
  end
  return {}
 end}
 local chunk=assert(loadstring(text));setfenv(chunk,env);local lifecycle=chunk()
 lifecycle.on_enable();assert(env.DiversBestFriend)
 local a,b,c=env.update();assert(a==7 and b==nil and c==9)
 if generation==1 then
  refuse=true;local ok,why=lifecycle.on_disable();assert(ok==false and why=='owned root still linked' and env.DiversBestFriend)
  refuse=false
 end
 assert(lifecycle.on_disable())
 assert(env.update==original and env.DiversBestFriend==nil)
end
assert(closes==100)
print('LLL lifecycle: 100 fresh enable/disable generations, callback tuples, alias ownership and failed-cleanup refusal passed')
