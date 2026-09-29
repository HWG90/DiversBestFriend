-- hd2ui/ammo_entry.lua -- DBF Ammo HUD: in-game entry. Requires the HD2UI
-- framework addon (a SEPARATE Arsenal mod: require('mods/dbf/hd2ui')) and adds:
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

local MR = require('hd2ui.memreader')
local LS = require('hd2ui.live_scan')
local A  = require('hd2ui.ammo_reader')
local AC = require('hd2ui.ammo_cache')
local STYLES = require('hd2ui.ammo_styles')
local BARS = require('hd2ui.ammo_bars')
local CH   = require('hd2ui.ammo_chain')
local LAY  = require('hd2ui.ammo_layout')

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
  local ok, v = pcall(function() return require('mods/dbf/hd2ui') end)
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
    local okr, v = pcall(function() return require(full) end)
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
