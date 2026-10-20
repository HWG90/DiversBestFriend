-- Mod Options Menu API 3 keys explicit IDs independently of caller chunk source.
local function exercise(legacy)
 local categories,options,registrations={},{},0
 local current_origin
 local menu={get=function()end,on_change=function()end,set=function()return true end}
 menu.register_option=function(id,spec)
  registrations=registrations+1
  local key=(not legacy and spec.mod_id) or (current_origin..spec.mod)
  categories[key]=categories[key] or {}
  assert(not options[id], 'duplicate option registration')
  options[id]=spec;table.insert(categories[key],id)
  return true
 end
 local function module(name,export)
  local f=assert(io.open('native-selection-poc/'..name..'.lua'))
  local s=f:read('*a');f:close()
  return assert(loadstring(s..'\nreturn '..export,'@src/'..name..'.lua'))()
 end
 local settings=module('settings','canary_settings')
 local blacklist=module('mission_blacklist','mission_blacklist_settings')
 local state,blacklist_state={registered={}},{enabled={},save=function()return true end}
 current_origin='settings';settings(menu,state,{})
 current_origin='mission_blacklist';blacklist(menu,blacklist_state,nil)
 local count=0;for _,rows in pairs(categories)do count=count+1 end
 assert(registrations==31)
 for i=1,100 do
  current_origin='settings';settings(menu,state,{})
  current_origin='mission_blacklist';blacklist(menu,blacklist_state,nil)
 end
 assert(registrations==31,'unchanged state must not register again')
 return count
end
assert(exercise(true)==2,'legacy source ownership reproduces duplicate')
assert(exercise(false)==1,'stable mod ID merges all controls')
print('Menu identity: legacy duplicate reproduced; options share one owner; idle registration stays unchanged.')
