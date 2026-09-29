-- HD2-Addon: mods/dbf/floaty/hud
-- dbf floaty hud r8; assembled by hd2ui/build_station.py; do not edit.
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
-- Display-only by construction: it READS memory. It never writes, never calls
-- a game function, never injects.
--
-- Three backends, one interface (B.attach / B.pid / B.module / B.read / ...):
--   * SELF-RPM backend (selected automatically when attach() gets our own
--     pid): ReadProcessMemory through the GetCurrentProcess PSEUDO HANDLE with
--     alias-bound declarations. Never OpenProcess -- requesting a real VM_READ
--     handle is the anti-cheat tripwire (proven crash source 2026-09-29, five
--     deterministic boot AVs; the same technique shipping ammo mods use on
--     GameGuard builds). A failed self-read returns 0 -> nil, never faults.
--   * the legacy FFI/RPM backend (attach to a foreign pid), and
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

local buffer = ffi.new('uint8_t[?]', 65536)
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

-- Self-read backend (the in-game path) ---------------------------------------
-- Technique taken from how shipping ammo mods survive anti-cheat on this
-- build: read own memory through the GetCurrentProcess() PSEUDO HANDLE --
-- never OpenProcess (requesting a real VM_READ handle is itself the pattern
-- anti-cheat kills; pseudo-handle self-reads look like game code, and a bad
-- address just returns 0, so no fault is possible).
--
-- Every declaration is ALIAS-BOUND (`__asm__("RealExport")`): LuaJIT silently
-- keeps the FIRST cdef of any name, and BSL shares one Lua state across all
-- mods -- a plain-named call could execute against another mod's incompatible
-- layout (crash-at-fixed-address territory). Private names bound to the real
-- exports cannot be hijacked. Own implementation.
local self_ok = nil
local function ensure_self_decls()
  if self_ok ~= nil then return self_ok end
  local list = {
    'void *dbf_GetCurrentProcess(void) __asm__("GetCurrentProcess");',
    'unsigned long dbf_GetCurrentProcessId(void) __asm__("GetCurrentProcessId");',
    'int dbf_ReadProcessMemory(void *process, const void *address, void *buffer, size_t size, size_t *read) __asm__("ReadProcessMemory");',
  }
  for _, d in ipairs(list) do
    if not pcall(ffi.cdef, d) then self_ok = false return false end
  end
  self_ok = true
  return true
end

local own_pid_cache, self_handle = nil, nil
local function own_pid()
  if not ensure_self_decls() then return nil end
  if not own_pid_cache then
    own_pid_cache = tonumber(K().dbf_GetCurrentProcessId())
    self_handle = K().dbf_GetCurrentProcess()
  end
  return own_pid_cache
end

-- Default FFI backend.
local B = {}

function B.attach(pid, module)
  local p = tonumber(pid)
  if p and p == own_pid() then
    -- self-read mode: RPM through the GetCurrentProcess pseudo handle. No
    -- OpenProcess, no handle request: the pattern shipping ammo mods use on
    -- anti-cheat-protected builds. A bad address returns 0 (nil), never faults.
    S.pid, S.module, S.process, S.attached, S.mode = p, module, self_handle, true, 'selfrpm'
    return true
  end
  S.mode = 'rpm'
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

function B.self_pid() return own_pid() end

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
  if size < 1 or size > 65536 then return nil end
  if address < 0x10000 or address + size > 0x7FFFFFFFFFFF then return nil end
  if not S.attached then return nil end
  if S.process == nil then return nil end
  got[0] = 0
  local k = K()
  local ok
  if S.mode == 'selfrpm' then
    -- alias-bound decl: immune to other mods cdefs in the shared LuaJIT state
    ok = k.dbf_ReadProcessMemory(S.process, ffi.cast('const void *', address), buffer, size, got) == 1
  else
    ok = k.ReadProcessMemory(S.process, ffi.cast('const void *', address), buffer, size, got) == 1
  end
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
  self_pid = B.self_pid,
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
  self_pid = function() return B.self_pid and B.self_pid() or nil end,
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
__hd2ui_modules['hd2ui.ammo_chain'] = function()
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
--   local CH = __hd2ui_require('hd2ui.ammo_chain')
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

end
__hd2ui_modules['hd2ui.station_bars'] = function()
-- hd2ui/station_bars.lua -- the Floaty HUD station (concepts/floaty-hud).
-- Pure display: one 150x62 chamfered plate (1080p reference units, local
-- coords, y-down, plate top-left at 0,0) that every weapon class docks into.
-- One grammar (DESIGN.md rule 1): plate, divider, numeral row and tray are
-- IDENTICAL for all classes; only the tray gauge and the unit words change.
--
-- Model contract (produced by station_entry's chain_model):
--   { rounds, mag_cap, spare, spare_max, spare_kind, pack_rounds, pack_total,
--     heat_frac, heat_lock, fuel_frac, charge_pct, charge_only, weapon_id }
-- classify() derives the presentation class; draw() emits scene elements.
--
-- Geometry is integer-disciplined wherever countability matters (the AC tick
-- column): fractional heights/gaps subpixel-snap and merge adjacent elements.
--
-- Lua 5.1 / LuaJIT.

local M = {}
M.W, M.H = 150, 62            -- plate box (reference units)
M.H_AC = 100                  -- AC variant: taller, the magazine cutaway fits
M.DIVIDER_Y = 43              -- primary row / tray boundary
M.NUM_X = 9                   -- numeral cell (fixed width -> nothing reflows)
M.UNIT_X = 67
M.BAR_X, M.BAR_W, M.BAR_Y, M.BAR_H = 8, 134, 48, 7
M.HAZARD_FRAC = 0.75          -- last quarter of the bar is the hazard band
M.CLIP_SLOTS = 10             -- AC backpack: stripper-clip pips (data-driven count)

local INK = { 242, 242, 242, 255 }
local INK_DIM = { 242, 242, 242, 140 }
local INK_FAINT = { 242, 242, 242, 64 }
local PLATE = { 14, 16, 13, 140 }     -- .55 alpha; no backdrop blur in-game
local BORDER = { 242, 242, 242, 41 }  -- .16
local TRAY = { 8, 9, 7, 115 }         -- .45
local AMBER = { 232, 163, 61, 235 }
local RED = { 224, 48, 48, 255 }
local CYAN = { 143, 216, 232, 235 }
local HAZ_Y = { 232, 192, 32, 97 }    -- faint stripe (always visible)
local HAZ_DARK = { 20, 20, 16, 115 }
local PALE = { 217, 212, 200, 235 }   -- heat fill low end

local floor, cos, sin, pi = math.floor, math.cos, math.sin, math.pi
local DEG = pi / 180

------------------------------------------------------------------------------
-- classification: model -> presentation class (pure, unit-tested)
------------------------------------------------------------------------------
function M.classify(m)
  if not m then return 'none' end
  -- an ok chain row always carries at least one numeric story; anything else
  -- is a degenerate sample -> hide (never a ghost "0" station)
  if not (m.rounds or m.count or m.heat_frac or m.fuel_frac or m.charge_pct or m.charge_only) then
    return 'none'
  end
  if m.charge_only then return 'charge' end
  if m.heat_frac then
    if m.spare_kind == 'backpack' then return 'fuel' end   -- burn support: 'heat' field is the fuel level
    return 'laser'
  end
  if m.fuel_frac then return 'fuel' end                    -- resource path (Cremator)
  if m.charge_pct and (m.rounds or m.count) then return 'magcharge' end  -- railgun
  if m.spare_kind == 'backpack' and (m.mag_cap or m.capacity) then
    local cap = m.mag_cap or m.capacity
    if cap >= 5 and cap <= 16 then return 'clips' end      -- autocannon family
    return 'pool'                                          -- round-pool support guns (MG-43)
  end
  if m.spare_kind == 'rounds' then return 'rounds' end
  return 'mags'
end

local function shown_rounds(m)
  return m.rounds or m.count or 0
end
local function mag_cap(m)
  local c = m.mag_cap or m.capacity or 1
  if c < 1 then c = 1 end
  return c
end

------------------------------------------------------------------------------
-- small composites
------------------------------------------------------------------------------
local function outline(sc, x, y, w, h, col)
  sc:add('rect', { x = x, y = y, w = w, h = 1 }, col)
  sc:add('rect', { x = x, y = y + h - 1, w = w, h = 1 }, col)
  sc:add('rect', { x = x, y = y + 1, w = 1, h = h - 2 }, col)
  sc:add('rect', { x = x + w - 1, y = y + 1, w = 1, h = h - 2 }, col)
end

local function heat_fill_color(frac, locked)
  if locked then return RED end
  if frac < 0.5 then
    local t = frac * 2
    return { PALE[1] + (AMBER[1] - PALE[1]) * t, PALE[2] + (AMBER[2] - PALE[2]) * t,
             PALE[3] + (AMBER[3] - PALE[3]) * t, PALE[4] }
  end
  local t = math.min(1, (frac - 0.5) * 2)
  return { AMBER[1] + (RED[1] - AMBER[1]) * t, AMBER[2] + (RED[2] - AMBER[2]) * t,
           AMBER[3] + (RED[3] - AMBER[3]) * t, AMBER[4] }
end

-- hazard band: 45-degree stripes confined to [x0,x1], faint always, lit above
-- the threshold. Integer rows (2px), phase advancing 2px per row.
local function hazard(sc, x0, x1, y0, y1, lit)
  local row, stripe_a = y0, (lit and AMBER or HAZ_Y)
  while row < y1 - 0.01 do
    local rh = math.min(2, y1 - row)
    local phase = (row - y0) % 4
    sc:add('rect', { x = x0, y = row, w = x1 - x0, h = rh }, HAZ_DARK)
    local p = phase
    while p < (x1 - x0) do
      local seg_w = math.min(2, (x1 - x0) - p)
      if seg_w > 0 then sc:add('rect', { x = x0 + p, y = row, w = seg_w, h = rh }, stripe_a) end
      p = p + 4
    end
    row = row + 2
  end
end

local function bar_gauge(sc, frac, fill_col, safe_frac, opts)
  local x, w, y, h = M.BAR_X, M.BAR_W, M.BAR_Y, M.BAR_H
  sc:add('rect', { x = x, y = y, w = w, h = h }, { 242, 242, 242, 26 })   -- 10% track
  frac = math.max(0, math.min(1, frac or 0))
  if safe_frac then
    local safe_w = floor(w * safe_frac + 0.5)
    if frac <= safe_frac then
      sc:add('rect', { x = x, y = y, w = floor(w * frac + 0.5), h = h }, fill_col)
    else
      sc:add('rect', { x = x, y = y, w = safe_w, h = h }, fill_col)
      sc:add('rect', { x = x + safe_w, y = y, w = floor(w * frac + 0.5) - safe_w, h = h },
             (opts and opts.over_col) or AMBER)
    end
    sc:add('rect', { x = x + safe_w, y = y - 1, w = 1, h = h + 2 }, INK_FAINT)  -- safe mark
  else
    sc:add('rect', { x = x, y = y, w = floor(w * frac + 0.5), h = h }, fill_col)
  end
end

-- up-facing arc dial with needle (gas-tank style), centered in the tray
local DIAL_CX, DIAL_CY, DIAL_R = 75, 59, 13
local DIAL_A0, DIAL_SWEEP = 210 * DEG, 120 * DEG
local function dial(sc, frac)
  local a0, sweep = DIAL_A0, DIAL_SWEEP
  sc:add('arc', { cx = DIAL_CX, cy = DIAL_CY, r = DIAL_R, th = 1.4,
                  a0 = a0, a1 = a0 + sweep, step = 0.06 }, { 242, 242, 242, 71 })  -- 28% track
  sc:add('arc', { cx = DIAL_CX, cy = DIAL_CY, r = DIAL_R, th = 1.4,
                  a0 = a0 + sweep * 0.75, a1 = a0 + sweep, step = 0.06 }, { 224, 48, 48, 153 })
  frac = math.max(0, math.min(1, frac or 0))
  local ang = a0 + sweep * frac
  local tx, ty = DIAL_CX + 10 * cos(ang), DIAL_CY + 10 * sin(ang)
  local px, py = -sin(ang) * 0.7, cos(ang) * 0.7
  sc:add('tri', { x1 = DIAL_CX, y1 = DIAL_CY, x2 = tx + px, y2 = ty + py, x3 = tx - px, y3 = ty - py }, INK)
  sc:add('circle', { cx = DIAL_CX, cy = DIAL_CY, r = 1.3, step = 0.12 }, AMBER)
end

------------------------------------------------------------------------------
-- tray gauges + aux elements per class
------------------------------------------------------------------------------
local function legality_ink(legal)
  -- one legality signal: the numeral itself turns amber at <=5 rounds
  return legal and AMBER or INK
end
-- one magazine pip: chamfered bullet (approved mock shape) -- rect body plus
-- a down-pointing tip, 6x10 total
local function pip_body(sc, x, col, y0)
  y0 = y0 or 48
  sc:add('rect', { x = x, y = y0, w = 6, h = 7 }, col)
  sc:add('tri', { x1 = x, y1 = y0 + 7, x2 = x + 6, y2 = y0 + 7, x3 = x + 3, y3 = y0 + 10 }, col)
end

local function pip_row(sc, lit, total, partial, x0, pulse_a, y0)
  y0 = y0 or 48
  total = math.min(total, M.CLIP_SLOTS)
  for i = 1, total do
    local x = x0 + (i - 1) * 12
    if i <= lit then
      pip_body(sc, x, AMBER, y0)
    elseif partial and i == lit + 1 then
      sc:add('rect', { x = x, y = y0 + 5, w = 6, h = 5 }, AMBER)              -- partial clip: half fill
      outline(sc, x, y0, 6, 10, INK_FAINT)
    else
      outline(sc, x, y0, 6, 10, INK_FAINT)                                    -- spent silhouette
    end
  end
  if pulse_a and lit == 1 and total >= 2 then                                  -- last mag: pulse
    local pa = { AMBER[1], AMBER[2], AMBER[3], floor(AMBER[4] * pulse_a) }
    pip_body(sc, x0, pa, y0)
  end
end

local function tray_bar_pool(sc, remain, total)
  local frac = (total and total > 0) and remain / total or 0
  sc:add('rect', { x = M.BAR_X, y = 51, w = M.BAR_W, h = 4 }, { 242, 242, 242, 26 })
  sc:add('rect', { x = M.BAR_X, y = 51, w = floor(M.BAR_W * math.min(1, frac) + 0.5), h = 4 }, INK_DIM)
end

local function laser_bricks(sc, sinks, sinks_max)
  local n = math.min(sinks_max or sinks or 0, 8)
  if n < 1 then return end
  for i = 1, n do
    local x = 142 - 4 - (n - i) * 7
    if i <= (sinks or 0) then
      sc:add('rect', { x = x, y = 29, w = 4, h = 9 }, INK_DIM)
    else
      outline(sc, x, 29, 4, 9, INK_FAINT)
    end
  end
end

-- autocannon magazine: a LOLLIPOP cutaway (user render, 2026-09-29): a
-- straight single-file tube up top feeding a large rotating drum below.
-- Rounds ride the INSIDE of the drum rim around an empty hub; the tube
-- column drains from the top as rounds feed down into the drum. User rules:
-- max 10 (no chamber +1), reload legal at <=5, reloads happen in fives.
local LOL = {
  col_x = 74, col_top = 6, col_slots = 5, col_space = 9, col_r = 4.3,
  drum_cx = 78, drum_cy = 62, drum_r = 30, drum_ring_r = 19, drum_slots = 5,
  drum_r_round = 5.3, hub_r = 9,
}
local TUBE_FILL = { 8, 9, 7, 205 }
M.LOL = LOL   -- exposed for tests (per-round tri mass derives from these)
local HUB_FILL = { 20, 22, 19, 220 }

local function lollipop(sc, rounds)
  rounds = math.max(0, math.min(rounds, 10))
  local drum_n = math.min(rounds, LOL.drum_slots)
  local col_n = rounds - drum_n

  -- drum: dark disc + hairline rim + empty hub with an axle
  sc:add('circle', { cx = LOL.drum_cx, cy = LOL.drum_cy, r = LOL.drum_r, step = 0.08 }, TUBE_FILL)
  sc:add('ring', { cx = LOL.drum_cx, cy = LOL.drum_cy, r0 = LOL.drum_r,
                   r1 = LOL.drum_r + 1, a0 = 0, a1 = 2 * pi, step = 0.08 }, BORDER)
  sc:add('circle', { cx = LOL.drum_cx, cy = LOL.drum_cy, r = LOL.hub_r, step = 0.1 }, HUB_FILL)
  sc:add('ring', { cx = LOL.drum_cx, cy = LOL.drum_cy, r0 = LOL.hub_r,
                   r1 = LOL.hub_r + 1, a0 = 0, a1 = 2 * pi, step = 0.1 }, INK_FAINT)
  sc:add('circle', { cx = LOL.drum_cx, cy = LOL.drum_cy, r = 2.5, step = 0.2 }, INK_FAINT)

  -- drum rounds: pentagon on the inside of the rim; the cylinder indexes
  -- 72 deg per shot so the remaining rounds stay evenly spread
  local off = (LOL.drum_slots - drum_n) * (2 * pi / LOL.drum_slots)
  for i = 0, LOL.drum_slots - 1 do
    local ang = -pi / 2 + off + i * (2 * pi / LOL.drum_slots)
    local x = LOL.drum_cx + LOL.drum_ring_r * cos(ang)
    local y = LOL.drum_cy + LOL.drum_ring_r * sin(ang)
    if i < drum_n then
      sc:add('circle', { cx = x, cy = y, r = LOL.drum_r_round, step = 0.15 }, AMBER)
    else
      sc:add('ring', { cx = x, cy = y, r0 = 4.0, r1 = 5.0, a0 = 0, a1 = 2 * pi, step = 0.2 }, INK_FAINT)
    end
  end

  -- column tube feeding the drum from above (border pass, then dark fill)
  sc:add('rect', { x = LOL.col_x - 6.5, y = LOL.col_top - 1, w = 13,
                   h = LOL.drum_cy - LOL.drum_r + LOL.hub_r - LOL.col_top + 1 }, BORDER)
  sc:add('circle', { cx = LOL.col_x, cy = LOL.col_top, r = 6.5, step = 0.15 }, BORDER)
  sc:add('rect', { x = LOL.col_x - 5.5, y = LOL.col_top, w = 11,
                   h = LOL.drum_cy - LOL.drum_r + LOL.hub_r - LOL.col_top }, TUBE_FILL)
  sc:add('circle', { cx = LOL.col_x, cy = LOL.col_top, r = 5.5, step = 0.15 }, TUBE_FILL)

  -- column rounds: the BOTTOM col_n are lit (they feed the drum first), the
  -- top empties out as the magazine burns down
  for i = 0, LOL.col_slots - 1 do
    local y = LOL.col_top + 4 + (LOL.col_slots - 1 - i) * LOL.col_space
    if i < col_n then
      sc:add('circle', { cx = LOL.col_x, cy = y, r = LOL.col_r, step = 0.15 }, AMBER)
    else
      sc:add('ring', { cx = LOL.col_x, cy = y, r0 = 3.3, r1 = 4.1, a0 = 0, a1 = 2 * pi, step = 0.2 }, INK_FAINT)
    end
  end
end

------------------------------------------------------------------------------
-- the station (rule 1: one grammar). opts: { clock } for the pulse.
------------------------------------------------------------------------------
function M.draw(sc, m, opts)
  opts = opts or {}
  local cls = M.classify(m)
  if cls == 'none' then return cls end

  -- plate: chamfered fill (8px cut, top-right) as three tris + hairline border.
  -- The AC variant is taller: the magazine cutaway lives beside the numeral.
  local W, H, C = M.W, (cls == 'clips') and M.H_AC or M.H, 8
  sc:add('tri', { x1 = 0, y1 = 0, x2 = W - C, y2 = 0, x3 = W, y3 = C }, PLATE)
  sc:add('tri', { x1 = 0, y1 = 0, x2 = W, y2 = C, x3 = W, y3 = H }, PLATE)
  sc:add('tri', { x1 = 0, y1 = 0, x2 = W, y2 = H, x3 = 0, y3 = H }, PLATE)
  sc:add('rect', { x = 0, y = 0, w = W - C, h = 1 }, BORDER)
  sc:add('quad', { ax = W - C, ay = 0, bx = W, by = C, cx = W, cy = C + 1, dx = W - C - 1, dy = 1 }, BORDER)
  sc:add('rect', { x = W - 1, y = C, w = 1, h = H - C }, BORDER)
  sc:add('rect', { x = 0, y = H - 1, w = W, h = 1 }, BORDER)
  sc:add('rect', { x = 0, y = 0, w = 1, h = H }, BORDER)

  -- divider + tray. AC: no divider (the carousel owns the middle) and the
  -- tray drops to the bottom of the taller plate.
  local tray_y = M.DIVIDER_Y + 1
  if cls == 'clips' then
    tray_y = H - 18
  else
    sc:add('rect', { x = 0, y = M.DIVIDER_Y, w = W, h = 1 }, { 242, 242, 242, 31 })
  end
  sc:add('rect', { x = 1, y = tray_y, w = W - 2, h = H - tray_y - 1 }, TRAY)

  local num_x, unit_x = M.NUM_X, M.UNIT_X
  local numeral, unit1, unit2 = '', '', ''
  local legal_ammo = false
  local clip_total
  local pulse = opts.clock and (0.55 + 0.45 * sin(opts.clock * 5)) or nil

  if cls == 'mags' then
    local shown, spare, smax = shown_rounds(m), m.spare, m.spare_max
    numeral, unit1, unit2 = tostring(shown), 'RNDS', 'MAGS'
    if spare ~= nil then
      local total = math.min(smax or spare, M.CLIP_SLOTS)
      pip_row(sc, spare, total, false, M.BAR_X, pulse)
    end
  elseif cls == 'clips' then
    local cap = mag_cap(m)
    local shown, pack_r, pack_t = shown_rounds(m), m.pack_rounds or m.spare or 0,
                                  m.pack_total or 0
    -- user rules: max 10, no chamber +1, reload legal at <=5, reloads in fives
    shown = math.min(shown, cap)
    numeral, unit1, unit2 = tostring(shown), 'RNDS', 'CLPS'
    num_x, unit_x = 9, 9            -- units stack under the numeral; the
    -- carousel owns the middle of the tall plate
    local clip = math.max(1, floor(cap / 2))
    local total = math.min(floor((pack_t + clip - 1) / clip), M.CLIP_SLOTS)
    local lit = floor(pack_r / clip)
    local partial = (pack_r - lit * clip) > 0
    if lit > total then lit = total end
    lollipop(sc, shown)
    legal_ammo = shown <= clip
    clip_total = total
  elseif cls == 'laser' then
    local frac = math.min(1, m.heat_frac or 0)
    numeral = tostring(m.heat_pct or floor(frac * 100 + 0.5))
    unit1, unit2 = 'HEAT', 'PCT'
    laser_bricks(sc, m.spare, m.spare_max)
    bar_gauge(sc, frac, heat_fill_color(frac, m.heat_lock), nil, nil)
    hazard(sc, M.BAR_X + floor(M.BAR_W * M.HAZARD_FRAC), M.BAR_X + M.BAR_W, M.BAR_Y, M.BAR_Y + M.BAR_H, frac >= M.HAZARD_FRAC)
  elseif cls == 'fuel' then
    -- burn support arrives as heat_frac (the chain's 'heat' field IS the fuel
    -- level there); resource weapons (Cremator) arrive as fuel_frac.
    local fuel = m.fuel_frac or m.heat_frac or 0
    numeral = tostring(floor(fuel * 100 + 0.5))
    unit1, unit2 = 'FUEL', 'PCT'
    dial(sc, fuel)
  elseif cls == 'magcharge' then
    -- railgun: the charge IS the story (DESIGN.md) -- charge % in the numeral,
    -- cyan strip with the safe-charge mark in the tray
    numeral = tostring(floor((m.charge_pct or 0) * 100 + 0.5))
    unit1, unit2 = 'CHRG', 'PCT'
    bar_gauge(sc, m.charge_pct, CYAN, 0.8, nil)
  elseif cls == 'charge' then
    numeral = tostring(floor((m.charge_pct or 0) * 100 + 0.5))
    unit1, unit2 = 'CHRG', 'PCT'
    bar_gauge(sc, m.charge_pct, CYAN, 0.8, nil)
  elseif cls == 'rounds' then
    numeral, unit1, unit2 = tostring(shown_rounds(m)), 'RNDS', 'RSV'
    if m.spare ~= nil then
      tray_bar_pool(sc, m.spare, m.spare_max or m.ammo_max or (m.spare * 2))
    end
  elseif cls == 'pool' then
    numeral, unit1, unit2 = tostring(shown_rounds(m)), 'RNDS', 'POOL'
    tray_bar_pool(sc, m.pack_rounds or m.spare or 0, m.pack_total or 0)
  end

  local ink = INK
  if cls == 'laser' and m.heat_lock then ink = RED
  elseif legal_ammo then ink = legality_ink(true) end
  sc:add('text', { str = numeral, x = num_x, y = 34, size = 33, align = 'left' }, ink)
  local uy1, uy2 = 18, 28
  if cls == 'clips' then uy1, uy2 = 42, 52 end
  sc:add('text', { str = unit1, x = unit_x, y = uy1, size = 9, align = 'left' }, INK_DIM)
  sc:add('text', { str = unit2, x = unit_x, y = uy2, size = 9, align = 'left' }, INK_DIM)
  if cls == 'clips' and clip_total then
    -- backpack reserve in stripper clips, e.g. "x10"
    sc:add('text', { str = 'x' .. tostring(clip_total), x = 9, y = 62, size = 9, align = 'left' }, INK_DIM)
  end
  return cls
end

return M

end
__hd2ui_modules['hd2ui.station_holo'] = function()
-- hd2ui/station_holo.lua -- camera math for the Dead Space-style hologram
-- anchor. Pure Lua (no FFI, no game): the entry feeds it the live camera
-- pose each frame; everything here is headless-testable.
--
-- The station's target point is defined in CAMERA-LOCAL space (right/up/
-- forward meters), so it rides the weapon line. It is tracked in WORLD space
-- with an exponential lag, so fast aim sweeps make the hologram trail and
-- settle -- the "floating in space" cue -- plus a slow idle bob. The world
-- point is transformed back into view space and perspective-projected every
-- frame, giving natural parallax and a little scale breathing.
--
-- Conventions: view space is x=right, y=up, z=FORWARD-positive (see
-- M.FORWARD_SIGN); screen space is y-down; projection assumes square pixels.
--
-- Lua 5.1 / LuaJIT.

local M = {}
M.DEFAULT_HFOV = math.rad(90)   -- horizontal fov fallback until the live
                                -- setting is read; parallax strength only
M.FORWARD_SIGN = 1              -- stingray convention check happens live;
                                -- flip to -1 if the hologram projects behind
M.LAG_RATE = 10.0               -- exp smoothing rate (higher = tighter)
M.BOB_AMP = 0.008               -- idle bob, meters along camera up
M.BOB_HZ = 0.7                  -- slow breathing, not a jelly effect

local sin, cos, exp = math.sin, math.cos, math.exp
local V = { x = 1, y = 2, z = 3 }

local function add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
local function scale(a, s) return { a[1] * s, a[2] * s, a[3] * s } end
M.add, M.scale = add, scale

------------------------------------------------------------------------------
-- quaternion: stingray order assumed {x, y, z, w}; normalize defensively
------------------------------------------------------------------------------
local function qnorm(q)
  local n = math.sqrt(q[1] ^ 2 + q[2] ^ 2 + q[3] ^ 2 + q[4] ^ 2)
  if n < 1e-9 then return { 0, 0, 0, 1 } end
  return { q[1] / n, q[2] / n, q[3] / n, q[4] / n }
end

-- rotate vector v by unit quaternion q (x,y,z,w)
function M.rotate(q, v)
  local qx, qy, qz, qw = q[1], q[2], q[3], q[4]
  -- t = 2 * cross(q.xyz, v)
  local tx = 2 * (qy * v[3] - qz * v[2])
  local ty = 2 * (qz * v[1] - qx * v[3])
  local tz = 2 * (qx * v[2] - qy * v[1])
  -- v + qw*t + cross(q.xyz, t)
  return {
    v[1] + qw * tx + (qy * tz - qz * ty),
    v[2] + qw * ty + (qz * tx - qx * tz),
    v[3] + qw * tz + (qx * ty - qy * tx),
  }
end

-- camera basis vectors from the orientation quaternion
function M.basis(q)
  q = qnorm(q)
  local r = M.rotate(q, { 1, 0, 0 })
  local u = M.rotate(q, { 0, 1, 0 })
  local f = M.rotate(q, { 0, 0, M.FORWARD_SIGN })
  return r, u, f
end

-- world point -> view space: v = R^T * (p - cam_pos)
function M.world_to_view(q, cam_pos, p)
  local d = { p[1] - cam_pos[1], p[2] - cam_pos[2], p[3] - cam_pos[3] }
  local r, u, f = M.basis(q)
  return {
    d[1] * r[1] + d[2] * r[2] + d[3] * r[3],
    d[1] * u[1] + d[2] * u[2] + d[3] * u[3],
    d[1] * f[1] + d[2] * f[2] + d[3] * f[3],
  }
end

-- view-space point (z forward) -> screen pixels; nil when behind the camera
function M.project(v, w, h, hfov)
  hfov = hfov or M.DEFAULT_HFOV
  if v[3] <= 0.01 then return nil end
  local fx = (w / 2) / math.tan(hfov / 2)
  local sx = w / 2 + (v[1] / v[3]) * fx
  local sy = h / 2 - (v[2] / v[3]) * fx      -- square pixels; screen y-down
  return sx, sy
end

-- camera-local offset (meters) -> world target for the hologram anchor
function M.local_target(q, cam_pos, dx, dy, dz)
  local r, u, f = M.basis(q)
  return add(cam_pos, add(add(scale(r, dx), scale(u, dy)), scale(f, dz)))
end

-- exponential lag: cur eases toward target, frame-rate independent
function M.smooth(cur, target, dt, rate)
  local k = 1 - exp(-(rate or M.LAG_RATE) * (dt or 0))
  return { cur[1] + (target[1] - cur[1]) * k,
           cur[2] + (target[2] - cur[2]) * k,
           cur[3] + (target[3] - cur[3]) * k }
end

-- idle bob offset (meters) along camera up
function M.bob(t)
  return scale(M.rotate({ 0, 0, 0, 1 }, { 0, 1, 0 }), M.BOB_AMP * sin(t * M.BOB_HZ * 2 * math.pi))
end

------------------------------------------------------------------------------
-- parse the camera world Matrix4x4 from its stingray tostring form:
--   "Matrix4x4( a,b,c,d,  e,f,g,h,  i,j,k,l,  m,n,o,p )"  (4 rows of 4)
-- Row semantics (live-verified 2026-09-29): rows = right/forward/up,
-- translation = row 4, world Z-up. Gated on orthonormality so a format
-- change can never feed garbage into the hologram.
-- Returns pos, right, fwd, up -- or nil, reason.
------------------------------------------------------------------------------
local MAT_NUM = '-?%d*%.?%d+[eE%-+]?%d*'
function M.parse_matrix(s)
  if type(s) ~= 'string' or not s:find('Matrix4x4') then return nil, 'not a matrix string' end
  -- parse only the parenthesized body: the type name itself contains digits
  local body = s:match('Matrix4x4%((.*)%)')
  if not body then return nil, 'no matrix body' end
  local f = {}
  for num in body:gmatch(MAT_NUM) do f[#f + 1] = tonumber(num) end
  if #f < 16 then return nil, 'expected 16 components, got ' .. #f end
  local right = { f[1], f[2], f[3] }
  local fwd = { f[5], f[6], f[7] }
  local up = { f[9], f[10], f[11] }
  local pos = { f[13], f[14], f[15] }
  local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
  if math.abs(dot(right, right) - 1) > 0.01 then return nil, 'right row not unit' end
  if math.abs(dot(fwd, fwd) - 1) > 0.01 then return nil, 'forward row not unit' end
  if math.abs(dot(right, fwd)) > 0.01 or math.abs(dot(right, up)) > 0.01 or math.abs(dot(fwd, up)) > 0.01 then
    return nil, 'rows not orthogonal'
  end
  return pos, right, fwd, up
end

------------------------------------------------------------------------------
-- defensive decode of the live camera pose. stingray bindings were never
-- probed for debug_camera_pose's exact return shape; support the plausible
-- ones and let the entry log what worked.
-- Returns pos {x,y,z}, quat {x,y,z,w}, shape_name -- or nil, err.
------------------------------------------------------------------------------
local function v3(v)
  if type(v) ~= 'userdata' and type(v) ~= 'table' then return nil end
  local ok, x, y, z = pcall(function() return v.x, v.y, v.z end)
  if ok and type(x) == 'number' and type(y) == 'number' and type(z) == 'number' then
    return { x, y, z }
  end
  return nil
end
local function quat(q)
  if type(q) ~= 'userdata' and type(q) ~= 'table' then return nil end
  local ok, x, y, z, w = pcall(function() return q.x, q.y, q.z, q.w end)
  if ok and type(x) == 'number' and type(y) == 'number' and type(z) == 'number' and type(w) == 'number' then
    return { x, y, z, w }
  end
  return nil
end

function M.decode_pose(a, b, c)
  -- (Vector3 pos, Quaternion rot)
  local p, q = v3(a), quat(b)
  if p and q then return p, q, 'vec3+quat' end
  -- (Camera handle) with sr.Camera accessors -- handled by the entry, which
  -- knows the sr table; here: (pos, fwd, up) basis triple
  p = v3(a)
  local f, u = v3(b), v3(c)
  if p and f and u then
    -- rebuild a rotation quaternion from the orthonormal basis. With rows
    -- right/up/forward, the quat-recovery matrix (v'=Mv) is the transpose:
    --   M11=rx M12=u1 M13=f1 / M21=ry M22=u2 M23=f2 / M31=rz M32=u3 M33=f3
    -- Shepperd's method, branch on the largest diagonal.
    -- right = up x forward (right-handed: facing +X with +Y up, right is -Z)
    local rx = u[2] * f[3] - u[3] * f[2]
    local ry = u[3] * f[1] - u[1] * f[3]
    local rz = u[1] * f[2] - u[2] * f[1]
    local m = { rx, ry, rz, u[1], u[2], u[3], f[1], f[2], f[3] }
    local tr = m[1] + m[5] + m[9]
    local out
    if tr > 0 then
      local s = math.sqrt(tr + 1) * 2
      out = { (m[6] - m[8]) / s, (m[7] - m[3]) / s, (m[2] - m[4]) / s, 0.25 * s }
    elseif m[1] > m[5] and m[1] > m[9] then
      local s = math.sqrt(1 + m[1] - m[5] - m[9]) * 2
      out = { 0.25 * s, (m[4] + m[2]) / s, (m[7] + m[3]) / s, (m[6] - m[8]) / s }
    elseif m[5] > m[9] then
      local s = math.sqrt(1 + m[5] - m[1] - m[9]) * 2
      out = { (m[4] + m[2]) / s, 0.25 * s, (m[8] + m[6]) / s, (m[7] - m[3]) / s }
    else
      local s = math.sqrt(1 + m[9] - m[1] - m[5]) * 2
      out = { (m[7] + m[3]) / s, (m[8] + m[6]) / s, 0.25 * s, (m[2] - m[4]) / s }
    end
    return p, qnorm(out), 'pos+fwd+up'
  end
  return nil, 'unrecognized pose shape'
end

return M

end
do
-- hd2ui/station_entry.lua -- DBF Floaty HUD: in-game entry. The product form
-- of concepts/floaty-hud (DESIGN.md): ONE graphical station, one grammar, no
-- text/graphical duality, no layout editor. Requires the HD2UI framework
-- addon (__hd2ui_require('mods/dbf/hd2ui')). Data layer is the RAH-method instant
-- chain (ammo_chain); the content-anchor scanner survives only as the
-- patch-day fallback (chain cannot verify the running build).
--
-- Behavior rules (DESIGN.md rule 4): visible exactly when the weapon HUD
-- would be; hidden on the bridge / menus / empty hands (sticky, anti-strobe);
-- redraws only when a rendered value changes (plus the pulse clock bucket).
--
-- Lua 5.1 / LuaJIT. Display-only: reads own process, no writes, no game calls.

local sr = rawget(_G, 'stingray')
if type(sr) ~= 'table' then return { installed = false, reason = 'no stingray' } end
if rawget(_G, '__DBF_FLOATY_INSTALLED') then return { installed = true } end

local MR = __hd2ui_require('hd2ui.memreader')
local LS = __hd2ui_require('hd2ui.live_scan')
local A  = __hd2ui_require('hd2ui.ammo_reader')
local AC = __hd2ui_require('hd2ui.ammo_cache')
local CH = __hd2ui_require('hd2ui.ammo_chain')
local STATION = __hd2ui_require('hd2ui.station_bars')
local HOLO = __hd2ui_require('hd2ui.station_holo')

LS.set_transport(MR)
A.set_transport(MR)

local VERSION = 'dbf-floaty r8'
local MATERIAL = 'mods/dbf/hd2ui/solid'   -- provided by the framework addon
local SCAN_BUDGET = 4 * 1048576
local SCAN_WINDOW = 65536
local MAX_ERRORS = 50
local OPACITY = 0.9
local floor = math.floor

local DEFAULTS = { anchor = 'gunside', size = 100, hidden = false }
local CONFIG = {}
for k, v in pairs(DEFAULTS) do CONFIG[k] = v end

------------------------------------------------------------------------------
-- Logging: %APPDATA%/Arrowhead/Helldivers2/hd2ui_floaty.log
------------------------------------------------------------------------------
local log_path
do
  local ok, d = pcall(os.getenv, 'DBF_AMMO_DIR')
  if (not ok or type(d) ~= 'string' or d == '') then
    local ok2, appdata = pcall(os.getenv, 'APPDATA')
    if ok2 and type(appdata) == 'string' and appdata ~= '' then d = appdata .. '/Arrowhead/Helldivers2' end
  end
  if type(d) == 'string' and d ~= '' then log_path = d .. '/hd2ui_floaty.log' end
end
local log_fail = false
local function log(msg)
  if not log_path or log_fail then return end
  local ok, f = pcall(io.open, log_path, 'a')
  if not ok or not f then log_fail = true return end
  local t = os.date and os.date('%H:%M:%S') or '?'
  pcall(f.write, f, string.format('[%s] %s\n', t, tostring(msg)))
  pcall(f.close, f)
end
if log_path then
  local ok, f = pcall(io.open, log_path, 'w')
  if ok and f then pcall(f.close, f) end
end
log(VERSION .. ' START')

------------------------------------------------------------------------------
-- Framework resolution (separate addon). Fail = log + no install (no crash).
------------------------------------------------------------------------------
local HD2 = rawget(_G, '__DBF_HD2UI')
if type(HD2) ~= 'table' then
  local ok, v = pcall(function() return __hd2ui_require('mods/dbf/hd2ui') end)
  if ok and type(v) == 'table' then HD2 = v end
end
if type(HD2) ~= 'table' or type(HD2.backend_stingray) ~= 'table' or type(HD2.scene) ~= 'table' then
  log('MISSING FRAMEWORK: install the HD2UI library addon first')
  return { installed = false, reason = 'hd2ui framework not installed' }
end
log('FRAMEWORK ' .. tostring(HD2.version or '?'))

------------------------------------------------------------------------------
-- Arsenal presets (Mod Options mechanism): anchor + size, read at install.
------------------------------------------------------------------------------
do
  local function preset(name)
    local full = 'mods/dbf/floaty/preset_' .. name
    local ok, has = pcall(sr.Application.can_get, 'lua', full)
    if not ok or not has then return nil end
    local okr, v = pcall(function() return __hd2ui_require(full) end)
    return okr and v or nil
  end
  local an = preset('anchor')
  if an == 'gunside' or an == 'crosshair' or an == 'hologram' then CONFIG.anchor = an end
  local sz = tonumber(preset('size'))
  if sz and sz >= 50 and sz <= 200 then CONFIG.size = sz end
  log(string.format('PRESETS anchor=%s size=%d (from mod options)', CONFIG.anchor, CONFIG.size))
end

------------------------------------------------------------------------------
-- Attach + build stamp (cache key). Same pattern as the archived ammo entry.
------------------------------------------------------------------------------
local self_pid = MR.self_pid and MR.self_pid() or nil
local ok_att, att_err = MR.attach(self_pid, 'helldivers2.exe')
if not ok_att then
  log('ATTACH_FAIL ' .. tostring(att_err))
  return { installed = false, reason = 'attach failed' }
end
A.set_anchor_weapon('r4_deadeye')
local PATTERN = A.anchor_pattern()

local MODULE_BASE, STAMP
local okmb, mb = pcall(LS.module_base, self_pid, 'game.dll')
MODULE_BASE = (okmb and mb) or nil
if MODULE_BASE then
  local okp, sp = pcall(AC.pe_stamp, MR.read_u32, MODULE_BASE)
  STAMP = (okp and sp) or 0
end
STAMP = STAMP or 0
local CACHE_FILE = (log_path and log_path:gsub('hd2ui_floaty%.log$', 'dbf_floaty_cache.txt')) or nil

-- RAH-method chain: instant, module-rooted, signature-verified.
local CHAIN = { enabled = false, fails = 0, last = nil, next_at = 0, status = nil }
do
  if MODULE_BASE then
    local ok_init = pcall(CH.init, { base = MODULE_BASE, read = function(a, n) return MR.read(a, n) end, log = log })
    local ok_ver, ver_err = ok_init and CH.verify() or false, nil
    if ok_init and not ok_ver then ver_err = select(2, CH.verify()) end
    if ok_init and ok_ver then
      CHAIN.enabled = true
      log(string.format('CHAIN ready (layout %s, base 0x%X)', CH.BUILD.name, MODULE_BASE))
    else
      CHAIN.boot_off = true
      log('CHAIN unavailable: ' .. tostring(ver_err or 'init') .. ' -- anchor fallback armed')
    end
  else
    CHAIN.boot_off = true
  end
end

local S = {
  clock = 0, retry_at = 0, errors = 0, disabled = false,
  state = 'scan', scan = nil, next_scan_at = 0, key = nil,
  pct = 0, last = nil, last_base = nil, probe_until = 0,
}

local backend = HD2.backend_stingray.new({ material = MATERIAL, log = log })
local scene, layout = HD2.scene, HD2.layout
local sc = scene.new()

local ANCHOR_REF = { gunside = { 1258, 668 }, crosshair = { 990, 526 } }
local ANCHOR_ORDER = { 'gunside', 'crosshair', 'hologram' }
local SIZE_ORDER = { 50, 75, 100, 125, 150, 200 }

local hud_model_hidden = { hidden = true }

------------------------------------------------------------------------------
-- Hologram anchor (Dead Space style): the station floats at a fixed offset
-- in front-right of the camera, tracked in WORLD space with exponential lag
-- (fast aim sweeps trail and settle) plus a slow idle bob, then projected
-- back to screen each frame. Requires World.debug_camera_pose; without it
-- the station falls back to the gun-side screen anchor.
------------------------------------------------------------------------------
local HOLO_OFF = { dx = 0.34, dy = -0.16, dz = 1.35 }   -- meters, camera-local
-- Pose source: World.debug_camera_pose(main_world) returns the camera's
-- world Matrix4x4 (proven safe: many calls across two addons, 2026-09-29).
-- We read it via tostring() + parse -- the ONLY engine interaction is that
-- one proven call. NO sr.* accessors on the result (proven AV, twice).
-- Row semantics (live-verified): rows = right/forward/up, pos = row 4.
local function pick_world(prefer_main)
  local ok, worlds = pcall(sr.Application.worlds)
  if not ok or type(worlds) ~= 'table' then return nil end
  local okm, main = pcall(sr.Application.main_world)
  if prefer_main and okm and main then return main end
  for _, w in pairs(worlds) do
    if not okm or w ~= main then return w end
  end
  return okm and main or nil
end

local function camera_pose_matrix()
  local okp, m = pcall(sr.World.debug_camera_pose, pick_world(true))
  if not okp or m == nil then return nil end
  local ok, s = pcall(tostring, m)
  if not ok then return nil end
  return HOLO.parse_matrix(s)
end

local holo = { pos = nil, ready = nil, fail_logged = false, fsign = nil, norm = nil }
local M_HALF_W, M_HALF_H = STATION.W / 2, STATION.H / 2

local function holo_screen(dt, w, h)
  local pos, right, fwd, up = camera_pose_matrix()
  if not pos then
    if not holo.fail_logged then
      holo.fail_logged = true
      log('HOLO unavailable: camera pose unreadable -- gun-side fallback')
    end
    holo.ready = false
    return nil
  end
  if not holo.ready then
    holo.ready = true
    log('HOLO ready (camera matrix tostring path)')
  end
  -- camera-local offset -> world target (plus the idle bob along camera up)
  local bob = HOLO.bob(S.clock)
  local target = {
    pos[1] + right[1] * HOLO_OFF.dx + up[1] * HOLO_OFF.dy + fwd[1] * HOLO_OFF.dz + bob[1],
    pos[2] + right[2] * HOLO_OFF.dx + up[2] * HOLO_OFF.dy + fwd[2] * HOLO_OFF.dz + bob[2],
    pos[3] + right[3] * HOLO_OFF.dx + up[3] * HOLO_OFF.dy + fwd[3] * HOLO_OFF.dz + bob[3],
  }
  holo.pos = holo.pos and HOLO.smooth(holo.pos, target, dt) or target
  -- lagged world delta back into the camera frame, then perspective project
  local d = { holo.pos[1] - pos[1], holo.pos[2] - pos[2], holo.pos[3] - pos[3] }
  local view = {
    d[1] * right[1] + d[2] * right[2] + d[3] * right[3],
    d[1] * up[1] + d[2] * up[2] + d[3] * up[3],
    d[1] * fwd[1] + d[2] * fwd[2] + d[3] * fwd[3],
  }
  return HOLO.project(view, w, h)
end

local function render(m, w, h, dt)
  local s = layout.scale_factor(h, CONFIG.size / 100)
  local ox, oy
  if CONFIG.anchor == 'hologram' then
    -- live path: debug_camera_pose(main world) -> tostring -> parse -> pure
    -- Lua projection. The ONE proven-safe engine call; no sr.* accessors.
    local sx, sy = holo_screen(dt, w, h)
    if sx then
      -- the projected point is the station center; draw from its top-left
      ox, oy = sx - (M_HALF_W * s), sy - (M_HALF_H * s)
    else
      local ref = ANCHOR_REF.gunside
      ox, oy = layout.place(w, h, ref[1], ref[2], s)
    end
  else
    local ref = ANCHOR_REF[CONFIG.anchor] or ANCHOR_REF.gunside
    ox, oy = layout.place(w, h, ref[1], ref[2], s)
  end
  sc:clear()
  STATION.draw(sc, m, { clock = S.clock })
  local dl = {}
  sc:render(dl, ox, oy, s)
  backend.emit(dl, OPACITY)
end

local function idx_of(list, v)
  for i = 1, #list do if list[i] == v then return i end end
end

------------------------------------------------------------------------------
-- Mod Options Menu (primary settings surface) + one MBM binding.
------------------------------------------------------------------------------
local function mom_apply(key, value)
  if key == 'dbf_floaty_anchor' then
    CONFIG.anchor = ANCHOR_ORDER[value or 1] or 'gunside'
  elseif key == 'dbf_floaty_size' then
    CONFIG.size = value or 100
  elseif key == 'dbf_floaty_enabled' then
    CONFIG.hidden = not value
  end
  S.key = nil
end

local MOM = { api = nil, tried_at = 0, reg = {} }
local function mom_register()
  local api = MOM.api
  local specs = {
    { id = 'dbf_floaty_anchor', spec = { type = 'choice', label = 'Station anchor', mod = 'DBF Floaty HUD',
        choices = { 'Gun-side', 'Right of crosshair', 'Hologram (3D)' }, default = idx_of(ANCHOR_ORDER, CONFIG.anchor) or 1,
        description = 'Where the station docks. Hologram floats in world space beside the weapon, Dead Space style (falls back to gun-side if the camera pose is unavailable).' } },
    { id = 'dbf_floaty_size', spec = { type = 'slider', label = 'Station size', mod = 'DBF Floaty HUD',
        min = 50, max = 200, step = 25, default = CONFIG.size,
        description = 'Station scale percentage.' } },
    { id = 'dbf_floaty_enabled', spec = { type = 'toggle', label = 'HUD enabled', mod = 'DBF Floaty HUD',
        default = not CONFIG.hidden, description = 'Master switch for the station.' } },
  }
  for _, s in ipairs(specs) do
    local okc = pcall(api.register_option, s.id, s.spec)
    MOM.reg[s.id] = okc and true or false
    if okc then
      local live = api.get(s.id)
      if live ~= nil then mom_apply(s.id, live) end
      pcall(api.on_change, s.id, function(v) mom_apply(s.id, v) end)
    end
  end
  log('MOM options registered: ' .. tostring(#specs))
end

local function mom_poll()
  if MOM.api then return end
  if S.clock < MOM.tried_at then return end
  MOM.tried_at = S.clock + 1
  local api = rawget(_G, 'ModOptionsMenu')
  if type(api) ~= 'table' or type(api.ready) ~= 'function' or not api.ready() then return end
  MOM.api = api
  mom_register()
end

local MBM = { api = nil, tried_at = 0, bound = {}, down = {} }
local function mbm_poll()
  if MBM.api then
    if MBM.bound.dbf_floaty_toggle then
      local ok, d = pcall(MBM.api.is_down, 'dbf_floaty_toggle')
      local now = ok and d == true
      if now and not MBM.down.dbf_floaty_toggle then
        CONFIG.hidden = not CONFIG.hidden
        if MOM.api and MOM.reg.dbf_floaty_enabled then pcall(MOM.api.set, 'dbf_floaty_enabled', not CONFIG.hidden) end
        S.key = nil
      end
      MBM.down.dbf_floaty_toggle = now
    end
    return
  end
  if S.clock < MBM.tried_at then return end
  MBM.tried_at = S.clock + 1
  local api = rawget(_G, 'ModBindingsMenu')
  if type(api) ~= 'table' or type(api.register_binding) ~= 'function' then return end
  if type(api.ready) == 'function' and not api.ready() then return end
  MBM.api = api
  MBM.bound.dbf_floaty_toggle = pcall(api.register_binding, 'dbf_floaty_toggle',
    'DBF Floaty: Toggle Station', nil, { category = 'DBF Floaty HUD' })
  log('MBM bindings registered: 1')
end

------------------------------------------------------------------------------
-- Cache fast path + frame-budgeted anchor scan (patch-day fallback only).
-- Verbatim mechanics from the archived ammo entry (proven), minus toasts.
------------------------------------------------------------------------------
local function try_cache()
  if not CACHE_FILE then return false end
  local cstamp, cbase = AC.load(CACHE_FILE)
  if cstamp ~= STAMP or not cbase then return false end
  local okb, berr = pcall(A.set_anchor_base, cbase)
  if not okb then
    log('CACHE_REJECT ' .. tostring(berr))
    return false
  end
  local ammo = A.read()
  if not ammo then
    log(string.format('CACHE_MISS base=0x%X (validation failed; will scan)', cbase))
    return false
  end
  log(string.format('CACHE_LOCKED base=0x%X mag=%d res=%d', cbase, ammo.magazine, ammo.reserve))
  S.state = 'locked'
  return true
end

local function start_scan()
  local ok, n = LS.enum_regions()
  if not ok then
    log('ENUM_FAIL ' .. tostring(n))
    S.next_scan_at = S.clock + 15
    return
  end
  local regions = LS.state().regions
  table.sort(regions, function(a, b)
    local sa = a.size + (a.private and 0x200000000 or 0)
    local sb = b.size + (b.private and 0x200000000 or 0)
    if sa == sb then return a.base > b.base end
    return sa > sb
  end)
  S.scan = { ri = 0, pos = 0, hits = {}, done = false }
  S.state = 'scan'
  S.pct = 0
  log('SCAN_START regions=' .. tostring(#regions) .. ' (arena-first order)')
end

local function try_lock(base)
  local ok = A.set_anchor_base(base)
  if not ok then return false end
  local ammo = A.read()
  if not ammo then return false end
  log(string.format('LOCKED base=0x%X mag=%d res=%d', base, ammo.magazine, ammo.reserve))
  S.last_base = base
  S.state = 'locked'
  S.scan = nil
  if CACHE_FILE and AC.save(CACHE_FILE, STAMP, base) then
    log(string.format('CACHE_SAVED stamp=%X base=0x%X', STAMP, base))
  end
  return true
end

local function validate_and_lock(hits)
  for i = 1, #hits do
    if try_lock(hits[i]) then return true end
  end
  log('SCAN_DONE no plausible hit (' .. #hits .. ' raw)')
  S.last = #hits > 0 and ('raw' .. #hits) or 'nohit'
  S.scan = nil
  S.next_scan_at = S.clock + 30
  return false
end

local function step_scan()
  local sc_ = S.scan
  local st = LS.state()
  local regions = st.regions
  local plen = #PATTERN
  local budget = SCAN_BUDGET
  while budget > 0 do
    if sc_.ri >= #regions then
      sc_.done = true
      break
    end
    S.pct = math.floor(100 * sc_.ri / math.max(1, #regions))
    local r = regions[sc_.ri + 1]
    if not r then sc_.ri = sc_.ri + 1 sc_.pos = 0
    elseif sc_.pos >= r.size then sc_.ri = sc_.ri + 1 sc_.pos = 0
    else
      local n = math.min(SCAN_WINDOW, r.size - sc_.pos)
      local data = MR.read(r.base + sc_.pos, n)
      if data then
        local from = 1
        while true do
          local s = data:find(PATTERN, from, true)
          if not s then break end
          local hit = r.base + sc_.pos + (s - 1)
          if try_lock(hit) then return end
          sc_.hits[#sc_.hits + 1] = hit
          from = s + 1
        end
        budget = budget - #data
        sc_.pos = sc_.pos + math.max(1, #data - (plen - 1))
      else
        budget = budget - SCAN_WINDOW
        sc_.pos = sc_.pos + SCAN_WINDOW
      end
    end
  end
  if sc_.done and #sc_.hits > 0 then validate_and_lock(sc_.hits) end
end

------------------------------------------------------------------------------
-- Chain model -> station model. The chain row IS the data; this only names
-- the fields the station consumes (station_bars.classify does the rest).
------------------------------------------------------------------------------
local function chain_model(row)
  local m = { weapon_id = row.weapon_id }
  if row.charge_only then
    m.charge_only = true
    m.charge_pct = row.charge_pct
    return m
  end
  if row.path == 'resource' then
    m.fuel_frac = row.fuel or 0
    m.spare, m.spare_kind = row.spare, row.spare_kind
    m.charge_pct = row.charge_pct
    return m
  end
  if row.path == 'heat' then
    local frac = 0
    if row.heat_max and row.heat_max > 0 then
      frac = math.min(1, row.heat / row.heat_max)
    else
      frac = math.min(1, (row.heat or 0) / 100)
    end
    m.heat_frac = frac
    m.heat_lock = row.overheated and true or false
    m.spare, m.spare_kind = row.spare, row.spare_kind
    m.spare_max = row.spare_max or row.sinks_max
    m.charge_pct = row.charge_pct
    return m
  end
  local cap = row.capacity or 0
  m.rounds = (row.rounds or 0) + (row.chamber or 0)
  m.mag_cap = cap + ((row.path == 'magazine' and row.chambered) and 1 or 0)
  if row.spare_kind == 'backpack' then
    -- user rule (AC): the magazine is a 10-round carousel with NO chamber
    -- round -- the pool never exceeds the true maximum
    m.rounds = math.min(m.rounds, m.mag_cap)
  end
  m.spare, m.spare_kind = row.spare, row.spare_kind
  m.spare_max = row.spare_max
  m.ammo_max = row.ammo_max
  m.charge_pct = row.charge_pct
  if row.spare_kind == 'backpack' then
    -- deposit count is a ROUND POOL; the station converts to stripper clips
    m.pack_rounds = row.spare or 0
    m.pack_total = row.pack_total or row.spare or 0
  end
  return m
end

------------------------------------------------------------------------------
-- Sticky presentation: identical to the archived entry's proven machinery.
-- Value / idle-hidden / error states flip only after 3 consecutive samples;
-- holster blips freeze instead of hiding; the bridge settles to hidden.
------------------------------------------------------------------------------
local IDLE_STATUS = { no_local_player = true, no_avatar = true, avatar_entity_missing = true,
  no_inventory = true, no_weapon_slot = true, weapon_entity_missing = true,
  no_weapon_driver = true, no_ammo_component = true, in_vehicle = true,
  player_not_owned = true, avatar_not_owned = true }
local LAYOUT_MARK = { ['.r'] = true, ['.m'] = true, ['.o'] = true,
                      ['.b'] = true, ['.z'] = true, ['.e'] = true }
local function mark(status)
  if type(status) ~= 'string' then return '.?' end
  if status:find('^error') then
    if status:find('unreadable') then return '.r' end
    if status:find('map probe') then return '.m' end
    if status:find('owner mismatch') then return '.o' end
    if status:find('budget') then return '.b' end
    if status:find('null pointer') then return '.z' end
    return '.e'
  end
  return '.?'
end

local function model()
  if CONFIG.hidden then return hud_model_hidden end
  if CHAIN.enabled then
    if CHAIN.clock == nil then CHAIN.clock = 0 end
    if S.clock >= CHAIN.next_at then
      CHAIN.next_at = S.clock + 0.1
      local row = CH.read()
      if row.status ~= CHAIN.status then
        CHAIN.status = row.status
        log('CHAIN status ' .. tostring(row.status) ..
            (row.status == 'ok' and string.format(' (reads %d)', row.reads) or ''))
      end
      if row.status == 'ok' then
        CHAIN.last, CHAIN.fails = row, 0
        CHAIN.last_ok_at, CHAIN.off_run = S.clock, 0
        CHAIN.ok_run = (CHAIN.ok_run or 0) + 1
        if CHAIN.ok_run >= 2 or CHAIN.shown == 'value' then CHAIN.shown = 'value' end
      else
        CHAIN.ok_run = 0
        local BLIP = row.status == 'no_weapon_driver' or row.status == 'no_weapon_slot'
        if not (BLIP and (S.clock - (CHAIN.last_ok_at or -99)) < 1.2) then
          CHAIN.off_run = (CHAIN.off_run or 0) + 1
        end
        local m = mark(row.status)
        if LAYOUT_MARK[m] then
          CHAIN.fails = CHAIN.fails + 1
          if CHAIN.fails >= 15 then
            log('CHAIN disabled after repeated layout errors -- re-arming in 10s')
            CHAIN.enabled = false
            CHAIN.rearm_at = S.clock + 10
            CHAIN.fails = 0
          end
        else
          CHAIN.fails = 0
        end
        -- unknown/unsupported states hide the station: no floating marks (rule 3)
        if CHAIN.off_run >= 3 then CHAIN.shown = 'hidden' end
      end
      if CHAIN.shown == 'value' and CHAIN.last then
        if CHAIN.last.weapon_id == row.weapon_id then
          return chain_model(CHAIN.last)
        end
        return hud_model_hidden   -- weapon switch: hide one sample, next read re-shows
      end
      return hud_model_hidden
    end
    if CHAIN.last and CHAIN.shown == 'value' then return chain_model(CHAIN.last) end
    return hud_model_hidden
  end
  return hud_model_hidden   -- chain off (patch day): station stays hidden until the anchor locks
end

------------------------------------------------------------------------------
-- Frame.
------------------------------------------------------------------------------
local function model_key(m, w, h)
  if m.hidden then return 'hidden' end
  local parts = {
    m.rounds or 'x', m.mag_cap or 'x', m.spare or 'x', m.spare_max or 'x',
    m.pack_rounds or 'x', m.pack_total or 'x',
    m.heat_frac and floor(m.heat_frac * 200) or 'x',
    m.heat_lock and 1 or 0,
    m.fuel_frac and floor(m.fuel_frac * 200) or 'x',
    m.charge_pct and floor(m.charge_pct * 200) or 'x',
    m.charge_only and 1 or 0,
    CONFIG.anchor, w, h, tostring(backend.mode()), backend.generation(),
    floor(S.clock * 3),      -- pulse clock bucket (~3 redraws/s while visible)
  }
  return table.concat(parts, '|')
end

local function frame(dt)
  mbm_poll()
  mom_poll()
  if not backend.ensure() then return end
  if backend.cursor_visible() then
    if S.key ~= 'hidden' then backend.clear(); S.key = 'hidden' end
    return
  end
  if not CHAIN.enabled then
    if CHAIN.rearm_at and S.clock >= CHAIN.rearm_at and not CHAIN.boot_off then
      CHAIN.enabled, CHAIN.rearm_at = true, nil
      CHAIN.status, CHAIN.fails = nil, 0
      log('CHAIN_REARM')
    end
  end
  if CHAIN.boot_off then
    if S.state == 'probe' then
      if try_lock(S.last_base) then
        log(string.format('PROBE recovered instantly at 0x%X', S.last_base))
      elseif S.clock >= S.probe_until then
        S.state = 'scan'
        S.scan = nil
        S.next_scan_at = 0
      end
    end
    if S.state == 'scan' then
      if S.scan then step_scan()
      elseif S.clock >= S.next_scan_at then start_scan() end
    end
  end
  local w, h = backend.resolution()
  if not w then return end
  local m = model()
  if m.hidden then
    if S.key ~= 'hidden' then backend.clear(); S.key = 'hidden' end
    return
  end
  local key = model_key(m, w, h)
  if key == S.key then return end
  S.key = key
  backend.clear()
  render(m, w, h, dt)
end

------------------------------------------------------------------------------
-- Hooks (same lifecycle pattern as the demo/archived entries).
------------------------------------------------------------------------------
local old_update = rawget(_G, 'update')
if type(old_update) ~= 'function' then
  log('no global update(); not installing')
  return { installed = false, reason = 'no update' }
end
rawset(_G, '__DBF_FLOATY_INSTALLED', true)

if not try_cache() then S.next_scan_at = 0 end

rawset(_G, 'update', function(...)
  local dt = select(1, ...)
  if type(dt) ~= 'number' or dt ~= dt then dt = 1 / 60 end
  if dt < 0 then dt = 0 elseif dt > 0.25 then dt = 0.25 end
  S.clock = S.clock + dt
  if not S.disabled and S.clock >= S.retry_at then
    local ok, err = pcall(frame, dt)
    if ok then
      S.errors = 0
    else
      S.errors = S.errors + 1
      S.retry_at = S.clock + 1
      log('frame error #' .. S.errors .. ': ' .. tostring(err))
      if S.errors >= MAX_ERRORS then
        S.disabled = true
        log('too many errors; disabling')
        pcall(backend.clear)
      end
    end
  end
  return old_update(...)
end)

local old_shutdown = rawget(_G, 'shutdown')
rawset(_G, 'shutdown', function(...)
  local ok, worlds = pcall(sr.Application.worlds)
  pcall(backend.release, ok and worlds or {})
  log('shutdown')
  if type(old_shutdown) == 'function' then return old_shutdown(...) end
end)

log('installed')
return { installed = true, version = VERSION, anchor = CONFIG.anchor, framework = HD2.version }

end
