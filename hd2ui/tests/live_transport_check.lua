package.path = './?.lua;' .. package.path
local MR = require('hd2ui.memreader')
local LS = require('hd2ui.live_scan')

local pid, pname = LS.find_process('helldivers2.exe')
print('find_process -> ' .. tostring(pid) .. ' / ' .. tostring(pname))
local ok, err = MR.attach(pid, pname)
print('attach -> ' .. tostring(ok) .. ' ' .. tostring(err))
local base, size = LS.module_base(pid, 'game.dll')
print('module_base -> ' .. (base and string.format('0x%X size=%d', base, size) or 'FAIL ' .. tostring(size)))

local mz = MR.read(base, 2)
print('read base 2 bytes -> ' .. tostring(mz) .. ' = ' .. (mz and (mz:byte(1) == 0x4D and mz:byte(2) == 0x5A and 'MZ ok' or 'not MZ') or ''))
print('e_lfanew -> ' .. tostring(MR.read_u32(base + 0x3C)))

local rok, n = LS.enum_regions()
print('enum_regions -> ' .. tostring(rok) .. ' count=' .. tostring(n))
local committed, img = 0, 0
for i = 1, n do
  local r = LS.region(i)
  committed = committed + r.size
  if r.image then img = img + r.size end
end
print(('%d regions, total committed ~%.1f GB (image ~%.0f MB)'):format(n, committed / 2^30, img / 2^20))

-- Quick bounded scan: 40 MB of the game.dll image for 'MZ' (sanity, cheap).
LS.state().regions = { { base = base, size = 40 * 1048576, image = true, private = false } }
LS.state().chunk = 1048576
local res = LS.scan_bytes('MZ', true)
print('scan MZ in first 40MB of image -> hits=' .. tostring(res and res.total))

-- PE signature at e_lfanew:
local e_lfanew = MR.read_u32(base + 0x3C)
local pe_sig = e_lfanew and MR.read(base + e_lfanew, 4)
print('PE sig @ e_lfanew -> ' .. tostring(pe_sig))
print('DONE')
