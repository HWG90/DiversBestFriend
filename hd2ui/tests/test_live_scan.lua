-- tests/test_live_scan.lua -- Headless tests for the live offset-derivation
-- scanner (live_scan.lua). Drives read_safe/scan_bytes/scan_u32/scan_u64
-- against a fake committed-range memory map (page-granular, with holes), so
-- the scan logic — including page-boundary overlap and the only_image filter —
-- is verified WITHOUT the game running. Run under the game's Lua 5.1 (LuaJIT).
--
-- Note: VirtualQueryEx region enumeration and the Toolhelp32 module_base are
-- thin FFI wrappers over the real target and are NOT unit-tested here (they
-- need a live process); the scan logic is what we can and do verify headlessly.

package.path = './?.lua;' .. package.path

local MR = require('hd2ui.memreader')
local LS = require('hd2ui.live_scan')
local checks = 0
local fails = 0
local function check(name, cond)
  checks = checks + 1
  if not cond then fails = fails + 1; print('FAIL ' .. name) else print('ok   ' .. name) end
end

check('live_scan loads', LS ~= nil and LS.available == true)

-- ---- Fake committed-range memory map (page-granular, with holes). --------
local PAGE = 4096
local ranges = {}  -- list of { start = number, data = byte string }
local function add_range(start, data)
  table.insert(ranges, { start = start, data = data })
  return start
end
local fake = {}
function fake.read(addr, n)
  for _, r in ipairs(ranges) do
    local s = r.start
    if addr >= s and addr + n <= s + #r.data then
      return r.data:sub(addr - s + 1, addr - s + n)
    end
  end
  return nil
end
function fake.read_u8(addr) local s = fake.read(addr, 1); return s and s:byte(1) end
function fake.read_u32(addr)
  local s = fake.read(addr, 4); if not s then return nil end
  return s:byte(1) + s:byte(2)*256 + s:byte(3)*65536 + (s:byte(4)*0x1000000) % 0x100000000
end
MR.set_backend(fake)

-- Build a deterministic memory image: two 64 KiB "pages-worth" ranges with a
-- hole between them. Sprinkle known 32-bit values, including one straddling a
-- PAGE boundary inside the first range (to exercise the scan overlap).
local R1_START = 0x1000000
local R2_START = 0x2000000
local r1 = string.rep('\x00', 65536)
local r2 = string.rep('\x00', 65536)

local function put_u32(buf, off, v)
  v = v % 0x100000000
  local b = string.char(v % 256, math.floor(v/256)%256, math.floor(v/65536)%256, math.floor(v/0x1000000)%256)
  return buf:sub(1, off) .. b .. buf:sub(off + 5)
end
-- Place a u32 whose low 2 bytes are at the very end of one 4 KiB page and high
-- 2 bytes at the start of the next — i.e. it crosses a page boundary.
r1 = put_u32(r1, 4094, 0xDEADBEEF)   -- bytes 4094,4095 | 4096,4097
r1 = put_u32(r1, 1000, 0x00002D00)   -- 11562
r2 = put_u32(r2, 5000, 0x12345678)

add_range(R1_START, r1)
add_range(R2_START, r2)

-- Populate regions exactly as enum_regions would (bypass the FFI enumeration).
LS.state().regions = {
  { base = R1_START, size = 65536, image = true,  private = false },
  { base = R2_START, size = 65536, image = false, private = true },
}

-- ---- read_safe: stops at a hole, returns the readable prefix. -------------
local pre = fake.read(R1_START + 1000, 4)
check('read prefix sanity', pre ~= nil)
-- A read that would cross the R1->hole boundary must stop (not error).
local s = LS.state()
-- (read_safe is internal; exercised through scan below.)

-- ---- scan_u32 finds an in-page value at the exact address. ----------------
local res = LS.scan_u32(0x00002D00, false)
check('scan_u32 in-page found', res ~= nil and res.total >= 1)
check('scan_u32 in-page exact addr', res ~= nil and res.addresses[1] == R1_START + 1000)

-- ---- scan_u32 finds a value that crosses a 4 KiB page boundary (once). ----
local res2 = LS.scan_u32(0xDEADBEEF, false)
check('scan_u32 page-straddling found', res2 ~= nil and res2.total == 1)
check('scan_u32 page-straddling exact addr', res2 ~= nil and res2.addresses[1] == R1_START + 4094)

-- ---- Same straddling value, forced through many overlapping windows. ----
-- A single 64 KiB region read as one window never exercises the (plen-1)
-- overlap advance; cap the window at 8 KiB so the value sits near a seam and
-- the match is still reported exactly once at the right address.
LS.state().chunk = 8192
local res2b = LS.scan_u32(0xDEADBEEF, false)
check('chunked scan: straddling found once', res2b ~= nil and res2b.total == 1)
check('chunked scan: straddling exact addr', res2b ~= nil and res2b.addresses[1] == R1_START + 4094)
-- And a value that sits exactly ON a window seam (8192 boundary).
r1 = string.rep('\x00', 65536)
r1 = put_u32(r1, 8190, 0x11223344)  -- bytes 8190,8191 | 8192,8193
ranges[1].data = r1
local res2c = LS.scan_u32(0x11223344, false)
check('chunked scan: seam value found once', res2c ~= nil and res2c.total == 1)
check('chunked scan: seam exact addr', res2c ~= nil and res2c.addresses[1] == R1_START + 8190)
LS.state().chunk = nil
-- The seam check above zeroed R1; re-plant the in-page value for the
-- only_image check below.
ranges[1].data = put_u32(r1, 1000, 0x00002D00)

-- ---- scan_u32 across regions finds a value in the second region. ----------
local res3 = LS.scan_u32(0x12345678, false)
check('scan_u32 other region found', res3 ~= nil and res3.total == 1)
check('scan_u32 other region exact addr', res3 ~= nil and res3.addresses[1] == R2_START + 5000)

-- ---- only_image filters to the image (R1) region. -------------------------
local res4 = LS.scan_u32(0x12345678, true)  -- lives in non-image R2
check('only_image excludes non-image', res4 ~= nil and res4.total == 0)
local res5 = LS.scan_u32(0x00002D00, true)  -- lives in image R1
check('only_image keeps image', res5 ~= nil and res5.total == 1)

-- ---- scan_u64 finds a little-endian 64-bit value. -------------------------
local r3 = string.rep('\x00', 65536)
local function put_u64(buf, off, v)
  local b = ''
  for i = 0, 7 do b = b .. string.char(v % 256); v = math.floor(v / 256) end
  return buf:sub(1, off) .. b .. buf:sub(off + 9)
end
r3 = put_u64(r3, 2048, 0x0123456789ABCDEF)
add_range(0x3000000, r3)
LS.state().regions[#LS.state().regions + 1] = { base = 0x3000000, size = 65536, image = true, private = false }
local res6 = LS.scan_u64(0x0123456789ABCDEF, false)
check('scan_u64 found', res6 ~= nil and res6.total == 1)
check('scan_u64 exact addr', res6 ~= nil and res6.addresses[1] == 0x3000000 + 2048)

-- ---- A value not present yields total 0. ---------------------------------
local res7 = LS.scan_u32(0xFFFFFFFF, true)
check('absent value -> total 0', res7 ~= nil and res7.total == 0)

MR.set_backend(nil)
print(('live_scan: %d checks, %d failures'):format(checks, fails))
if fails > 0 then error(fails .. ' failures') end
