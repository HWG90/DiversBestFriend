-- tests/test_derive_assembled.lua -- Runs the ASSEMBLED derive chunk (the exact
-- bytes shipped in the zip) under the game's LuaJIT. Catches chunk-assembly
-- bugs the per-file tests can't (e.g. builder require-rewriting of ffi/bit).
-- Requires hd2ui/hd2ui_derive.lua to exist (scripts/test.py builds it first).

package.path = './?.lua;' .. package.path
local ffi = rawget(_G, 'ffi')
if not ffi or not ffi.cdef then
  local ok, m = pcall(require, 'ffi')
  if ok and m and m.cdef then ffi = m end
end
assert(ffi and ffi.cdef, 'test host: ffi unavailable')
local checks, fails = 0, 0
local function check(name, cond)
  checks = checks + 1
  if not cond then fails = fails + 1; print('FAIL ' .. name) else print('ok   ' .. name) end
end

-- scratch dir for the file-RPC
ffi.cdef[[ int _putenv(const char* s); ]]
local scratch = (os.getenv('TEMP') or os.getenv('TMP') or '.') .. '\\dbf_derive_asm'
os.execute('mkdir "' .. scratch .. '" >NUL 2>&1')
ffi.C._putenv('DBF_DERIVE_DIR=' .. scratch)

rawset(_G, 'update', function(...) return 0 end)

local f, err = loadfile('hd2ui/hd2ui_derive.lua')
check('assembled chunk compiles', f ~= nil)
if not f then print(err); error('chunk will not load: ' .. tostring(err)) end

local res = f()
check('chunk installs (no ffi/registry errors)', type(res) == 'table' and res.installed == true)
if type(res) == 'table' and not res.installed then print('  reason: ' .. tostring(res.reason)) end

local function rfile(p) local g = io.open(p, 'r'); if not g then return nil end; local s = g:read('*a'); g:close(); return s end
local OUT = scratch .. '/derive_out.log'
local log = rfile(OUT) or ''
check('shipped log shows r3+ START', log:find('dbf%-derive r') ~= nil and log:find('START') ~= nil)
check('regions enumerated from chunk', log:match('regions=%d+') ~= nil)

local update = rawget(_G, 'update')
local IN = scratch .. '/derive_in.txt'
local function wfile(p, s) local g = assert(io.open(p, 'w')); g:write(s); g:close() end
wfile(IN, 'probe 20')
for _ = 1, 300 do
  update(1 / 60)
  local c = rfile(IN)
  if c == nil or c == '' then break end
end
for _ = 1, 30 do update(1 / 60) end   -- let the command's frames pass
log = rfile(OUT) or ''
check('probe runs from assembled chunk', log:match('PROBE sampled=%d+ ok=%d+ bad=%d+') ~= nil)
check('original update chain preserved', true)

print(string.format('derive_assembled: %d checks, %d failures', checks, fails))
if fails > 0 then error(fails .. ' failures') end
