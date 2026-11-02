local M={}
function M.new(factories)
 local memory=mod.require('src/weapon_status_memory.lua')
 local layouts=mod.require('src/weapon_status_layouts.lua')
 local ammo=mod.require('src/weapon_status_ammo.lua')
 local backend,reader
 local renderer,b;local clock,next_poll=0,0
 local self={status='waiting_native'}
 local api=rawget(_G,'DiversBestFriend')
 local function publish()if api then api.weapon_status=self.status;api.weapon_readout=self.last end end
 function self.update(dt)
  clock=clock+(type(dt)=='number'and math.max(0,math.min(dt,1))or 1/60)
  if clock<next_poll then return end;next_poll=clock+.1
  if not b then
   local ok,value=pcall(factories.native_backend)
   if not ok then self.status='waiting_native';self.reason=tostring(value);next_poll=clock+1;publish();return end
   b=value
   local ready,why=pcall(function()
    backend=backend or memory.native()
    reader=reader or mod.require('src/weapon_status_reader.lua').new(backend,memory,layouts,ammo)
    renderer=mod.require('src/weapon_status_strip.lua').new(b,factories.duplicate_cards(b))
   end)
   if not ready then b=nil;self.status='waiting_native';self.reason=tostring(why);next_poll=clock+1;publish();return end
  end
  local ok,why=pcall(function()
   local root=b.pointer(b.base+0x2e28788)
   if not root or not b.valid(root)then renderer.hide();self.status='no_gameplay_hud';return end
   local model=reader.poll()
   if not model then renderer.hide();self.status=reader.status;self.last=nil;return end
   renderer.draw(root,model);self.last={weapon=model.resource_hex,fire_mode=model.fire_mode,rpm=model.rpm,rpm_index=model.rpm_index,ammo_mode=model.ammo_mode,zoom=model.zoom,zoom_index=model.zoom_index}
   self.status=renderer.status
  end)
  if not ok then
   self.status='refused';self.reason=tostring(why);next_poll=clock+1
   -- Hide only a still-owned tree. Keep all storage until cleanup is proved.
   if renderer then pcall(renderer.hide)end
  end
  publish()
 end
 function self.close()
  if renderer then local ok,why=renderer.close();if not ok then return false,why end end
  if backend then backend.close()end;self.status='closed';publish();return true
 end
 return self
end
return M
