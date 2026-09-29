-- HD2-Addon: mods/dbf/ammo/hud
-- dbf ammo hud r5; assembled by hd2ui/build_ammo.py; do not edit.
local __hd2ui_modules, __hd2ui_loaded = {}, {}
local __hd2ui_real = require
local function __hd2ui_require(name)
  local m = __hd2ui_loaded[name]
  if m ~= nil then return m end
  local f = __hd2ui_modules[name]
  if not f then
    -- Not ours: defer to the game's require (Arsenal/BSL preset lua resources
    -- arrive as mods/<mod>/preset_* lookups the manager deployed).
    local ok, v = pcall(__hd2ui_real, name)
    if ok then
      __hd2ui_loaded[name] = v
      return v
    end
    error('hd2ui: missing module ' .. tostring(name))
  end
  m = f()
  if m == nil then m = true end
  __hd2ui_loaded[name] = m
  return m
end
__hd2ui_modules['hd2ui.memreader'] = function()
-- hd2ui/memreader.lua -- The memory-read seam for the ammo reader.
--
-- Display-only by construction: it ATTACHES to the game process and READS its
-- memory. It never writes, never calls a game function, never injects. The
-- only FFI it loads is kernel32's ReadProcessMemory (and the process/module
-- lookup calls needed to find the right PID). That is the same boundary
-- ReticleAmmoHUD operates at; the technique is general and this code is ours.
--
-- Two backends, one interface (B.attach / B.pid / B.module / B.read / B.read_u8):
--   * the default FFI backend (real game process), and
--   * a test backend injected via `attach` (a fake process = a byte buffer),
--     so the walk/decode logic is verifiable headlessly without the game.
--
-- Offsets are NOT here. This is the transport. The pointer chain, the
-- per-build offsets, and the interpretation live in the reader that sits on
-- top of B.read -- and those must be derived against the running build
-- (the game is not running in this environment; that step needs you in-game).
--
-- Lua 5.1 / LuaJIT (no bitwise operators; 64-bit math via mul_low32, as in
-- every HD2 Lua addon).

local ok_ffi, ffi = pcall(require, 'ffi')
local ok_bit, bit = pcall(require, 'bit')
if not ok_ffi or not ok_bit then
  return { available = false, reason = 'ffi_or_bit_missing' }
end

local floor = math.floor
local b2, b4 = bit.bor, bit.band
local band, bor, lshift = bit.band, bit.bor, bit.lshift
local shr = bit.rshift

-- 64-bit product, low 32 bits. (Standard HD2 addon idiom for pointer math.)
local function mul_low32(a, b)
  a = a % 0x100000000; b = b % 0x100000000
  local hi = floor((a % 0x10000) * b / 0x10000)
  return (a * b + hi * 0x10000) % 0x100000000
end

local S = {
  available = true,
  process = nil,
  pid = nil,
  module = nil,
  attached = false,
}

local buffer = ffi.new('uint8_t[?]', 4096)
local got = ffi.new('size_t[1]')

local kernel = nil
local function K()
  if not kernel then kernel = ffi.load('kernel32') end
  return kernel
end

local function decls()
  local k = K()
  local list = {
    'void *OpenProcess(unsigned long access, int inherit, unsigned long pid);',
    'int CloseHandle(void *handle);',
    'int ReadProcessMemory(void *process, const void *address, void *buffer, size_t size, size_t *read);',
    'int GetModuleFileNameExA(void *process, void *module, char *buffer, unsigned long size);',
    'unsigned long EnumProcesses(void *list, unsigned long size, unsigned long *needed);',
    'unsigned long GetLastError(void);',
  }
  for _, d in ipairs(list) do
    local ok, err = pcall(ffi.cdef, d)
    if not ok then return false, err end
  end
  return true
end

-- Default FFI backend.
local B = {}

function B.attach(pid, module)
  local ok, err = decls()
  if not ok then return false, 'cdef: ' .. tostring(err) end
  local k = K()
  local access = b2(0x0400, 0x0010)          -- PROCESS_QUERY_INFORMATION | PROCESS_VM_READ
  local h = k.OpenProcess(access, 0, pid)
  if h == nil or tonumber(ffi.cast('uintptr_t', h)) == 0 then
    local ge = k.GetLastError and tonumber(k.GetLastError()) or -1
    return false, ('OpenProcess failed (pid %s, access 0x410, win32 error %s)')
      :format(tostring(pid), tostring(ge))
  end
  S.process = h
  S.pid = pid
  S.module = module
  S.attached = true
  return true
end

function B.module_path()
  if not S.attached then return nil end
  local k = K()
  local buf = ffi.new('char[?]', 8192)
  local n = k.GetModuleFileNameExA(S.process, nil, buf, 8192)
  if n and n > 0 then return ffi.string(buf, n) end
  return nil
end

-- Read `size` bytes at `address`. Returns a byte string, or nil on failure.
function B.read(address, size)
  if type(address) ~= 'number' or type(size) ~= 'number' then return nil end
  if size < 1 or size > 4096 then return nil end
  if address < 0x10000 or address + size > 0x7FFFFFFFFFFF then return nil end
  if not S.attached or S.process == nil then return nil end
  local k = K()
  got[0] = 0
  local ok = k.ReadProcessMemory(S.process, ffi.cast('const void *', address), buffer, size, got) == 1
  if not ok or got[0] ~= size then return nil end
  return ffi.string(buffer, size)
end

-- Read a single byte. Returns a number 0..255, or nil.
function B.read_u8(address)
  local s = B.read(address, 1)
  if not s then return nil end
  return s:byte(1)
end

-- Read a 32-bit little-endian value (u32). Returns a number, or nil.
function B.read_u32(address)
  local s = B.read(address, 4)
  if not s then return nil end
  return s:byte(1) + s:byte(2) * 256 + s:byte(3) * 65536 + s:byte(4) * 0x1000000 % 0x100000000
end

-- Read a 64-bit little-endian pointer, as a number (low 48 bits; the game's
-- pointer range fits). Returns a number, or nil.
function B.read_ptr(address)
  local s = B.read(address, 8)
  if not s then return nil end
  local lo = s:byte(1) + s:byte(2) * 256 + s:byte(3) * 65536 + (s:byte(4) * 0x1000000) % 0x100000000
  local hi = s:byte(5) + s:byte(6) * 256 + s:byte(7) * 65536 + (s:byte(8) * 0x1000000) % 0x100000000
  -- Combine two 32-bit halves into a <2^48 value. lo + hi*2^32 stays < 2^53,
  -- so it is exactly representable in a Lua double. (No bitwise operators.)
  return (lo + hi * 0x100000000) % 0x10000000000000000
end

-- Walk a pointer chain: a flat list of addresses; each entry is the address
-- of the pointer to the NEXT node. read_ptr is followed at every entry, so the
-- list ends on the node that POINTS AT the target data (e.g. magazine/rounds),
-- and the result is that node's address -- read the value from it separately.
-- Returns the final address, or nil at the first hop that fails.
function B.walk(chain)
  local a
  for i = 1, #chain do
    a = B.read_ptr(chain[i])
    if a == nil then return nil end
  end
  return a
end

-- Find our own PID via EnumProcesses + module match. Best-effort; the host
-- (in-game addon) usually already knows the PID. Returns pid, module, err.
function B.find_game()
  local k = K()
  local n = ffi.new('unsigned long[1]')
  local list = ffi.new('unsigned long[?]', 4096)
  local need = k.EnumProcesses(list, 4096 * 8, n)
  if need == 0 then return nil, nil, 'EnumProcesses failed' end
  local want = 'helldivers2.exe'
  for i = 0, n[0] / 4 - 1 do
    local pid = tonumber(list[i])
    if pid and pid > 4 then
      local access = b2(0x0010, 0x0008)
      local h = k.OpenProcess(access, 0, pid)
      if h ~= nil and tonumber(ffi.cast('uintptr_t', h)) ~= 0 then
        local buf = ffi.new('char[?]', 8192)
        if k.GetModuleFileNameExA(h, nil, buf, 8192) and ffi.string(buf, 260):lower():find('helldivers2%.[eE]?[xX]?[eE]?$', 1, true) then
          k.CloseHandle(h)
          return pid, ffi.string(buf, 8192)
        end
        k.CloseHandle(h)
      end
    end
  end
  return nil, nil, 'helldivers2 process not found'
end

-- Test-injection seam. The API closures captured the `B` table by reference,
-- so we must swap its FIELDS in place (reassigning B would not affect them).
-- fake must expose read / read_u8 / read_u32 / read_ptr / walk. Pass nil to
-- restore the FFI backend.
local ffi_backend = {
  read = B.read, read_u8 = B.read_u8, read_u32 = B.read_u32,
  read_ptr = B.read_ptr, walk = B.walk, attach = B.attach,
}
local function set_backend(fake)
  if fake then
    for k, v in pairs(fake) do B[k] = v end
  else
    for k, v in pairs(ffi_backend) do B[k] = v end
  end
end

local api = {
  available = true,
  attach = function(pid, module)
    -- Record identity in our own state (independent of the backend), then
    -- delegate to the backend's attach (FFI: OpenProcess; test: trivial).
    S.pid = pid
    S.module = module
    S.attached = true
    if B.attach then local ok, err = B.attach(pid, module); if not ok then return false, err end end
    return true
  end,
  pid = function() return S.pid end,
  module = function() return S.module or (S.module_path and S.module_path()) end,
  read = function(a, s) return B.read(a, s) end,
  read_u8 = function(a) return B.read_u8(a) end,
  read_u32 = function(a) return B.read_u32(a) end,
  read_ptr = function(a) return B.read_ptr(a) end,
  walk = function(chain) return B.walk(chain) end,
  find_game = function() return B.find_game() end,
  set_backend = set_backend,
  backend = function() return B end,
  state = function() return S end,
  mul_low32 = mul_low32,
}

return api

end
__hd2ui_modules['hd2ui.live_scan'] = function()
-- hd2ui/live_scan.lua -- Memory-region enumeration + value scanner for the
-- live offset-derivation pass. Display-only: reads committed regions of the
-- game process via ReadProcessMemory, never writes.
--
-- Sits ON TOP of memreader: it reuses memreader's attached process handle (or
-- its injected backend) for reads, and adds VirtualQueryEx region enumeration
-- + byte-sequence value scanning (the classic "watch a value" technique).
-- Offsets live in the reader, not here.
--
-- Lua 5.1 / LuaJIT.

-- Transport (memreader module). Resolved lazily so the in-game assembled
-- chunk (which has no filesystem require) can inject it via set_transport().
local MR
local function resolve_fs()
  if MR then return true end
  local ok, m = pcall(require, 'hd2ui.memreader')
  if ok and m and m.available then MR = m return true end
  return false
end
resolve_fs()

local ok_ffi, ffi = pcall(require, 'ffi')
local ok_bit, bit = pcall(require, 'bit')
if not ok_ffi or not ok_bit then
  return { available = false, reason = 'ffi_or_bit_missing' }
end
local b2, band = bit.bor, bit.band

-- Region info (VirtualQueryEx). MEMORY_COMMIT = 0x1000, MEM_IMAGE = 0x1000000,
-- MEM_PRIVATE = 0x20000.
local MEM_COMMIT, MEM_IMAGE, MEM_PRIVATE = 0x1000, 0x1000000, 0x20000

local S = {
  available = true,
  attached = false,
  regions = {},
  scan_max = 256, -- cap on returned hit addresses per scan
  chunk = nil,    -- optional scan-window cap (bytes); nil = the 1 MiB default
}

-- Default scan window. 1 MiB keeps a single ReadProcessMemory call bounded
-- while making the (plen-1) overlap advance cheap (a 64 MiB game section =
-- 64 windows, not 4096).
local DEFAULT_WINDOW = 0x100000

local k32 = nil
local function K()
  if not k32 then k32 = ffi.load('kernel32') end
  return k32
end

local function decls()
  local k = K()
  local list = {
    'size_t VirtualQueryEx(void *process, const void *address, void *buffer, size_t size);',
    'void *CreateToolhelp32Snapshot(unsigned long flags, unsigned long pid);',
    'int Module32FirstW(void *h, void *pe);',
    'int Module32NextW(void *h, void *pe);',
    'typedef struct { unsigned int dwSize; unsigned int th32ModuleID; unsigned int th32ProcessID; unsigned int GlblcntUsage; unsigned int ProccntUsage; void *modBaseAddr; unsigned int modSize; void *hModule; char szModule[512]; char szExePath[520]; } MODULEENTRY32;',
    'int Process32FirstW(void *h, void *pe);',
    'int Process32NextW(void *h, void *pe);',
    'typedef struct { unsigned int dwSize; unsigned int cntUsage; unsigned int th32ProcessID; unsigned long long th32DefaultHeapID; unsigned int th32ModuleID; unsigned int cntThreads; unsigned int th32ParentProcessID; int pcPriClassBase; unsigned int dwFlags; char szExeFile[520]; } PROCESSENTRY32;',
    'int CloseHandle(void *handle);',
  }
  for _, d in ipairs(list) do
    local ok, err = pcall(ffi.cdef, d)
    if not ok then return false, err end
  end
  return true
end

local region_buf = ffi.new([[
  struct {
    uint8_t *BaseAddress;
    uint64_t AllocationBase;
    uint32_t AllocationProtect;
    uint64_t RegionSize;
    uint32_t State;
    uint32_t Protect;
    uint32_t Type;
  }[1]
]])

-- Enumerate all committed regions of the attached process.
function S.enum_regions()
  if not MR then return false, 'no transport (call set_transport first)' end
  local ok, err = decls()
  if not ok then return false, 'cdef: ' .. tostring(err) end
  local k = K()
  local h = MR.state().process
  if h == nil then return false, 'not attached (run live_pass step 1 first)' end
  local regions = {}
  local addr = ffi.cast('const void *', 0)
  while true do
    local n = k.VirtualQueryEx(h, addr, region_buf, ffi.sizeof(region_buf))
    if not n or n == 0 then break end
    local base = tonumber(ffi.cast('uintptr_t', region_buf[0].BaseAddress))
    local size = tonumber(region_buf[0].RegionSize)
    local state = tonumber(region_buf[0].State)
    local rtype = tonumber(region_buf[0].Type)
    if size and size > 0 and band(state, MEM_COMMIT) == MEM_COMMIT then
      table.insert(regions, { base = base, size = size, image = band(rtype, MEM_IMAGE) == MEM_IMAGE, private = band(rtype, MEM_PRIVATE) == MEM_PRIVATE })
    end
    local nextb = base + size
    if nextb <= base then break end -- overflow guard
    addr = ffi.cast('const void *', nextb)
  end
  S.regions = regions
  S.attached = true
  return true, #regions
end

function S.regions_count() return #S.regions end
function S.region(i) return S.regions[i] end

-- Remote module base: a Toolhelp32 snapshot of the target process's module
-- list. Returns (base, size) of `name` (case-insensitive match on the module
-- name or its tail) within pid `pid`, or nil, err. This is how we find
-- game.dll's IMAGE base in the GAME process (GetModuleHandleA only works
-- within our own process).
-- UTF-16LE ASCII field -> Lua string (drops interleaved NULs; names are ASCII).
-- maxlen = the field's declared byte size (do not over-read the next field).
local function wstr(arr, maxlen)
  return ((ffi.string(arr, maxlen)):gsub('%z', ''))
end

local TH32CS_SNAPMODULE = 0x00000008
function S.module_base(pid, name)
  local ok, err = decls()
  if not ok then return nil, 'cdef: ' .. tostring(err) end
  local k = K()
  local h = k.CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, pid)
  if h == nil or tonumber(ffi.cast('intptr_t', h)) == -1 then -- INVALID_HANDLE_VALUE
    return nil, 'CreateToolhelp32Snapshot failed for pid ' .. tostring(pid)
  end
  local pe = ffi.new('MODULEENTRY32')
  pe.dwSize = ffi.sizeof('MODULEENTRY32')
  local found_base, found_size, found_name
  -- NOTE: cdata 'int' 0 is TRUTHY in Lua; BOOL returns must be compared ~= 0.
  if k.Module32FirstW(h, pe) ~= 0 then
    while true do
      local n = wstr(pe.szModule, 512):lower()
      if n == name:lower() or n:match(name:lower() .. '$') or n:match('[/\\]' .. name:lower() .. '$') then
        found_base = tonumber(ffi.cast('uintptr_t', pe.modBaseAddr))
        found_size = tonumber(pe.modSize)
        found_name = wstr(pe.szModule, 512)
        break
      end
      pe.dwSize = ffi.sizeof('MODULEENTRY32')
      if k.Module32NextW(h, pe) == 0 then break end
    end
  end
  k.CloseHandle(h)
  if found_base then return found_base, found_size, found_name end
  return nil, ('module %s not found in pid %s'):format(name, tostring(pid))
end

-- Read as many bytes as possible starting at `addr` (up to `n`), stopping
-- cleanly at the first unreadable page. MR.read caps at one page (4096), so
-- the scan proceeds page-wise; halving recovers partial reads at a hole.
-- Returns a byte string (possibly shorter than n), or nil if addr is unreadable.
local PAGE = 4096
local S_stats = { pages_ok = 0, pages_bad = 0 }
local function read_safe(addr, n, stats)
  if n <= 0 then return '' end
  local out = {}
  local off = 0
  while off < n do
    local want = math.min(PAGE, n - off)
    local s = MR.read(addr + off, want)
    if s == nil then
      if stats then stats.pages_bad = stats.pages_bad + 1 end
      S_stats.pages_bad = S_stats.pages_bad + 1
      while want > 1 do
        want = math.floor(want / 2)
        s = MR.read(addr + off, want)
        if s then break end
      end
      if not s then break end
    else
      if stats then stats.pages_ok = stats.pages_ok + 1 end
      S_stats.pages_ok = S_stats.pages_ok + 1
    end
    out[#out + 1] = s
    off = off + #s
  end
  if #out == 0 then return nil end
  return table.concat(out)
end

local function to_bytes_u32(v)
  v = v % 0x100000000
  return string.char(v % 256, math.floor(v/256) % 256, math.floor(v/65536) % 256, math.floor(v/0x1000000) % 256)
end
local function to_bytes_u64(v)
  local s = ''
  for i = 0, 7 do s = s .. string.char(v % 256); v = math.floor(v/256) end
  return s
end

-- Scan committed regions for a byte pattern. Returns { addresses = {...}, total = N }.
-- `only_image` restricts to MEM_IMAGE (the exe/dll sections); `min_base`/`max_base`
-- restrict by address range.
function S.scan_bytes(pattern, only_image)
  local pat = assert(pattern, 'pattern')
  local plen = #pattern
  local addrs = {}
  local total = 0
  local stats = { bytes = 0, pages_ok = 0, pages_bad = 0, regions = 0 }
  local regions = S.regions
  if #regions == 0 then return nil, 'no regions (call enum_regions first)' end
  S_stats.pages_ok, S_stats.pages_bad = 0, 0
  for i = 1, #regions do
    local r = regions[i]
    local base, size = r.base, r.size
    if S.progress and (i % 4 == 0) then S.progress(i, #regions) end
    -- Skip a region only when the caller wants image pages and this one isn't.
    if (not only_image) or r.image then
      stats.regions = stats.regions + 1
      -- Scan in windows (S.chunk override, else the 1 MiB default) with a
      -- (plen-1) overlap so a match on a window seam is found exactly once.
      local wcap = S.chunk or DEFAULT_WINDOW
      local pos = 0
      while pos < size do
        local n = math.min(wcap, size - pos)
        local data = read_safe(base + pos, n, stats)
        if data then
          stats.bytes = stats.bytes + #data
          local from = 1
          while true do
            local s = data:find(pattern, from, true)
            if not s then break end
            total = total + 1
            if #addrs < S.scan_max then table.insert(addrs, base + pos + (s - 1)) end
            from = s + 1
          end
        end
        if n >= plen then
          -- Full window: overlap by (plen-1) so a match on the seam is found
          -- exactly once.
          pos = pos + (n - (plen - 1))
        else
          -- Tail window shorter than the pattern: no full match fits here,
          -- just advance one byte to make progress.
          pos = pos + 1
        end
      end
    end
  end
  stats.regions_scanned = stats.regions
  S.last_stats = stats
  return { addresses = addrs, total = total, stats = stats }
end

-- Scan for a 32-bit value (little-endian), unaligned.
function S.scan_u32(v, only_image)
  return S.scan_bytes(to_bytes_u32(v % 0x100000000), only_image)
end

-- Scan for a 64-bit value (little-endian), unaligned.
function S.scan_u64(v, only_image)
  return S.scan_bytes(to_bytes_u64(v % 0x10000000000000000), only_image)
end

-- f32 (IEEE-754 single) little-endian byte pattern for a number.
local function f32_bits_le(v)
  local sign = 0
  if v < 0 then sign = 0x80000000; v = -v end
  if v ~= v then return string.char(0, 0, 0xC0, 0x7F) end
  if v == 0 then return string.char(sign % 256, math.floor(sign/256) % 256, math.floor(sign/65536) % 256, math.floor(sign/0x1000000) % 256) end
  local e, m = 0, v
  if v >= 2 then
    while m >= 2 do m = m / 2; e = e + 1 end
  elseif v < 1 then
    while m < 1 do m = m * 2; e = e - 1 end
  end
  local exp = e + 127
  if exp <= 0 then return string.char(0,0,0,0) end -- denormals: not needed here
  if exp >= 255 then return string.char(0, 0, 0x80, 0x7F) end -- +inf
  local mant = math.floor((m - 1) * 0x800000 + 0.5)
  local bits = sign + math.floor(exp * 0x800000) + mant
  return string.char(bits % 256, math.floor(bits/256) % 256, math.floor(bits/65536) % 256, math.floor(bits/0x1000000) % 256)
end
function S.scan_f32(v, only_image)
  return S.scan_bytes(f32_bits_le(v), only_image)
end

-- Find a process by exe name (case-insensitive) via Toolhelp32 snapshot.
-- Returns pid, name or nil, err. (kernel32 only — EnumProcesses lives in
-- psapi, which the memreader cdefs don't declare.)
local TH32CS_SNAPPROCESS = 0x00000002
function S.find_process(name)
  local ok, err = decls()
  if not ok then return nil, 'cdef: ' .. tostring(err) end
  local k = K()
  local h = k.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
  if h == nil or tonumber(ffi.cast('intptr_t', h)) == -1 then
    return nil, 'CreateToolhelp32Snapshot(process) failed'
  end
  local pe = ffi.new('PROCESSENTRY32')
  pe.dwSize = ffi.sizeof('PROCESSENTRY32')
  local want = name:lower()
  if k.Process32FirstW(h, pe) ~= 0 then
    while true do
      local n = wstr(pe.szExeFile, 520):lower()
      if n == want or n:sub(-#want) == want then
        local pid = tonumber(pe.th32ProcessID)
        k.CloseHandle(h)
        return pid, wstr(pe.szExeFile, 520)
      end
      pe.dwSize = ffi.sizeof('PROCESSENTRY32')
      if k.Process32NextW(h, pe) == 0 then break end
    end
  end
  k.CloseHandle(h)
  return nil, ('process %s not found'):format(name)
end

local api = {
  available = true,
  -- In-game injection point: pass the memreader module table (from the
  -- assembled chunk registry) before calling any scan function.
  set_transport = function(t)
    assert(type(t) == 'table' and t.read and t.state,
      'live_scan: transport must expose read() and state()')
    MR = t
  end,
  state = function() return S end,
  enum_regions = function() return S.enum_regions() end,
  module_base = function(pid, name) return S.module_base(pid, name) end,
  find_process = function(name) return S.find_process(name) end,
  regions_count = function() return S.regions_count() end,
  region = function(i) return S.region(i) end,
  scan_bytes = function(p, oi) return S.scan_bytes(p, oi) end,
  scan_u32 = function(v, oi) return S.scan_u32(v, oi) end,
  scan_u64 = function(v, oi) return S.scan_u64(v, oi) end,
  scan_f32 = function(v, oi) return S.scan_f32(v, oi) end,
  f32_bytes = f32_bits_le,
}
return api

end
__hd2ui_modules['hd2ui.ammo_reader'] = function()
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
-- this with the chunk-registry module (`__hd2ui___hd2ui_require('hd2ui.memreader')`);
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

end
__hd2ui_modules['hd2ui.ammo_cache'] = function()
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

end
__hd2ui_modules['hd2ui.ammo_styles'] = function()
-- hd2ui/ammo_styles.lua -- Ammo HUD style implementations for the DBF Ammo
-- addon. CONSUMES the HD2UI framework (passed in as `api` = the table from
-- __hd2ui_require('mods/dbf/hd2ui')); nothing here edits the framework.
--
-- Model contract (same as demo_counter): { count, label, capacity }.
-- A style returns an object:
--   frame(model, backend, vp_w, vp_h)  -- build display list + emit
--   style                              -- name
--   provisional                        -- true when the intended 3D binding
--                                        -- fell back to a screen anchor
--
-- 'world' (The Division style: text floating beside the gun) needs a
-- world->screen projector: a function (x, y, z) -> sx, sy or nil. The game's
-- camera matrix lives in memory we can read, so a projector is implementable
-- (derive the view matrix chain + use the weapon transform), but until it is
-- wired in the style falls back to the gunside screen anchor and flags itself
-- provisional instead of failing. Pass api-style opts.projector when available.
--
-- Lua 5.1.

local M = {}

local function base_setup(api)
  return api.scene, api.layout, api.colors, api.geometry
end

------------------------------------------------------------------------------
-- crosshair: the framework demo counter right of the reticle (verified path)
------------------------------------------------------------------------------
local function style_crosshair(api, cfg)
  local counter = api.demo_counter.new({
    side = cfg.side or 'right',
    offset_x = cfg.offset_x or 140,
    offset_y = cfg.offset_y or 0,
    scale = cfg.scale or 1.0,
    opacity = cfg.opacity or 0.9,
    color = cfg.color or '#f2f2f2',
  })
  return {
    style = 'crosshair',
    frame = function(model, backend, w, h) counter.frame(model, backend, w, h) end,
  }
end

------------------------------------------------------------------------------
-- gunside: bigger readout low-right, where the first-person weapon sits.
-- (First-person weapon render is camera-locked, so a fixed anchor here reads
-- as "next to the gun"; the world style refines this with real projection.)
------------------------------------------------------------------------------
local function style_gunside(api, cfg)
  local scene, layout, colors = base_setup(api)
  local sc = scene.new()
  local col = (type(cfg.color) == 'string') and colors.from_hex(cfg.color) or (cfg.color or colors.from_hex('#f2f2f2'))
  local size_mult = (cfg.scale or 1.0)
  -- Reference anchor (1080p): right-of-center, below the midline.
  local ref_x, ref_y = cfg.ref_x or 1285, cfg.ref_y or 705

  local function build(model)
    sc:clear()
    -- soft backing plate + the two numbers
    sc:add('rect', { x = -46, y = -34, w = 92, h = 46 }, colors.alpha(col, 0.16))
    sc:add('text', { str = model.label, x = 0, y = -6, size = 26 * size_mult, align = 'center' },
           colors.alpha(col, 0.95))
    sc:add('text', { str = 'mag / reserve', x = 0, y = -26, size = 10 * size_mult, align = 'center' },
           colors.alpha(col, 0.55))
  end

  return {
    style = 'gunside',
    frame = function(model, backend, w, h)
      build(model)
      local s = layout.scale_factor(h, 1.0)
      local ox, oy = layout.place(w, h, ref_x, ref_y, s)
      local dl = {}
      sc:render(dl, ox, oy, s)
      backend.emit(dl, cfg.opacity or 0.9)
    end,
  }
end

------------------------------------------------------------------------------
-- world: text bound to a 3D point beside the weapon, projected to screen each
-- frame. opts.projector(x,y,z) -> sx, sy (screen px) or nil when unavailable.
-- No projector (yet): falls back to gunside geometry, provisional = true.
------------------------------------------------------------------------------
local function style_world(api, cfg)
  local scene, layout, colors = base_setup(api)
  local sc = scene.new()
  local col = (type(cfg.color) == 'string') and colors.from_hex(cfg.color) or (cfg.color or colors.from_hex('#f2f2f2'))
  local projector = cfg.projector   -- wired by the entry when the camera chain resolves
  local size_mult = (cfg.scale or 1.0)
  -- Anchor point in WEAPON-LOCAL space (meters right/up/forward of the ammo
  -- component's entity origin). Only meaningful once projection exists.
  local wx, wy, wz = cfg.world_x or 0.18, cfg.world_y or -0.06, cfg.world_z or 0.32
  local fallback = style_gunside(api, cfg)
  local last_projected = false

  local function build(model)
    sc:clear()
    sc:add('text', { str = model.label, x = 0, y = 0, size = 24 * size_mult, align = 'center' },
           colors.alpha(col, 0.95))
    sc:add('text', { str = 'mag / reserve', x = 0, y = -20, size = 9 * size_mult, align = 'center' },
           colors.alpha(col, 0.5))
  end

  local obj = {
    style = 'world',
    provisional = true,
    frame = function(model, backend, w, h)
      local sx, sy = nil, nil
      if projector then
        local ok, rx, ry = pcall(projector, wx, wy, wz)
        if ok and rx then sx, sy = rx, ry end
      end
      if not sx then
        if obj.provisional and not last_projected then fallback.frame(model, backend, w, h) end
        obj.provisional = true
        return
      end
      -- Real projection: build the scene at the projected point.
      obj.provisional = false
      last_projected = true
      build(model)
      local s = layout.scale_factor(h, 1.0)
      local dl = {}
      sc:render(dl, sx, sy, s)
      backend.emit(dl, cfg.opacity or 0.9)
    end,
  }
  return obj
end

M.styles = { crosshair = style_crosshair, gunside = style_gunside, world = style_world }

function M.new(name, api, cfg)
  local f = M.styles[name] or M.styles.crosshair
  return f(api, cfg or {})
end

return M

end
do
-- hd2ui/ammo_entry_stub.lua -- R5 ISOLATION STUB: proves whether the ammo
-- addon's PRESENCE (archives/resources/manifest) crashes boot, separate from
-- anything its real code does. Does: logging + framework require + no-op
-- update hook. Does NOT: touch ffi, memory, rendering, presets, options.
local sr = rawget(_G, 'stingray')
if type(sr) ~= 'table' then return { installed = false, reason = 'no stingray' } end
if rawget(_G, '__DBF_AMMO_INSTALLED') then return { installed = true } end

local log_path
do
  local ok, d = pcall(os.getenv, 'DBF_AMMO_DIR')
  if (not ok or type(d) ~= 'string' or d == '') then
    local ok2, appdata = pcall(os.getenv, 'APPDATA')
    if ok2 and type(appdata) == 'string' and appdata ~= '' then d = appdata .. '/Arrowhead/Helldivers2' end
  end
  if type(d) == 'string' and d ~= '' then log_path = d .. '/hd2ui_ammo.log' end
end
local function log(msg)
  if not log_path then return end
  local ok, f = pcall(io.open, log_path, 'a')
  if not ok or not f then return end
  local t = os.date and os.date('%H:%M:%S') or '?'
  pcall(f.write, f, string.format('[%s] %s\n', t, tostring(msg)))
  pcall(f.close, f)
end
log('dbf-ammo r5 STUB start')

local HD2 = rawget(_G, '__DBF_HD2UI')
if type(HD2) ~= 'table' then
  local ok, v = pcall(function() return __hd2ui_require('mods/dbf/hd2ui') end)
  if ok and type(v) == 'table' then HD2 = v end
end
log('dbf-ammo r5 STUB framework=' .. tostring(type(HD2) == 'table' and HD2.version or 'missing'))

local old_update = rawget(_G, 'update')
if type(old_update) ~= 'function' then
  log('dbf-ammo r5 STUB no global update(); not installing')
  return { installed = false, reason = 'no update' }
end
rawset(_G, '__DBF_AMMO_INSTALLED', true)
rawset(_G, 'update', function(...) return old_update(...) end)
log('dbf-ammo r5 STUB installed')
return { installed = true, version = 'r5-stub' }

end
