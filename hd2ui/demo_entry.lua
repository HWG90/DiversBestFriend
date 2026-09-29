-- hd2ui/demo_entry.lua -- In-game entry for the hd2ui demo counter.
--
-- Assembled by hd2ui/build_demo.py into one chunk together with the core
-- modules (there is no filesystem `require` in the game VM). The builder
-- prepends a tiny module registry and rewrites `require(` to `__hd2ui_require(`.
--
-- Lifecycle (same shape as the shipping ReticleAmmoHUD / DRIVER HUD addons):
--   * bail out quietly when `stingray` is missing or we are already installed
--   * wrap the global `update(dt)`: pcall our frame, back off 1 s on error,
--     give up after HD2UI_MAX_ERRORS consecutive errors, always call the original
--   * wrap the global `shutdown()` to destroy our screen GUI
--   * hide while the OS cursor is visible (menus), recreate the GUI if its
--     world disappears (mission transitions)
--   * only rebuild the retained triangles/text when the frame signature changes
local sr = rawget(_G, 'stingray')
if type(sr) ~= 'table' then return { installed = false, reason = 'no stingray' } end
if rawget(_G, '__HD2UI_DEMO_INSTALLED') then return { installed = true } end

local VERSION = 'hd2ui-demo r1'
local MATERIAL = 'mods/dbf/hd2ui/solid'
local HD2UI_MAX_ERRORS = 50

-- Demo configuration. (Options-menu / preset plumbing is a later step; these
-- are the same knobs demo_counter exposes.)
local CONFIG = {
  side = 'right',      -- 'left' | 'right' of centre
  offset_x = 140,      -- 1080p px from centre
  offset_y = 0,
  scale = 1.0,
  opacity = 0.9,
  color = '#f2f2f2',
}

------------------------------------------------------------------------------
-- Logging: %APPDATA%/Arrowhead/Helldivers2/hd2ui_demo.log (best effort).
------------------------------------------------------------------------------
local log_path
do
  local ok, dir = pcall(os.getenv, 'APPDATA')
  if ok and type(dir) == 'string' and dir ~= '' then
    log_path = dir .. '/Arrowhead/Helldivers2/hd2ui_demo.log'
  end
end
local log_fail = false
local function log(msg)
  if not log_path or log_fail or not io or not io.open then return end
  local ok, f = pcall(io.open, log_path, 'a')
  if not ok or not f then log_fail = true return end
  local t = os.date and os.date('%H:%M:%S') or '?'
  pcall(f.write, f, string.format('[%s] %s\n', t, tostring(msg)))
  pcall(f.close, f)
end
-- Fresh log per install.
if log_path and io and io.open then
  local ok, f = pcall(io.open, log_path, 'w')
  if ok and f then pcall(f.close, f) end
end
log(VERSION .. ' START')

------------------------------------------------------------------------------
-- Wire the framework.
------------------------------------------------------------------------------
local backend_mod = require('hd2ui.backend_stingray')
local counter_mod = require('hd2ui.demo_counter')

local backend = backend_mod.new({ material = MATERIAL, log = log })
local counter = counter_mod.new(CONFIG)

local App = sr.Application
local S = { clock = 0, retry_at = 0, errors = 0, disabled = false, key = nil, mode_logged = false }

-- Demo data model: a magazine that drains one round every 0.4 s and reloads,
-- so it is obvious on screen that the counter is live. Replace `model()` with
-- a real reader (ReticleAmmoHUD's weapon reader is the reference pattern).
local CAPACITY = 45
local function model()
  local n = CAPACITY - (math.floor(S.clock / 0.4) % (CAPACITY + 1))
  return { count = n, label = tostring(n), capacity = CAPACITY }
end

local function frame(dt)
  if not backend.ensure() then return end
  if backend.cursor_visible() then
    if S.key ~= 'hidden' then backend.clear(); S.key = 'hidden' end
    return
  end
  local w, h = backend.resolution()
  if not w then return end
  if not S.mode_logged then
    S.mode_logged = true
    log(string.format('gui ready mode=%s resolution=%dx%d', tostring(backend.mode()), w, h))
  end
  local m = model()
  local key = table.concat({ m.label, w, h, tostring(backend.mode()), backend.generation() }, '|')
  if key == S.key then return end
  S.key = key
  backend.clear()
  counter.frame(m, backend, w, h)
end

------------------------------------------------------------------------------
-- Hooks.
------------------------------------------------------------------------------
local old_update = rawget(_G, 'update')
if type(old_update) ~= 'function' then
  log('no global update(); not installing')
  return { installed = false, reason = 'no update' }
end
rawset(_G, '__HD2UI_DEMO_INSTALLED', true)

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
      if S.errors >= HD2UI_MAX_ERRORS then
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
  local ok, worlds = pcall(App.worlds)
  pcall(backend.release, ok and worlds or {})
  log('shutdown')
  if type(old_shutdown) == 'function' then return old_shutdown(...) end
end)

log('installed')
return { installed = true, version = VERSION }
