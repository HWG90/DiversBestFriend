-- hd2ui/derive_entry.lua -- In-game offset-derivation module (Bingus Shared
-- Loader / Arsenal addon, no rendering). Display-only: reads own-process
-- memory via ReadProcessMemory on our own pid (same technique the shipping
-- ammo mods use). Never writes to game memory, never calls game functions.
--
-- Why in-game: external (cross-process) reads get ~95% of the game's private
-- heap denied; reads from INSIDE the process cover it fully.
--
-- File-RPC protocol (all under %APPDATA%\Arrowhead\Helldivers2\):
--   derive_in.txt   one command line; when it changes we run it, then clear it
--   derive_out.log  results, one line per event
--   derive_tag.txt  current candidate address list (hex per line)
--
-- Commands:
--   probe [n]              read-sample n region first-pages, report ok/bad
--   scan <value> [f]       find u32 (or f32 with f) == value, chunked across
--                          frames (~6 MB per frame so the game keeps running)
--   scanb <hexbytes>       raw byte-pattern scan (e.g. CC970AAD24000000)
--   pointers <addr>        find 8-byte little-endian pointers to addr
--   next <value>           candidates from tag file whose u32 is now == value
--   nextf <value>          same, f32 compare
--   hex <addr> [n]         dump n bytes (default 64)
--   read <addr> <kind>     u32|u64|f32|ptr at addr
--   watch <addr> <kind> [period_s]  log value every period (default 1 s)
--   unwatch <addr>
--   stop                   cancel an in-progress scan
--
-- Lua 5.1 / LuaJIT.

local MR = require('hd2ui.memreader')
local LS = require('hd2ui.live_scan')
LS.set_transport(MR)

-- ffi resolution: BSL/LuaJIT may expose ffi as a global OR as a preloaded
-- module. The pcall below deliberately passes require as a VALUE (the builder
-- only rewrites the call form), and BSL's value-form require for 'ffi' is
-- proven to work in-game.
local ffi = rawget(_G, 'ffi')
if not ffi or not ffi.cdef then
  local ok, m = pcall(require, 'ffi')
  if ok and m and m.cdef then ffi = m end
end
assert(ffi and ffi.cdef, 'derive: ffi unavailable (global or module)')


local VERSION = 'dbf-derive r11'
local MAX_ERRORS = 50
local SCAN_BUDGET_BYTES = 6 * 1048576    -- per frame

-- ---------------------------------------------------------------------------
-- Paths + log.
-- ---------------------------------------------------------------------------
local dir
do
  local ok, d = pcall(os.getenv, 'DBF_DERIVE_DIR')
  if not ok or type(d) ~= 'string' or d == '' then
    local ok2, appdata = pcall(os.getenv, 'APPDATA')
    if not ok2 or type(appdata) ~= 'string' or appdata == '' then
      return { installed = false, reason = 'no APPDATA' }
    end
    d = appdata .. '/Arrowhead/Helldivers2'
  end
  dir = d .. '/'
end
local IN_FILE  = dir .. 'derive_in.txt'
local LOG_FILE = dir .. 'derive_out.log'
local TAG_FILE = dir .. 'derive_tag.txt'

local function log(msg)
  local ok, f = pcall(io.open, LOG_FILE, 'a')
  if not ok or not f then return end
  local t = os.date and os.date('%H:%M:%S') or '?'
  pcall(f.write, f, string.format('[%s] %s\n', t, tostring(msg)))
  pcall(f.close, f)
end
local function write_file(path, content)
  local ok, f = pcall(io.open, path, 'w')
  if not ok or not f then return false end
  pcall(f.write, f, content)
  pcall(f.close, f)
  return true
end
local function read_file(path)
  local ok, f = pcall(io.open, path, 'r')
  if not ok or not f then return nil end
  local s = f:read('*a')
  f:close()
  return s
end

write_file(IN_FILE, '')
write_file(TAG_FILE, '')
write_file(LOG_FILE, '')   -- fresh log per install (previous run archived externally)

-- ---------------------------------------------------------------------------
-- Attach to OURSELVES (the game process). GetCurrentProcessId is unambiguous
-- (the Steam launcher is also 'helldivers2.exe').
-- ---------------------------------------------------------------------------
local self_pid = MR.self_pid and MR.self_pid() or nil   -- alias-bound via memreader
local ok_att, att_err = MR.attach(self_pid, 'helldivers2.exe')
if not ok_att then
  log('ATTACH_FAIL ' .. tostring(att_err))
  return { installed = false, reason = 'attach failed' }
end
local rok, rn = LS.enum_regions()
if not rok then
  log('ENUM_FAIL ' .. tostring(rn))
  return { installed = false, reason = 'enum failed' }
end
log(VERSION .. ' START pid=' .. self_pid .. ' regions=' .. rn)

-- ---------------------------------------------------------------------------
-- State.
-- ---------------------------------------------------------------------------
local S = {
  clock = 0, next_poll = 0, last_in = nil,
  errors = 0, disabled = false,
  scan = nil,          -- { mode='u32'|'f32', pat, addrs, total, region_i, pos, base, size, bytes_this_frame }
  watches = {},        -- addr -> { kind, period, next_at }
}

local function load_tag()
  local s = read_file(TAG_FILE)
  local addrs = {}
  if s then
    for line in s:gmatch('%x+') do
      local a = tonumber('0x' .. line)
      if a then addrs[#addrs + 1] = a end
    end
  end
  return addrs
end

-- f32 byte pattern for compare (kept local; live_scan has its own copy).
local function f32_pat(v)
  local bits
  if v == 0 then bits = 0 else
    local sign = 0
    if v < 0 then sign = 0x80000000 v = -v end
    local e, m = 0, v
    if v >= 2 then while m >= 2 do m = m / 2 e = e + 1 end
    elseif v < 1 then while m < 1 do m = m * 2 e = e - 1 end end
    local exp = e + 127
    local mant = math.floor((m - 1) * 0x800000 + 0.5)
    bits = sign + math.floor(exp * 0x800000) + mant
  end
  return string.char(bits % 256, math.floor(bits / 256) % 256,
                     math.floor(bits / 65536) % 256, math.floor(bits / 0x1000000) % 256)
end

local function decode(addr, kind)
  if kind == 'u64' or kind == 'ptr' then
    local p = MR.read_ptr(addr); return p and string.format('0x%X', p) or 'nil'
  elseif kind == 'f32' then
    local s = MR.read(addr, 4); if not s then return 'nil' end
    local b1, b2, b3, b4 = s:byte(1), s:byte(2), s:byte(3), s:byte(4)
    local bits = b1 + b2 * 256 + b3 * 65536 + (b4 * 0x1000000) % 0x100000000
    local sign = (math.floor(bits / 0x80000000) == 1) and -1 or 1
    local exp = math.floor(bits / 0x800000) % 256
    local mant = bits % 0x800000
    if exp == 255 then return (mant == 0) and (sign * math.huge) or 'nan' end
    if exp == 0 then return sign * (mant / 0x800000) * 2 ^ -126 end
    return sign * 2 ^ (exp - 127) * (1 + mant / 0x800000)
  else
    local v = MR.read_u32(addr); return v == nil and 'nil' or tostring(v)
  end
end

-- ---------------------------------------------------------------------------
-- Per-frame chunked scan.
-- ---------------------------------------------------------------------------
local function start_scan(value, is_f32)
  local st = LS.state()
  LS.enum_regions()   -- refresh: allocations since install are invisible to a stale list
  S.scan = {
    is_f32 = is_f32,
    pat = is_f32 and f32_pat(value) or string.char(value % 256, math.floor(value / 256) % 256,
            math.floor(value / 65536) % 256, math.floor(value / 0x1000000) % 256),
    addrs = {}, total = 0, ri = 0, pos = 0, bytes_done = 0,
  }
  st.chunk = 1048576
  st.scan_max = 8000000
  log('SCAN_START ' .. (is_f32 and 'f32=' or 'u32=') .. tostring(value) .. ' regions=' .. #st.regions)
end

local function step_scan()
  local sc = S.scan
  local st = LS.state()
  local plen = #sc.pat
  local budget = SCAN_BUDGET_BYTES
  while budget > 0 do
    if sc.ri >= #st.regions then
      -- done
      local lines = {}
      for i = 1, #sc.addrs do lines[#lines + 1] = string.format('%X', sc.addrs[i]) end
      write_file(TAG_FILE, table.concat(lines, '\n') .. '\n')
      log(string.format('SCAN_DONE total=%d kept_in_file=%d bytes=%.2fGB', sc.total, #sc.addrs, sc.bytes_done / 2^30))
      S.scan = nil
      return
    end
    if sc.pos == 0 then
      local r = st.regions[sc.ri + 1]
      if r then sc.base, sc.size = r.base, r.size else sc.base, sc.size = 0, 0 end
    end
    local r = st.regions[sc.ri + 1]
    if not r or sc.pos >= r.size then
      sc.ri = sc.ri + 1 sc.pos = 0
    else
      -- MR.read caps at 4096 bytes per call (one page).
      local n = math.min(4096, r.size - sc.pos)
      local data = MR.read(r.base + sc.pos, n)
      if data then
        local from = 1
        while true do
          local s = data:find(sc.pat, from, true)
          if not s then break end
          sc.total = sc.total + 1
          if #sc.addrs < st.scan_max then sc.addrs[#sc.addrs + 1] = r.base + sc.pos + (s - 1) end
          from = s + 1
        end
        sc.bytes_done = sc.bytes_done + #data
        budget = budget - #data
        local adv = (#data >= plen) and (#data - (plen - 1)) or 1
        sc.pos = sc.pos + adv
      else
        sc.pos = sc.pos + 4096   -- page unreadable; skip one page
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Commands (immediate ones).
-- ---------------------------------------------------------------------------
-- Chunked narrowing: stream derive_tag.txt line-wise, re-check NARROW_SLICE
-- candidates per frame, survivors into a tmp file, swap at EOF. Keeps both
-- frame time (~20k reads) and memory (no full candidate load) bounded.
local NARROW_SLICE = 20000
local function start_narrow(value, is_f32)
  local f = io.open(TAG_FILE, 'r')
  if not f then log('NEXT_ERR no tag file') return end
  local tmp = TAG_FILE .. '.tmp'
  local w = io.open(tmp, 'w')
  if not w then f:close() log('NEXT_ERR tmp open failed') return end
  S.narrow = { fin = f, fout = w, tmp = tmp, value = value,
               pat = is_f32 and f32_pat(value) or nil, done = 0, kept = 0 }
  log(string.format('NARROW_START value=%s is_f32=%s', tostring(value), tostring(is_f32)))
end

local function step_narrow()
  local nw = S.narrow
  local n = 0
  while n < NARROW_SLICE do
    local line = nw.fin:read('*l')   -- this LuaJIT build wants the starred option form
    if not line then break end
    local hex = line:match('%x+')
    local a = hex and tonumber('0x' .. hex)
    if a then
      local hit
      if nw.pat then hit = (MR.read(a, 4) == nw.pat)
      else hit = (MR.read_u32(a) == nw.value) end
      if hit then nw.kept = nw.kept + 1; nw.fout:write(hex, '\n') end
      nw.done = nw.done + 1
    end
    n = n + 1
  end
  if n == 0 then
    nw.fin:close(); nw.fout:close()
    os.remove(TAG_FILE)
    os.rename(nw.tmp, TAG_FILE)
    log(string.format('NEXT_DONE value=%s rechecked=%d kept=%d', tostring(nw.value), nw.done, nw.kept))
    local r = io.open(TAG_FILE, 'r')
    if r then
      local c = 0
      while c < 20 do
        local l = r:read('*l')
        if not l then break end
        log('  0x' .. l)
        c = c + 1
      end
      r:close()
    end
    S.narrow = nil
  end
end

local function cmd_probe(n)
  local st = LS.state()
  local ok_c, bad_c, bytes = 0, 0, 0
  local total = #st.regions
  if n > total then n = total end
  local stride = math.max(1, math.floor(total / n))
  for i = 1, total, stride do
    local r = st.regions[i]
    if r then
      local s = MR.read(r.base, 4096)
      if s then ok_c = ok_c + 1 bytes = bytes + #s else bad_c = bad_c + 1 end
    end
    if ok_c + bad_c >= n then break end
  end
  log(string.format('PROBE sampled=%d ok=%d bad=%d bytes=%.1fMB regions_total=%d',
    ok_c + bad_c, ok_c, bad_c, bytes / 2^20, total))
end

-- Parse an address token (0x-prefixed or bare hex). NEVER tonumber(s, 16) in
-- this LuaJIT build (saturates to 32 bits) — prefix 0x and use plain tonumber.
local function parse_addr(s)
  if not s then return nil end
  local bare = s:match('^[0-9a-fA-F]+$') and s or s:match('^0[xX]([0-9a-fA-F]+)$')
  return bare and tonumber('0x' .. bare)
end

local function handle_line(line)
  local cmd, rest = line:match('^(%S+)%s*(.-)%s*$')
  if not cmd or cmd == '' then return end
  if cmd == 'probe' then cmd_probe(tonumber(rest) or 200)
  elseif cmd == 'scan' then
    local is_f32 = rest:match('f') ~= nil
    local v = tonumber((rest:match('0[xX]%x+') or rest:match('^%s*%d+')))
    if v then if S.scan then log('SCAN_QUEUED_STOP current first') S.scan = nil end start_scan(v, is_f32)
    else log('ERR scan needs value') end
  elseif cmd == 'next' or cmd == 'nextf' then
    local v = tonumber((rest:match('^%s*(%d+%.?%d*)') or rest:match('(%d+%.?%d*)$')))
    if not v then log('ERR next needs value')
    elseif S.scan then log('ERR busy: scan running, try again')
    elseif S.narrow then log('ERR busy: narrowing already running')
    else start_narrow(v, cmd == 'nextf') end
  elseif cmd == 'stop' then
    if S.scan then S.scan = nil log('SCAN_STOPPED') end
    if S.narrow then
      pcall(function() S.narrow.fin:close(); S.narrow.fout:close() end)
      S.narrow = nil log('NARROW_STOPPED')
    end
  elseif cmd == 'scanb' or cmd == 'pointers' then
    local pat
    if cmd == 'pointers' then
      local a = parse_addr((rest:match('^(%S+)')))
      if not a then log('ERR pointers <addr>') return end
      pat = ''
      local v = a
      for _ = 1, 8 do pat = pat .. string.char(v % 256); v = math.floor(v / 256) end
    else
      local hexs = (rest:match('^([0-9a-fA-F]+)') or ''):gsub('..', function(b) return string.char(tonumber(b, 16)) end)
      if #hexs == 0 then log('ERR scanb <hex bytes, e.g. CC970AAD24000000>') return end
      pat = hexs
    end
    if S.narrow then log('ERR busy: narrowing running') return end
    S.scan = nil
    local st = LS.state()
    LS.enum_regions()
    st.chunk = 1048576
    st.scan_max = 8000000
    S.scan = { is_f32 = false, pat = pat, addrs = {}, total = 0, ri = 0, pos = 0, bytes_done = 0 }
    log(string.format('SCANB_START patlen=%d regions=%d', #pat, #st.regions))
  elseif cmd == 'cam' then
    -- SAFE camera probe: the ONE proven engine call (main world only; R4/R5
    -- proved everything else AVs). Reports the handle's tostring (LuaJIT
    -- userdata usually embeds a pointer) + field reads, and if an address is
    -- visible, hex-dumps around it via self-RPM. NEVER calls sr.Camera
    -- accessors on the handle (proven AV 2026-09-29, twice).
    local sr = rawget(_G, 'stingray')
    if type(sr) ~= 'table' or type(sr.World) ~= 'table' then
      log('CAM stingray not exposed to the derive VM') return
    end
    local okw, worlds = pcall(sr.Application.worlds)
    local main
    if okw and type(worlds) == 'table' then
      local okm, m = pcall(sr.Application.main_world)
      if okm and m then main = m end
    end
    if not main then log('CAM no main world') return end
    local okp, cam = pcall(sr.World.debug_camera_pose, main)
    if not okp or cam == nil then log('CAM pose call failed: ' .. tostring(cam)) return end
    local okx, x, y, z, w = pcall(function() return cam.x, cam.y, cam.z, cam.w end)
    local hs = tostring(cam)
    log(string.format('CAM handle tostring=%s fields x=%s y=%s z=%s w=%s', hs,
      tostring(x), tostring(y), tostring(z), tostring(w)))
    local hex = hs:match('(0x%x+)') or hs:match('^userdata:%s*(%x+)$')
    local addr
    if hex then addr = tonumber('0x' .. hex:gsub('^0x', '')) end
    if addr and addr > 65536 then
      log(string.format('CAM dumping 0x%X..+0x140 (handle header + payload)', addr - 0x40))
      local d = MR.read(addr - 0x40, 0x140)
      if d then
        for i = 1, #d, 16 do
          local chunk, hline = d:sub(i, i + 15), {}
          for j = 1, #chunk do hline[#hline + 1] = string.format('%02X', chunk:byte(j)) end
          log(string.format('CAMHEX 0x%X  %s', addr - 0x40 + i - 1, table.concat(hline, ' ')))
        end
      else
        log('CAM dump failed (handle addr unreadable)')
      end
    else
      log('CAM no address visible in tostring')
    end
  elseif cmd == 'hex' then
    local a = parse_addr((rest:match('^(%S+)')))
    local n = tonumber((rest:match('%s(%d+)$'))) or 64
    if a then
      local s = MR.read(a, math.min(n, 4096))
      if s then
        for i = 1, #s, 16 do
          local chunk, hline = s:sub(i, i + 15), {}
          for j = 1, #chunk do hline[#hline + 1] = string.format('%02X', chunk:byte(j)) end
          log(string.format('HEX 0x%X  %s', a + i - 1, table.concat(hline, ' ')))
        end
      else log('HEX read failed at ' .. rest) end
    end
  elseif cmd == 'read' then
    local a, kind = rest:match('^(%S+)%s+(%w+)$')
    local addr = parse_addr(a)
    if addr then log('READ ' .. string.format('0x%X', addr) .. ' ' .. kind .. ' = ' .. tostring(decode(addr, kind or 'u32')))
    else log('ERR read <addr> <u32|u64|f32|ptr>') end
  elseif cmd == 'watch' then
    local a, kind, period = rest:match('^(%S+)%s+(%w+)%s+(%d*%.?%d+)$')
    if not period then a, kind = rest:match('^(%S+)%s+(%w+)$') period = '1' end
    local addr = parse_addr(a)
    if addr then
      S.watches[addr] = { kind = kind or 'u32', period = tonumber(period) or 1, next_at = 0 }
      log('WATCH_SET ' .. string.format('0x%X', addr) .. ' ' .. tostring(kind) .. ' every ' .. tostring(period) .. 's')
    else log('ERR watch <addr> <kind> [period]') end
  elseif cmd == 'unwatch' then
    local a = parse_addr((rest:match('^(%S+)')))
    if a then S.watches[a] = nil log('WATCH_OFF ' .. string.format('0x%X', a)) end
  elseif cmd == 'watches' then
    local c = 0
    for addr, w in pairs(S.watches) do c = c + 1; log(string.format('WATCH %s %s', string.format('0x%X', addr), w.kind)) end
    if c == 0 then log('WATCH none') end
  else
    log('ERR unknown command: ' .. cmd)
  end
end

-- ---------------------------------------------------------------------------
-- Frame tick.
-- ---------------------------------------------------------------------------
local function frame(dt)
  S.clock = S.clock + dt
  if S.clock >= S.next_poll then
    S.next_poll = S.clock + 0.25
    local cur = read_file(IN_FILE)
    if cur and cur ~= S.last_in and cur ~= '' then
      S.last_in = cur
      write_file(IN_FILE, '')
      for line in cur:gmatch('[^\n]+') do
        local ok, err = pcall(handle_line, line)
        if not ok then log('CMD_ERR ' .. tostring(err)) end
      end
    end
  end
  if S.scan then
    local ok, err = pcall(step_scan)
    if not ok then log('SCAN_ERR ' .. tostring(err)); S.scan = nil end
  end
  if S.narrow then
    local ok, err = pcall(step_narrow)
    if not ok then
      log('NARROW_ERR ' .. tostring(err))
      pcall(function() S.narrow.fin:close(); S.narrow.fout:close() end)
      S.narrow = nil
    end
  end
  for addr, w in pairs(S.watches or {}) do
    if S.clock >= w.next_at then
      w.next_at = S.clock + w.period
      log('WATCH ' .. string.format('0x%X', addr) .. ' ' .. w.kind .. ' = ' .. tostring(decode(addr, w.kind)))
    end
  end
end

local old_update = rawget(_G, 'update')
if type(old_update) ~= 'function' then
  log('NO_UPDATE no global update(); not installing')
  return { installed = false, reason = 'no update' }
end
rawset(_G, '__DBF_DERIVE_INSTALLED', true)

rawset(_G, 'update', function(...)
  local dt = select(1, ...)
  if type(dt) ~= 'number' or dt ~= dt then dt = 1 / 60 end
  if dt < 0 then dt = 0 elseif dt > 0.25 then dt = 0.25 end
  if not S.disabled and S.errors < MAX_ERRORS then
    local ok, err = pcall(frame, dt)
    if not ok then
      S.errors = S.errors + 1
      log('FRAME_ERR #' .. S.errors .. ': ' .. tostring(err))
      if S.errors >= MAX_ERRORS then log('DISABLED after ' .. S.errors .. ' errors') S.disabled = true end
    else
      S.errors = 0
    end
  end
  return old_update(...)
end)

local old_shutdown = rawget(_G, 'shutdown')
rawset(_G, 'shutdown', function(...)
  log('SHUTDOWN')
  if type(old_shutdown) == 'function' then return old_shutdown(...) end
end)

log('INSTALLED')
return { installed = true, version = VERSION }
