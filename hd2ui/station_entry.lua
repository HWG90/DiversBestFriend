-- hd2ui/station_entry.lua -- DBF Floaty HUD: in-game entry. The product form
-- of concepts/floaty-hud (DESIGN.md): ONE graphical station, one grammar, no
-- text/graphical duality, no layout editor. Requires the HD2UI framework
-- addon (require('mods/dbf/hd2ui')). Data layer is the RAH-method instant
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

local MR = require('hd2ui.memreader')
local LS = require('hd2ui.live_scan')
local A  = require('hd2ui.ammo_reader')
local AC = require('hd2ui.ammo_cache')
local CH = require('hd2ui.ammo_chain')
local STATION = require('hd2ui.station_bars')
local HOLO = require('hd2ui.station_holo')

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
  local ok, v = pcall(function() return require('mods/dbf/hd2ui') end)
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
    local okr, v = pcall(function() return require(full) end)
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
