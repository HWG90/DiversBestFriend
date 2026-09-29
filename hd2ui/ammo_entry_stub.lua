-- hd2ui/ammo_entry_stub.lua -- R5 ISOLATION STUB: proves whether the ammo
-- addon's PRESENCE (archives/resources/manifest) crashes boot, separate from
-- anything its real code does. Does: logging + framework require + no-op
-- update hook. Does NOT: touch ffi, memory, rendering, presets, options.
local sr = rawget(_G, 'stingray')
if type(sr) ~= 'table' then return { installed = false, reason = 'no stingray' } end
if rawget(_G, '__DBF_AMMO_INSTALLED') then return { installed = true } end

local log_path
do
  local ok, d = pcall(os.getenv, 'DBF_AMMO_DIR')
  if (not ok or type(d) ~= 'string' or d == '') then
    local ok2, appdata = pcall(os.getenv, 'APPDATA')
    if ok2 and type(appdata) == 'string' and appdata ~= '' then d = appdata .. '/Arrowhead/Helldivers2' end
  end
  if type(d) == 'string' and d ~= '' then log_path = d .. '/hd2ui_ammo.log' end
end
local function log(msg)
  if not log_path then return end
  local ok, f = pcall(io.open, log_path, 'a')
  if not ok or not f then return end
  local t = os.date and os.date('%H:%M:%S') or '?'
  pcall(f.write, f, string.format('[%s] %s\n', t, tostring(msg)))
  pcall(f.close, f)
end
log('dbf-ammo r5 STUB start')

local HD2 = rawget(_G, '__DBF_HD2UI')
if type(HD2) ~= 'table' then
  local ok, v = pcall(function() return require('mods/dbf/hd2ui') end)
  if ok and type(v) == 'table' then HD2 = v end
end
log('dbf-ammo r5 STUB framework=' .. tostring(type(HD2) == 'table' and HD2.version or 'missing'))

local old_update = rawget(_G, 'update')
if type(old_update) ~= 'function' then
  log('dbf-ammo r5 STUB no global update(); not installing')
  return { installed = false, reason = 'no update' }
end
rawset(_G, '__DBF_AMMO_INSTALLED', true)
rawset(_G, 'update', function(...) return old_update(...) end)
log('dbf-ammo r5 STUB installed')
return { installed = true, version = 'r5-stub' }
