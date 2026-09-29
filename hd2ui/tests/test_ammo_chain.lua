-- tests/test_ammo_chain.lua -- Headless end-to-end of the RAH-method chain:
-- builds a synthetic game world in a byte map (module image with globals at
-- the real RVAs + verified signatures; heap with player/owner/inventory/
-- driver/magazine managers, entity records, hash maps, static config table
-- with the home-row probe) and drives ammo_chain.init/verify/read against it.
-- Checks: instant verify, magazine-path decode (7/4, cap 8), chamber logic,
-- and the support-weapon backpack/deposit path (reserve 42 via entity+1).

local checks, fails = 0, 0
local function ok(c, msg)
  checks = checks + 1
  if not c then fails = fails + 1; print('FAIL: ' .. msg) else print('ok   ' .. msg) end
end

-- ---------------------------------------------------------------- fake memory
local mem = {}                      -- absolute byte address -> byte value
local ZERO = 0
local function put(addr, s)
  for i = 1, #s do mem[addr + i - 1] = s:byte(i) end
end
local function put_u32(addr, v)
  v = v % 4294967296
  put(addr, string.char(v % 256, math.floor(v / 256) % 256,
                       math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256))
end
local function put_ptr(addr, v)
  put_u32(addr, v % 4294967296)
  put_u32(addr + 4, math.floor(v / 4294967296) % 4294967296)
end
local function read_fake(addr, n)
  local out = {}
  for i = 0, n - 1 do
    local b = mem[addr + i]
    out[#out + 1] = string.char(b or 0)
  end
  return table.concat(out)
end
local function pad(n) return string.rep('\0', n) end
local ZERO8 = string.rep('\0', 8)

-- map builder: header {slots*, pad, cap, empty, mult} at addr (20B), rows 8B
local function make_map(addr, pairs, cap, mult)
  cap = cap or 8; mult = mult or 1
  local slots = addr + 0x1000
  put_ptr(addr, slots)                -- full 8-byte slots pointer (matches u64 header read)
  put_u32(addr + 8, cap)        -- capacity
  put_u32(addr + 12, 0)         -- empty key
  put_u32(addr + 16, mult)      -- multiplier
  for i = 0, cap - 1 do mem[slots + i * 8] = nil end  -- zero rows (key 0 = empty)
  for _, kv in ipairs(pairs) do
    local key, index = kv[1], kv[2]
    local row = (key * mult) % cap
    put_u32(slots + row * 8, key)
    put_u32(slots + row * 8 + 4, index)
  end
end

local CH = require('hd2ui.ammo_chain')
local BUILD = CH.BUILD

-- ------------------------------------------------------------- fake world
local MOD  = 0x140000000
local PM   = 0x7FF600010000
local OWN  = 0x7FF600020000
local INV  = 0x7FF600030000
local DM   = 0x7FF600040000
local MM   = 0x7FF600050000
local SEL  = 0x7FF600060000
local DEPM = 0x7FF600070000
local HM   = 0x7FF600080000    -- heat manager
local HSTB = 0x7FF600110000    -- static heat config table
local STB  = 0x7FF600100000    -- static magazine table
local P_REC = 0x7FF600200000   -- player entity record
local AV_REC = 0x7FF600201000  -- avatar record (also at owner+records+0)
local WP_REC = 0x7FF600202000  -- weapon 8001 record
local BP_REC = 0x7FF600202100  -- backpack 8002 record

-- globals: module slots -> managers
put_ptr(MOD + BUILD.player, PM)
put_ptr(MOD + BUILD.owner, OWN)
put_ptr(MOD + BUILD.inventory, INV)
put_ptr(MOD + BUILD.driver, DM)
put_ptr(MOD + BUILD.magazine, MM)
put_ptr(MOD + BUILD.selector, SEL)
put_ptr(MOD + BUILD.deposit[1], DEPM)
put_ptr(MOD + BUILD.heat, HM)
-- signatures
for _, s in ipairs(BUILD.signatures) do
  local bytes = ''
  for hh in s[2]:gmatch('%x%x') do bytes = bytes .. string.char(tonumber(hh, 16)) end
  put(MOD + s[1], bytes)
end

-- player manager
put_u32(PM + 0x84, 1); put_u32(PM + 0x88, 1)          -- counts
put_ptr(PM + 0xe8, P_REC)
make_map(PM + 0xd0, { { 4001, 0 } }, 8, 1)            -- player registry: key=unit, index 0
put_u32(PM + 0x3a8, 5001)                             -- avatar unit
-- player record: u32@8 unit 4001, u8@20 owned(1)
put(P_REC + 8, string.char(0xA1, 0x0F, 0, 0))         -- 4001
put(P_REC + 20, string.char(1))

-- owner manager: unit_map / entity_map / records live at owner+offsets
make_map(OWN + BUILD.unit_map, { { 5001, 0 } }, 8, 1)
make_map(OWN + BUILD.entity_map, { { 8001, 1 }, { 8002, 2 } }, 8, 1)
local RECS = OWN + BUILD.records
-- avatar record (idx 0): @8 avatar_id 7001, @16 unit 5001, @20 owned
put(RECS + 0 * 24 + 8, string.char(0x59, 0x1B, 0, 0))
put(RECS + 0 * 24 + 16, string.char(0x89, 0x13, 0, 0))   -- unit 5001
put(RECS + 0 * 24 + 20, string.char(1))
local AV_BYTES = read_fake(RECS, 24)

-- weapon record (idx 1): resource8, @8 id 8001, owned
local WRES = string.char(0x01, 0x00, 0xAD, 0xDE, 0x11, 0x11, 0x00, 0x00)  -- lo 0xDEAD0001 hi 0x00001111
put(RECS + 1 * 24, WRES)
put(RECS + 1 * 24 + 8, string.char(0x41, 0x1F, 0, 0))
put(RECS + 1 * 24 + 16, string.char(0xB2, 0x13, 0, 0))  -- some unit id
put(RECS + 1 * 24 + 20, string.char(1))
local WP_BYTES = read_fake(RECS + 24, 24)

-- inventory: count@0x14; map@0x28 avatar_id->ii; registry ptr@0x40 -> [ptr->avatar rec]; state ptr@0x50 -> 48B rows
put_u32(INV + 0x14, 1)
make_map(INV + 0x28, { { 7001, 0 } }, 8, 1)
put_ptr(INV + 0x40, INV + 0x2000)
put_ptr(INV + 0x2000, RECS)                              -- -> avatar record bytes
local ISTATE = INV + 0x3000
put_ptr(INV + 0x50, ISTATE)
put_u32(ISTATE + 0x1c, 2)                                -- slot 2 -> weapon id at off 4
put_u32(ISTATE + 4, 8001)                                -- primary... slot2's weapon
put_u32(ISTATE + 0, 7001)                                -- (avatar id candidate)
put_u32(ISTATE + 12, 8002)                               -- backpack candidate (= wid+1)

-- selector (may return the same wielded id)
put_u32(SEL + 0x10, 1)                                   -- cap
put_u32(SEL + 0x18, 1)                                   -- live
make_map(SEL + 0x30, { { 7001, 0 } }, 8, 1)
put_ptr(SEL + 0x48, SEL + 0x2000)
put_ptr(SEL + 0x2000, RECS)                              -- owner check == avatar
put_ptr(SEL + 0x60, SEL + 0x3000)
put_u32(SEL + 0x3000, 8001)                              -- selected entity

-- driver: map@0x28 id->di, registry@0x40, runtime@0x50 40B stride
make_map(DM + 0x28, { { 8001, 0 } }, 8, 1)
put_ptr(DM + 0x40, DM + 0x2000)
put_ptr(DM + 0x2000, RECS + 24)                          -- -> weapon record (identity)
put_ptr(DM + 0x50, DM + 0x3000)
put_u32(DM + 0x3000, 0x80)                               -- flags: magazine weapon

-- magazine manager: map@0x20, registry@0x38, state ptr@0x48 (16B), runtime ptr@0x50 (12B)
make_map(MM + 0x20, { { 8001, 5 } }, 8, 1)               -- component index 5
put_ptr(MM + 0x38, MM + 0x2000)
put_ptr(MM + 0x2000 + 5 * 8, RECS + 24)                  -- registry[5] -> weapon record
put_ptr(MM + 0x48, MM + 0x4000)
put_ptr(MM + 0x50, MM + 0x5000)
put_u32(MM + 0x4000 + 5 * 16, 7)                         -- rounds = 7
put_u32(MM + 0x4000 + 5 * 16 + 8, 0)                     -- chamber token
put_u32(MM + 0x5000 + 5 * 12, 4)                         -- spare magazines = 4
-- override map: empty (key 0 == empty) -> static config path
make_map(MM + BUILD.mag_override[1], {}, 8, 1)

-- static magazine table: owner+slot -> base; 540 rows; entry at home_row
put_ptr(OWN + BUILD.static.magazine.slot, STB)
local n = BUILD.static.magazine.count
local lo = 0xDEAD0001
local hi = 0x1111
local home = ((hi % n) * (4294967296 % n) + lo % n) % n
put(STB + home * 16, WRES)                               -- key
put_u32(STB + home * 16 + 8, 7)                          -- record index 7
put_u32(STB + home * 16 + 12, 0)
local CFG = STB + n * 16 + 7 * 160
put_u32(CFG + 0x88, 8)                                   -- capacity
put_u32(CFG + 0x8c, 5)                                   -- (own reserve >0)
put_u32(CFG + 0x94, 3)                                   -- mags max
put(CFG + 0x9c, string.char(0))                           -- chambered: no

-- ------------------------------------------------------------------- run it
CH.init({ base = MOD, read = read_fake })
ok(CH.verify() == true, 'chain verify: signatures at layout RVAs match')

local row = CH.read()
ok(row.status == 'ok', 'chain read status ok (got ' .. tostring(row.status) .. ')')
ok(row.path == 'magazine', 'magazine-path weapon detected via driver flags')
ok(row.rounds == 7, 'rounds decoded (state i32@0): ' .. tostring(row.rounds))
ok(row.capacity == 8, 'capacity from static config (home-row probe): ' .. tostring(row.capacity))
ok(row.spare == 4 and row.spare_kind == 'mags', 'spare magazines from runtime: ' .. tostring(row.spare) .. '/' .. tostring(row.spare_kind))

-- universal charge probe must be safe on weapons with no charge component
ok(row.charge_pct == nil and row.status == 'ok', 'charge probe no-ops on plain mags')
ok(row.chambered == false and row.chamber == 0, 'chamber state honored')

-- ------------------------------------------------- support weapon + backpack
-- same weapon, but config says NO own reserve; a deposit entity (id+1) feeds it
put_u32(CFG + 0x8c, 0)
put_u32(CFG + 0x94, 0)
put_u32(MM + 0x5000 + 5 * 12, 0)                          -- own spares zeroed
-- backpack entity record (idx 2): resource, id 8002, owned
local BRES = string.char(0x30, 0xB0, 0, 0, 0x22, 0x22, 0, 0)
put(RECS + 2 * 24, BRES)
put(RECS + 2 * 24 + 8, string.char(0x42, 0x1F, 0, 0))    -- id 8002
put(RECS + 2 * 24 + 20, string.char(1))
-- deposit component: map@0x20, registry@0x38, counts ptr@0x50 (8B rows)
make_map(DEPM + 0x20, { { 8002, 0 } }, 8, 1)
put_ptr(DEPM + 0x38, DEPM + 0x2000)
put_ptr(DEPM + 0x2000, RECS + 48)                         -- registry[0] -> backpack rec
put_ptr(DEPM + 0x50, DEPM + 0x3000)
put_u32(DEPM + 0x3000, 42)                                -- deposit count

CH.init({ base = MOD, read = read_fake })                 -- clear static cache
row = CH.read()
ok(row.status == 'ok', 'support-weapon read ok (got ' .. tostring(row.status) .. ')')
ok(row.spare == 42 and row.spare_kind == 'backpack',
   'backpack deposit (42) as reserve: got ' .. tostring(row.spare) .. '/' .. tostring(row.spare_kind))

-- ---------------------------------------------------- scenario 3: heat laser
put_u32(DM + 0x3000, 0x200)                                -- heat flags
local HRES = string.char(0x51, 0x23, 0, 0, 0x44, 0x44, 0, 0)
put(RECS + 1 * 24, HRES)
put(RECS + 1 * 24 + 8, string.char(0x1D, 0x25, 0, 0))      -- id 9501 = 0x251D
put(RECS + 1 * 24 + 20, string.char(1))
make_map(OWN + BUILD.entity_map, { { 8001, 1 }, { 8002, 2 }, { 9501, 1 } }, 8, 1)
make_map(DM + 0x28, { { 9501, 0 } }, 8, 1)
put_ptr(DM + 0x2000, RECS + 24)
make_map(MM + 0x20, {}, 8, 1)                              -- not a magazine weapon
make_map(HM + 0x28, { { 9501, 2 } }, 8, 1)                 -- heat map 0x28/0x40
put_ptr(HM + 0x40, HM + 0x2000)
put_ptr(HM + 0x2000 + 2 * 8, RECS + 24)
put_ptr(HM + 0x58, HM + 0x4000)                            -- runtime 12B
put_u32(HM + 0x4000 + 2 * 12, 3)                           -- spare sinks
put_u32(HM + 0x4000 + 2 * 12 + 4, 0x42280000)              -- heat 42.0f
put(HM + 0x4000 + 2 * 12 + 8, string.char(0))              -- lock off
put_ptr(OWN + BUILD.static.heat.slot, HSTB)
local hn = BUILD.static.heat.count
local hlo, hhi = 0x00002351, 0x00004444
local hhome = ((hhi % hn) * (4294967296 % hn) + hlo % hn) % hn
put(HSTB + hhome * 16, HRES)
put_u32(HSTB + hhome * 16 + 8, 4)
put_u32(HSTB + hhome * 16 + 12, 0)
local HCFG = HSTB + hn * 16 + 4 * 0x250
put_u32(HCFG + 0x5c, 6)                                    -- sinks max
put_u32(HCFG + 0x60, 0x42C80000)                           -- overheat temp 100.0f
make_map(HM + 0x68, {}, 8, 1)                              -- no config override
put_u32(ISTATE + 4, 9501)                                  -- equipped

CH.init({ base = MOD, read = read_fake })
row = CH.read()
ok(row.status == 'ok', 'heat weapon read ok (got ' .. tostring(row.status) .. ')')
ok(row.path == 'heat', 'heat path selected via driver flags')
ok(row.heat == 42.0, 'heat f32 decoded: ' .. tostring(row.heat))
ok(row.spare == 3 and row.spare_kind == 'sinks', 'spare sinks: ' .. tostring(row.spare))
ok(row.overheated == false, 'lock byte off')
ok(row.sinks_max == 6, 'config sinks max from static heat table')

-- ------------------------------------------------- scenario 4: resource ammo
-- Cremator-style burn weapon 9700: flags 0x400, fuel in resource manager,
-- provider entity 8002 (the backpack) whose deposit count is TANKS.
put_u32(DM + 0x3000, 0x400)
local RRES = string.char(0x77, 0x77, 0, 0, 0x88, 0x88, 0, 0)
put(RECS + 3 * 24, RRES)
put(RECS + 3 * 24 + 8, string.char(0xE4, 0x25, 0, 0))      -- id 9700
put(RECS + 3 * 24 + 20, string.char(1))
make_map(OWN + BUILD.entity_map, { { 9700, 3 }, { 8002, 2 }, { 9501, 1 } }, 8, 1)
make_map(DM + 0x28, { { 9700, 0 } }, 8, 1)
put_ptr(DM + 0x2000, RECS + 3 * 24)
make_map(HM + 0x28, {}, 8, 1)                              -- heat component gone
local RESM = 0x7FF600090000
put_ptr(MOD + BUILD.resource[1], RESM)
make_map(RESM + 0x20, { { 9700, 1 } }, 8, 1)
put_ptr(RESM + 0x38, RESM + 0x2000)
put_ptr(RESM + 0x2000 + 1 * 8, RECS + 3 * 24)
put_ptr(RESM + 0x48, RESM + 0x4000)                        -- 36B runtime rows
put_u32(DEPM + 0x3000, 500)                                -- pickup: full 500-unit pack
put_u32(RESM + 0x4000 + 1 * 36, 8002)                      -- provider = backpack
put_u32(RESM + 0x4000 + 1 * 36 + 0x10, 0x3F400000)         -- tank fraction 0.75f
put_u32(RESM + 0x4000 + 1 * 36 + 0x20, 1)                  -- single shared tank (Cremator)
put_u32(ISTATE + 4, 9700)

CH.init({ base = MOD, read = read_fake })
row = CH.read()
ok(row.status == 'ok', 'resource weapon read ok (got ' .. tostring(row.status) .. ')')
ok(row.path == 'resource', 'resource path via flags 0x400')
ok(row.fuel == 1, 'pickup: fraction = count/capacity = full (cold f32 ignored): ' .. tostring(row.fuel))
ok(row.spare == 500 and row.spare_kind == 'units', 'single-pool: raw backpack units: ' .. tostring(row.spare))
ok(row.tanks == 1, 'tank count field u32@+0x20 = 1 for shared pool')
-- after firing 100 units: count drops vs remembered capacity
put_u32(DEPM + 0x3000, 358)
row = CH.read()
ok(row.spare == 358 and row.spare_kind == 'units', 'reserve = backpack units: ' .. tostring(row.spare))
ok(math.abs(row.fuel - 358 / 500) < 0.001, 'fraction vs seen capacity: ' .. tostring(row.fuel))
-- multi-tank gun: reserve reads as TANKS
put_u32(RESM + 0x4000 + 1 * 36 + 0x20, 3)
row = CH.read()
ok(row.spare == 3 and row.spare_kind == 'tanks', 'multi-tank: reserve = tank count: ' .. tostring(row.spare))

print(string.format('ammo_chain: %d checks, %d failures', checks, fails))
if fails > 0 then error(fails .. ' failures') end
