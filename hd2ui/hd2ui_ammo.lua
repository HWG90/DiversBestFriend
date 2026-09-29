-- HD2-Addon: mods/dbf/ammo/hud
-- dbf ammo hud r52; assembled by hd2ui/build_ammo.py; do not edit.
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
__hd2ui_modules['hd2ui.ammo_bars'] = function()
-- hd2ui/ammo_bars.lua -- Graphical presentation layer for the ammo HUD.
-- Orthogonal to the position styles (crosshair/gunside/world): the style owns
-- the anchor; this layer draws scene primitives in LOCAL coordinates around
-- the anchor (rect x,y = left/bottom corner, y-up, matching the framework's
-- gunside backdrop convention).
--
--   HEAT  (lasers):      vertical bar FILLS as heat rises; red + LOCK at cap.
--   FUEL  (burn guns):   vertical bar EMPTIES as the tank drains.
--   counter:             numeric label always kept (user spec).
--   spare magazines:     horizontal bar that shrinks as packs are consumed
--                        and returns when refilled (ratio vs the highest
--                        spare count seen for this weapon id, or the config
--                        max when known).
--
-- Lua 5.1 / LuaJIT. M.draw(sc, model, mult, colors) -- colors is api.colors
-- (the framework palette module; there is no standalone hd2ui.colors).

local M = {}
M.seen = {}   -- weapon_key -> { spare = max seen }

local function heat_color(colors, frac, locked)
  if locked then return colors.from_hex('#e03030') end
  local pale, amber = colors.from_hex('#d9d4c8'), colors.from_hex('#e0a030')
  local red = colors.from_hex('#e03030')
  if frac < 0.5 then return colors.mix(pale, amber, frac * 2) end
  return colors.mix(amber, red, (frac - 0.5) * 2)
end

-- hazard overlay: 45-degree yellow/black caution stripes confined to a zone
-- [y0, y0+zh] of the bar. Rendered as 1-unit scanline steps whose phase
-- advances 1 unit per row (true diagonal at this resolution; no clipping
-- needed because every segment is intersected with the bar width).
local STRIPE_W, STRIPE_PERIOD = 2, 4   -- pattern units (yellow 2 of every 4)
local ROW = 1.25                          -- stripe scanline thickness (ref units)

local function hazard_zone(sc, colors, x, y0, w, zh, active)
  local yellow = colors.from_hex('#e8c020')
  local dark   = colors.from_hex('#141410')
  local a_stripe, a_dark = active and 0.95 or 0.30, active and 0.85 or 0.45
  local row = 0
  while row < zh - 0.5 do
    local phase = row % STRIPE_PERIOD
    local yy = y0 + row
    -- dark base line
    sc:add('rect', { x = x, y = yy, w = w, h = ROW }, colors.alpha(dark, a_dark))
    -- yellow segments clipped to [x, x+w]
    local p = phase
    while p < w do
      local seg_x = x + p
      local seg_w = math.min(STRIPE_W, w - p)
      if seg_w > 0 then
        sc:add('rect', { x = seg_x, y = yy, w = seg_w, h = ROW }, colors.alpha(yellow, a_stripe))
      end
      p = p + STRIPE_PERIOD
    end
    row = row + 1.25
  end
end

-- Vertical bar spanning [bottom, bottom+h].
-- mode 'heat': fills TOP-DOWN (anchored at the top; danger grows toward the
--              hazard-striped BOTTOM 10%).  mode 'fuel': fills from the bottom
--              and empties down into the same bottom hazard band.
local function vert_bar(sc, colors, x, bottom, h, w, frac, col, label, mode)
  local fill = math.max(0, math.min(1, frac))
  sc:add('rect', { x = x, y = bottom, w = w, h = h },
         colors.alpha(colors.from_hex('#1e211d'), 0.35))
  -- both gauges hang from the TOP: heat grows down INTO the hazard field,
  -- fuel shrinks up to EXPOSE it. The fill carves the field: stripe rows
  -- are only drawn below the fill's leading edge, and the fill itself is
  -- near-opaque, so the gauge cleanly overwrites the stripes (user spec).
  local fy = mode and (bottom + h * (1 - fill)) or bottom
  if mode then
    -- hazard stripes are a THRESHOLD ALARM: they exist only once the gauge
    -- enters the danger quarter (heat >= 75% / fuel <= 25%), carved by the
    -- fill's leading edge so the gauge still overwrites them.
    -- hazard marks are ALWAYS drawn (faint); they LIT UP past the threshold
    -- (heat >= 75% / fuel <= 25%). Carve at the fill's bottom edge so the
    -- gauge still overwrites the band where it physically covers it.
    local danger
    if mode == 'heat' then danger = fill >= 0.75 else danger = fill <= 0.25 end
    local zh = math.max(3, math.floor(h * 0.25 + 0.5))
    local cut = bottom + h * (1 - fill)
    local visible_h = math.max(0, math.min(bottom + zh, cut) - bottom)
    if visible_h > 0.5 then
      hazard_zone(sc, colors, x, bottom, w, visible_h, danger)
    end
  end
  if fill > 0.005 then
    sc:add('rect', { x = x, y = fy, w = w, h = h * fill },
           colors.alpha(col, 0.9))
  end
  if label then
    sc:add('text', { str = label, x = x + w / 2, y = bottom - 12, size = 8, align = 'center' },
           colors.alpha(colors.from_hex('#c8c8c8'), 0.8))
  end
end

-- left-anchored horizontal bar (spare mags): empties as packs are consumed
local function horiz_bar(sc, colors, x, y, total_w, h, frac, col)
  local fill = math.max(0, math.min(1, frac))
  sc:add('rect', { x = x, y = y, w = total_w, h = h },
         colors.alpha(colors.from_hex('#1e211d'), 0.30))
  if fill > 0.005 then
    sc:add('rect', { x = x, y = y, w = total_w * fill, h = h }, colors.alpha(col, 0.85))
  end
end

-- per-element offset helper (dashboard-movable)
local function off(LAY, id, mult)
  local x, y = LAY.get(id)
  return x * mult, y * mult
end

-- sub-tray: a shallow drawer welded to the panel's bottom edge, so secondary
-- rows (sinks, tanks, charge) read as PART of the station, not floaters
local function tray(sc, colors, x, y, w, mult)
  -- deliberately DARKER than the panel body so the two-tone station reads
  sc:add('rect', { x = x, y = y + 2 * mult, w = w, h = 11 * mult },
         colors.alpha(colors.from_hex('#040504'), 0.80))
  sc:add('rect', { x = x, y = y + 2 * mult, w = w, h = 0.8 * mult },
         colors.alpha(colors.from_hex('#4a5158'), 0.55))
end

-- model fields consumed: label, color, weapon_key, spare, spare_kind,
-- spare_max, heat_frac, heat_lock, heat_pct, fuel_frac, charge_pct,
-- pack {remain,total}, mag_rounds, mag_cap, layout_all (dashboard).
--
-- UNIFIED PANEL DESIGN (R52): every weapon class docks into ONE frosted core
-- panel at a fixed station right of the crosshair. The panel is the contract;
-- only its contents change per class. Coordinate convention stated once:
-- scene space is y-DOWN (backend flips at emit): larger y = lower on screen.
function M.draw(sc, model, mult, colors)
  mult = mult or 1
  local m = model
  local LAY = M.LAY or { active = false, get = function() return 0, 0 end }
  local lox, loy = off(LAY, 'label', mult)
  local PX = 34 * mult + lox            -- panel top-left (y-down)
  local PY = -17 * mult + loy
  local PW = 120 * mult                 -- panel width (grows for AC)
  local PH = 34 * mult

  -- observed max spare (rack/brick denominators)
  local ref = math.max(m.spare_max or 0, 1)
  if m.weapon_key and m.spare_kind == 'mags' then
    local seen = M.seen[m.weapon_key]
    if not seen then seen = { spare = 0 }; M.seen[m.weapon_key] = seen end
    if (m.spare or 0) > seen.spare then seen.spare = m.spare end
    ref = math.max(ref, seen.spare, 1)
  end

  local is_ac   = m.pack and m.mag_rounds ~= nil and (m.mag_cap or 1) > 1
  local is_heat = m.heat_frac ~= nil
  local is_fuel = m.fuel_frac ~= nil
  if is_ac then PW = 128 * mult end

  local function panel_bg()
    -- two-tone: charcoal body + near-black tray = one visible station
    sc:add('rect', { x = PX, y = PY, w = PW, h = PH },
           colors.alpha(colors.from_hex('#1a1e1a'), 0.66))
    sc:add('rect', { x = PX, y = PY, w = PW, h = 1.2 * mult },
           colors.alpha(colors.from_hex('#000000'), 0.5))
    sc:add('rect', { x = PX, y = PY + PH - 1.2 * mult, w = PW, h = 1.2 * mult },
           colors.alpha(colors.from_hex('#c9d2d6'), 0.30))
  end

  local function big_text(str, x, y, size, col, a)
    sc:add('text', { str = str, x = x + 1.2 * mult, y = y + 1.2 * mult,
                     size = size, align = 'left' },
           colors.alpha(colors.from_hex('#000000'), 0.6))
    sc:add('text', { str = str, x = x, y = y, size = size, align = 'left' },
           colors.alpha(colors.from_hex(col or '#f6f6f6'), a or 1.0))
  end

  -- =================================================================== AC ==
  if is_ac then
    panel_bg()
    local cap = math.min(14, m.mag_cap)
    local rounds = math.max(0, math.min(cap, m.mag_rounds))
    local ready = rounds > 0 and rounds <= 5
    -- mini magazine column inside the panel (slot 0 = top; drains downward)
    local cx0, cy0, rh = PX + 7 * mult, PY + 3 * mult, (PH - 6 * mult) / cap
    if rounds == 0 then
      sc:add('rect', { x = cx0 - 1 * mult, y = cy0, w = 12 * mult + 2, h = cap * rh },
             colors.alpha(colors.from_hex('#e03030'), 0.25))
    end
    for i = 0, cap - 1 do
      local alive = i < rounds
      local col = alive and colors.alpha(colors.from_hex(ready and '#7fd4ff' or '#d9d9d9'), 0.92)
                     or  colors.alpha(colors.from_hex('#d9d9d9'), 0.14)
      sc:add('rect', { x = cx0, y = cy0 + i * rh, w = 12 * mult, h = rh - 0.7 * mult }, col)
    end
    -- clip line through the 5th slot's middle
    local ly = cy0 + (cap - 5) * rh + (rh - 0.7 * mult) / 2
    local dx = cx0 - 2 * mult
    while dx < cx0 + 15 * mult do
      sc:add('rect', { x = dx, y = ly - 0.4 * mult, w = 2.2 * mult, h = 0.9 * mult },
             colors.alpha(colors.from_hex(ready and '#7fd4ff' or '#c8c8c8'), ready and 0.95 or 0.4))
      dx = dx + 4.4 * mult
    end
    -- live count
    big_text(tostring(rounds), PX + 26 * mult, PY + 6 * mult, 22 * mult)
    -- backpack magazine bars: solid bars + ghost slots, bottom-right first
    local remain = math.max(0, m.pack.remain or 0)
    local total = math.max(m.pack.total or 0, remain, 1)
    if total > 14 then total = 14 end
    local bx0, bw, gap = PX + 58 * mult, 4.6 * mult, 1.8 * mult
    local rows = math.ceil(total / 7)
    for i = 0, total - 1 do
      local c = i % 7
      local r = math.floor(i / 7)
      local bx, by = bx0 + c * (bw + gap), PY + 5 * mult + r * 15 * mult
      if i < remain then
        sc:add('rect', { x = bx, y = by, w = bw, h = 12 * mult },
               colors.alpha(colors.from_hex('#d9d9d9'), 0.92))
        sc:add('rect', { x = bx, y = by, w = bw, h = 1.6 * mult },
               colors.alpha(colors.from_hex('#000000'), 0.35))
      else
        sc:add('rect', { x = bx, y = by + 10.4 * mult, w = bw, h = 1.6 * mult },
               colors.alpha(colors.from_hex('#d9d9d9'), 0.28))
      end
    end
  -- ================================================================ LASER ==
  elseif is_heat then
    panel_bg()
    local frac = math.max(0, math.min(1, m.heat_frac))
    big_text(string.format('%d%%', m.heat_pct or 0), PX + 9 * mult, PY + 6 * mult,
             22 * mult, m.color)
    -- heat bar rides the panel's right edge: fills UP from bottom into the
    -- hazard band at the base (band always drawn faint, lit >=75%)
    local bx, by, bw2, bh = PX + PW - 22 * mult, PY + 4 * mult, 9 * mult, PH - 8 * mult
    sc:add('rect', { x = bx, y = by, w = bw2, h = bh },
           colors.alpha(colors.from_hex('#141410'), 0.8))
    local fill_h = bh * frac
    if fill_h > 0.5 then
      sc:add('rect', { x = bx, y = by + bh - fill_h, w = bw2, h = fill_h },
             colors.alpha(heat_color(colors, frac, m.heat_lock), 0.95))
    end
    -- hazard band = TOP quarter (heat rises INTO danger; the fill carves the
    -- band from below as it approaches full)
    local band_h = bh * 0.25
    local fill_top = by + bh - fill_h
    local limit = math.min(by + band_h, fill_top)
    local danger = frac >= 0.75
    local SW, PER = 2 * mult, 4 * mult
    local sy = by
    while sy < limit - 0.5 do
      local row_h = math.min(1.3 * mult, limit - sy)
      local shift = (sy - by) % PER               -- 45-degree phase walk
      local sx2 = bx - PER + shift
      while sx2 < bx + bw2 do
        local x0 = math.max(bx, sx2)
        local x1 = math.min(bx + bw2, sx2 + SW)
        if x1 > x0 then
          sc:add('rect', { x = x0, y = sy, w = x1 - x0, h = row_h },
                 colors.alpha(colors.from_hex('#e8c020'), danger and 0.92 or 0.32))
        end
        sx2 = sx2 + PER
      end
      sy = sy + 1.3 * mult
    end
    -- heat sinks: brick row in the sub-tray drawer (spare, then ghosts to max)
    tray(sc, colors, PX, PY + PH, PW, mult)
    local n = math.max(0, math.min(8, m.spare or 0))
    local tot = math.max(m.spare_max or 0, n, 1)
    if tot > 8 then tot = 8 end
    for i = 0, tot - 1 do
      sc:add('rect', { x = PX + 4 * mult + i * 11 * mult, y = PY + PH + 7 * mult,
                       w = 9 * mult, h = 4.6 * mult },
             colors.alpha(colors.from_hex('#d9d9d9'), i < n and 0.92 or 0.22))
    end
  -- ============================================================== FUEL gun ==
  elseif is_fuel then
    panel_bg()
    local frac = math.max(0, math.min(1, m.fuel_frac))
    big_text(string.format('%d%%', math.floor(frac * 100 + 0.5)),
             PX + 9 * mult, PY + 6 * mult, 22 * mult,
             frac <= 0.25 and '#e88080' or m.color)
    -- gas-tank dial INTEGRATED into the panel's right half (nothing pokes
    -- outside the station silhouette)
    local ox2, oy2 = off(LAY, 'fuel', mult)
    local dcx, dcy, r = PX + PW - 33 * mult + ox2 * 0.4, PY + PH - 9 * mult + oy2 * 0.4, 13.5 * mult
    local th = 3.2 * mult
    local AE, AF = math.rad(-200), math.rad(20)
    local alert = frac <= 0.25
    local fill_col = alert and '#e03030' or '#e8b84a'
    sc:add('arc', { cx = dcx, cy = dcy, r = r + 1.6 * mult, th = th + 2 * mult,
                    a0 = AE, a1 = AF }, colors.alpha(colors.from_hex('#0b0c0a'), 0.4))
    sc:add('arc', { cx = dcx, cy = dcy, r = r, th = th, a0 = AE, a1 = AF },
           colors.alpha(colors.from_hex('#1e211d'), 0.6))
    local a25 = AE + (AF - AE) * 0.25
    sc:add('arc', { cx = dcx, cy = dcy, r = r - 1, th = th + 2, a0 = a25 - 0.05, a1 = a25 + 0.05 },
           colors.alpha(colors.from_hex('#8899aa'), alert and 0.6 or 0.25))
    local ang = AE + (AF - AE) * frac
    if frac > 0.003 then
      sc:add('arc', { cx = dcx, cy = dcy, r = r, th = th, a0 = AE, a1 = ang },
             colors.alpha(colors.from_hex(fill_col), 0.92))
    end
    local ca, sa = math.cos(ang), math.sin(ang)
    local hub, tipr = 1.4 * mult, r + 3 * mult
    sc:add('tri', { x1 = dcx - sa * hub, y1 = dcy + ca * hub,
                    x2 = dcx + sa * hub, y2 = dcy - ca * hub,
                    x3 = dcx + ca * tipr, y3 = dcy + sa * tipr },
           colors.alpha(colors.from_hex(alert and '#ffd0c0' or '#f2f2f2'), 0.95))
    sc:add('circle', { cx = dcx, cy = dcy, r = 2.4 * mult },
           colors.alpha(colors.from_hex('#2a2e2a'), 0.92))
    sc:add('circle', { cx = dcx, cy = dcy, r = 1 * mult },
           colors.alpha(colors.from_hex('#c8c8c8'), 0.8))
    -- multi-tank: spare tank bricks under the panel
    if m.spare_kind == 'tanks' and (m.spare or 0) > 0 then
      tray(sc, colors, PX, PY + PH, PW, mult)
      for i = 0, math.min(6, m.spare) - 1 do
        sc:add('rect', { x = PX + 4 * mult + i * 11 * mult, y = PY + PH + 7 * mult,
                         w = 9 * mult, h = 4.6 * mult },
               colors.alpha(colors.from_hex('#e8b84a'), 0.9))
      end
    end
  -- ====================================================== plain counter ==
  elseif (m.label or '') ~= '' or m.layout_all then
    local _had_pack = m.pack and true or false
    panel_bg()
    local txt = m.label
    if is_ac then txt = '' end
    -- de-dup: the pip rack already depicts reserve, text = live count only
    if m.spare_kind == 'mags' then txt = tostring(m.count or '') end
    big_text(txt, PX + 9 * mult, PY + 6 * mult, 22 * mult, m.color)
    -- spare-mag pips inside the panel right half
    if m.spare_kind == 'mags' then
      local n = math.max(0, m.spare or 0)
      local total = math.max(ref, n, 1)
      if total <= 12 then
        local cols = math.min(6, total)
        for i = 0, total - 1 do
          local px = PX + 60 * mult + (i % cols) * 5 * mult
          local py = PY + 5 * mult + math.floor(i / cols) * 13 * mult
          if i < n then
            sc:add('rect', { x = px, y = py, w = 3.4 * mult, h = 8.4 * mult },
                   colors.alpha(colors.from_hex('#d4b054'), 0.97))
            sc:add('tri', { x1 = px, y1 = py, x2 = px + 3.4 * mult, y2 = py,
                            x3 = px + 1.7 * mult, y3 = py - 2.4 * mult },
                   colors.alpha(colors.from_hex('#e0cf94'), 0.97))
          else
            sc:add('rect', { x = px, y = py, w = 3.4 * mult, h = 8.4 * mult },
                   colors.alpha(colors.from_hex('#d9d9d9'), 0.2))
          end
        end
      else
        horiz_bar(sc, colors, PX + 60 * mult, PY + 14 * mult, 52 * mult, 5 * mult,
                  n / total, colors.from_hex('#d4b054'))
      end
    end
    -- support guns fed from a backpack (mortar etc): magazine bars in the tray
    if m.pack then
      tray(sc, colors, PX, PY + PH, PW, mult)
      local remain = math.max(0, m.pack.remain or 0)
      local total2 = math.max(m.pack.total or 0, remain, 1)
      if total2 > 11 then total2 = 11 end
      for i = 0, total2 - 1 do
        if i < remain then
          sc:add('rect', { x = PX + 4 * mult + i * 10 * mult, y = PY + PH + 5 * mult,
                           w = 6 * mult, h = 8 * mult },
                 colors.alpha(colors.from_hex('#d9d9d9'), 0.92))
        else
          sc:add('rect', { x = PX + 4 * mult + i * 10 * mult, y = PY + PH + 12.4 * mult,
                           w = 6 * mult, h = 1.6 * mult },
                 colors.alpha(colors.from_hex('#d9d9d9'), 0.28))
        end
      end
    end
  else
    panel_bg()   -- charge-only guns still get the station
  end

  -- charge gauge: strip inside a sub-tray drawer flush to the panel
  if m.charge_pct then
    local ox3, oy3 = off(LAY, 'charge', mult)
    tray(sc, colors, PX, PY + PH, PW, mult)
    local cx0, cy0 = PX + 2 * mult + ox3, PY + PH + 7 * mult + oy3
    sc:add('rect', { x = cx0, y = cy0, w = PW, h = 4 * mult },
           colors.alpha(colors.from_hex('#12212b'), 0.6))
    local f = math.max(0, math.min(1, m.charge_pct))
    if f > 0.003 then
      sc:add('rect', { x = cx0, y = cy0, w = PW * f, h = 4 * mult },
             colors.alpha(colors.from_hex(f >= 1 and '#66e0ff' or '#3fa8d8'), 0.95))
    end
    sc:add('rect', { x = cx0 + PW - 1.2 * mult, y = cy0 - 1 * mult, w = 1.2 * mult, h = 6 * mult },
           colors.alpha(colors.from_hex('#66e0ff'), 0.55))
  end

  -- == dashboard chrome: brackets + hint ==
  if LAY.active then
    local id = LAY.current()
    local b = LAY.box[id]
    if b then
      local ox, oy = off(LAY, id, mult)
      bracket(sc, colors, (b.x + ox / mult) * mult, (b.y + oy / mult) * mult, b.w * mult, b.h * mult)
    end
    -- == control panel: the whole editor lives on screen ==
    local px, py, pw2, ph2 = -150 * mult, 58 * mult, 236 * mult, 64 * mult
    sc:add('rect', { x = px, y = py, w = pw2, h = ph2 },
           colors.alpha(colors.from_hex('#0b0c0a'), 0.82))
    sc:add('rect', { x = px, y = py, w = pw2, h = 1.4 * mult },
           colors.alpha(colors.from_hex('#7fd4ff'), 0.55))
    sc:add('text', { str = 'DBF LAYOUT  ' .. (LAY.names[id] or id) ..
                     string.format('  (%d/%d)', LAY.sel or 1, #LAY.order),
                     x = px + 6 * mult, y = py + 6 * mult, size = 12 * mult, align = 'left' },
           colors.alpha(colors.from_hex('#7fd4ff'), 0.98))
    local ox2, oy2 = LAY.get(id)
    sc:add('text', { str = string.format('x %+d  y %+d', math.floor(ox2), math.floor(oy2)),
                     x = px + 6 * mult, y = py + 22 * mult, size = 10 * mult, align = 'left' },
           colors.alpha(colors.from_hex('#c8d0d4'), 0.85))
    local function keycap(kx, ky, label, hint)
      local kw = #label * 6.2 * mult + 8 * mult
      sc:add('rect', { x = kx, y = ky, w = kw, h = 11 * mult },
             colors.alpha(colors.from_hex('#26292b'), 0.95))
      sc:add('rect', { x = kx, y = ky, w = kw, h = 0.9 * mult },
             colors.alpha(colors.from_hex('#9aa4a8'), 0.35))
      sc:add('text', { str = label, x = kx + kw / 2, y = ky + 3 * mult, size = 9 * mult, align = 'center' },
             colors.alpha(colors.from_hex('#e8e8e8'), 0.95))
      sc:add('text', { str = hint, x = kx + kw / 2, y = ky + 15 * mult, size = 8 * mult, align = 'center' },
             colors.alpha(colors.from_hex('#8899aa'), 0.85))
      return kx + kw + 6 * mult
    end
    local kx = px + 6 * mult
    kx = keycap(kx, py + 32 * mult, 'TAB', 'next')
    kx = keycap(kx, py + 32 * mult, 'WASD+ARROWS', 'move')
    kx = keycap(kx, py + 32 * mult, 'ENTER', 'save')
    kx = keycap(kx, py + 32 * mult, 'ESC', 'exit+save')
    -- element strip: current highlighted
    for li = 1, #LAY.order do
      local lx = px + 6 * mult + (li - 1) * 33 * mult
      if li == LAY.sel then
        sc:add('rect', { x = lx, y = py + 54 * mult, w = 31 * mult, h = 6 * mult },
               colors.alpha(colors.from_hex('#7fd4ff'), 0.28))
      end
      sc:add('text', { str = (LAY.names[LAY.order[li]] or '?'):sub(1, 5),
                       x = lx + 1 * mult, y = py + 55 * mult, size = 5.5 * mult, align = 'left' },
             colors.alpha(colors.from_hex(li == LAY.sel and '#7fd4ff' or '#8899aa'), 0.9))
    end
  end
end

return M

end
__hd2ui_modules['hd2ui.ammo_layout'] = function()
-- hd2ui/ammo_layout.lua -- Dashboard layout state for the ammo HUD.
--
-- Every graphical element has an id, a default anchor (defined by the style /
-- bars code) and a user offset (dx, dy) in 1080p reference units. A layout
-- mode (toggled by a user-bound key via ModBindingsMenu) turns the HUD into a
-- live editor: select an element, nudge it with bound directions, save. Offsets
-- persist to a plain text file (in-game io is available on the live install).
--
-- Element boxes are used to draw selection brackets; they are coarse on
-- purpose -- the bracket is a grab handle, not a bounding-rect proof.
--
-- Lua 5.1 / LuaJIT.

local M = {}

M.active = false        -- dashboard mode on/off
M.sel = 1               -- index into M.order
M.order = { 'label', 'mag', 'pack', 'heat', 'fuel', 'charge' }   -- 'pips' folded into 'label' module
-- station geometry (y-down, 1080p units): the unified panel lives at x=34..
M.box = {
  label  = { x = 34, y = -17, w = 120, h = 46 },   -- charcoal plate + tray
  mag    = { x = 34, y = -17, w = 30, h = 34 },    -- AC column + count zone
  pack   = { x = 90, y = -12, w = 72, h = 26 },    -- AC magazine bars area
  heat   = { x = 34, y = -17, w = 120, h = 46 },   -- plate w/ heat bar + sinks
  fuel   = { x = 34, y = -17, w = 128, h = 34 },   -- plate w/ integrated dial
  charge = { x = 36, y = 21, w = 116, h = 13 },    -- sub-tray strip
  pips   = { x = 88, y = -12, w = 62, h = 26 },    -- legacy: rifle pip area
}
M.names = {
  label = 'COUNTER TEXT', mag = 'MAG COLUMN', pack = 'BACKPACK PANEL',
  heat = 'HEAT GAUGE', fuel = 'FUEL DIAL', charge = 'CHARGE BAR', pips = 'SPARE PIPS',
}

local offsets = {}
for _, id in ipairs(M.order) do offsets[id] = { x = 0, y = 0 } end

function M.get(id)
  local o = offsets[id]
  if not o then return 0, 0 end
  return o.x, o.y
end

function M.nudge(id, dx, dy)
  local o = offsets[id]
  if o then o.x = o.x + dx; o.y = o.y + dy end
end

function M.cycle(dir)
  M.sel = M.sel + (dir or 1)
  if M.sel > #M.order then M.sel = 1 end
  if M.sel < 1 then M.sel = #M.order end
end

function M.current() return M.order[M.sel] end

------------------------------------------------------------------------------
-- persistence: one line per element 'id dx dy' (integers, reference units)
------------------------------------------------------------------------------
function M.load(path)
  if not path then return false end
  local ok, f = pcall(io.open, path, 'r')
  if not ok or not f then return false end
  local n = 0
  for line in f:lines() do
    local id, x, y = line:match('^(%w+)%s+(-?%d+)%s+(-?%d+)$')
    if id and offsets[id] then
      offsets[id].x = tonumber(x); offsets[id].y = tonumber(y); n = n + 1
    end
  end
  f:close()
  return n > 0, n
end

function M.save(path)
  if not path then return false end
  local ok, f = pcall(io.open, path, 'w')
  if not ok or not f then return false end
  f:write('# dbf ammo hud layout (1080p reference units)\n')
  for _, id in ipairs(M.order) do
    f:write(id .. ' ' .. math.floor(offsets[id].x) .. ' ' .. math.floor(offsets[id].y) .. '\n')
  end
  f:close()
  return true
end

------------------------------------------------------------------------------
-- input pump: pure logic over an injected down(vk) predicate -- unit-testable
-- and independent of ffi/binding availability. arrows+WASD move, TAB cycles,
-- ENTER saves, ESC exits (auto-saves).
M.prev = {}
M.nat = 0
function M.poll(clock, down)
  if not M.active then M.prev = {} return nil end
  local id = M.current()
  local function edge(vk)
    local d = down(vk)
    local e = d and not M.prev[vk]
    M.prev[vk] = d
    return e
  end
  local function hold(vk, dx, dy)
    local d = down(vk)
    if d and (not M.prev[vk] or clock >= M.nat) then
      M.nat = clock + 0.07
      M.nudge(id, dx, dy)
    end
    M.prev[vk] = d
  end
  hold(0x25, -3, 0)  -- left
  hold(0x27, 3, 0)   -- right
  hold(0x26, 0, -3)  -- up   (positive y = DOWN on screen, field-confirmed)
  hold(0x28, 0, 3)   -- down
  hold(0x41, -3, 0)  -- a
  hold(0x44, 3, 0)   -- d
  hold(0x57, 0, -3)  -- w
  hold(0x53, 0, 3)   -- s
  if edge(0x09) then M.cycle(1) end
  if edge(0x0D) then return 'save' end
  if edge(0x1B) then
    M.active = false
    return 'exit'
  end
  return nil
end

return M

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
local BARS = __hd2ui_require('hd2ui.ammo_bars')

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
  local scene, layout, colors = base_setup(api)
  local sc = scene.new()
  local gfx_reported = false
  return {
    style = 'crosshair',
    frame = function(model, backend, w, h)
      if cfg.display == 'graphical' then
        sc:clear()
        BARS.draw(sc, model, (cfg.scale or 1.0), colors)
        local s = layout.scale_factor(h, 1.0)
        local ox, oy = layout.place(w, h, 990, 540, s)   -- right of the reticle
        local dl = {}
        sc:render(dl, ox, oy, s)
        if cfg.log and not gfx_reported then
          gfx_reported = true
          local nr, nt = 0, 0
          for _, el in ipairs(sc.elements) do
            if el.kind == 'rect' then nr = nr + 1 elseif el.kind == 'text' then nt = nt + 1 end
          end
          cfg.log(string.format('GFX crosshair prims=%d rects=%d texts=%d label=%s spare=%s kind=%s',
            sc:count(), nr, nt, tostring(model.label),
            tostring(model.spare), tostring(model.spare_kind)))
        end
        backend.emit(dl, cfg.opacity or 0.9)
        return
      end
      counter.frame(model, backend, w, h)
    end,
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
  local sc_reported = false
  local col = (type(cfg.color) == 'string') and colors.from_hex(cfg.color) or (cfg.color or colors.from_hex('#f2f2f2'))
  local size_mult = (cfg.scale or 1.0)
  -- Reference anchor (1080p): right-of-center, below the midline.
  local ref_x, ref_y = cfg.ref_x or 1285, cfg.ref_y or 705

  local function build(model)
    sc:clear()
    if cfg.display == 'graphical' then
      BARS.draw(sc, model, size_mult, colors)
      if cfg.log and not sc_reported then
        sc_reported = true
        local nr, nt = 0, 0
        for _, el in ipairs(sc.elements) do
          if el.kind == 'rect' then nr = nr + 1 elseif el.kind == 'text' then nt = nt + 1 end
        end
        cfg.log(string.format('GFX gunside prims=%d rects=%d texts=%d label=%s spare=%s kind=%s',
          sc:count(), nr, nt, tostring(model.label),
          tostring(model.spare), tostring(model.spare_kind)))
      end
      return
    end
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

  local obj
  obj = {
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
  cfg.display = cfg.display or 'text'
  local f = M.styles[name] or M.styles.crosshair
  return f(api, cfg or {})
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
do
-- hd2ui/ammo_entry.lua -- DBF Ammo HUD: in-game entry. Requires the HD2UI
-- framework addon (a SEPARATE Arsenal mod: __hd2ui_require('mods/dbf/hd2ui')) and adds:
--   * content-anchor ammo reading (GUID scan -> validate -> lock -> read)
--   * per-build cache fast path (instant boot when the cached base revalidates)
--   * style switching via the BSL/Arsenal Mod Options menu (preset lua
--     resources the manager deploys next to the addon)
--   * a stingray capability probe logging whether world-space text / camera
--     projection exist in this loader build
--
-- Everything here is a CONSUMER: framework modules are never modified; the
-- ammo product parts are memreader (transport) + live_scan (regions) +
-- ammo_reader (anchor decode/gates) + ammo_cache (fast boot) + ammo_styles.
--
-- Display-only: reads own process, no writes, no game calls, no input hooks.
-- Lua 5.1 / LuaJIT.

local sr = rawget(_G, 'stingray')
if type(sr) ~= 'table' then return { installed = false, reason = 'no stingray' } end
if rawget(_G, '__DBF_AMMO_INSTALLED') then return { installed = true } end

local MR = __hd2ui_require('hd2ui.memreader')
local LS = __hd2ui_require('hd2ui.live_scan')
local A  = __hd2ui_require('hd2ui.ammo_reader')
local AC = __hd2ui_require('hd2ui.ammo_cache')
local STYLES = __hd2ui_require('hd2ui.ammo_styles')
local BARS = __hd2ui_require('hd2ui.ammo_bars')
local CH   = __hd2ui_require('hd2ui.ammo_chain')
local LAY  = __hd2ui_require('hd2ui.ammo_layout')

-- raw keyboard for the layout editor (RAH-style: no keybinding ceremony).
-- cdef collision in the SHARED LuaJIT state is expected (other mods declare
-- this too) -- identical declarations merge; if resolve fails, MBM bindings
-- remain the fallback path.
local GAKS
do
  pcall(function() ffi.cdef('short __stdcall GetAsyncKeyState(int vKey);') end)
  -- ffi.C does NOT see user32 exports in the game's import table; the symbol
  -- must come from an explicit ffi.load('user32') (same pattern memreader
  -- uses for kernel32). ffi.C stays as a lucky-draw fallback.
  local ok, user32 = pcall(function() return ffi.load('user32') end)
  if ok and user32 then pcall(function() GAKS = user32.GetAsyncKeyState end) end
  if not GAKS then pcall(function() GAKS = ffi.C.GetAsyncKeyState end) end
end
local function key_down(vk)
  if not GAKS then return false end
  local ok, s = pcall(GAKS, vk)
  if not ok then return false end
  local u = s < 0 and (65536 + s) or s
  return u >= 0x8000
end

LS.set_transport(MR)
A.set_transport(MR)


local VERSION = 'dbf-ammo r8.1'
local MATERIAL = 'mods/dbf/hd2ui/solid'   -- provided by the framework addon
local SCAN_BUDGET = 4 * 1048576             -- bytes per frame for background locate
local SCAN_WINDOW = 65536                   -- read granularity (few big RPM calls, not page pokes)
local MAX_ERRORS = 50

local DEFAULTS = {
  weapon = 'r4_deadeye',   -- anchor key in ammo_reader's table
  style = 'crosshair',     -- crosshair | gunside | world
  size = 100,              -- percent
  color = '#f2f2f2',
  opacity = 0.9,
  side = 'right', offset_x = 140, offset_y = 0,
  hidden = false, display = 'text',
}

------------------------------------------------------------------------------
-- Logging: %APPDATA%/Arrowhead/Helldivers2/hd2ui_ammo.log
------------------------------------------------------------------------------
local log_path
do
  local ok, d = pcall(os.getenv, 'DBF_AMMO_DIR')
  if (not ok or type(d) ~= 'string' or d == '') then
    local ok2, appdata = pcall(os.getenv, 'APPDATA')
    if ok2 and type(appdata) == 'string' and appdata ~= '' then d = appdata .. '/Arrowhead/Helldivers2' end
  end
  if type(d) == 'string' and d ~= '' then log_path = d .. '/hd2ui_ammo.log' end
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
-- Framework resolution (separate addon). Two paths, loader-order agnostic:
-- the global the framework chunk installs when it executes, or a direct
-- resource require. Fail = log + no install (no crash; dependency missing).
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
-- Mod Options menu: the manager deploys chosen options as tiny lua resources
-- (the BSL/Arsenal mechanism; ours reimplemented). Read via the game's
-- require; anything invalid falls back to DEFAULTS.
------------------------------------------------------------------------------
local CONFIG = {}
for k, v in pairs(DEFAULTS) do CONFIG[k] = v end
do
  local function preset(name)
    local full = 'mods/dbf/ammo/preset_' .. name
    local ok, has = pcall(sr.Application.can_get, 'lua', full)
    if not ok or not has then return nil end
    local okr, v = pcall(function() return __hd2ui_require(full) end)
    return okr and v or nil
  end
  local st = preset('style')
  if st == 'crosshair' or st == 'gunside' or st == 'world' then CONFIG.style = st end
  local sz = tonumber(preset('size'))
  if sz and sz >= 50 and sz <= 400 then CONFIG.size = sz end
  log(string.format('PRESETS style=%s size=%d (from mod options)', CONFIG.style, CONFIG.size))
end

------------------------------------------------------------------------------
-- Stingray capability probe: does THIS loader expose anything for world-space
-- text or camera projection? Evidence over guesses -- the log answers whether
-- the 'world' style can ever do more than its screen fallback.
------------------------------------------------------------------------------
do
  for _, k in ipairs({ 'World', 'Gui', 'Application', 'Debug' }) do
    local t = sr[k]
    if type(t) == 'table' then
      local names = {}
      for key, _ in pairs(t) do names[#names + 1] = tostring(key) end
      table.sort(names)
      log('SRAPI sr.' .. k .. ': ' .. table.concat(names, ','))
    end
  end
  for _, w in ipairs({ 'camera', 'project', 'world_to', 'screen_to', 'unproject',
                       'view', 'transform', 'label' }) do
    if type(rawget(_G, w)) == 'table' then log('SRAPI _G.' .. w .. ' exists') end
  end
end

------------------------------------------------------------------------------
-- Attach to ourselves and enumerate regions (in-process: full heap access).
------------------------------------------------------------------------------
-- attach() with our own pid selects the self-read backend inside memreader:
-- GetCurrentProcess pseudo handle + alias-bound RPM. No OpenProcess at boot.
local self_pid = MR.self_pid and MR.self_pid() or nil
local ok_att, att_err = MR.attach(self_pid, 'helldivers2.exe')
if not ok_att then
  log('ATTACH_FAIL ' .. tostring(att_err))
  return { installed = false, reason = 'attach failed' }
end
A.set_anchor_weapon(CONFIG.weapon)
local PATTERN = A.anchor_pattern()

-- Stamp of the running game.dll (cache key). Fallback 0 when game.dll is
-- unreadable (headless test hosts): cache entries are still gated by the
-- full structural validation, the stamp only scopes them per build.
-- Toolhelp module lookup + PE stamp are best-effort at boot: if anything in
-- this chain fails or is gated, STAMP=0 scopes the cache to self-validated
-- entries only (every use re-runs the full structural gates regardless).
local MODULE_BASE, STAMP
local okmb, mb = pcall(LS.module_base, self_pid, 'game.dll')
MODULE_BASE = (okmb and mb) or nil
if MODULE_BASE then
  local okp, sp = pcall(AC.pe_stamp, MR.read_u32, MODULE_BASE)
  STAMP = (okp and sp) or 0
end
STAMP = STAMP or 0
local CACHE_FILE = (log_path and log_path:gsub('hd2ui_ammo%.log$', 'dbf_ammo_cache.txt')) or nil
local LAYOUT_FILE = (log_path and log_path:gsub('hd2ui_ammo%.log$', 'dbf_ammo_layout.txt')) or nil
BARS.LAY = LAY
if LAY.load(LAYOUT_FILE) then log('LAYOUT loaded from ' .. tostring(LAYOUT_FILE)) end
log('LAYOUT input: raw keyboard ' .. (GAKS and 'ACTIVE' or 'unavailable (use bound keys)'))

-- RAH-method chain resolver: instant, module-rooted, signature-verified.
-- When available it replaces the anchor scan entirely (which survives only as
-- the patch-day fallback). Idle statuses (no weapon, sprint, dead) are normal
-- life; only LAYOUT failures (bad reads, owner mismatches, budget) disqualify
-- the chain after a few samples.
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
      CHAIN.boot_off = true   -- signature/layout genuinely unknown to us:
      log('CHAIN unavailable: ' .. tostring(ver_err or 'init') .. ' -- anchor fallback armed')
    end
  else
    CHAIN.boot_off = true     -- no module base: anchor owns resolution
  end
end

local S = {
  clock = 0, retry_at = 0, errors = 0, disabled = false,
  state = 'scan',           -- 'scan' | 'locked'
  scan = nil,               -- { ri, pos, hits }
  next_scan_at = 0,         -- rescan scheduling
  key = nil,                -- render signature
  pct = 0,                  -- scan progress (visible in HUD while unresolved)
  last = nil,               -- last sweep verdict: 'nohit' | 'raw<n>'
  last_base = nil,          -- last locked component base (in-process continuity)
  probe_until = 0,          -- probe deadline
}

local backend = HD2.backend_stingray.new({ material = MATERIAL, log = log })

local STYLE_ORDER = { 'crosshair', 'gunside', 'world' }
local SIZE_ORDER = { 50, 75, 100, 125, 150, 200 }
local S_TOAST = nil   -- {text=, until=}

local hud
local function rebuild_hud()
  hud = STYLES.new(CONFIG.style, HD2, {
    scale = CONFIG.size / 100, opacity = CONFIG.opacity, color = CONFIG.color,
    side = CONFIG.side, offset_x = CONFIG.offset_x, offset_y = CONFIG.offset_y,
    display = CONFIG.display,
    log = log,         -- styles self-report graphical frames here
    projector = nil,   -- wired when the camera-chain projector lands
  })
  S.key = nil   -- force redraw
  log('STYLE ' .. CONFIG.style .. ' size=' .. CONFIG.size .. '%' ..
      ' display=' .. CONFIG.display
    .. (hud.provisional and ' (provisional screen anchor until camera projection)' or ''))
end
rebuild_hud()

local function toast(text)
  S_TOAST = { text = text, expires = S.clock + 2.0 }
end

local function idx_of(list, v)
  for i = 1, #list do if list[i] == v then return i end end
end

-- In-game options: ModBindingsMenu (when installed) gives these native rows on
-- the game's MODS tab (Options > Controls); the user binds the keys. Soft
-- dependency: absent menu = Arsenal preset defaults only, everything else works.
local MBM = { api = nil, tried_at = 0, bound = {}, down = {} }
local MBM_ACTIONS = {
  { id = 'dbf_ammo_cycle_style', label = 'DBF Ammo: Cycle HUD Style',
    act = function()
      local i = idx_of(STYLE_ORDER, CONFIG.style) or 1
      local next_idx = (i % #STYLE_ORDER) + 1
      if not mom_set('dbf_ammo_style', next_idx) then   -- menu syncs + applies
        CONFIG.style = STYLE_ORDER[next_idx]
        rebuild_hud()
      end
      toast(STYLE_ORDER[next_idx])
    end },
  { id = 'dbf_ammo_size_up', label = 'DBF Ammo: Text Size Up',
    act = function()
      local i = idx_of(SIZE_ORDER, CONFIG.size) or 3
      local nv = math.min(200, CONFIG.size + 25)
      if not mom_set('dbf_ammo_size', nv) then
        CONFIG.size = SIZE_ORDER[math.min(#SIZE_ORDER, i + 1)]
        rebuild_hud()
      end
      toast((nv or CONFIG.size) .. '%')
    end },
  { id = 'dbf_ammo_size_down', label = 'DBF Ammo: Text Size Down',
    act = function()
      local i = idx_of(SIZE_ORDER, CONFIG.size) or 3
      local nv = math.max(50, CONFIG.size - 25)
      if not mom_set('dbf_ammo_size', nv) then
        CONFIG.size = SIZE_ORDER[math.max(1, i - 1)]
        rebuild_hud()
      end
      toast(nv .. '%')
    end },
  { id = 'dbf_ammo_toggle', label = 'DBF Ammo: Toggle HUD',
    act = function()
      if not mom_set('dbf_ammo_enabled', not not CONFIG.hidden) then
        CONFIG.hidden = not CONFIG.hidden
      end
      toast(CONFIG.hidden and 'hidden' or 'visible')
    end },
  { id = 'dbf_ammo_layout_mode', label = 'DBF Ammo: Layout Mode',
    act = function()
      LAY.active = not LAY.active
      if not LAY.active then
        LAY.save(LAYOUT_FILE)
        toast('layout saved')
      else
        toast('LAYOUT: ' .. (LAY.names[LAY.current()] or '?'))
      end
    end },
  { id = 'dbf_ammo_layout_next', label = 'DBF Ammo: Layout Next Element',
    act = function()
      LAY.cycle(1)
      toast(LAY.names[LAY.current()] or '?')
    end },
  { id = 'dbf_ammo_layout_left', label = 'DBF Ammo: Layout Left', hold = true,
    act = function() if LAY.active then LAY.nudge(LAY.current(), -3, 0) end end },
  { id = 'dbf_ammo_layout_right', label = 'DBF Ammo: Layout Right', hold = true,
    act = function() if LAY.active then LAY.nudge(LAY.current(), 3, 0) end end },
  { id = 'dbf_ammo_layout_up', label = 'DBF Ammo: Layout Up', hold = true,
    act = function() if LAY.active then LAY.nudge(LAY.current(), 0, -3) end end },
  { id = 'dbf_ammo_layout_down', label = 'DBF Ammo: Layout Down', hold = true,
    act = function() if LAY.active then LAY.nudge(LAY.current(), 0, 3) end end },
  { id = 'dbf_ammo_layout_save', label = 'DBF Ammo: Layout Save',
    act = function() LAY.save(LAYOUT_FILE); toast('SAVED') end },
}
-- Mod Options Menu (_G.ModOptionsMenu): native MODS page inside the game's
-- OPTIONS menu with toggle/choice/slider rows + APPLY persistence. When it is
-- installed it becomes the primary settings surface; MBM keybinds and Arsenal
-- presets both feed the same CONFIG (bidirectionally synced).
local MOM = { api = nil, tried_at = 0, reg = {} }
local function mom_apply(key, value)
  if key == 'dbf_ammo_style' then
    CONFIG.style = STYLE_ORDER[value or 1] or 'gunside'
  elseif key == 'dbf_ammo_size' then
    CONFIG.size = value or 100
  elseif key == 'dbf_ammo_display' then
    CONFIG.display = (value == 2) and 'graphical' or 'text'
  elseif key == 'dbf_ammo_enabled' then
    CONFIG.hidden = not value
  elseif key == 'dbf_ammo_layout' then
    LAY.active = value and true or false
    if not LAY.active then LAY.save(LAYOUT_FILE) end
  end
  rebuild_hud()
end

local function mom_register()
  local api = MOM.api
  local style_idx = math.max(1, idx_of(STYLE_ORDER, CONFIG.style) or 2)
  local specs = {
    { id = 'dbf_ammo_style', spec = { type = 'choice', label = 'HUD style', mod = 'DBF Ammo HUD',
        choices = { 'Crosshair', 'Gunside', 'World (beta)' }, default = style_idx,
        description = 'Where the ammo readout sits. World is experimental.' } },
    { id = 'dbf_ammo_size', spec = { type = 'slider', label = 'Text size', mod = 'DBF Ammo HUD',
        min = 50, max = 200, step = 25, default = CONFIG.size,
        description = 'HUD text scale percentage.' } },
    { id = 'dbf_ammo_display', spec = { type = 'choice', label = 'Display mode', mod = 'DBF Ammo HUD',
        choices = { 'Text', 'Graphical' }, default = CONFIG.display == 'graphical' and 2 or 1,
        description = 'Graphical: heat/fuel bars, spare-mag bar, numeric counter.' } },
    { id = 'dbf_ammo_enabled', spec = { type = 'toggle', label = 'HUD enabled', mod = 'DBF Ammo HUD',
        default = not CONFIG.hidden, description = 'Master switch for the ammo readout.' } },
    { id = 'dbf_ammo_layout', spec = { type = 'toggle', label = 'Layout editor mode', mod = 'DBF Ammo HUD',
        default = false,
        description = 'On-screen HUD mover: WASD/arrows move, TAB next, ENTER save, ESC exit+save. Turning OFF also saves.' } },
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

local function mom_set(id, value)
  if MOM.api and MOM.reg[id] then
    local okf = pcall(MOM.api.set, id, value)
    if okf then return true end
  end
  return false
end

local function mbm_poll()
  if MBM.api then
    for _, a in ipairs(MBM_ACTIONS) do
      if MBM.bound[a.id] then
        local ok, d = pcall(MBM.api.is_down, a.id)
        local now = ok and d == true
        if now and not MBM.down[a.id] then pcall(a.act) end
        if a.hold and now and S.clock >= (a.next_at or 0) then
          a.next_at = S.clock + 0.08
          pcall(a.act)
        end
        MBM.down[a.id] = now
      end
    end
    return
  end
  if S.clock < MBM.tried_at then return end
  MBM.tried_at = S.clock + 1
  local api = rawget(_G, 'ModBindingsMenu')
  if type(api) ~= 'table' or type(api.register_binding) ~= 'function' then return end
  if type(api.ready) == 'function' and not api.ready() then return end   -- input tables not built yet
  MBM.api = api
  for _, a in ipairs(MBM_ACTIONS) do
    local ok = pcall(api.register_binding, a.id, a.label, nil, { category = 'DBF Ammo HUD' })
    MBM.bound[a.id] = ok and true or false
  end
  log('MBM bindings registered: ' .. tostring(#MBM_ACTIONS))
end

------------------------------------------------------------------------------
-- Cache fast path: try the last validated base (per-build stamp key) BEFORE
-- paying for a full heap scan (~2.5 min). Goes through the exact same
-- structural gates as the scan lock (flag==1, aim f32 range, mag<=capacity,
-- reserve sane), so a stale or foreign base can never render a wrong number
-- -- it fails validation and falls through to scanning. Same-session mission
-- restarts and stale recovery lock on the first frame when it still holds.
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

------------------------------------------------------------------------------
-- Frame-budgeted anchor scan (same shape as derive's step_scan, inlined so
-- the HUD never blocks a frame).
------------------------------------------------------------------------------
local function start_scan()
  local ok, n = LS.enum_regions()
  if not ok then
    log('ENUM_FAIL ' .. tostring(n))
    S.next_scan_at = S.clock + 15
    return
  end
  -- Sweep order: biggest regions first, private above image. Ammo components
  -- live in large private arenas (observed: multi-MB, high addresses); image
  -- regions mostly hold the registry copy. Address order is what made sweeps
  -- take minutes to reach the payload.
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

-- Single-hit lock attempt: ammo_reader's structural gates (flag==1, aim f32
-- range, mag<=capacity, reserve sane) reject registry/blob copies and our own
-- pattern string. First hit that survives = the lock. Shared by the early-exit
-- mid-scan path (step_scan calls it per window) and the end-of-sweep batch.
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
  S.next_scan_at = S.clock + 30   -- retry later (mid-loadout etc.)
  return false
end

local function step_scan()
  local sc = S.scan
  local st = LS.state()
  local regions = st.regions
  local plen = #PATTERN
  local budget = SCAN_BUDGET
  while budget > 0 do
    if sc.ri >= #regions then
      sc.done = true
      break
    end
    S.pct = math.floor(100 * sc.ri / math.max(1, #regions))
    local r = regions[sc.ri + 1]
    if not r then sc.ri = sc.ri + 1 sc.pos = 0
    elseif sc.pos >= r.size then sc.ri = sc.ri + 1 sc.pos = 0
    else
      local n = math.min(SCAN_WINDOW, r.size - sc.pos)
      local data = MR.read(r.base + sc.pos, n)
      if data then
        local from = 1
        while true do
          local s = data:find(PATTERN, from, true)
          if not s then break end
          local hit = r.base + sc.pos + (s - 1)
          -- early-exit: validate immediately; first hit that survives the
          -- structural gates locks NOW, mid-scan, no full sweep required
          if try_lock(hit) then return end
          sc.hits[#sc.hits + 1] = hit
          from = s + 1
        end
        budget = budget - #data
        sc.pos = sc.pos + math.max(1, #data - (plen - 1))
      else
        budget = budget - SCAN_WINDOW   -- failed spans also cost the frame budget
        sc.pos = sc.pos + SCAN_WINDOW
      end
    end
  end
  if sc.done and #sc.hits > 0 then validate_and_lock(sc.hits) end
end

------------------------------------------------------------------------------
-- Frame: resolve -> read -> render.
------------------------------------------------------------------------------
local STATUS_MARK = {
  no_local_player = '.p', no_avatar = '.a', avatar_entity_missing = '.ae',
  no_inventory = '.i', no_weapon_slot = '.s', weapon_entity_missing = '.w',
  no_weapon_driver = '.d', no_ammo_component = '.n', player_not_owned = '.po',
  avatar_not_owned = '.ao', in_vehicle = '.v',
  unsupported_resource_ammo = '.u',
}
local LAYOUT_MARK = { ['.r'] = true, ['.m'] = true, ['.o'] = true,
                      ['.b'] = true, ['.z'] = true, ['.e'] = true }
local function mark(status)
  if STATUS_MARK[status] then return STATUS_MARK[status] end
  if type(status) == 'string' and status:find('^error') then
    if status:find('unreadable') then return '.r' end
    if status:find('map probe') then return '.m' end
    if status:find('owner mismatch') then return '.o' end
    if status:find('budget') then return '.b' end
    if status:find('null pointer') then return '.z' end
    return '.e'
  end
  return '.?'
end
local IDLE_STATUS = { no_local_player = true, no_avatar = true, avatar_entity_missing = true,
  no_inventory = true, no_weapon_slot = true, weapon_entity_missing = true,
  no_weapon_driver = true, no_ammo_component = true, in_vehicle = true,
  player_not_owned = true, avatar_not_owned = true }

local function chain_model()
  local row = CHAIN.last
  if row.charge_only then
    -- Arc-thrower: no number, no rack -- just the charge gauge
    return { count = 0, label = '', capacity = 1,
             weapon_key = row.weapon_id, charge_pct = row.charge_pct }
  end
  if row.path == 'resource' then
    local pct = math.floor((row.fuel or 0) * 100 + 0.5)
    -- fuel reads percentage-first, always: % / tanks (multi-tank) or
    -- % / total units (single shared pool like the Cremator)
    local label
    if row.spare ~= nil then label = string.format('%d%% / %d', pct, row.spare)
    else label = string.format('%d%%', pct) end
    return { count = row.spare or pct, label = label, capacity = 100,
             spare_kind = row.spare_kind,
             weapon_key = row.weapon_id,
             fuel_frac = row.fuel or 0, charge_pct = row.charge_pct }
  end
  if row.path == 'heat' then
    local pct = 0
    if row.heat_max and row.heat_max > 0 then
      pct = math.floor(row.heat / row.heat_max * 100 + 0.5)
    end
    local label
    if row.overheated then label = string.format('HEAT %d%% (LOCK)', pct)
    elseif row.spare ~= nil then label = string.format('HEAT %d%% / %d', pct, row.spare)
    else label = string.format('HEAT %d%%', pct) end
    local heat_frac = (row.heat and row.heat_max) and math.min(1, row.heat / row.heat_max) or 0
    return { count = pct, label = label, capacity = 100,
             weapon_key = row.weapon_id,
             heat_frac = heat_frac, heat_lock = row.overheated, heat_pct = pct,
             spare = row.spare, spare_kind = row.spare_kind,
             spare_max = row.spare_max or row.sinks_max }
  end
  local cap = row.capacity or 0
  local shown = row.rounds + (row.chamber or 0)
  -- reserve presentation follows the user's spec: everything reads as
  -- mag / REMAINING MAGAZINES. Backpack-fed weapons (flamethrower, support
  -- guns) store a round pool in the deposit; convert with the configured
  -- magazine capacity (1 for single-shot launchers = rounds == mags, exact).
  -- the deposit/provider count IS the backpack magazine/tank number (RAH
  -- reads it raw); no division.
  local reserve = row.spare
  local label
  if reserve ~= nil then label = string.format('%d/%d', shown, reserve)
  else label = tostring(shown) end
  local pack
  if row.spare_kind == 'backpack' then
    local r, tt = row.spare or 0, row.pack_total or row.spare or 0
    -- if the pool is bigger than any plausible drum count, it is measured in
    -- rounds: convert to magazines with the weapon's capacity
    if cap > 1 and (r > 15 or tt > 15) then
      r, tt = math.floor(r / cap), math.floor(tt / cap)
    end
    pack = { remain = r, total = tt }
  end
  return { count = shown, label = label, capacity = math.max(cap, 1),
           spare_kind = row.spare_kind, pack = pack, spare = row.spare,
           mag_rounds = shown, charge_pct = row.charge_pct,
           mag_cap = cap + ((row.path == 'magazine' and row.chambered) and 1 or 0) }
end

-- dashboard demo: show the CLASS that owns the selected element, so what you
-- position is what you actually use
local function layout_demo()
  local sel = LAY.current()
  if sel == 'mag' or sel == 'pack' then
    return { label = '4/10', count = 4, capacity = 10, weapon_key = 'demo',
             spare = 4, spare_kind = 'backpack', pack = { remain = 4, total = 12 },
             mag_rounds = 4, mag_cap = 10 }
  elseif sel == 'heat' then
    return { label = '62%', count = 1, capacity = 100, weapon_key = 'demo',
             heat_frac = 0.62, heat_pct = 62, spare = 3, spare_kind = 'sinks', spare_max = 6 }
  elseif sel == 'fuel' then
    return { label = '61%', count = 545, capacity = 100, weapon_key = 'demo',
             fuel_frac = 0.61, spare = 545, spare_kind = 'units' }
  elseif sel == 'charge' then
    return { label = '4/16', count = 4, capacity = 4, weapon_key = 'demo',
             spare = 16, spare_kind = 'rounds', charge_pct = 0.42 }
  end
  return { label = '30/180', count = 30, capacity = 30, weapon_key = 'demo',
           spare = 6, spare_kind = 'mags', spare_max = 8 }
end

local function model()
  if LAY.active then
    local ev = LAY.poll(S.clock, key_down)
    if ev == 'save' then
      LAY.save(LAYOUT_FILE)
      toast('layout saved')
    elseif ev == 'exit' then
      LAY.save(LAYOUT_FILE)
      S.key = nil
      toast('layout saved')
    end
    return layout_demo()
  end
  if S_TOAST and S.clock < S_TOAST.expires then
    return { count = 0, label = S_TOAST.text, capacity = 8 }
  end
  if CONFIG.hidden then
    return { count = 0, label = '', capacity = 8, hidden = true }
  end
  if CHAIN.enabled then
    if CHAIN.clock == nil then CHAIN.clock = 0 end
    if S.clock >= CHAIN.next_at then
      CHAIN.next_at = S.clock + 0.1
      local row = CH.read()
      if row.status ~= CHAIN.status then
        CHAIN.status = row.status
        -- off resets ONLY on ok reads; two failure states oscillating must
        -- still converge to the mark (R19 stale-hold bug class)
        log('CHAIN status ' .. tostring(row.status) ..
            (row.status == 'ok' and string.format(' (reads %d)', row.reads) or ''))
      end
      -- Sticky presentation: state flips only after 3 CONSECUTIVE samples in
      -- the same category (value / idle-hidden / error-mark). Transitions and
      -- flapping states can never strobe; the bridge settles to hidden.
      if row.status == 'ok' then
        CHAIN.last, CHAIN.fails = row, 0
        CHAIN.last_ok_at, CHAIN.off_run = S.clock, 0
        CHAIN.ok_run = (CHAIN.ok_run or 0) + 1
        if CHAIN.ok_run >= 2 or CHAIN.shown == 'value' then CHAIN.shown = 'value' end
      else
        CHAIN.ok_run = 0
        -- Holster-transition blips (weapon slot/driver momentarily gone) are
        -- a FREEZE, not a hide: the presentation holds whatever it was, so
        -- ok<->blip oscillation cannot strobe. They only converge to hidden
        -- once the last real 'ok' is >1.2s stale (bridge, empty hands).
        -- Presence-lost statuses (avatar/player/inventory gone -- the bridge
        -- for real) count toward hiding immediately.
        local BLIP = row.status == 'no_weapon_driver' or row.status == 'no_weapon_slot'
        if not (BLIP and (S.clock - (CHAIN.last_ok_at or -99)) < 1.2) then
          CHAIN.off_run = (CHAIN.off_run or 0) + 1
        end
        local m = mark(row.status)
        if LAYOUT_MARK[m] then
          CHAIN.fails = CHAIN.fails + 1
          if CHAIN.fails >= 15 then
            log('CHAIN disabled after repeated layout errors -- re-arming in 10s (no heap scan)')
            CHAIN.enabled = false
            CHAIN.rearm_at = S.clock + 10
            CHAIN.fails = 0
          end
        else
          CHAIN.fails = 0   -- unknown weapons are NOT a layout failure
        end
        if CHAIN.off_run >= 3 then
          CHAIN.shown = IDLE_STATUS[row.status] and 'hidden' or ('mark:' .. m)
        end
      end
      if CHAIN.shown == 'value' and CHAIN.last then
        if CHAIN.last.weapon_id == row.weapon_id then
          return chain_model()
        end
        return { count = 0, label = '', capacity = 8, hidden = true }
      elseif CHAIN.shown and CHAIN.shown:find('^mark:') then
        return { count = 0, label = CHAIN.shown:sub(6), capacity = 8 }
      end
      return { count = 0, label = '', capacity = 8, hidden = true }
    end
    if CHAIN.last then return chain_model() end
    return { count = 0, label = '', capacity = 8, hidden = true }
  end
  if CHAIN.rearm_at then   -- runtime-disabled window: hold, don't anchor-scan
    return { count = 0, label = '', capacity = 8, hidden = true }
  end
  local spec = A.anchor_spec()
  local cap = (spec and spec.capacity) or 8
  if S.state == 'locked' then
    local ammo = A.read()
    if ammo then
      return {
        count = ammo.magazine,
        label = string.format('%d/%d', ammo.magazine, ammo.reserve),
        capacity = cap,
      }
    end
    -- weapon switched / component freed: within one game process the component
    -- usually reallocates at (or near) its previous address on the next draw.
    -- Probe the last known base cheaply for a while; sweep only if that fails.
    if S.last_base then
      S.state = 'probe'
      S.probe_until = S.clock + 20
      log('STALE -> probing last base before sweep')
    else
      log('STALE -> rescanning')
      S.state = 'scan'
      start_scan()
    end
  end
  local label = '--'
  if S.state == 'probe' then label = '--.'
  elseif S.last == 'nohit' and S.clock < S.next_scan_at then label = '--nohit'
  elseif S.last and S.last:find('^raw') and S.clock < S.next_scan_at then label = '--' .. S.last
  elseif S.state == 'scan' then label = '--' .. (S.pct or 0) end
  return { count = 0, label = label, capacity = cap }
end

local function frame(dt)
  mbm_poll()
  mom_poll()
  if not backend.ensure() then return end
  if backend.cursor_visible() then
    -- menu is open: do not burn frame budget scanning
    if S.key ~= 'hidden' then backend.clear(); S.key = 'hidden' end
    return
  end
  if not CHAIN.enabled then
    if CHAIN.rearm_at and S.clock >= CHAIN.rearm_at and not CHAIN.boot_off then
      CHAIN.enabled, CHAIN.rearm_at = true, nil
      CHAIN.status, CHAIN.off, CHAIN.fails = nil, 0, 0
      log('CHAIN_REARM')
    end
  end
  if CHAIN.boot_off then
    -- anchor scan / probe machinery is reserved for builds the chain cannot
    -- verify at all (patch day); runtime weapon gaps must never degrade to it
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
  local key = table.concat({ m.label, w, h, tostring(backend.mode()), backend.generation() }, '|')
  if LAY.active then key = key .. tostring(S.clock) end   -- editor redraws live
  if key == S.key then return end
  S.key = key
  backend.clear()
  hud.frame(m, backend, w, h)
end

------------------------------------------------------------------------------
-- Hooks (same lifecycle pattern as the demo entry).
------------------------------------------------------------------------------
local old_update = rawget(_G, 'update')
if type(old_update) ~= 'function' then
  log('no global update(); not installing')
  return { installed = false, reason = 'no update' }
end
rawset(_G, '__DBF_AMMO_INSTALLED', true)

-- Try the per-build cache first (instant lock on live-reload / same session);
-- otherwise the first scan kicks off next frame (region enum can be heavy).
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
return { installed = true, version = VERSION, style = CONFIG.style, framework = HD2.version }

end
