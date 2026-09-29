-- hd2ui/tools/dump_station.lua -- render every weapon class through the REAL
-- station_bars + scene + geometry stack and dump the display list as JSON for
-- hd2ui/tools/mock_render.py. The visual gate between the Lua implementation
-- and the approved concepts/floaty-hud mock.
-- Run: python run_lua.py hd2ui/tools/dump_station.lua > station_scenes.json
package.path = './?.lua;hd2ui/?.lua;' .. package.path
local scene = require('hd2ui.scene')

local SB = require('hd2ui.station_bars')

-- model shapes exactly as station_entry.chain_model produces them
local classes = {
  { name = 'rifle_38',    model = { rounds = 38, mag_cap = 45, spare = 7, spare_max = 8,
                                    spare_kind = 'mags', weapon_id = 1 } },
  { name = 'shotgun_7',   model = { rounds = 7, mag_cap = 8, spare = 28, spare_max = 56,
                                    spare_kind = 'rounds', ammo_max = 56, weapon_id = 2 } },
  { name = 'ac_full',     model = { rounds = 10, mag_cap = 10, spare = 50, spare_kind = 'backpack',
                                    pack_rounds = 50, pack_total = 50, weapon_id = 3 } },
  { name = 'ac_mid',      model = { rounds = 7, mag_cap = 10, spare = 23, spare_kind = 'backpack',
                                    pack_rounds = 23, pack_total = 50, weapon_id = 3 } },
  { name = 'ac_reload',   model = { rounds = 4, mag_cap = 10, spare = 12, spare_kind = 'backpack',
                                    pack_rounds = 12, pack_total = 50, weapon_id = 3 } },
  { name = 'laser_62',    model = { heat_frac = 0.62, heat_pct = 62, spare = 3, spare_max = 5,
                                    spare_kind = 'sinks', weapon_id = 4 } },
  { name = 'laser_lock',  model = { heat_frac = 0.97, heat_pct = 97, heat_lock = true, spare = 0,
                                    spare_max = 5, spare_kind = 'sinks', weapon_id = 4 } },
  { name = 'cremator_71', model = { fuel_frac = 0.71, spare = 545, spare_kind = 'units', weapon_id = 5 } },
  { name = 'railgun_96',  model = { rounds = 4, mag_cap = 5, spare = 6, spare_max = 8,
                                    spare_kind = 'mags', charge_pct = 0.96, weapon_id = 6 } },
  { name = 'arc_42',      model = { charge_only = true, charge_pct = 0.42, weapon_id = 7 } },
}

local out = {}
for _, cls in ipairs(classes) do
  local sc = scene.new()
  local draw_cls = SB.draw(sc, cls.model, { clock = 0.37 })
  -- real anchor geometry: the entry places the plate top-left at (1258,668)
  -- in 1080p reference space; render with that origin so the dump carries the
  -- true on-screen offset from the crosshair (960,540)
  local dl = {}
  sc:render(dl, 1258, 668, 1)
  local tris, texts = {}, {}
  for i = 1, #dl do
    local rec = dl[i]
    if rec.tri then
      local t = rec.tri
      tris[#tris + 1] = { t[1], t[2], t[3], t[4], t[5], t[6], t[7][1], t[7][2], t[7][3], t[7][4] }
    elseif rec.txt then
      local t = rec.txt
      texts[#texts + 1] = { t[1], t[2], t[3], t[4], t[5][1], t[5][2], t[5][3], t[5][4] }
    end
  end
  out[#out + 1] = { name = cls.name .. ' [' .. tostring(draw_cls) .. ']', tris = tris, texts = texts }
end

local function num(v) return string.format('%.2f', v or 0) end
local parts = {}
for _, cls in ipairs(out) do
  local tris = {}
  for _, q in ipairs(cls.tris) do
    tris[#tris + 1] = '[' .. q[1] .. ',' .. q[2] .. ',' .. q[3] .. ',' .. q[4] .. ','
      .. q[5] .. ',' .. q[6] .. ',' .. q[7] .. ',' .. q[8] .. ',' .. q[9] .. ',' .. q[10] .. ']'
  end
  local texts = {}
  for _, q in ipairs(cls.texts) do
    texts[#texts + 1] = '[' .. string.format('%q', q[1]) .. ',' .. num(q[2]) .. ',' .. num(q[3])
      .. ',' .. num(q[4]) .. ',' .. q[5] .. ',' .. q[6] .. ',' .. q[7] .. ',' .. q[8] .. ']'
  end
  parts[#parts + 1] = '{"name":' .. string.format('%q', cls.name) .. ',"tris":['
    .. table.concat(tris, ',') .. '],"texts":[' .. table.concat(texts, ',') .. ']}'
end
print('{"classes":[' .. table.concat(parts, ',') .. ']}')
