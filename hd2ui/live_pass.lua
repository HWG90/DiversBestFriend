-- hd2ui/live_pass.lua -- Interactive offset-derivation driver. Run with the
-- game RUNNING:  python run_lua.py hd2ui/live_pass.lua
-- A small REPL (commands below). Everything display-only: OpenProcess with
-- QUERY_INFORMATION|VM_READ, ReadProcessMemory, VirtualQueryEx, module
-- snapshots. No writes, no calls into the game.
--
-- Commands:
--   attach [pid]          find helldivers2.exe (or use given pid) and open it
--   base                  game.dll IMAGE base in the game process (+ASLR note)
--   regions [image]       committed regions (or image-only), count + sample
--   walk a,a,a,...        follow a pointer chain; prints every hop + result
--   read <addr> [u32|u64|f32|sN]   read a value (default: u32)
--   scan <value> [i]      scan committed regions for a value ('i' = image only)
--   hex <addr> [n]        dump n bytes (default 32) as hex
--   dump <base>           print derived layout as a paste-ready lua snippet
--   quit

package.path = './?.lua;' .. package.path
local MR = require('hd2ui.memreader')
local LS = require('hd2ui.live_scan')
local bit = require('bit')
local band, bor = bit.band, bit.bor

local function hx(v) return string.format('0x%X', v % 0x10000000000000000) end
local function line(s) io.write(s or '', '\n') end
local function prompt() io.write('> '); io.flush() end

local attached, base_addr, base_size = false, nil, nil
local layout = nil -- filled by 'dump' once the chain is confirmed

local function need_attach()
  if attached then return true end
  line('not attached -- run: attach')
  return false
end

local function cmd_attach(arg)
  local err
  local pid = tonumber(arg and arg:match('%d+') or '')
  if pid then
    local ok
    ok, err = MR.attach(pid, nil)
    if not ok then line('attach failed: ' .. tostring(err)) return end
  else
    local p, pname
    p, pname = LS.find_process('helldivers2.exe')
    if not p then line('game not found: ' .. tostring(pname)) return end
    local ok
    ok, err = MR.attach(p, pname)
    if not ok then line('attach failed: ' .. tostring(err)) return end
    pid = p
  end
  attached = true
  base_addr, base_size = LS.module_base(pid, 'game.dll')
  line('attached pid ' .. tostring(pid))
  if base_addr then
    line(('game.dll base %s (size %s bytes, ASLR -- re-derive offsets per session unless relative)'
        ):format(hx(base_addr), tostring(base_size)))
  else
    line('game.dll base not found via module snapshot')
  end
end

local function cmd_base()
  if not need_attach() then return end
  local pid = MR.pid()
  base_addr, base_size = LS.module_base(pid, 'game.dll')
  if base_addr then line(('game.dll %s size %s'):format(hx(base_addr), tostring(base_size)))
  else line('not found') end
end

local function cmd_regions(arg)
  if not need_attach() then return end
  local image = arg and arg:lower() == 'image'
  local ok, n = LS.enum_regions()
  if not ok then line('enum failed: ' .. tostring(n)) return end
  line('committed regions: ' .. tostring(n))
  local shown = 0
  for i = 1, n do
    local r = LS.region(i)
    if (not image) or r.image then
      line(('  %d: base=%s size=%s %s%s'):format(i, hx(r.base), tostring(r.size),
        r.image and 'IMAGE' or '', r.private and ' private' or ''))
      shown = shown + 1
      if shown >= 24 then line('  ...') break end
    end
  end
end

-- NOTE: this LuaJIT build saturates tonumber(str, 16) to 32 bits (0xFFFFFFFF
-- on overflow). ALWAYS parse hex as tonumber('0x'..bare) or tonumber('0x...')
-- with NO explicit base.
local function hexnum(s)
  if not s then return nil end
  if s:match('^[0-9a-fA-F]+$') then s = '0x' .. s end
  return tonumber(s)
end

local function cmd_walk(arg)
  if not need_attach() then return end
  local chain = {}
  for a in arg:gmatch('0[xX][%x]+') do
    chain[#chain + 1] = hexnum(a)
  end
  if #chain == 0 then line('usage: walk 0x1000,0x48,0x10') return end
  local addr = chain[1]
  for i = 2, #chain do
    local next_ = MR.read_ptr(addr)
    if next_ == nil then line(('hop %d FAILED at %s'):format(i - 1, hx(addr))) return end
    line(('hop %d: %s -> %s'):format(i - 1, hx(addr), hx(next_)))
    addr = next_ + chain[i]
  end
  line(('chain end: %s'):format(hx(addr)))
  local v = MR.read_u32(addr)
  if v then line('u32 at end: ' .. tostring(v) .. '  (' .. string.format('%08X', v) .. ')') end
end

local function cmd_read(arg)
  if not need_attach() then return end
  local addr = hexnum(arg:match('0[xX]%x+') or arg:match('%x+'))
  if not addr then line('usage: read 0xADDR [u32|u64|f32|sN]') return end
  local kind = arg:match('%s(%w+)') or 'u32'
  if kind == 'u64' then
    local lo = MR.read_u32(addr); local hi = MR.read_u32(addr + 4)
    if lo and hi then line(hx((lo + hi * 0x100000000) % 0x10000000000000000)) end
  elseif kind == 'f32' then
    local s = MR.read(addr, 4)
    if s then
      local b1, b2, b3, b4 = s:byte(1), s:byte(2), s:byte(3), s:byte(4)
      local bits = b1 + b2*256 + b3*65536 + (b4*0x1000000) % 0x100000000
      local sign = (math.floor(bits / 0x80000000) == 1) and -1 or 1
      local exp  = math.floor(bits / 0x800000) % 256
      local mant = bits % 0x800000
      local val
      if exp == 0 then val = sign * (mant / 0x800000) * 2^-126
      elseif exp == 255 then val = (mant == 0) and sign * math.huge or 0/0
      else val = sign * 2^(exp - 127) * (1 + mant / 0x800000) end
      line('f32: ' .. tostring(val))
    end
  elseif kind:match('^s%d+$') then
    local s = MR.read(addr, tonumber(kind:sub(2)))
    line(s and ('%q'):format(s) or 'read failed')
  else
    local v = MR.read_u32(addr)
    if v then line('u32: ' .. tostring(v) .. '  (' .. string.format('%08X', v) .. ')') end
  end
end

local function cmd_hex(arg)
  if not need_attach() then return end
  local addr = hexnum(arg:match('0[xX]%x+') or arg:match('%x+'))
  if not addr then line('usage: hex 0xADDR [n]') return end
  local n = tonumber(arg:match('%s%d+$')) or 32
  local s = MR.read(addr, n)
  if not s then line('read failed') return end
  for i = 1, #s, 16 do
    local chunk, hexline = s:sub(i, i + 15), {}
    for j = 1, #chunk do hexline[#hexline + 1] = string.format('%02X', chunk:byte(j)) end
    line(('%s  %s'):format(hx(addr + i - 1), table.concat(hexline, ' ')))
  end
end

local function scan_file(tag) return 'hd2ui/scan_' .. tag .. '.txt' end

local function cmd_scan(arg)
  if not need_attach() then return end
  LS.enum_regions()
  local v = hexnum(arg:match('0[xX]%x+')) or tonumber(arg:match('^%s*%d+'))
  if not v then line('usage: scan <value> [tag] [i|f]') return end
  local image = arg:find('%si%s*$') ~= nil or arg:find('%s i f$') ~= nil
  local fmode = arg:find('f%s*$') ~= nil
  local tag = arg:match('%s(%w+)%s*[if]*%s*$') or 'last'
  local st = LS.state()
  st.scan_max = 4000000 -- keep the FULL candidate set (narrowing uses the file)
  st.progress = function(i, n) io.write('.'); io.flush() end
  line(('scanning %d committed regions for %s=%s%s ...'):format(#st.regions, fmode and 'f32' or 'u32', tostring(v), image and ' (image only)' or ''))
  local res, err
  if fmode then res, err = LS.scan_f32(v, image)
  else res, err = LS.scan_u32(v, image) end
  st.progress = nil
  line('')
  if not res then line('scan failed: ' .. tostring(err)) return end
  local s = res.stats
  line(('pages ok=%d bad=%d, bytes read=%.1f GB, regions=%d'):format(s.pages_ok, s.pages_bad, s.bytes / 2^30, s.regions))
  line('hits: ' .. tostring(res.total) .. '  -> saved to tag "' .. tag .. '"')
  local f = assert(io.open(scan_file(tag), 'w'))
  for i = 1, #res.addresses do f:write(string.format('%X\n', res.addresses[i])) end
  f:close()
  for i = 1, math.min(5, #res.addresses) do
    local a = res.addresses[i]
    local note = (base_addr and a >= base_addr and a < base_addr + base_size)
      and (' [game.dll +0x%X]'):format(a - base_addr) or ''
    line('  ' .. hx(a) .. note)
  end
  if #res.addresses > 5 then line('  ...') end
end

-- next <tag> <value>  -- re-check every candidate from a prior scan and keep
-- only those whose u32 now equals <value>. This is the narrowing step:
-- scan 30 -> fire 1 round -> next <tag> 29 -> few survivors.
local function cmd_next(arg)
  if not need_attach() then return end
  local tag = arg:match('^(%w+)')
  local v = tonumber(arg:match('%s(%d+)'))
  if not tag or not v then line('usage: next <tag> <value>') return end
  local f = io.open(scan_file(tag), 'r')
  if not f then line('no tag: ' .. tag) return end
  local addrs = {}
  for l in f:lines() do
    local a = hexnum(l)
    if a then addrs[#addrs + 1] = a end
  end
  f:close()
  local keep = {}
  for i = 1, #addrs do
    if MR.read_u32(addrs[i]) == v then keep[#keep + 1] = addrs[i] end
    if i % 5000 == 0 then io.write('#'); io.flush() end
  end
  line('')
  line(('rechecked %d candidates, %d still == %d'):format(#addrs, #keep, v))
  local w = assert(io.open(scan_file(tag), 'w'))
  for i = 1, #keep do w:write(string.format('%X\n', keep[i])) end
  w:close()
  for i = 1, math.min(12, #keep) do
    local a = keep[i]
    local rel = (base_addr and a >= base_addr and a < base_addr + base_size)
      and (' [game.dll +0x%X]'):format(a - base_addr)
      or (' [heap/priv +0x%X]'):format(a - 0)
    line('  ' .. hx(a) .. rel)
  end
end

-- nextf <tag> <value> -- like next, but the field is f32 (compares byte pattern).
local function cmd_nextf(arg)
  if not need_attach() then return end
  local tag = arg:match('^(%w+)')
  local v = tonumber(arg:match('%s(%d+%.?%d*)'))
  if not tag or not v then line('usage: nextf <tag> <value>') return end
  local f = io.open(scan_file(tag), 'r')
  if not f then line('no tag: ' .. tag) return end
  local pat = LS.f32_bytes(v)
  local addrs = {}
  for l in f:lines() do
    local a = hexnum(l)
    if a then addrs[#addrs + 1] = a end
  end
  f:close()
  local keep = {}
  for i = 1, #addrs do
    if MR.read(addrs[i], 4) == pat then keep[#keep + 1] = addrs[i] end
  end
  line(('rechecked %d candidates, %d still == f32 %s'):format(#addrs, #keep, tostring(v)))
  local w = assert(io.open(scan_file(tag), 'w'))
  for i = 1, #keep do w:write(string.format('%X\n', keep[i])) end
  w:close()
  for i = 1, math.min(12, #keep) do line('  ' .. hx(keep[i])) end
end

local function cmd_dump()
  -- Once the chain is confirmed by 'walk', print it as a paste-ready layout
  -- table for ammo_reader.set_layout.
  line('-- derived layout (paste into ammo_reader set_layout):')
  if base_addr then
    line('-- game.dll base at derivation: ' .. hx(base_addr) .. ' (ASLR: use relative offsets)')
  end
  line('-- NOTE: fill chain/field offsets from the walk/read output above.')
end

local commands = {
  attach = cmd_attach, base = cmd_base, regions = cmd_regions, walk = cmd_walk,
  read = cmd_read, hex = cmd_hex, scan = cmd_scan, next = cmd_next, nextf = cmd_nextf,
  dump = cmd_dump,
}

line('live pass driver -- game must be running. commands:')
line('  attach [pid] | base | regions [image] | walk 0xa,0xoff,... | read 0xa [u32|u64|f32|sN]')
line('  hex 0xa [n] | scan <value> [tag] [i|f] | next <tag> <value> | nextf <tag> <value> | dump | quit')
prompt()
while true do
  local input = io.read('*l')
  if input == nil then line('') break end
  local name, arg = input:match('^(%S+)%s*(.*)$')
  if not name or name == 'quit' or name == 'q' then break end
  local fn = commands[name]
  if fn then
    local ok, err = pcall(fn, arg)
    if not ok then line('error: ' .. tostring(err)) end
  else
    line('unknown: ' .. name)
  end
  prompt()
end
line('bye')
os.exit(0)
