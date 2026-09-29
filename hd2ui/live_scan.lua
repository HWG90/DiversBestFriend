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
    -- Alias-bound exports: LuaJIT keeps the FIRST cdef of a name and BSL shares
    -- one state across all mods, so a plain name could silently execute against
    -- another mod's incompatible signature (crash). Private names bound to the
    -- real exports via __asm__ cannot be hijacked. Structs are DBF_-renamed for
    -- the same reason. (Technique as used by shipping ammo mods; own code.)
    'size_t dbf_VirtualQueryEx(void *process, const void *address, void *buffer, size_t size) __asm__("VirtualQueryEx");',
    'void *dbf_CreateToolhelp32Snapshot(unsigned long flags, unsigned long pid) __asm__("CreateToolhelp32Snapshot");',
    'int dbf_Module32FirstW(void *h, void *pe) __asm__("Module32FirstW");',
    'int dbf_Module32NextW(void *h, void *pe) __asm__("Module32NextW");',
    'void *dbf_GetModuleHandleA(const char *name) __asm__("GetModuleHandleA");',
    'typedef struct { unsigned int dwSize; unsigned int th32ModuleID; unsigned int th32ProcessID; unsigned int GlblcntUsage; unsigned int ProccntUsage; void *modBaseAddr; unsigned int modSize; void *hModule; char szModule[512]; char szExePath[520]; } DBF_MODULEENTRY32;',
    'int dbf_Process32FirstW(void *h, void *pe) __asm__("Process32FirstW");',
    'int dbf_Process32NextW(void *h, void *pe) __asm__("Process32NextW");',
    'typedef struct { unsigned int dwSize; unsigned int cntUsage; unsigned int th32ProcessID; unsigned long long th32DefaultHeapID; unsigned int th32ModuleID; unsigned int cntThreads; unsigned int th32ParentProcessID; int pcPriClassBase; unsigned int dwFlags; char szExeFile[520]; } DBF_PROCESSENTRY32;',
    'int dbf_CloseHandle(void *handle) __asm__("CloseHandle");',
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
  local st = MR.state()
  local h = st.process
  if h == nil and st.mode == 'selfrpm' then
    -- self-read mode: VirtualQueryEx accepts the current-process pseudo handle
    h = ffi.cast('void *', ffi.cast('intptr_t', -1))
  end
  if h == nil then return false, 'not attached (run live_pass step 1 first)' end
  local regions = {}
  local addr = ffi.cast('const void *', 0)
  while true do
    local n = k.dbf_VirtualQueryEx(h, addr, region_buf, ffi.sizeof(region_buf))
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
  -- own process: GetModuleHandleA, no Toolhelp snapshot needed
  if MR and MR.self_pid and pid == MR.self_pid() then
    local h2 = k.dbf_GetModuleHandleA(name)
    if h2 ~= nil then return tonumber(ffi.cast('uintptr_t', h2)), nil, name end
    return nil, ('module %s not loaded in self'):format(name)
  end
  local h = k.dbf_CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, pid)
  if h == nil or tonumber(ffi.cast('intptr_t', h)) == -1 then -- INVALID_HANDLE_VALUE
    return nil, 'CreateToolhelp32Snapshot failed for pid ' .. tostring(pid)
  end
  local pe = ffi.new('DBF_MODULEENTRY32')
  pe.dwSize = ffi.sizeof('DBF_MODULEENTRY32')
  local found_base, found_size, found_name
  -- NOTE: cdata 'int' 0 is TRUTHY in Lua; BOOL returns must be compared ~= 0.
  if k.dbf_Module32FirstW(h, pe) ~= 0 then
    while true do
      local n = wstr(pe.szModule, 512):lower()
      if n == name:lower() or n:match(name:lower() .. '$') or n:match('[/\\]' .. name:lower() .. '$') then
        found_base = tonumber(ffi.cast('uintptr_t', pe.modBaseAddr))
        found_size = tonumber(pe.modSize)
        found_name = wstr(pe.szModule, 512)
        break
      end
      pe.dwSize = ffi.sizeof('DBF_MODULEENTRY32')
      if k.dbf_Module32NextW(h, pe) == 0 then break end
    end
  end
  k.dbf_CloseHandle(h)
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
  local h = k.dbf_CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
  if h == nil or tonumber(ffi.cast('intptr_t', h)) == -1 then
    return nil, 'CreateToolhelp32Snapshot(process) failed'
  end
  local pe = ffi.new('DBF_PROCESSENTRY32')
  pe.dwSize = ffi.sizeof('DBF_PROCESSENTRY32')
  local want = name:lower()
  if k.dbf_Process32FirstW(h, pe) ~= 0 then
    while true do
      local n = wstr(pe.szExeFile, 520):lower()
      if n == want or n:sub(-#want) == want then
        local pid = tonumber(pe.th32ProcessID)
        k.dbf_CloseHandle(h)
        return pid, wstr(pe.szExeFile, 520)
      end
      pe.dwSize = ffi.sizeof('DBF_PROCESSENTRY32')
      if k.dbf_Process32NextW(h, pe) == 0 then break end
    end
  end
  k.dbf_CloseHandle(h)
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
