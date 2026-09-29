-- tests/test_station_hud.lua -- e2e for the Floaty HUD entry against a fake
-- stingray, fake backend capture, and seeded fake data modules (memreader /
-- live_scan / ammo_reader / ammo_cache / ammo_chain). No real memory is
-- touched: the chain is scripted, so the full sticky presentation machinery
-- (value / blip-freeze / bridge-hide), the render path (real scene geometry,
-- captured display lists), anchor/size options, and the hide rules are all
-- exercised deterministically. Run under Lua 5.1 (LuaJIT).

package.path = './?.lua;hd2ui/?.lua;' .. package.path

local checks, fails = 0, 0
local function check(name, cond, extra)
  checks = checks + 1
  if not cond then fails = fails + 1; print('FAIL ' .. name .. (extra and (' (' .. tostring(extra) .. ')') or '')) else print('ok   ' .. name) end
end

------------------------------------------------------------------------------
-- fake stingray
------------------------------------------------------------------------------
local gui_ids = 0
local emitted_all = {}
local camera_handle = newproxy(true)   -- the entry requires a userdata handle
local FAKE_MATRIX = [[Matrix4x4(
 1, 0, 0, 0,
 0, 1, 0, 0,
 0, 0, 1, 0,
 10, 20, 30, 1
)]]
do  -- newproxy userdata: the metatable arrives attached; mutate it in place
  local mt = getmetatable(camera_handle)
  mt.__tostring = function() return FAKE_MATRIX end
end
local clears = 0
local cursor = false
local SR = {
  Gui = {
    resolution = function() return 3840, 2160 end,
    triangle = function(...) gui_ids = gui_ids + 1; return gui_ids end,
    text = function(...) gui_ids = gui_ids + 1; return gui_ids end,
  },
  Window = { show_cursor = function() return cursor end },
  Application = {
    can_get = function(_, kind, name) return kind == 'material' end,
    worlds = function() return { 0x11 } end,
    main_world = function() return 0x22 end,
  },
  World = {
    create_screen_gui = function(...) return 0x33 end,
    destroy_gui = function() end,
    debug_camera_pose = function(world) return camera_handle end,
  },
  Camera = {
    world_position = function(cam) return { x = 0, y = 0, z = 0 } end,
    world_rotation = function(cam) return { x = 0, y = 0, z = 0, w = 1 } end,
    world_to_screen = function(cam, v) return { x = 1173, y = 654 } end,
  },
  Vector3 = function(x, y, z) return { x, y, z } end,
  Vector2 = function(x, y) return { x, y } end,
  Color = function(a, r, g, b) return { a, r, g, b } end,
}
rawset(_G, 'stingray', SR)

local fake_backend_emits = emitted_all
local fake_backend
fake_backend = {
  new = function(opts)
    return {
      ensure = function() return true end,
      clear = function() clears = clears + 1 end,
      release = function() end,
      emit = function(dl, a) fake_backend_emits[#fake_backend_emits + 1] = { dl = dl, alpha = a } end,
      resolution = function() return 3840, 2160 end,
      cursor_visible = function() return cursor end,
      generation = function() return 1 end,
      mode = function() return 'geometry' end,
    }
  end,
}

-- framework: real scene + layout, fake backend (captures display lists)
local real_scene = require('hd2ui.scene')
local real_layout = require('hd2ui.core.layout')
rawset(_G, '__DBF_HD2UI', {
  version = 'test-framework',
  backend_stingray = fake_backend,
  scene = real_scene,
  layout = real_layout,
  colors = require('hd2ui.core.colors'),
})

------------------------------------------------------------------------------
-- fake data modules (seeded so the entry's require() picks them up)
------------------------------------------------------------------------------
local mr_calls = { attach = 0 }
local MR = {
  set_transport = function() end,
  attach = function(pid, mod) mr_calls.attach = mr_calls.attach + 1; mr_calls.mod = mod; return true end,
  self_pid = function() return 4242 end,
  read = function() return nil end,
  read_u32 = function() return 0 end,
  state = function() return {} end,
}
local LS = {
  set_transport = function() end,
  module_base = function() return 0x7FF000000000 end,   -- chain boots ON
  enum_regions = function() return false, 'headless' end,
  state = function() return { regions = {} } end,
}
local A = {
  set_transport = function() end,
  set_anchor_weapon = function() end,
  anchor_pattern = function() return 'PATTERN' end,
  anchor_spec = function() return { capacity = 8 } end,
  set_anchor_base = function() return false end,
  read = function() return nil end,
}
local AC = { pe_stamp = function() return 0x6AB3B43F end, load = function() return nil end, save = function() return true end }

-- scripted chain: a queue of rows; read() pops (repeats the last row forever)
local chain_queue = {}
local chain_last = { status = 'no_local_player' }   -- the real chain always returns a row
local CH = {
  BUILD = { name = 'test-layout' },
  init = function() return true end,
  verify = function() return true end,
  read = function()
    if #chain_queue > 0 then chain_last = table.remove(chain_queue, 1) end
    chain_last.reads = chain_last.reads or 3   -- real rows always carry read stats
    return chain_last
  end,
}

package.loaded['hd2ui.memreader'] = MR
package.loaded['hd2ui.live_scan'] = LS
package.loaded['hd2ui.ammo_reader'] = A
package.loaded['hd2ui.ammo_cache'] = AC
package.loaded['hd2ui.ammo_chain'] = CH

------------------------------------------------------------------------------
-- fake menus
------------------------------------------------------------------------------
local mom_opts, mom_values, mom_cbs = {}, {}, {}
rawset(_G, 'ModOptionsMenu', {
  ready = function() return true end,
  register_option = function(id, spec) mom_opts[id] = spec; return true end,
  get = function(id) return mom_values[id] end,
  set = function(id, v) mom_values[id] = v; if mom_cbs[id] then mom_cbs[id](v) end; return true end,
  on_change = function(id, cb) mom_cbs[id] = cb; return true end,
})
local mbm_bound, mbm_down = {}, {}   -- declared BEFORE the closure below captures them
rawset(_G, 'ModBindingsMenu', {
  ready = function() return true end,
  register_binding = function(id) mbm_bound[id] = true; return true end,
  is_down = function(id) return mbm_down and mbm_down[id] or false end,
})

------------------------------------------------------------------------------
-- load the entry (fresh chunk each run of this file)
------------------------------------------------------------------------------
local orig_calls = 0
rawset(_G, 'update', function() orig_calls = orig_calls + 1; return 'orig' end)  -- must exist: the entry wraps it
local entry_path = 'hd2ui/station_entry.lua'
local chunk = assert(loadfile(entry_path))
local result = chunk()
check('entry installs', result and result.installed == true, result and result.reason)
check('entry identity matches r6', result.version == 'dbf-floaty r8', result.version)
check('attach went to our own pid', mr_calls.attach == 1 and mr_calls.mod == 'helldivers2.exe')

local step = _G.update   -- the wrapped update

local ok_row = function(wid)
  return { status = 'ok', weapon_id = wid or 77, path = 'magazine', rounds = 30, capacity = 45,
           chamber = 0, chambered = false, spare = 7, spare_max = 8, spare_kind = 'mags' }
end
local function tick(n)
  for _ = 1, (n or 1) do step(1 / 60) end
end

-- boot: chain enabled, no ok samples yet -> nothing rendered
tick(30)
check('boot: no render before first ok sample (sticky)', #emitted_all == 0, #emitted_all)

-- 2 consecutive ok samples -> value shown, station rendered
chain_queue = { ok_row(), ok_row(), ok_row() }
tick(30)
check('value: station renders after 2 ok samples', #emitted_all > 0, #emitted_all)
local first = emitted_all[#emitted_all]
local numeral
for _, r in ipairs(first.dl) do if r.txt then numeral = r.txt[1] break end end
check('value: numeral is the round count', numeral == '30', tostring(numeral))
local plate_tri
for _, r in ipairs(first.dl) do if r.tri then plate_tri = r break end end
-- viewport 2160p -> scale 2; gun-side ref (1258,668) -> place() = (2516,1336)
check('value: plate fill at the gun-side anchor',
  plate_tri and math.abs(plate_tri.tri[1] - 2516) < 2 and math.abs(plate_tri.tri[2] - 1336) < 2,
  plate_tri and string.format('%.0f,%.0f', plate_tri.tri[1], plate_tri.tri[2]))
check('value: global alpha applied', first.alpha == 0.9, first.alpha)

-- redraw gating: same values -> no new emits
local n_before = #emitted_all
tick(20)
check('gating: unchanged values re-emit at most for the pulse bucket (<=2)',
  #emitted_all - n_before <= 2, #emitted_all - n_before)

-- value change -> re-emit with new numeral
chain_queue = { { status = 'ok', weapon_id = 77, path = 'magazine', rounds = 29, capacity = 45,
                  chamber = 0, chambered = false, spare = 7, spare_max = 8, spare_kind = 'mags' } }
tick(15)
check('gating: value change re-emits', #emitted_all > n_before)
local last = emitted_all[#emitted_all]
local num2
for _, r in ipairs(last.dl) do if r.txt then num2 = r.txt[1] break end end
check('gating: new numeral is 29', num2 == '29', tostring(num2))

-- holster blip: 1-2 samples of no_weapon_slot right after ok -> FREEZE (no clear, no hide)
local clears_before = clears
local n_b4 = #emitted_all
chain_queue = { { status = 'no_weapon_driver', weapon_id = 77 }, { status = 'no_weapon_driver', weapon_id = 77 } }
tick(15)
check('blip: driver blip holds the station (no hide; <=1 pulse redraw)',
  clears - clears_before <= 1 and #emitted_all - n_b4 <= 1,
  tostring(clears - clears_before) .. ' clears')

-- bridge: 3+ consecutive idle samples -> hidden + cleared
chain_queue = { { status = 'no_avatar' }, { status = 'no_avatar' }, { status = 'no_avatar' }, { status = 'no_avatar' } }
tick(40)
check('bridge: idle settles to hidden + clear', clears > clears_before)
local n_now = #emitted_all
tick(20)
check('bridge: stays hidden (no further emits)', #emitted_all == n_now)

-- return to a weapon: weapon switch guard shows on the NEXT ok read
chain_queue = { ok_row(99), ok_row(99), ok_row(99), ok_row(99) }
tick(40)
check('redeploy: station returns after fresh ok samples', #emitted_all > n_now)
local ret = emitted_all[#emitted_all]
local num3
for _, r in ipairs(ret.dl) do if r.txt then num3 = r.txt[1] break end end
check('redeploy: numeral fresh from the new reads', num3 == '30', tostring(num3))

-- laser class through the real chain_model -> heat bar + red lock numeral
chain_queue = { { status = 'ok', weapon_id = 5, path = 'heat', heat = 0.99, heat_max = 1.0,
                  overheated = true, sinks = 0, sinks_max = 5, spare = 0, spare_kind = 'sinks' } }
tick(15)
local hot = emitted_all[#emitted_all]
local hot_num, hot_col
for _, r in ipairs(hot.dl) do if r.txt then hot_num, hot_col = r.txt[1], r.txt[5] and r.txt[5][1] break end end
check('laser: heat pct numeral', hot_num == '99', tostring(hot_num))
check('laser: lock red numeral', hot_col == 224, tostring(hot_col))

-- AC class: magazine path with backpack pool -> clip pips
chain_queue = { { status = 'ok', weapon_id = 6, path = 'magazine', rounds = 7, capacity = 10,
                  chamber = 0, chambered = false, spare = 23, spare_kind = 'backpack', pack_total = 50 } }
tick(15)
local ac = emitted_all[#emitted_all]
local ac_num
for _, r in ipairs(ac.dl) do if r.txt then ac_num = r.txt[1] break end end
check('AC: numeral 7', ac_num == '7', tostring(ac_num))

-- cursor visible -> clear + skip (rule 4)
cursor = true
local clears_now = clears
tick(5)
check('cursor: menu clears and holds', clears > clears_now)
cursor = false
tick(5)

-- options: MOM registered the three rows
check('MOM: three options registered', mom_opts.dbf_floaty_anchor and mom_opts.dbf_floaty_size and mom_opts.dbf_floaty_enabled)
check('MOM: anchor defaults to gun-side', mom_opts.dbf_floaty_anchor.choices[1] == 'Gun-side')
-- live size apply
mom_values.dbf_floaty_size = 150
if mom_cbs.dbf_floaty_size then mom_cbs.dbf_floaty_size(150) end
chain_queue = { ok_row() }
tick(10)
local big = emitted_all[#emitted_all]
local big_plate
for _, r in ipairs(big.dl) do if r.tri then big_plate = r break end end
-- scale = (2160/1080) * 1.5 = 3 -> gun-side ox = 1920 + 298*3 = 2814
check('size 150%: plate scales up',
  big_plate and math.abs(big_plate.tri[1] - 2814) < 2,
  big_plate and string.format('%.0f', big_plate.tri[1]))
-- anchor switch -> crosshair anchor: ox = 1920 + 30*3 = 2010
if mom_cbs.dbf_floaty_anchor then mom_cbs.dbf_floaty_anchor(2) end
tick(10)
local cross = emitted_all[#emitted_all]
local cross_plate
for _, r in ipairs(cross.dl) do if r.tri then cross_plate = r break end end
check('anchor: crosshair variant moves the plate',
  cross_plate and math.abs(cross_plate.tri[1] - 2010) < 2,
  cross_plate and string.format('%.0f', cross_plate.tri[1]))
if mom_cbs.dbf_floaty_anchor then mom_cbs.dbf_floaty_anchor(1) end

-- MBM toggle binding
check('MBM: toggle binding registered', mbm_bound.dbf_floaty_toggle == true)
mbm_down.dbf_floaty_toggle = true
tick(2)
mbm_down.dbf_floaty_toggle = false
tick(2)
check('MBM: toggle fires and syncs the menu value to hidden',
  mom_values.dbf_floaty_enabled == false, tostring(mom_values.dbf_floaty_enabled))
mbm_down.dbf_floaty_toggle = true
tick(2)
mbm_down.dbf_floaty_toggle = false
tick(15)
check('MBM: toggle back syncs to visible and the station renders',
  mom_values.dbf_floaty_enabled == true and #emitted_all > 0)

-- hologram anchor: camera handle -> engine projection -> station at the
-- projected position (all coordinates through the fake sr.Camera)
if mom_cbs.dbf_floaty_anchor then mom_cbs.dbf_floaty_anchor(3) end
-- r6: hologram selection is a logged fallback to gun-side (no engine calls)
chain_queue = { ok_row(), ok_row(), ok_row(), ok_row() }
tick(30)
local holo_emit
for i = #emitted_all, 1, -1 do
  local tri = emitted_all[i].dl and emitted_all[i].dl[1] and emitted_all[i].dl[1].tri
  if tri then holo_emit = emitted_all[i] break end
end
local ht = holo_emit and holo_emit.dl[1].tri
-- size is still 150% (scale 3). 4K viewport: center (1920,1080), focal 1920
-- at fov 90. The camera-local offset (0.34,-0.16,1.35) projects to
-- (1920+0.34/1.35*1920, 1080+0.16/1.35*1920) = (2403.6, 1307.6) -> top-left
check('hologram: station renders at the projected position',
  ht and math.abs(ht[1] - 2178.6) < 3 and math.abs(ht[2] - 1214.6) < 3,
  ht and string.format('%.0f,%.0f', ht[1], ht[2]) or 'no emit')
if mom_cbs.dbf_floaty_anchor then mom_cbs.dbf_floaty_anchor(1) end
tick(5)

-- shutdown chains
local shutdown_ran = false
rawset(_G, 'shutdown', function() shutdown_ran = true end)
step(1 / 60)
_G.shutdown(0)
check('shutdown: chained original', shutdown_ran)

print(string.format('\nstation_hud: %d checks, %d failures', checks, fails))
if fails > 0 then error(fails .. ' failures') end
