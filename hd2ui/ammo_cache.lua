-- hd2ui/ammo_cache.lua -- Per-build cache for the ammo anchor resolver
-- (technique ported from how commercial ammo mods start instantly: a PE
-- stamp-keyed cache checked BEFORE any scanning, validated by the reader's
-- own structural gates). Own implementation, own data.
--
-- File format (single line): <pe_stamp_hex> <anchor_base_hex>
-- A cache hit is only trusted through validate(): the exact same context
-- gates the lock path uses (flag u32==1, aim f32 range, mag 0..capacity,
-- reserve sane). Wrong/stale base = validation fails = caller falls back to
-- scanning. This can never show a wrong number.
--
-- Lua 5.1.

local M = {}

-- Read the PE timestamp of a module from its own live headers. base = module
-- image base. Returns stamp (number) or nil.
function M.pe_stamp(read_u32, base)
  local e_lfanew = read_u32(base + 0x3C)
  if not e_lfanew or e_lfanew <= 0 or e_lfanew > 0x1000 then return nil end
  local sig = read_u32(base + e_lfanew)
  if sig ~= 0x00004550 then return nil end   -- 'PE\0\0'
  return read_u32(base + e_lfanew + 8)
end

function M.load(path)
  local ok, f = pcall(io.open, path, 'r')
  if not ok or not f then return nil end
  local line = f:read('*l')
  f:close()
  if not line then return nil end
  local stamp_hex, base_hex = line:match('^(%x+)%s+(%x+)$')
  if not stamp_hex or not base_hex then return nil end
  return tonumber('0x' .. stamp_hex), tonumber('0x' .. base_hex)
end

function M.save(path, stamp, base)
  local ok, f = pcall(io.open, path, 'w')
  if not ok or not f then return false end
  f:write(string.format('%X %X\n', stamp, base))
  f:close()
  return true
end

-- Validate a candidate base against the anchor spec using live memory.
-- t = transport exposing read_u32(addr) and read(addr, n); f32_decode =
-- the caller's IEEE-754 decoder (ammo_reader owns it).
function M.validate(t, f32_decode, spec, base)
  if not base or base < 0x10000 then return false end
  local flag = t.read_u32(base + spec.flag_off)
  if flag ~= spec.flag_val then return false end
  local raw = t.read(base + spec.aim_off, 4)
  if not raw then return false end
  local aim = f32_decode(raw)
  if aim ~= aim or aim < spec.aim_min or aim > spec.aim_max then return false end
  local mag = t.read_u32(base + spec.mag_off)
  if mag == nil or mag < 0 or mag > spec.capacity then return false end
  local res = t.read_u32(base + spec.res_off)
  if res == nil or res < 0 or res > 20000 then return false end
  return true
end

return M
