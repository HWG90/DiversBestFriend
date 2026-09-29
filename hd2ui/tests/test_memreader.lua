-- tests/test_memreader.lua -- Headless tests for the memory-read seam.
-- Drives memreader against a fake backend (a byte buffer standing in for the
-- game process), so the transport (read_u32 / read_ptr / walk) is verified
-- without the game running. Run under the game's Lua 5.1 (LuaJIT).

-- Resolve modules from the repo root (run_lua.py / test.py chdir to repo root),
-- matching test_core.lua.
package.path = './?.lua;' .. package.path

local M = require('hd2ui.memreader')
local checks = 0
local fails = 0
local function check(name, cond)
  checks = checks + 1
  if not cond then fails = fails + 1; print('FAIL ' .. name) else print('ok   ' .. name) end
end

check('module loads', M ~= nil and M.available == true)
local real_read = M.backend().read  -- hold the real FFI read for restore check

-- ---- Build a fake process memory image. -------------------------------
-- A flat buffer; addresses are byte offsets into it. Clean 3-node pointer
-- chain plus a few spot values:
--   base = 0x1000 ; [base+0]=ptr->N1 ; [base+16]=u32 0x11223344 ; [base+32]=u8 0xAB
--   N1 = base+1024 ; [N1+0]=ptr->N2 ; [N1+8]=u32 7
--   N2 = base+2048 ; [N2+0]=ptr->N3
--   N3 = base+4096 ; [N3+0]=u32 0xDEADBEEF  (the "ammo rounds" target)
local base = 0x1000
local N1 = base + 1024
local N2 = base + 2048
local N3 = base + 4096
local mem = {}
local function put(addr, bytes)
  for i = 1, #bytes do mem[addr + i - 1] = bytes:byte(i) end
end
local function put_u32(addr, v) put(addr, string.char(v % 256, math.floor(v/256) % 256, math.floor(v/65536) % 256, math.floor(v/0x1000000) % 256)) end
local function put_ptr(addr, v)
  local bytes = ''
  for i = 0, 7 do bytes = bytes .. string.char(v % 256); v = math.floor(v / 256) end
  put(addr, bytes)
end

put_ptr(base + 0, N1)
put_u32(base + 16, 0x11223344)
put(base + 32, '\xAB')
put_ptr(N1 + 0, N2)
put_u32(N1 + 8, 7)
put_ptr(N2 + 0, N3)
put_u32(N3 + 0, 0xDEADBEEF)

-- ---- Fake backend over the buffer. ------------------------------------
local function at(addr, n)
  local s = ''
  for i = 0, n - 1 do
    local b = mem[addr + i]
    if b == nil then return nil end
    s = s .. string.char(b)
  end
  return s
end
local fake = {}
function fake.read(addr, n) return at(addr, n) end
function fake.read_u8(addr) local s = at(addr, 1); return s and s:byte(1) end
function fake.read_u32(addr)
  local s = at(addr, 4); if not s then return nil end
  return s:byte(1) + s:byte(2) * 256 + s:byte(3) * 65536 + (s:byte(4) * 0x1000000) % 0x100000000
end
function fake.read_ptr(addr)
  local s = at(addr, 8); if not s then return nil end
  local lo = s:byte(1) + s:byte(2) * 256 + s:byte(3) * 65536 + (s:byte(4) * 0x1000000) % 0x100000000
  local hi = s:byte(5) + s:byte(6) * 256 + s:byte(7) * 65536 + (s:byte(8) * 0x1000000) % 0x100000000
  return (lo + hi * 0x100000000) % 0x10000000000000000
end
function fake.walk(chain)
  local a
  for i = 1, #chain do a = fake.read_ptr(chain[i]); if a == nil then return nil end end
  return a
end
function fake.attach(pid) return true end

-- ---- Drive the API through the seam. ----------------------------------
local saved = M.backend()
M.set_backend(fake)

local ok_attach = M.attach(1234)
check('attach via seam', ok_attach == true)
check('pid stored', M.pid() == 1234)

local u = M.read_u8(base + 32)
check('read_u8', u ~= nil and u == 0xAB)

local u32 = M.read_u32(base + 16)
check('read_u32 LE', u32 ~= nil and u32 == 0x11223344)

local p = M.read_ptr(base + 0)
check('read_ptr base->N1', p ~= nil and p == N1)
local p2 = M.read_ptr(N1 + 0)
check('read_ptr N1->N2', p2 ~= nil and p2 == N2)
local p3 = M.read_ptr(N2 + 0)
check('read_ptr N2->N3', p3 ~= nil and p3 == N3)

-- walk reads a pointer at each hop; the chain of {base, N1, N2} yields N3.
local w = M.walk({ base + 0, N1 + 0, N2 + 0 })
check('walk chain -> N3', w ~= nil and w == N3)
local w_nil = M.walk({ base + 0, 0x99999999 })
check('walk nil on bad hop', w_nil == nil)

local bad = M.read(0x10, 4)
check('read rejects low address', bad == nil)
local bad2 = M.read(base + 0, 99999)
check('read rejects oversized', bad2 == nil)

-- Restore FFI backend.
M.set_backend(nil)
check('seam restore (read back to FFI)', M.backend().read == real_read)

-- Direct self-read backend (real in-process reads, region-guarded) ----------
local okf, ffi2 = pcall(require, 'ffi')
if okf and ffi2 and M.self_pid then
  local pid = M.self_pid()
  check('direct: self pid', type(pid) == 'number' and pid > 4)
  local cell = ffi2.new('uint8_t[8]')
  cell[0] = 0xAB; cell[7] = 0xCD
  local caddr = tonumber(ffi2.cast('unsigned long long', cell))
  local ok_att = M.attach(pid, 'testhost')
  check('direct: attach(self) has no OpenProcess path', ok_att == true)
  local s = M.read(caddr, 8)
  check('direct: reads live bytes in-process', s ~= nil and s:byte(1) == 0xAB and s:byte(8) == 0xCD)
  local u = M.read(0x10010, 4)
  check('direct: unmapped address returns nil (no fault)', u == nil)
end

print(('memreader: %d checks, %d failures'):format(checks, fails))
if fails > 0 then error(fails .. ' failures') end
