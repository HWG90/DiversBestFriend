-- LLL live lifecycle: detach owned native UI before allowing reload.
local started,core=false,nil
return {live_lua_api=1,name="Diver's Best Friend",version='R46',
 on_enable=function()
  assert(not started,'ASS is already enabled')
  assert(not rawget(_G,'DiversBestFriend'),'Another ASS provider is already active')
  for _,name in ipairs({'src/layout.lua','src/guards.lua','src/native.lua','src/menu_latch.lua','src/mission_blacklist.lua','src/input.lua','src/pointing.lua','src/camera.lua','src/icon_colors.lua','src/duplicate.lua','src/emote.lua','src/expanded.lua','src/cooldown_dock.lua','src/binding_warning.lua','src/binding_defaults.lua','src/selection.lua','src/release.lua','src/blacklist.lua','src/settings.lua','src/feedback.lua','src/hud_plus.lua','src/foliage_compat.lua','src/entry.lua'}) do
   for key,value in pairs(mod.require(name)) do mod.scope[key]=value end
  end
  assert(type(mod.scope.update)=='function','ASS startup callback unavailable')
  rawset(_G,'update',mod.scope.update);core=rawget(_G,'DiversBestFriend');started=true
  local fields={}
  for key,value in pairs(mod.config.preferences or {}) do
   local id=key
   fields[id]={type=type(value),get=function()local m=rawget(_G,'ModOptionsMenu');return m and m.get('native_stratagem_radial.'..id)end,
    set=function(v)local m=rawget(_G,'ModOptionsMenu');if not m or not m.set then return false,'Mod Options Menu unavailable' end;local ok,why=m.set('native_stratagem_radial.'..id,v);local owner=rawget(_G,'DiversBestFriend');if ok and owner and owner.invalidate_settings then owner.invalidate_settings()end;return ok,why end}
  end
  mod.expose('dbf',{settings=fields})
 end,
 on_disable=function()
  if not started then return true end
  local owner=rawget(_G,'DiversBestFriend')
  if not owner or owner~=core or type(owner.shutdown)~='function' then return false,'ASS cleanup owner unavailable' end
  local ok,why=owner.shutdown();if not ok then return false,why end
  started=false;return true
 end}
