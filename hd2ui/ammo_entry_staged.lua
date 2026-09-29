-- hd2ui/ammo_entry_staged.lua -- R7 DIAGNOSTIC ENTRY: boots the real product
-- stack step by step, announcing every step to a log file (three fallback
-- directories, since io behavior in the loader env is itself a question).
-- The LAST 'STEP n' line present in any log identifies where things die.
-- Memory attach is fully deferred (only after first no-cursor frame), so this
-- build also tests "boot with our modules loaded but zero OS memory calls".
local sr = rawget(_G, 'stingray')

-- staged logging ------------------------------------------------------------
local LOGS = {}
do
  local function mk(base)
    if type(base) == 'string' and base ~= '' then
      local p = base .. '\\dbf_staged.log'
      LOGS[#LOGS + 1] = p
    end
  end
  local ok, t = pcall(os.getenv, 'TEMP');     if ok then mk(t) end
  mk((os.getenv and os.getenv('APPDATA')) and (os.getenv('APPDATA') .. '\\Arrowhead\\Helldivers2') or nil)
  local ok2, l = pcall(os.getenv, 'LOCALAPPDATA'); if ok2 then mk(l) end
end
local function staged(msg)
  for i = 1, #LOGS do
    local ok, f = pcall(io.open, LOGS[i], 'a')
    if ok and f then
      pcall(f.write, f, (os.date and os.date('[%H:%M:%S] ') or '?') .. msg .. '\n')
      pcall(f.close, f)
    end
  end
  if sr and type(sr.Debug) == 'table' and sr.Debug.log then
    pcall(sr.Debug.log, 'dbf staged: ' .. msg)
  end
end
pcall(function() staged('STEP 0 chunk entered') end)

if type(sr) ~= 'table' then staged('ABORT no stingray') return { installed = false } end
if rawget(_G, '__DBF_AMMO_INSTALLED') then return { installed = true } end

-- STEP 1: pure-lua product modules (no ffi) ----------------------------------
local STYLES, CACHE, READER
local ok1, err1 = pcall(function()
  STYLES = require('hd2ui.ammo_styles')
  CACHE  = require('hd2ui.ammo_cache')
  READER = require('hd2ui.ammo_reader')
end)
staged('STEP 1 pure modules ' .. (ok1 and 'ok' or ('FAIL ' .. tostring(err1))))
if not ok1 then return { installed = false } end

-- STEP 2: memreader (its top-level ffi.cdef kernel32 block) -------------------
local MR
local ok2, err2 = pcall(function() MR = require('hd2ui.memreader') end)
staged('STEP 2 memreader ' .. (ok2 and 'ok' or ('FAIL ' .. tostring(err2))))
if not ok2 then return { installed = false } end

-- STEP 3: live_scan (Toolhelp + VirtualQueryEx cdef blocks) ------------------
local LS
local ok3, err3 = pcall(function() LS = require('hd2ui.live_scan') end)
staged('STEP 3 live_scan ' .. (ok3 and 'ok' or ('FAIL ' .. tostring(err3))))
if not ok3 then return { installed = false } end

-- STEP 4: transport wiring + ffi + PID --------------------------------------
local PID
local ok4, err4 = pcall(function()
  LS.set_transport(MR)
  READER.set_transport(MR)
  local ffi = rawget(_G, 'ffi')
  if not ffi or not ffi.cdef then
    local okf, m = pcall(require, 'ffi')
    if okf and m then ffi = m end
  end
  if not ffi then error('no ffi') end
  ffi.cdef[[ unsigned long GetCurrentProcessId(void); ]]
  PID = tonumber(ffi.C.GetCurrentProcessId())
end)
staged('STEP 4 wiring+pid ' .. (ok4 and ('ok pid=' .. tostring(PID)) or ('FAIL ' .. tostring(err4))))

-- STEP 5: framework require (already proven by fw's own 'loaded') -------------
local HD2 = rawget(_G, '__DBF_HD2UI')
if type(HD2) ~= 'table' then
  local okv, v = pcall(function() return require('mods/dbf/hd2ui') end)
  if okv and type(v) == 'table' then HD2 = v end
end
staged('STEP 5 framework ' .. (type(HD2) == 'table' and ('ok ' .. tostring(HD2.version)) or 'MISSING'))
if type(HD2) ~= 'table' then return { installed = false } end

-- STEP 6: backend + style (render path, -- model; NO memory reads yet) -------
local ok6, err6 = pcall(function()
  BACKEND = HD2.backend_stingray.new({ material = 'mods/dbf/hd2ui/solid', log = staged })
  HUD = STYLES.new('crosshair', HD2, { scale = 1, opacity = 0.9, color = '#f2f2f2',
                                       side = 'right', offset_x = 140 })
end)
staged('STEP 6 render init ' .. (ok6 and 'ok' or ('FAIL ' .. tostring(err6))))

-- STEP 7: deferred memory path -- attach + anchor + scan start ONLY once the
-- cursor is hidden (in-mission), never at menu/boot. -------------------------
local S = { clock = 0, armed = false, state = 'idle', key = nil, attach_err = nil }
local old_update = rawget(_G, 'update')
if type(old_update) ~= 'function' then staged('ABORT no update') return { installed = false } end
rawset(_G, '__DBF_AMMO_INSTALLED', true)

local BACKEND, HUD
local function arm_memory()
  local ok, err = pcall(function()
    local ok_att, att_err = MR.attach(PID, 'helldivers2.exe')
    if not ok_att then S.attach_err = tostring(att_err) staged('ARM attach FAIL ' .. S.attach_err) return end
    staged('ARM attach ok')
    READER.set_anchor_weapon('r4_deadeye')
    local mb = LS.module_base(PID, 'game.dll')
    staged('ARM game.dll base ' .. (mb and string.format('0x%X', mb) or 'nil'))
    S.state = 'resolving'
    staged('ARM memory path live (scan machinery ready)')
  end)
  if not ok then staged('ARM crash ' .. tostring(err)) end
  S.armed = true
end

rawset(_G, 'update', function(...)
  local dt = select(1, ...)
  if type(dt) ~= 'number' or dt ~= dt then dt = 1 / 60 end
  S.clock = S.clock + dt
  local ok, err = pcall(function()
    if not BACKEND then return end
    local cursor = BACKEND.cursor_visible()
    if not cursor then
      if not S.armed then arm_memory() end
      if BACKEND.ensure() then
        local w, h = BACKEND.resolution()
        if w then
          if S.key ~= 'shown' .. tostring(BACKEND.generation()) then
            S.key = 'shown' .. tostring(BACKEND.generation())
            BACKEND.clear()
            HUD.frame({ count = 0, label = 'staged', capacity = 8 }, BACKEND, w, h)
          end
        end
      end
    else
      if S.key ~= 'hidden' then BACKEND.clear(); S.key = 'hidden' end
    end
  end)
  if not ok then staged('frame err ' .. tostring(err)) end
  return old_update(...)
end)

staged('STEP 7 installed (memory deferred to in-mission); DONE')
return { installed = true, version = 'r7-staged' }
