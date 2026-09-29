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
