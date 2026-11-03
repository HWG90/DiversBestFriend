-- A current-build module can expose its initialized code after mod startup.
-- Never cast/use game entry points until the complete fingerprint set passes.
local function native_startup(factory,clock)
 local backend,next_probe,reason=nil,0,nil
 local self={}
 function self.poll()
  if backend then return backend end
  local now=clock()
  if now<next_probe then return nil,reason end
  local ok,value=pcall(factory)
  if ok then
   assert(value,'Native backend factory returned no backend')
   backend=value;return backend
  end
  local message=tostring(value)
  if not message:find('Native signature changed:',1,true)then error(value,0)end
  reason='waiting for native fingerprints: '..message:match('Native signature changed: (.*)')
  next_probe=now+1
  return nil,reason
 end
 return self
end
return {native_startup=native_startup}
