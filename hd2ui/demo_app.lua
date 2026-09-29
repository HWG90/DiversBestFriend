-- hd2ui/demo_app.lua -- The demo counter's per-frame logic, host-agnostic.
--
-- Two hosts drive this:
--   * demo_entry.lua  (Bingus Shared Loader addon: wraps global update/shutdown)
--   * mdl_mod.lua     (MDL - Mod Dynamic Loader loose mod: on_update/on_disable)
--
--   local app = demo_app.new({ log = fn, material = 'mods/dbf/hd2ui/solid',
--                              config = function() return { side=..., ... } end })
--   app.frame(dt)     -- call every game frame; safe to pcall
--   app.release()     -- destroy everything (host shutdown / unload)
--
-- Config (all optional, read every frame so live option changes apply):
--   side 'left'|'right', offset_x, offset_y (1080p px), scale (1.0 = 100%),
--   opacity 0..1, color '#rrggbb', capacity (demo magazine size)
local backend_mod = require('hd2ui.backend_stingray')
local counter_mod = require('hd2ui.demo_counter')

local DEFAULTS = { side = 'right', offset_x = 140, offset_y = 0, scale = 1.0,
                   opacity = 0.9, color = '#f2f2f2', capacity = 45 }

local function new(opts)
  opts = opts or {}
  local log = opts.log or function() end
  local get_config = opts.config or function() return nil end
  local backend = backend_mod.new({ material = opts.material, log = log })
  local S = { clock = 0, key = nil, cfg_key = nil, counter = nil, mode_logged = false, capacity = DEFAULTS.capacity }

  local function resolve_config()
    local c = get_config() or {}
    local cfg = {}
    for k, v in pairs(DEFAULTS) do
      local x = c[k]
      if x == nil then x = v end
      cfg[k] = x
    end
    return cfg
  end

  local function ensure_counter()
    local cfg = resolve_config()
    local key = table.concat({ cfg.side, cfg.offset_x, cfg.offset_y, cfg.scale, cfg.opacity, cfg.color, cfg.capacity }, '|')
    if key ~= S.cfg_key then
      S.cfg_key = key
      S.counter = counter_mod.new(cfg)
      S.capacity = cfg.capacity
      S.key = nil -- force redraw
    end
    return S.counter
  end

  -- Demo data model: a magazine that drains one round every 0.4 s and reloads,
  -- so it is obvious on screen that the counter is live. Replace with a real
  -- reader (ReticleAmmoHUD's weapon reader is the reference pattern).
  local function model()
    local cap = S.capacity
    local n = cap - (math.floor(S.clock / 0.4) % (cap + 1))
    return { count = n, label = tostring(n), capacity = cap }
  end

  local function frame(dt)
    if type(dt) ~= 'number' or dt ~= dt then dt = 1 / 60 end
    if dt < 0 then dt = 0 elseif dt > 0.25 then dt = 0.25 end
    S.clock = S.clock + dt
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
    local counter = ensure_counter()
    local m = model()
    local key = table.concat({ m.label, w, h, tostring(backend.mode()), backend.generation() }, '|')
    if key == S.key then return end
    S.key = key
    backend.clear()
    counter.frame(m, backend, w, h)
  end

  local function release()
    local sr = rawget(_G, 'stingray')
    local ok, worlds = pcall(sr.Application.worlds)
    pcall(backend.release, ok and worlds or {})
    S.key = nil
  end

  return { frame = frame, release = release, backend = backend, defaults = DEFAULTS }
end

return { new = new, DEFAULTS = DEFAULTS }
