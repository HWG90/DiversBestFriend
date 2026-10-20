-- MDL API 2 restart-only adapter. No game access or module loading at import.
local G=rawget(_G,'_G') or _G
local started=false
local modules={'src/layout.lua','src/guards.lua','src/native.lua','src/menu_latch.lua','src/mission_blacklist.lua','src/input.lua','src/pointing.lua','src/camera.lua','src/icon_colors.lua','src/duplicate.lua','src/emote.lua','src/expanded.lua','src/cooldown_dock.lua','src/binding_warning.lua','src/binding_defaults.lua','src/selection.lua','src/release.lua','src/blacklist.lua','src/settings.lua','src/feedback.lua','src/hud_plus.lua','src/foliage_compat.lua','src/entry.lua'}
return {name="Diver's Best Friend",version='R46',author='Goose',
 on_enable=function(ctx)
  assert(ctx.api==2 and type(ctx.dir)=='string' and type(ctx.on_cleanup)=='function','MDL API 2 required')
  assert(not started and not rawget(G,'DiversBestFriend'),'Another ASS provider is active; restart required')
  -- Keep diagnostics private if the host has no archived Shared Loader facade.
  local logs={api=1,log_directory=ctx.dir,open_log=function(name)
   assert(name=='DiversBestFriend.log' or name=='DiversBestFriend-native.log','Unexpected diagnostic filename')
   return assert(G.io.open(ctx.dir..'/'..name,'wb'))
  end}
  local scope=setmetatable({_G=G,rawget=function(t,k)
   if t==G and k=='CowboyBingusModLoader' then return G.rawget(G,k) or logs end
   return G.rawget(t,k)
  end},{__index=G})
  local chunks={}
  for _,name in ipairs(modules)do
   local f=assert(G.io.open(ctx.dir..'/'..name,'rb'),'Missing ASS module '..name)
   local s=f:read('*a');f:close()
   chunks[#chunks+1]=assert(G.loadstring(s,'@ASS/'..name))
  end
  ctx.on_cleanup(function()if started then return false,'ASS requires a game restart' end;return true end)
  for _,chunk in ipairs(chunks)do G.setfenv(chunk,scope);for k,v in pairs(chunk())do scope[k]=v end end
  assert(type(scope.update)=='function','ASS startup callback unavailable')
  G.rawset(G,'update',scope.update);started=true
 end,
 on_disable=function()if not started then return true end;return false,'ASS requires a game restart' end}
