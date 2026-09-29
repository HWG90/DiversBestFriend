-- tests/test_ammo_cache.lua -- Headless tests for hd2ui/ammo_cache.lua:
-- PE TimeDateStamp reading from a synthetic header, cache-file save/load
-- round-trips, and the structural validation gates that guard the fast-path
-- lock. Pure-Lua fake transport (mirrors test_ammo_reader); no ffi, no game.

package.path = './?.lua;' .. package.path

local AC = require('hd2ui.ammo_cache')

local checks, fails = 0, 0
local function check(name, cond)
  checks = checks + 1
  if not cond then fails = fails + 1; print('FAIL ' .. name) else print('ok   ' .. name) end
end

check('module loads', type(AC) == 'table')

-- ------------------------------------------------------------- fake transport
local mem = {}
local function put_u32(addr, v)
  mem[addr] = string.char(v % 256, math.floor(v / 256) % 256,
                          math.floor(v / 65536) % 256, math.floor(v / 0x1000000) % 256)
end
local T = {}
function T.read_u32(addr)
  local s = mem[addr]
  if not s then return nil end
  return s:byte(1) + s:byte(2) * 256 + s:byte(3) * 65536 + s:byte(4) * 0x1000000
end
function T.read(addr, n)
  if n ~= 4 then return nil end
  return mem[addr]
end

-- ------------------------------------------------------------------ pe_stamp
local IMG = 0x10000000
put_u32(IMG + 0x3C, 0x80)         -- e_lfanew
put_u32(IMG + 0x80, 0x00004550)   -- 'PE\0\0'
put_u32(IMG + 0x88, 0x6A86132E)   -- TimeDateStamp (the user's game.dll build)
check('pe_stamp reads TimeDateStamp', AC.pe_stamp(T.read_u32, IMG) == 0x6A86132E)

put_u32(IMG + 0x80, 0xDEADBEEF)   -- corrupt signature
check('pe_stamp rejects bad signature', AC.pe_stamp(T.read_u32, IMG) == nil)
put_u32(IMG + 0x80, 0x00004550)

put_u32(IMG + 0x3C, 0x2000)       -- e_lfanew beyond the sane header range
check('pe_stamp rejects far e_lfanew', AC.pe_stamp(T.read_u32, IMG) == nil)
put_u32(IMG + 0x3C, 0)
check('pe_stamp rejects zero e_lfanew', AC.pe_stamp(T.read_u32, IMG) == nil)

check('pe_stamp unmapped base -> nil', AC.pe_stamp(T.read_u32, 0x20000000) == nil)

-- ------------------------------------------------------------------ validate
local HIT = 0x30000080            -- GUID hit; component fields at negative offsets
local spec = {
  mag_off = -0x24, res_off = -0x2C, capacity = 8,
  flag_off = -0x30, flag_val = 1, aim_off = -0x28, aim_min = 0, aim_max = 4,
}
local F32_1   = string.char(0x00, 0x00, 0x80, 0x3F)  -- 1.0
local F32_5   = string.char(0x00, 0x00, 0xA0, 0x40)  -- 5.0
local F32_NAN = string.char(0x00, 0x00, 0xC0, 0xFF)  -- quiet NaN
local function f32_decode(raw)
  if raw == F32_1 then return 1.0 end
  if raw == F32_5 then return 5.0 end
  if raw == F32_NAN then return 0 / 0 end
  return 999.0   -- unknown bytes: deliberately out of aim range
end

put_u32(HIT + spec.flag_off, 1)
mem[HIT + spec.aim_off] = F32_1
put_u32(HIT + spec.mag_off, 7)
put_u32(HIT + spec.res_off, 56)
check('validate accepts planted component', AC.validate(T, f32_decode, spec, HIT) == true)

put_u32(HIT + spec.flag_off, 0)
check('validate rejects wrong flag', AC.validate(T, f32_decode, spec, HIT) == false)
put_u32(HIT + spec.flag_off, 1)

mem[HIT + spec.aim_off] = F32_5
check('validate rejects aim out of range', AC.validate(T, f32_decode, spec, HIT) == false)
mem[HIT + spec.aim_off] = F32_NAN
check('validate rejects NaN aim', AC.validate(T, f32_decode, spec, HIT) == false)
mem[HIT + spec.aim_off] = F32_1

put_u32(HIT + spec.mag_off, 9)
check('validate rejects mag over capacity', AC.validate(T, f32_decode, spec, HIT) == false)
put_u32(HIT + spec.mag_off, 7)

put_u32(HIT + spec.res_off, 20001)
check('validate rejects absurd reserve', AC.validate(T, f32_decode, spec, HIT) == false)
put_u32(HIT + spec.res_off, 56)

check('validate rejects unmapped base', AC.validate(T, f32_decode, spec, 0x40000080) == false)
check('validate rejects low base', AC.validate(T, f32_decode, spec, 0x100) == false)

-- ------------------------------------------------------------------- save/load
local tmp = (os.getenv('TEMP') or os.getenv('TMP') or '.') .. '\\dbf_ammo_cache_test.txt'
os.remove(tmp)
check('load missing file -> nil', AC.load(tmp) == nil)
check('save returns true', AC.save(tmp, 0x6A86132E, 0x29A510697CC) == true)
local s, b = AC.load(tmp)
check('load round-trips stamp', s == 0x6A86132E)
check('load round-trips 40-bit base', b == 0x29A510697CC)

local f = io.open(tmp, 'w')
f:write('')
f:close()
check('load empty file -> nil', AC.load(tmp) == nil)
f = io.open(tmp, 'w')
f:write('not hex at all')
f:close()
check('load garbage -> nil', AC.load(tmp) == nil)
os.remove(tmp)

print(string.format('ammo_cache: %d checks, %d failures', checks, fails))
if fails > 0 then error(fails .. ' failures') end
