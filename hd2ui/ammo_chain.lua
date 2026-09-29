-- hd2ui/ammo_chain.lua -- RAH-method ammo reading: module-static pointer
-- chain, resolved instantly from game.dll globals + fixed offsets for the
-- known build. Structure, layout constants and interpretation follow
-- ReticleAmmoHUD's approach (its build-25327279/pe-0x6AB3B43F table applies
-- to the live build); reimplemented as our own module on our own transport.
-- Every read is bounded and identity-checked (24-byte entity ownership,
-- pow2 map probes, range guards) exactly as that design does; a layout that
-- fails any check disables the chain, and the caller falls back to the
-- content-anchor scanner.
--
-- Usage:
--   local CH = require('hd2ui.ammo_chain')
--   CH.init({ base = game_dll_base, read = function(a, n) ... end, log = f })
--   if CH.verify() then local row = CH.read() end   -- per sample (~10Hz)
--
-- Returns model: { status, rounds, chamber, capacity, spare, spare_max,
--                  spare_kind ('mags'|'backpack'), path, resource, raw }
-- Lua 5.1 / LuaJIT. No bitwise ops (mod arithmetic + mul_low32).

local M = { available = true }

-- Layout for the live build (PE 0x6AB3B43F; same table serves 0x6AA96B14).
local BUILD = {
  name = 'pe-6AB3B43F', pe = 0x6AB3B43F, image_size = 0x4744000,
  player = 0x3326468, owner = 0x346BF98, inventory = 0x3326738,
  driver = 0x3326660, magazine = 0x3326648, rounds = 0x3326CF0,
  heat = 0x3326D48, selector = 0x3326420, weapondata = 0x3326CE0,
  charge = 0x3326C20,
  deposit = { 0x33265F0, 0x33265E8 },
  resource = { 0x3326AA0, 0x3326AA8, 0x3326A98, 0x3326AB0 },
  unit_map = 0xF22EC8, entity_map = 0xF1AEB0, records = 0xF32F18,
  mag_override = { 0x60, 0xa0 },
  heat_ok = true,
  static = {
    magazine = { slot = 0xF124A0, count = 540, stride = 160, source = 'known' },
    rounds     = { slot = 0xF12820, count = 50,  stride = 0x88, source = 'known' },
    heat       = { slot = 0xF12CC8, count = 58,  stride = 0x250, source = 'known' },
    charge     = { slot = 0xF12AD8, count = 20,  stride = 0xd8,  source = 'known' },
  },
  -- Code verification: these instruction bytes must sit at these RVAs for the
  -- layout to be trusted on the running binary (identity check for the build).
  signatures = {
    { 0x607200, '488b0561f2d10283b88400000000' },   -- local player global + count
    { 0xfd9c93, '4c8b15fe224902' },                 -- entity owner global
    { 0x9a83e0, '4c8b1551e39702' },                 -- inventory global
    { 0x745db6, '488b1da308be02' },                 -- weapon driver global
    { 0x744d02, '488b2d3f19be02' },                 -- magazine global
    { 0x744dc2, '4c8b0d271fbe02' },                 -- rounds global
  },
}
M.BUILD = BUILD

local floor = math.floor
local INVALID = 0xFFFFFFFF

local ctx = nil      -- { base, read, log }
local GAME = nil
local STATIC = {}    -- static-table record cache (per resource)
local CAL = { deposit = nil, resource = nil }
local BP_PAIRS = {}
local SEEN = {}
M = M or {}

------------------------------------------------------------------------------
-- byte helpers (no FFI in the hot path; strings in, numbers out)
------------------------------------------------------------------------------
local function u8(s, o) return s:byte(o + 1) end
local function u32(s, o)
  local a, b, c, d = s:byte(o + 1, o + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end
local function i32(s, o)
  local v = u32(s, o)
  if v >= 2147483648 then v = v - 4294967296 end
  return v
end
local function f32(s, o)
  local bits = u32(s, o)
  local sign = 1
  if bits >= 2147483648 then sign = -1; bits = bits - 2147483648 end
  local e = floor(bits / 8388608)
  local m = bits - e * 8388608
  if e == 255 then return (m == 0) and sign * (0/0) or 0/0 end
  if e == 0 then return sign * m * 2 ^ -149 end
  return sign * (1 + m / 8388608) * 2 ^ (e - 127)
end
local function resource_id(s, o)
  local out = {}
  for i = o + 8, o + 1, -1 do out[#out + 1] = string.format('%02x', s:byte(i)) end
  return table.concat(out)
end
local function mul_low32(a, b)
  a = a % 0x100000000; b = b % 0x100000000
  local hi = floor((a % 0x10000) * b / 0x10000)
  return (a * b + hi * 0x10000) % 0x100000000
end

local RD = { reads = 0, bytes = 0, max_reads = 320, max_bytes = 32768 }

local function rd(address, size)
  RD.reads = RD.reads + 1
  RD.bytes = RD.bytes + size
  if RD.reads > RD.max_reads or RD.bytes > RD.max_bytes then error('read budget', 0) end
  if type(address) ~= 'number' or address % 1 ~= 0 then error('bad address', 0) end
  local s = ctx and ctx.read(address, size)
  if not s or #s ~= size then error(string.format('unreadable 0x%X+%d', address, size), 0) end
  return s
end
local function ptr_of(s, o)
  local lo, hi = u32(s, o), u32(s, o + 4)
  if hi >= 32768 then error('pointer out of range', 0) end
  local p = lo + hi * 4294967296
  if p < 65536 then error('null pointer', 0) end
  return p
end
local function ptr(address) return ptr_of(rd(address, 8), 0) end
local function global(rva) return ptr(GAME + rva) end

------------------------------------------------------------------------------
-- engine structures, walked like the game walks them
------------------------------------------------------------------------------
-- Open-addressing map: slots ptr @0, capacity u32 @8 (pow2), empty key @12,
-- multiplier @16; rows {key u32, index u32}.
local function lookup(address, key, limit)
  local h = rd(address, 20)
  local capacity, empty, mult = u32(h, 8), u32(h, 12), u32(h, 16)
  if capacity == 0 or key == empty or key == INVALID then return nil end
  if capacity > limit or (capacity % (capacity / 2) ~= 0 and capacity > 1) then error('unsupported map', 0) end
  local slots = ptr_of(h, 0)
  local start = mul_low32(key, mult)
  for probe = 0, (capacity < 128 and capacity or 128) - 1 do
    local row = rd(slots + ((start + probe) % capacity) * 8, 8)
    local k, index = u32(row, 0), u32(row, 4)
    if k == key then return index ~= INVALID and index or nil end
    if k == empty then return nil end
  end
  error('map probe limit', 0)
end

-- Component lookup with the full 24-byte owner identity check.
local function component(manager, map_off, registry_off, entity_id, entity_bytes)
  local index = lookup(manager + map_off, entity_id, 65536)
  if not index then return nil end
  if index >= 4096 then error('component index out of range', 0) end
  local owner_rec = rd(ptr(ptr(manager + registry_off) + index * 8), 24)
  if owner_rec ~= entity_bytes then error('component owner mismatch', 0) end
  return index
end

local function entity_by_id(owner, id)
  if not id or id == 0 or id == INVALID then return nil end
  local i = lookup(owner + BUILD.entity_map, id, 1048576)
  if not i or i >= 1048576 then return nil end
  local rec = rd(owner + BUILD.records + i * 24, 24)
  if u32(rec, 8) ~= id then return nil end
  return rec
end

-- Static per-resource config table: rows of 16 {resource u64, index u32, 0},
-- home row = u64 resource mod n (split arithmetic), linear probing, records
-- follow at base + n*16 + index*stride.
local function home_row(resource8, n)
  local lo, hi = u32(resource8, 0), u32(resource8, 4)
  return ((hi % n) * (4294967296 % n) + lo % n) % n
end

local ZERO8 = string.rep('\0', 8)
local function static_record(kind, resource8)
  local spec = BUILD.static[kind]
  if not spec or not spec.count or spec.count < 1 then return nil end
  local owner = global(BUILD.owner)
  local base = ptr(owner + spec.slot)
  local key = kind .. ':' .. base .. ':' .. resource8
  local cached = STATIC[key]
  if cached ~= nil then return cached or nil end
  local n = spec.count
  local home = home_row(resource8, n)
  local index, probed, pos, done = false, 0, home, false
  while probed < n and not done do
    local cnt = math.min(32, n - pos, n - probed)
    local blk = rd(base + pos * 16, cnt * 16)
    for r = 0, cnt - 1 do
      local k = blk:sub(r * 16 + 1, r * 16 + 8)
      if k == resource8 then
        if u32(blk, r * 16 + 12) == 0 and u32(blk, r * 16 + 8) < n then index = u32(blk, r * 16 + 8) end
        done = true
        break
      end
      if k == ZERO8 then done = true break end
    end
    probed, pos = probed + cnt, (pos + cnt) % n
  end
  local record = index and rd(base + n * 16 + index * spec.stride, spec.stride) or false
  STATIC[key] = record
  return record or nil
end

-- per-weapon config: its override record (customisations/armour passives) or
-- the static resource template. Losing config costs only display polish.
local function config_record(kind, manager, resource8, weapon_id, override_map, override_array, stride)
  if override_map then
    local ok, rec = pcall(function()
      local ov = lookup(manager + override_map, weapon_id, 65536)
      if not ov then return nil end
      if ov >= 4096 then error('override index out of range', 0) end
      return rd(ptr(manager + override_array) + ov * stride, stride)
    end)
    if ok and rec then return rec, 'override' end
  end
  local ok, rec = pcall(static_record, kind, resource8)
  if not ok then return nil, 'error' end
  return rec, rec and 'static' or 'missing'
end

------------------------------------------------------------------------------
-- backpack / deposit (support weapons fed from a backpack entity)
------------------------------------------------------------------------------
local function find_component(rvas, id, rec)
  for _, rva in ipairs(rvas) do
    local okm, m = pcall(global, rva)
    if okm and m then
      local ok, idx = pcall(component, m, 0x20, 0x38, id, rec)
      if ok and idx then return m, idx, rva end
    end
  end
  return nil
end

local function deposit_count(owner, id)
  if not id or id == 0 or id == INVALID then return nil end
  local ok, rec = pcall(entity_by_id, owner, id)
  if not ok or not rec then return nil end
  local m, idx = find_component(BUILD.deposit, id, rec)
  if not m then return nil end
  local c = rd(ptr(m + 0x50) + idx * 8, 8)
  local count = i32(c, 0)
  if count < 0 or count > 5000 then return nil end
  return count
end

------------------------------------------------------------------------------
-- M API
------------------------------------------------------------------------------
function M.init(opts)
  assert(type(opts) == 'table' and type(opts.read) == 'function' and opts.base, 'init{base,read,log}')
  ctx = { read = opts.read, log = opts.log or function() end, base = opts.base }
  GAME = opts.base
  STATIC = {}
  return true
end

-- Build identity: instruction bytes at the layout's code RVAs must match.
function M.verify()
  local ok, err = pcall(function()
    for _, s in ipairs(BUILD.signatures) do
      local have = rd(GAME + s[1], #s[2] / 2)
      local want = (s[2]:gsub('%x%x', function(hh) return string.char(tonumber(hh, 16)) end))
      if have ~= want then error('sig mismatch at 0x' .. string.format('%X', s[1]), 0) end
    end
  end)
  return ok, err
end

-- One full sample: current wielded weapon -> ammo model (RAH read_weapon,
-- main-weapon + backpack scope).
function M.read()
  RD.reads, RD.bytes = 0, 0
  local row = { status = 'ok' }
  local ok, err = pcall(function()
    local pm = global(BUILD.player)
    local counts = rd(pm + 0x84, 8)
    if u32(counts, 0) == 0 or u32(counts, 4) == 0 then row.status = 'no_local_player' return end
    local player = rd(ptr(pm + 0xe8), 24)
    if (u8(player, 20) % 2) == 0 then row.status = 'player_not_owned' return end
    if lookup(pm + 0xd0, u32(player, 8), 64) ~= 0 then row.status = 'player_registry_mismatch' return end
    local avatar_unit = u32(rd(pm + 0x3a8, 4), 0)
    if avatar_unit == 0x7fff then row.status = 'no_avatar' return end

    local owner = global(BUILD.owner)
    local ei = lookup(owner + BUILD.unit_map, avatar_unit, 1048576)
    if not ei or ei >= 1048576 then row.status = 'avatar_entity_missing' return end
    local avatar = rd(owner + BUILD.records + ei * 24, 24)
    if u32(avatar, 16) ~= avatar_unit then row.status = 'avatar_unit_mismatch' return end
    if (u8(avatar, 20) % 2) == 0 then row.status = 'avatar_not_owned' return end
    local avatar_id = u32(avatar, 8)

    local inv = global(BUILD.inventory)
    local ii = lookup(inv + 0x28, avatar_id, 65536)
    if not ii or ii >= u32(rd(inv + 0x14, 4), 0) then row.status = 'no_inventory' return end
    if rd(ptr(ptr(inv + 0x40) + ii * 8), 24) ~= avatar then row.status = 'inventory_owner_mismatch' return end
    local inv_state = rd(ptr(inv + 0x50) + ii * 48, 48)
    local slot = u32(inv_state, 0x1c)
    row.slot = slot

    local SLOT_OFFSETS = { [1] = 0, [2] = 4, [3] = 8, [4] = 16, [5] = 16, [6] = 12 }
    local slot_off = SLOT_OFFSETS[slot]
    local wid = slot_off and u32(inv_state, slot_off) or nil
    if wid == 0 or wid == INVALID then wid = nil end
    row.weapon_id = wid
    if not wid then row.status = 'no_weapon_slot' return end

    local rec = entity_by_id(owner, wid)
    if not rec then row.status = 'weapon_entity_missing' return end
    row.resource = resource_id(rec, 0)

    local dm = global(BUILD.driver)
    local di = component(dm, 0x28, 0x40, wid, rec)
    if not di then row.status = 'no_weapon_driver' return end
    local driver = rd(ptr(dm + 0x50) + di * 40, 40)
    local flags = u32(driver, 0)
    row.flags = flags

    -- magazine-path weapon (sidearms, most primaries)
    if flags % 256 >= 128 then
      local mm = global(BUILD.magazine)
      local idx = component(mm, 0x20, 0x38, wid, rec)
      if idx then
        local state = rd(ptr(mm + 0x48) + idx * 16, 16)
        local runtime = rd(ptr(mm + 0x50) + idx * 12, 12)
        local cfg = config_record('magazine', mm, rec:sub(1, 8), wid,
          BUILD.mag_override[1], BUILD.mag_override[2], 160)
        row.path = 'magazine'
        row.state, row.runtime, row.config = state, runtime, cfg
        row.idx, row.mm = idx, mm
      end
    end
    if not row.path and (flags % 512) >= 256 then
      local rm = global(BUILD.rounds)
      local idx = component(rm, 0x28, 0x40, wid, rec)
      if idx then
        local state = rd(ptr(rm + 0x50) + idx * 24, 24)
        local runtime = rd(ptr(rm + 0x58) + idx * 20, 20)
        local cfg = config_record('rounds', rm, rec:sub(1, 8), wid, 0x68, 0xa8, 0x88)
        row.path = 'rounds'
        row.state, row.runtime, row.config = state, runtime, cfg
      end
    end
    if not row.path and flags % 1024 >= 512 and BUILD.heat_ok then
      -- laser / heat weapons: runtime spare sinks @0, heat f32 @4, lock u8 @8
      local hm = global(BUILD.heat)
      local idx = component(hm, 0x28, 0x40, wid, rec)
      if idx then
        local runtime = rd(ptr(hm + 0x58) + idx * 12, 12)
        local cfg = config_record('heat', hm, rec:sub(1, 8), wid, 0x68, 0xa8, 0x250)
        row.path = 'heat'
        row.runtime = runtime
        row.config = cfg
      end
    end
    if not row.path and flags % 4096 >= 1024 then
      -- 'resource ammo' (FlAME-4 Cremator & co): fuel units live in the
      -- resource manager's 36B runtime row; the provider entity is the
      -- backpack, whose deposit count IS the magazine/tank number.
      for _, rva in ipairs(BUILD.resource) do
        local okr, rm, ridx = pcall(function()
          local m = global(rva)
          local i2 = component(m, 0x20, 0x38, wid, rec)
          if not i2 then return nil end
          return m, i2
        end)
        if okr and rm then
          local rt = rd(ptr(rm + 0x48) + ridx * 36, 36)
          row.path = 'resource'
          row.runtime = rt
          row.resource_provider = u32(rt, 0)
          break
        end
      end
    end
    if not row.path then
      if flags % 4096 >= 1024 then
        -- resource-flagged weapon with no backpack provider: Arc-thrower and
        -- other charge guns. Their whole story is the charge gauge, and RAH
        -- proves the charge component answers for them -- so don't error,
        -- fall through to the charge-only presentation below.
        row.path = 'charge'
      else
        row.status = row.status == 'ok' and 'no_ammo_component' or row.status
        return
      end
    end

    -- charge probe shared across all ammo paths
    local function charge_probe()
      if row.charge ~= nil then return end
      local okc, cdat = pcall(function()
        local cm = global(BUILD.charge)
        local cidx = component(cm, 0x20, 0x38, wid, rec)
        if not cidx then return nil end
        local rt = rd(ptr(cm + 0x40) + cidx * 40, 40)
        local cfg = config_record('charge', cm, rec:sub(1, 8), wid, 0x50, 0x90, 0xd8)
        if not rt or not cfg then return nil end
        return { runtime = rt, config = cfg }
      end)
      row.charge = (okc and cdat) and cdat or false
      if row.charge and row.charge ~= false then
        local secs = f32(row.charge.runtime, 4)
        local full = f32(row.charge.config, 0x18)
        if secs == secs and full == full and full > 0.01 and full < 60 then
          row.charge_pct = math.min(1, math.max(0, secs / full))
        end
      end
    end

    if row.path == 'charge' then
      -- Arc-thrower family: resource bit set, no ammo managers answer, but
      -- the charge manager does. The charge gauge IS the weapon's HUD.
      charge_probe()
      if row.charge_pct == nil then
        row.path = nil
        row.status = 'unsupported_resource_ammo'
        return
      end
      row.rounds, row.capacity = 0, 1
      row.chamber, row.chambered = 0, false
      row.spare = nil
      row.charge_only = true
      return
    end

    if row.path == 'heat' then
      row.heat = f32(row.runtime, 4)
      row.overheated = u8(row.runtime, 8) ~= 0
      row.sinks = i32(row.runtime, 0)
      if row.config then
        row.sinks_max = u32(row.config, 0x5c)
        row.heat_max = f32(row.config, 0x60)
        if not row.heat_max or row.heat_max <= 0 or row.heat_max > 10000 then row.heat_max = nil end
      end
      -- Burn weapons (flamethrowers) land here too and their 'heat' field is
      -- really fuel; never reject out-of-gauge values, clamp the display only.
      if row.heat ~= row.heat then row.heat = 0 end   -- NaN guard
      if row.heat < 0 or row.heat > 1e6 then row.heat = 0 end
      row.rounds = 1
      row.capacity = 1
      local own = (row.sinks_max and row.sinks_max > 0)
      if row.backpack then
        row.spare, row.spare_kind = row.backpack, 'backpack'
      elseif own then
        row.spare, row.spare_kind = row.sinks, 'sinks'
        row.spare_max = row.sinks_max
      end
      return
    end

    -- resource weapons: backpack (provider) deposit = TANK count, shown raw
    if row.path == 'resource' then
  charge_probe()
      if row.resource_provider and row.resource_provider ~= INVALID then
        local okd, cnt = pcall(deposit_count, owner, row.resource_provider)
        if okd and cnt then row.spare, row.spare_kind = cnt, 'units' end
      end
      -- RAH-exact resource semantics: the provider deposit count IS the
      -- counter; percentage = count / highest count observed for this weapon
      -- (its capacity). The runtime f32 is a smoothed gun-side gauge that is
      -- UNINITIALIZED (0) right after pickup — never use it for display.
      local count = row.spare or 0
      local skey = 'res:' .. tostring(wid)
      if count > (SEEN[skey] or 0) then SEEN[skey] = count end
      row.capacity_units = math.max(SEEN[skey] or count, count, 1)
      row.fuel = count / row.capacity_units
      local tanks = u32(row.runtime, 0x20)
      if tanks > 99 then tanks = 0 end
      row.tanks = tanks
      if tanks > 1 and row.spare ~= nil then
        row.spare, row.spare_kind = tanks, 'tanks'
      end
      row.rounds, row.capacity = 0, 0
      row.chamber, row.chambered = 0, false
      return
    end

    -- backpack detection for weapons with no own reserve (support guns):
    -- inv_state carries candidate entity ids; the backpack pairs with the
    -- weapon by adjacency (weapon id + 1) or a learned resource pair.
    local own_reserve = false
    if row.path == 'magazine' and row.config then
      own_reserve = u32(row.config, 0x8c) > 0 or u32(row.config, 0x94) > 0
    elseif row.path == 'rounds' and row.config then
      own_reserve = u32(row.config, 0x50) > 0
    end
    if not own_reserve then
      for _, off in ipairs({ 12, 16, 20, 24 }) do
        local bid = u32(inv_state, off)
        if bid ~= 0 and bid ~= INVALID and bid ~= wid and bid ~= avatar_id then
          local okb, brec = pcall(entity_by_id, owner, bid)
          local bres = okb and brec and resource_id(brec, 0)
          local pair = BP_PAIRS[row.resource]
          if bres and (bid == wid + 1 or pair == bres) then
            local okc, count = pcall(deposit_count, owner, bid)
            if okc and count then
              row.backpack, row.backpack_id = count, bid
              if pair ~= bres then BP_PAIRS[row.resource] = bres end
              break
            end
          end
        end
      end
    end

    ----------------------------------------------------------------------------
    -- interpret (RAH's documented layout):
    --   magazine state(+0,16): rounds i32@0, chamber token u32@8
    --            runtime(+0,12): spare mags i32@0, mirror i32@4, block u8@8
    --            config: capacity@0x88 mags_max@0x94 chambered u8@0x9c
    --   rounds   state(+24): per-mag rounds @4/@8, chamber token @0x10
    --            runtime(+20): reserve @0, selected mag @4
    --            config: capacity f32[2]@0x48, ammo_max u32@0x50, chambered u8@0x68
    ----------------------------------------------------------------------------
    local skey = tostring(wid) .. ':' .. row.resource
    local seen = SEEN[skey]
    if not seen then seen = { rounds = 0, spare = 0 }; SEEN[skey] = seen end

    if row.path == 'heat' then return end   -- handled above
    if row.path == 'magazine' then
      local rounds, token = i32(row.state, 0), u32(row.state, 8)
      local spare, mirror = i32(row.runtime, 0), i32(row.runtime, 4)
      if rounds < 0 or rounds > 5000 then row.status = 'rounds out of range' return end
      local cap, mags_max, chambered
      if row.config then
        cap, mags_max, chambered = u32(row.config, 0x88), u32(row.config, 0x94), u8(row.config, 0x9c) == 1
        if cap < 1 or cap > 5000 or mags_max > 5000 then cap, mags_max, chambered = nil, nil, nil end
      end
      seen.rounds = math.max(seen.rounds, rounds)
      row.rounds = rounds
      row.chamber = (chambered and token > 0) and 1 or 0
      row.capacity = cap and math.max(chambered and (cap - 1) or cap, rounds)
                      or math.max(seen.rounds, 1)
      row.chambered = chambered or false
      if row.backpack then
        row.spare, row.spare_kind = row.backpack, 'backpack'
        -- grid reference: largest backpack count seen for this weapon
        local sk = 'bp:' .. skey
        if (row.backpack or 0) > (SEEN[sk] or 0) then SEEN[sk] = row.backpack end
        row.pack_total = SEEN[sk]
      elseif row.config and mags_max == 0 and u32(row.config, 0x8c) == 0 then
        -- unknown reserve: leave nil
      elseif spare >= 0 and spare <= 5000 then
        seen.spare = math.max(seen.spare, spare)
        row.spare, row.spare_kind = spare, 'mags'
        row.spare_max = math.max(mags_max or 0, seen.spare)
      end
    else
      local sel = u32(row.runtime, 4)
      if sel > 1 then row.status = 'selected magazine out of range' return end
      local rounds, token = i32(row.state, 4 + sel * 4), u32(row.state, 0x10)
      local reserve = i32(row.runtime, 0)
      local cap, ammo_max, chambered
      if row.config then
        cap, ammo_max, chambered = f32(row.config, 0x48 + sel * 4), u32(row.config, 0x50), u8(row.config, 0x68) == 1
        if cap < 1 or cap > 5000 or ammo_max > 100000 then cap, ammo_max, chambered = nil, nil, nil
        else cap = floor(cap + 0.5) end
      end
      if rounds < 0 or rounds > 5000 then row.status = 'rounds out of range' return end
      seen.rounds = math.max(seen.rounds, rounds)
      row.rounds = rounds
      if cap and chambered then
        row.chamber = token ~= 0 and 1 or 0
        row.chambered = true
        cap = cap - 1
      else
        row.chamber, row.chambered = 0, false
      end
      row.capacity = cap and math.max(cap, rounds) or math.max(seen.rounds, rounds, 1)
      row.mag_index = sel
      if row.backpack then
        row.spare, row.spare_kind = row.backpack, 'backpack'
      elseif ammo_max == 0 and reserve == 0 then
        -- unknown
      elseif reserve >= 0 and reserve <= 100000 then
        row.spare, row.spare_kind = reserve, 'rounds'
        row.ammo_max = ammo_max   -- surfacing for reserve-bar gauges (additive)
      end
    end

    -- universal charge probe: charge time is a property of ANY charge weapon
    -- (Arc-thrower, Railgun, mortar pistol), independent of ammo path
    charge_probe()
  end)
  if not ok then row.status = row.status == 'ok' and ('error: ' .. tostring(err)) or row.status end
  row.reads, row.bytes = RD.reads, RD.bytes
  return row
end

return M
