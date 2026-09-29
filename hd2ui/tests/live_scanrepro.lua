package.path = './?.lua;' .. package.path
local MR = require('hd2ui.memreader')
local LS = require('hd2ui.live_scan')
local pid = LS.find_process('helldivers2.exe')
local ok = MR.attach(pid, 'helldivers2.exe')
local base = LS.module_base(pid, 'game.dll')
print('attach', ok, 'base', string.format('0x%X', base))
local rok, n = LS.enum_regions()
print('enum', rok, n)
-- sanity read at base right now
print('read base 4096 ->', MR.read(base, 4096) and 'OK' or 'FAIL')
-- now read first page of each of the first 12 regions + a few mid-regions
local idxs = {1, 2, 3, 4, 5, 100, 500, 1000, 5000, 12000, 20000, 24000}
for _, i in ipairs(idxs) do
  local r = LS.region(i)
  if r then
    local s = MR.read(r.base, 4096)
    local s4 = MR.read(r.base, 4)
    print(('region %d base=%s size=%d read4096=%s read4=%s'):format(
      i, string.format('0x%X', r.base), r.size, s and 'OK' or 'FAIL', s4 and 'OK' or 'FAIL'))
  end
end
