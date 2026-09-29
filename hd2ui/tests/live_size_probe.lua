package.path = './?.lua;' .. package.path
local MR = require('hd2ui.memreader')
local LS = require('hd2ui.live_scan')
local pid = LS.find_process('helldivers2.exe')
print('pid', pid)
local ok = MR.attach(pid, 'helldivers2.exe')
print('attach', ok)
local base = LS.module_base(pid, 'game.dll')
print('base', base and string.format('0x%X', base))
for _, n in ipairs({1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096}) do
  local s = MR.read(base, n)
  print(('read %4d -> %s'):format(n, s and ('OK len=%d first="%s"'):format(#s, s:sub(1, 2)) or 'FAIL'))
end
