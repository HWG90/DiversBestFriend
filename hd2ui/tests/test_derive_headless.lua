-- tests/test_derive_headless.lua -- End-to-end test of the in-game derivation
-- module WITHOUT the game: it attaches to the current process (the game's own
-- LuaJIT running inside python via run_lua.py), we plant a u32 marker in ffi
-- memory, and drive the file-RPC protocol (scan/next/watch) through it. This
-- validates exactly the machinery the live game pass will use (in-process RPM,
-- region enum, chunked scan, tag file, watch loop).
--
-- Env: DBF_DERIVE_DIR must point to a scratch dir (set by the test runner).

package.path = './?.lua;' .. package.path
local ffi = require('ffi')

local checks, fails = 0, 0
local function check(name, cond)
  checks, fails = checks + 1, fails
  if not cond then fails = fails + 1; print('FAIL ' .. name) else print('ok   ' .. name) end
end

-- Self-contained scratch dir so this runs inside the full suite too.
ffi.cdef[[ int _putenv(const char* s); ]]
local scratch = (os.getenv('TEMP') or os.getenv('TMP') or '.') .. '\\dbf_derive_test'
os.execute('mkdir "' .. scratch .. '" >NUL 2>&1')
ffi.C._putenv('DBF_DERIVE_DIR=' .. scratch)

-- derive_entry requires a global update() to wrap (as in-game).
local real_frames = 0
rawset(_G, 'update', function(...) real_frames = real_frames + 1 return 0 end)

local IN  = scratch .. '/derive_in.txt'
local OUT = scratch .. '/derive_out.log'
local TAG = scratch .. '/derive_tag.txt'
local function wfile(p, s) local f = assert(io.open(p, 'w')); f:write(s); f:close() end
local function rfile(p) local f = io.open(p, 'r'); if not f then return nil end; local s = f:read('*a'); f:close(); return s end

local D = require('hd2ui.derive_entry')
check('derive installs', type(D) == 'table' and D.installed == true)
local log = rfile(OUT) or ''
check('log has START', log:find('START') ~= nil)
check('regions enumerated', log:match('regions=(%d+)') ~= nil)
os.remove(OUT)   -- fresh log per run: stale SCAN_DONE lines from previous
                 -- invocations in the same scratch dir would race the waits

-- Plant a marker u32 with a KNOWN address (ffi-owned memory is in our own
-- committed heap; the in-process scan must find it).
local MARK = 0x44332211
local MARKDEC = string.format('%d', MARK)   -- derive; never hand-typed decimal
local cell = ffi.new('uint32_t[1]', MARK)
local cell_addr = tonumber(ffi.cast('unsigned long long', cell))
check('marker address in process range', cell_addr > 0x10000)

local update = rawget(_G, 'update')
local function pump(frames)
  for _ = 1, frames do update(1 / 60) end
end
local function rfile_q(p) local f = io.open(p, 'r'); if not f then return nil end; local s = f:read('*a'); f:close(); return s end
local function newlog() return (rfile(OUT) or '') end
-- Write a command and pump until the module consumes it (poll is 0.25s-worth
-- of frames, so a fixed small pump can miss the window).
local function send(cmd)
  wfile(IN, cmd)
  for _ = 1, 200 do
    pump(1)
    local c = rfile_q(IN)
    if c == nil or c == '' then break end
  end
  pump(2)
end

pump(4)  -- let install-time work settle

-- probe: in-process reads should be near-fully OK (vs external ~5%).
send('probe 60')
log = newlog()
local okc, badc = log:match('PROBE sampled=%d+ ok=(%d+) bad=(%d+)')
check('probe runs', okc ~= nil)
check('in-process coverage good (ok>=bad)', okc and badc and tonumber(okc) >= tonumber(badc))

-- scan for the marker.
send('scan ' .. MARKDEC)
for _ = 1, 400 do
  pump(1)
  if (newlog()):find('SCAN_DONE') then break end
end
log = newlog()
local done = log:match('SCAN_DONE total=(%d+)')
check('scan finished', done ~= nil)
check('scan found marker value', done and tonumber(done) >= 1)
local tags = newlog()
local tagdata = rfile(TAG) or ''
check('marker address in tag file', tagdata:upper():find(string.format('%X', cell_addr), 1, true) ~= nil)

-- next (same value) must keep it; next with wrong value must drop it.
send('next ' .. MARKDEC)
tagdata = rfile(TAG) or ''
check('next keeps marker', tagdata:upper():find(string.format('%X', cell_addr), 1, true) ~= nil)
send('next 777777')
tagdata = rfile(TAG) or ''
check('next wrong value drops marker', not tagdata:upper():find(string.format('%X', cell_addr), 1, true))

-- restore a targeted candidate set and watch it.
wfile(TAG, string.format('%X\n', cell_addr))
send('watch ' .. string.format('0x%X', cell_addr) .. ' u32 0.1')
cell[0] = 12345
pump(30)
send('unwatch ' .. string.format('0x%X', cell_addr))
log = newlog()
check('watch logged new value', log:match('WATCH 0x' .. string.format('%X', cell_addr):upper() .. ' u32 = 12345') ~= nil)

-- read + hex commands.
send('read ' .. string.format('0x%X', cell_addr) .. ' u32')
log = newlog()
check('read returns 12345', log:match('READ 0x' .. string.format('%X', cell_addr):upper() .. ' u32 = 12345') ~= nil)

-- scanb / pointers: plant a uint64 holding the marker address, find it.
local holder = ffi.new('uint64_t[1]', cell_addr)
local holder_addr = tonumber(ffi.cast('unsigned long long', holder))
local function done_count(s) local c = 0 for _ in s:gmatch('SCAN_DONE') do c = c + 1 end return c end
send('pointers ' .. string.format('0x%X', cell_addr))
for _ = 1, 400 do
  pump(1)
  if done_count(newlog()) >= 2 then break end   -- second SCAN_DONE = pointers scan
end
log = newlog()
local pdone = log:match('SCAN_DONE total=(%d+)')
check('pointers scan finished', done_count(log) >= 2)
local tagp = rfile(TAG) or ''
check('holder found by pointers scan', tagp:upper():find(string.format('%X', holder_addr), 1, true) ~= nil)

-- unknown command -> ERR line.
send('bogus')
log = newlog()
check('unknown cmd -> ERR', log:find('ERR unknown command: bogus') ~= nil)

check('original update still called', real_frames > 0)

print(string.format('derive_headless: %d checks, %d failures', checks, fails))
if fails > 0 then error(fails .. ' failures') end
