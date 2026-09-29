-- HD2-Addon: mods/dbf/hd2ui/derive
-- hd2ui derive r11; assembled by hd2ui/build_derive.py; do not edit.
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
do
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

local MR = __hd2ui_require('hd2ui.memreader')
local LS = __hd2ui_require('hd2ui.live_scan')
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

end
