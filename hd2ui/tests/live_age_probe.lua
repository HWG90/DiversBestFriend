package.path = './?.lua;' .. package.path
local MR = require('hd2ui.memreader')
local LS = require('hd2ui.live_scan')
local ffi = require('ffi')
local k = ffi.load('kernel32')
ffi.cdef[[
void *OpenProcess(unsigned long access, int inherit, unsigned long pid);
int ReadProcessMemory(void *p, const void *a, void *buf, unsigned long long size, unsigned long long *got);
unsigned long GetLastError(void);
int CloseHandle(void *h);
]]
local pid = LS.find_process('helldivers2.exe')
local base = LS.module_base(pid, 'game.dll')
print('pid', pid, 'base', base and string.format('0x%X', base))
local h = k.OpenProcess(0x410, 0, pid)
print('OpenProcess', h, 'err', tonumber(k.GetLastError()))
local buf = ffi.new('uint8_t[4096]'); local got = ffi.new('unsigned long long[1]')
for _, n in ipairs({4, 4096}) do
  got[0] = 0
  local r = k.ReadProcessMemory(h, ffi.cast('const void *', base), buf, n, got)
  print(('RPM(%d) ret=%d got=%d lasterr=%d'):format(n, tonumber(r), tonumber(got[0]), tonumber(k.GetLastError())))
  -- ret 0 could also be a stale lasterr from a previous call: GetLastError is only
  -- meaningful when ret==0.
end
-- also try a second handle, and reading MR's own handle path:
local ok = MR.attach(pid, 'helldivers2.exe')
local st = MR.state()
print('MR.attach', ok, 'handle', tostring(st.process))
print('MR.read(base,4) ->', MR.read(base, 4))
k.CloseHandle(h)
