-- tests/test_ammo_reader.lua -- Headless tests for the layout-driven ammo
-- reader (the layer ABOVE memreader). Drives ammo_reader against a fake
-- transport (a byte buffer standing in for the game process), so the chain
-- walk, per-hop plausibility, field decode, and rederive seams are verified
-- without the game running. Run under the game's Lua 5.1 (LuaJIT).

package.path = './?.lua;' .. package.path

local A = require('hd2ui.ammo_reader')
local checks = 0
local fails = 0
local function check(name, cond)
  checks = checks + 1
  if not cond then fails = fails + 1; print('FAIL ' .. name) else print('ok   ' .. name) end
end

check('module loads', A ~= nil and A.available == true)

-- ---- Fake transport over a byte buffer (mirrors test_memreader). --------
local base = 0x100000
local N1 = base + 0x400
local N2 = base + 0x800
local N3 = base + 0xC00
local N4 = base + 0x1000
local N5 = base + 0x1400
local N6 = base + 0x1800
local N7 = base + 0x1C00
local N8 = base + 0x2000   -- terminal weapon node
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
-- Full 8-hop chain: base -> N1 -> ... -> N8, pointer at offset 0x10 on each node.
local hops = { base, N1, N2, N3, N4, N5, N6, N7 }
local targets = { N1, N2, N3, N4, N5, N6, N7, N8 }
for i = 1, 8 do put_ptr(hops[i] + 0x10, targets[i]) end
-- Terminal fields on N8: magazine=45 (0x20), reserve=90 (0x24), heat=0.25 (0x28).
put_u32(N8 + 0x20, 45)
put_u32(N8 + 0x24, 90)
put(N8 + 0x28, '\x00\x00\x80\x3E')  -- 0.25f little-endian

local fake = {}
local function at(addr, n)
  local s = ''
  for i = 0, n - 1 do
    local b = mem[addr + i]
    if b == nil then return nil end
    s = s .. string.char(b)
  end
  return s
end
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

A.set_transport(fake)
check('transport seam returns injected', A.transport() == fake)

-- ---- Shape / validation. -------------------------------------------------
local dl = A.default_layout()
check('default_layout: 8 hops', dl ~= nil and #dl.hops == 8)
check('default_layout: fields', dl.fields.magazine == 0 and dl.fields.reserve == 0 and dl.fields.heat == 0)
check('default_layout: limits', dl.limits.magazine_max == 200 and dl.limits.reserve_max == 20000)

local bad, verr = pcall(A.set_layout, { hops = {}, fields = { magazine = 0, reserve = 0 } })
check('set_layout rejects empty hops', not bad)
local bad2, _ = pcall(A.set_layout, { hops = { { off = 0 } }, fields = { magazine = 0 } })
check('set_layout rejects missing reserve', not bad2)
local bad3, _ = pcall(A.set_module_base, 0x10)
check('set_module_base rejects tiny address', not bad3)

-- ---- No layout yet -> needs_live_pass. -----------------------------------
A.set_module_base(base)
local r0, rerr = A.read()
check('read without layout -> needs_live_pass', r0 == nil and rerr == 'needs_live_pass')

-- ---- Full read through the fake chain. -----------------------------------
local layout = {
  hops = { { off = 0x10 }, { off = 0x10 }, { off = 0x10 }, { off = 0x10 },
           { off = 0x10 }, { off = 0x10 }, { off = 0x10 }, { off = 0x10 } },
  fields = { magazine = 0x20, reserve = 0x24, heat = 0x28 },
  limits = { magazine_min = 1, magazine_max = 200,
             reserve_min = 0, reserve_max = 20000,
             heat_min = 0, heat_max = 1.0 },
}
A.set_layout(layout)
local ammo, aerr = A.read()
check('read: magazine 45', ammo ~= nil and ammo.magazine == 45)
check('read: reserve 90', ammo ~= nil and ammo.reserve == 90)
check('read: heat 0.25 (f32 decode)', ammo ~= nil and math.abs(ammo.heat - 0.25) < 1e-6)
check('read: no error on success', A.last_error() == nil)

-- ---- Broken chain: point a mid hop at garbage. ----------------------------
put_ptr(N4 + 0x10, 0)  -- hop 5 follows a null pointer
local r2, r2err = A.read()
check('broken hop -> nil + named reason', r2 == nil and tostring(r2err):find('hop 5') ~= nil)

-- ---- Plausibility gates. ---------------------------------------------------
put_ptr(N4 + 0x10, N5)  -- restore chain
put_u32(N8 + 0x20, 99999)  -- magazine absurd
local r3, r3err = A.read()
check('implausible magazine -> rejected', r3 == nil and tostring(r3err):find('plausibility') ~= nil)
put_u32(N8 + 0x20, 45)

put(N8 + 0x28, '\x00\x00\xC0\x7F')  -- heat = NaN (exp=255, mant!=0)
local r4, r4err = A.read()
check('NaN heat -> rejected', r4 == nil and tostring(r4err):find('NaN') ~= nil)
put(N8 + 0x28, '\x00\x00\x80\x3E')  -- restore 0.25

put_u32(N8 + 0x24, 0x7FFFFFFF)  -- reserve absurd
local r5, r5err = A.read()
check('implausible reserve -> rejected', r5 == nil and tostring(r5err):find('plausibility') ~= nil)
put_u32(N8 + 0x24, 90)

-- ---- rederive seam: new layout, same transport. ----------------------------
local layout2 = {
  hops = { { off = 0x10 }, { off = 0x10 }, { off = 0x10 }, { off = 0x10 },
           { off = 0x10 }, { off = 0x10 }, { off = 0x10 }, { off = 0x10 } },
  fields = { magazine = 0x20, reserve = 0x24, heat = 0x28 },
  limits = { magazine_min = 0, magazine_max = 10,   -- tight: 45 should now fail
             reserve_min = 0, reserve_max = 20000,
             heat_min = 0, heat_max = 1.0 },
}
local r6, r6err = A.rederive(layout2)
check('rederive with tight limits -> rejected', r6 == nil and tostring(r6err):find('plausibility') ~= nil)
local r7 = A.rederive(layout)  -- back to the real layout
check('rederive restores working read', r7 ~= nil and r7.magazine == 45)

---- Anchor mode (content-based resolution; Deadeye GUID layout) ----
local GUID_AT = 0x500000
put(GUID_AT, string.char(0x95,0xd2,0xa2,0x94,0xb5,0x2b,0xd4,0x5e,
                         0x6e,0xd2,0x82,0xd0,0xe0,0x89,0x68,0xb9))
put_u32(GUID_AT - 0x30, 1)                   -- structural flag (must be 1)
put(GUID_AT - 0x28, '\x00\x00\x80\x3F')      -- aim f32 = 1.0
put_u32(GUID_AT - 0x24, 8)    -- magazine  (mag = guid_hit - 0x24)
put_u32(GUID_AT - 0x2C, 57)   -- reserve
check('anchor: unknown weapon rejected', pcall(A.set_anchor_weapon, 'nope') == false)
check('anchor: base before weapon rejected', A.set_anchor_base(GUID_AT) == false)
A.set_anchor_weapon('r4_deadeye')
local pat = A.anchor_pattern()
check('anchor: pattern bytes', pat and #pat == 16 and pat:byte(1) == 0x95 and pat:byte(16) == 0xb9)
check('anchor: unresolved base still reads', (function()
  local rr = A.read()  -- no base yet -> chain path (r7) or needs_live_pass; must not error
  return rr == nil or type(rr) == 'table' end)())
A.set_anchor_base(GUID_AT)
local ar = A.read()
check('anchor: reads mag/res at negative offsets',
  ar and ar.magazine == 8 and ar.reserve == 57)
check('anchor: heat nil when absent', ar and ar.heat == nil)
put_u32(GUID_AT - 0x24, 99)   -- beyond capacity: component considered moved
local ar2, ar2err = A.read()
check('anchor: implausible clears base + anchor_stale',
  ar2 == nil and tostring(ar2err):find('anchor_stale') ~= nil)
check('anchor: base cleared after stale', A.anchor_base() == nil)

-- ---- Seam teardown: nil transport falls back to filesystem memreader. -----
A.set_transport(nil)
local t2 = A.transport()
check('seam falls back to filesystem transport', t2 ~= nil and t2.available == true)

print(('ammo_reader: %d checks, %d failures'):format(checks, fails))
if fails > 0 then error(fails .. ' failures') end
