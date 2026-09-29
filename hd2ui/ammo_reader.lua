-- hd2ui/ammo_reader.lua -- Layout-driven weapon ammo reader on top of memreader.
--
-- This is the LAYER ABOVE the transport. It:
--   * takes a chain of (base_offset, sub_offset) hops resolved against the
--     game module base (the "layout"),
--   * walks the chain through memreader,
--   * plausibility-checks each intermediate pointer (so a broken offset
--     reports WHICH hop failed, not just "read failed"),
--   * decodes magazine / reserve / heat at the terminal node,
--   * exposes `rederive` seams so a live pass can substitute signature-scan
--     results for the static offsets.
--
-- OFFSETS ARE NOT HERE. The layout table below is a placeholder for the
-- chain SHAPE (the number of hops and their roles); the actual per-build
-- values must be derived against the running game.dll (PE 0x6A86132E). Until
-- then `read()` returns nil with a `needs_live_pass` reason, and the harness
-- is fully exercisable via `set_layout` against a fake backend.
--
-- Display-only: no writes, no game function calls. Same boundary as the
-- transport; this layer adds interpretation, not new system access.
--
-- Lua 5.1 / LuaJIT (no bitwise operators, no //).

-- Resolve the transport. PRIMARY path: explicit injection via
-- set_transport() -- the in-game assembled chunk has no filesystem require,
-- so the entry injects the chunk-registry module here (same pattern as
-- memreader.set_backend / demo_counter's `source` injection). FALLBACK:
-- headless tests and dev can just require us; we resolve the transport from
-- the filesystem ourselves.
local function resolve_from_filesystem()
  local ok, m = pcall(require, 'hd2ui.memreader')
  if ok and m and m.available then return m end
  return nil
end

local floor = math.floor
-- 0/0 is NaN under LuaJIT (PUC Lua 5.1 errors on it, but the only runtime we
-- target is the game's LuaJIT); this is what the NaN branch returns.
local NAN = 0 / 0

local S = {
  available = true,
  transport = nil,       -- injected via set_transport (in-game chunk) or lazy-resolved
  module_base = nil,     -- game.dll base address (number)
  layout = nil,          -- current offset layout (see below)
  last_error = nil,      -- human-readable reason for the last failed read
  last_chain = nil,      -- last successful chain (for diagnostics)
}

-- Current transport: the injected one, else lazy-resolved from filesystem
-- (headless/dev). Nil when no transport exists at all.
local function transport()
  local t = S.transport
  if not t then t = resolve_from_filesystem() end
  return t
end

-- A layout is a list of hops plus terminal field offsets. Each hop is
-- { off = <number> } meaning: at the CURRENT node, read a pointer at
-- (node_base + off) to get the NEXT node's address. The first hop's base is
-- module_base (the "player" chain start). The terminal hop's address is where
-- magazine/reserve/heat live, at fixed offsets from the final node.
--
-- Shape (placeholder values are 0 until derived):
--   hops: player -> owner -> unit_map -> entity_map -> records -> inventory
--         -> selected_slot -> weapon_driver   (8 hops)
--   terminal: magazine (u32), reserve (u32), heat (f32/u32)
local DEFAULT_LAYOUT = {
  module = 'game.dll',
  hops = {
    { off = 0 },  -- player
    { off = 0 },  -- owner
    { off = 0 },  -- unit_map
    { off = 0 },  -- entity_map
    { off = 0 },  -- records
    { off = 0 },  -- inventory
    { off = 0 },  -- selected_slot
    { off = 0 },  -- weapon_driver (terminal node)
  },
  fields = {
    magazine = 0,   -- u32 at weapon_driver + magazine
    reserve  = 0,   -- u32 at weapon_driver + reserve
    heat     = 0,   -- f32 at weapon_driver + heat (interpreted as 0..1)
  },
  -- Plausibility bounds for a real HD2 weapon (used to sanity-check a read):
  limits = {
    magazine_min = 1, magazine_max = 200,
    reserve_min  = 0, reserve_max  = 20000,
    heat_min     = 0, heat_max     = 1.0,
  },
}

local function clone_layout(t)
  local c = {}
  for k, v in pairs(t) do
    if type(v) == 'table' then
      c[k] = clone_layout(v)
    else
      c[k] = v
    end
  end
  return c
end

local R = {}
R.available = true
R.state = function() return S end

-- Transport injection seam. In the in-game assembled chunk the entry calls
-- this with the chunk-registry module (`__hd2ui_require('hd2ui.memreader')`);
-- headless tests can call it with any object exposing read/read_u8/read_u32/
-- read_ptr (or omit it entirely and let the filesystem fallback resolve the
-- real memreader). Mirrors memreader.set_backend: the seam, not the module.
function R.set_transport(t)
  if t ~= nil then
    assert(type(t) == 'table' and type(t.read) == 'function'
      and type(t.read_u32) == 'function' and type(t.read_ptr) == 'function',
      'transport must expose read/read_u32/read_ptr')
  end
  S.transport = t
  return true
end

function R.transport()
  return transport()
end

-- The documented chain shape (8 hops + terminal fields) with zeroed offsets.
-- The live pass fills in the real offsets for the running build; the test
-- harness uses it as the starting shape. Not auto-applied: zeroed offsets
-- would read garbage, so a layout must be set explicitly before read() works.
function R.default_layout()
  return clone_layout(DEFAULT_LAYOUT)
end

function R.set_layout(layout)
  -- Validate the shape, then store.
  local l = layout or {}
  assert(type(l.hops) == 'table' and #l.hops >= 1, 'layout.hops must be a non-empty list')
  for i, h in ipairs(l.hops) do
    assert(type(h) == 'table' and type(h.off) == 'number',
      ('layout.hops[%d].off must be a number'):format(i))
  end
  assert(type(l.fields) == 'table', 'layout.fields required')
  assert(type(l.fields.magazine) == 'number', 'layout.fields.magazine required')
  assert(type(l.fields.reserve)  == 'number', 'layout.fields.reserve required')
  S.layout = clone_layout(l)
  return true
end

function R.layout()
  return S.layout
end

-- Resolve the module base. If `module_base` was set explicitly (live pass does
-- this after finding game.dll), use it. Otherwise return nil (live pass must
-- set it; headless tests set it via set_module_base).
function R.set_module_base(addr)
  assert(type(addr) == 'number' and addr >= 0x10000, 'module_base must be a number >= 0x10000')
  S.module_base = addr
  return true
end

function R.module_base()
  return S.module_base
end

------------------------------------------------------------------------------
-- Anchor layout mode (content-based; no module chain needed)
--
-- The ammo component carries a per-weapon-type 16-byte GUID at mag+0x24, byte
-- identical across sessions/redeploys. The HOST scans for it (frame-budgeted,
-- e.g. live_scan.scan_bytes) and hands us the HIT ADDRESS; fields then live at
-- fixed negative offsets. This is the primary resolution path until (if ever)
-- a module-static chain replaces it.
--
-- f32_from_le is defined further down (shared with the chain path); forward-
-- declare it here so read_anchor's closure captures the LOCAL, not a global.
local f32_from_le
------------------------------------------------------------------------------
local ANCHOR_TABLE = {
  -- weapon key -> { guid hex (32 chars), mag_off, res_off, heat_off?, capacity }
  -- Derived live 2026-09-28/29 against PE 0x6A86132E (own scan, own layout).
  -- The struct also carries a constant flag u32==1 at -0x30 and an aim/state
  -- f32 (observed 1.0) at -0x28; enforcing them distinguishes real components
  -- from raw GUID copies (asset registry blobs, our own scan pattern).
  r4_deadeye = {
    guid = '95d2a294b52bd45e6ed282d0e08968b9',
    mag_off = -0x24, res_off = -0x2C, capacity = 8,
    flag_off = -0x30, flag_val = 1, aim_off = -0x28, aim_min = 0, aim_max = 4,
  },
}

local function hex_to_bytes(h)
  return (h:gsub('..', function(b) return string.char(tonumber(b, 16) or 0) end))
end

R.anchor_keys = function()
  local out = {}
  for k in pairs(ANCHOR_TABLE) do out[#out + 1] = k end
  table.sort(out)
  return out
end

function R.set_anchor_weapon(key)
  local spec = ANCHOR_TABLE[key]
  assert(spec, 'ammo_reader: unknown anchor weapon ' .. tostring(key))
  S.anchor = { key = key, spec = spec, pattern = hex_to_bytes(spec.guid), base = nil }
  return true
end

-- base = ADDRESS where the host's pattern scan found the GUID.
function R.set_anchor_base(base)
  if not S.anchor then return false, 'no anchor weapon selected' end
  assert(type(base) == 'number' and base > 0x10000, 'anchor base must be a plausible address')
  S.anchor.base = base
  return true
end

R.anchor_base = function() return S.anchor and S.anchor.base or nil end
R.anchor_pattern = function() return S.anchor and S.anchor.pattern or nil end
R.anchor_spec = function() return S.anchor and S.anchor.spec or nil end
R.f32_decode = f32_from_le   -- shared with the cache validator

local function read_anchor(anchor)
  local t = transport()
  if not t then return nil, 'no transport (set_transport or filesystem require)' end
  local spec, base = anchor.spec, anchor.base
  -- Structural context first: cheap, and rejects GUID copies (registry blobs
  -- and the scanner's own pattern string).
  if spec.flag_off then
    local flag = t.read_u32(base + spec.flag_off)
    if flag ~= spec.flag_val then return nil, 'anchor flag mismatch' end
  end
  if spec.aim_off then
    local raw = t.read(base + spec.aim_off, 4)
    if not raw then return nil, 'anchor aim read failed' end
    local aim = f32_from_le(raw)
    if aim ~= aim or aim < spec.aim_min or aim > spec.aim_max then
      return nil, 'anchor aim out of range'
    end
  end
  local mag = t.read_u32(base + spec.mag_off)
  if mag == nil then return nil, 'anchor magazine read failed' end
  local res = t.read_u32(base + spec.res_off)
  if res == nil then return nil, 'anchor reserve read failed' end
  local heat
  if spec.heat_off then
    local raw = t.read(base + spec.heat_off, 4)
    if not raw then return nil, 'anchor heat read failed' end
    heat = f32_from_le(raw)
    if heat ~= heat then return nil, 'anchor heat NaN (component moved?)' end
  end
  return { magazine = mag, reserve = res, heat = heat }
end

local function anchor_plausible(ammo, spec)
  return ammo.magazine >= 0 and ammo.magazine <= spec.capacity
    and ammo.reserve >= 0 and ammo.reserve <= 20000
end

-- Walk the chain. Returns the terminal node address, or (nil, reason).
-- Each intermediate address is plausibility-checked; the first hop that
-- produces an implausible pointer aborts with a reason naming the hop.
local function walk_chain(module_base, layout)
  local t = transport()
  if not t then return nil, 'no transport (set_transport or filesystem require)' end
  local addr = module_base
  for i, hop in ipairs(layout.hops) do
    local next_addr = t.read_ptr(addr + hop.off)
    if next_addr == nil then
      return nil, ('hop %d (off 0x%X): read_ptr failed'):format(i, hop.off)
    end
    -- Plausibility: a real pointer is not null and not absurdly large.
    if next_addr < 0x10000 or next_addr > 0x7FFFFFFFFFFF then
      return nil, ('hop %d (off 0x%X): implausible pointer 0x%X'):format(i, hop.off, next_addr)
    end
    addr = next_addr
  end
  return addr
end

-- Decode a 32-bit little-endian IEEE-754 float. Field layout: sign(1)|exp(8)|
-- mant(23). All ops integer-friendly for LuaJIT (no bitwise operators).
f32_from_le = function(s)
  local b1, b2, b3, b4 = s:byte(1), s:byte(2), s:byte(3), s:byte(4)
  local bits = b1 + b2 * 256 + b3 * 65536 + b4 * 0x1000000 % 0x100000000
  local sign = (floor(bits / 0x80000000) == 1) and -1 or 1   -- +/-1
  local exp  = floor(bits / 0x800000) % 256           -- bits 23..30
  local mant = bits % 0x800000                        -- bits 0..22 (23 bits)
  if exp == 0 then
    if mant == 0 then return 0 end
    return sign * 2 ^ (1 - 127) * (mant / 0x800000)
  elseif exp == 255 then
    if mant == 0 then return sign * math.huge end
    return sign * NAN
  end
  return sign * 2 ^ (exp - 127) * (1 + mant / 0x800000)
end

-- Read the terminal weapon node and decode magazine / reserve / heat.
-- Returns { magazine = number, reserve = number, heat = number } or (nil, reason).
local function read_weapon(weapon_addr, layout)
  local t = transport()
  local f = layout.fields
  local mag = t.read_u32(weapon_addr + f.magazine)
  if mag == nil then return nil, 'magazine read failed' end
  local res = t.read_u32(weapon_addr + f.reserve)
  if res == nil then return nil, 'reserve read failed' end
  local heat_raw = t.read(weapon_addr + f.heat, 4)
  if heat_raw == nil then return nil, 'heat read failed' end
  local heat = f32_from_le(heat_raw)
  if heat ~= heat then return nil, 'heat decoded as NaN (offsets likely stale)' end
  return { magazine = mag, reserve = res, heat = heat }
end

-- Main read. Returns { magazine, reserve, heat } or (nil, reason).
-- Priority: anchor mode (if weapon+base set) > module chain (if module_base +
-- layout set) > 'needs_live_pass'.
function R.read()
  if S.anchor and S.anchor.base then
    local ammo, aerr = read_anchor(S.anchor)
    if not ammo then
      S.last_error = aerr
      return nil, aerr
    end
    if not anchor_plausible(ammo, S.anchor.spec) then
      S.anchor.base = nil   -- component moved/switched: host must re-scan
      S.last_error = ('anchor_stale: mag=%d res=%d out of range for %s')
        :format(ammo.magazine, ammo.reserve, S.anchor.key)
      return nil, S.last_error
    end
    S.last_error = nil
    return ammo
  end
  if not S.module_base or not S.layout then
    S.last_error = 'needs_live_pass'
    return nil, 'needs_live_pass'
  end
  local terminal, werr = walk_chain(S.module_base, S.layout)
  if not terminal then
    S.last_error = werr
    return nil, werr
  end
  S.last_chain = terminal
  local ammo, derr = read_weapon(terminal, S.layout)
  if not ammo then
    S.last_error = derr
    return nil, derr
  end
  -- Plausibility gate: if values are wildly out of range, the offsets are
  -- probably wrong for this build. Report it rather than trusting garbage.
  local lim = S.layout.limits
  if ammo.magazine < lim.magazine_min or ammo.magazine > lim.magazine_max
    or ammo.reserve < lim.reserve_min or ammo.reserve > lim.reserve_max
    or ammo.heat < lim.heat_min or ammo.heat > lim.heat_max then
    S.last_error = ('plausibility: mag=%d res=%d heat=%s out of range (offsets likely stale)')
      :format(ammo.magazine, ammo.reserve, tostring(ammo.heat))
    return nil, S.last_error
  end
  S.last_error = nil
  return ammo
end

-- `rederive` seam: a live pass can call this with a new layout (e.g. after a
-- signature scan finds fresh offsets) without re-attaching. The transport
-- (memreader) is untouched; only the layout changes.
function R.rederive(new_layout)
  R.set_layout(new_layout)
  return R.read()
end

function R.last_error()
  return S.last_error
end

return R
