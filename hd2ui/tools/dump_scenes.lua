-- hd2ui/tools/dump_scenes.lua -- render every weapon class through the REAL
-- bars + scene + geometry stack and dump the resulting display list as JSON
-- for the mockup renderer (hd2ui/tools/mock_render.py).
-- Run: python run_lua.py hd2ui/tools/dump_scenes.lua > scratch/scenes.json
package.path = './?.lua;hd2ui/?.lua;' .. package.path
local scene    = require('hd2ui.scene')
local geometry = require('hd2ui.core.geometry')
local colors   = require('hd2ui.core.colors')
local bars     = require('hd2ui.ammo_bars')
local LAY      = require('hd2ui.ammo_layout')

bars.LAY = LAY
LAY.active = false

-- the spread starter (same values we ship in dbf_ammo_layout.txt)
-- unified panel: no spread offsets needed; the panel IS the layout

local classes = {
  { name = 'rifle',    model = { count = 30, label = '30/180', capacity = 30,
      weapon_key = 'r', spare = 6, spare_kind = 'mags', spare_max = 8 } },
  { name = 'shotgun',  model = { count = 7, label = '7/28', capacity = 8,
      weapon_key = 's', spare = 28, spare_kind = 'rounds' } },
  { name = 'ac_full',  model = { count = 10, label = '10/10', capacity = 10,
      weapon_key = 'a', spare = 9, spare_kind = 'backpack',
      pack = { remain = 9, total = 12 }, mag_rounds = 10, mag_cap = 10 } },
  { name = 'ac_low',   model = { count = 4, label = '4/10', capacity = 10,
      weapon_key = 'a', spare = 4, spare_kind = 'backpack',
      pack = { remain = 4, total = 12 }, mag_rounds = 4, mag_cap = 10 } },
  { name = 'laser',    model = { count = 1, label = '82%', capacity = 100,
      weapon_key = 'l', heat_frac = 0.82, heat_pct = 82,
      spare = 4, spare_kind = 'sinks', spare_max = 6 } },
  { name = 'cremator', model = { count = 545, label = '61%', capacity = 100,
      weapon_key = 'c', fuel_frac = 0.61, spare = 545, spare_kind = 'units' } },
  { name = 'railgun',  model = { count = 4, label = '4/16', capacity = 4,
      weapon_key = 'rg', spare = 16, spare_kind = 'rounds', charge_pct = 0.35 } },
  { name = 'empty',    model = { count = 0, label = '', capacity = 0, weapon_key = 'e' } },
}

-- capture the display list per class
local out = {}
for _, cls in ipairs(classes) do
  local sc = scene.new()
  local dl = {}
  bars.draw(sc, cls.model, 1, colors)
  sc:render(dl, 960, 540, 1)   -- crosshair-centred, 1080p reference
  local tris, texts = {}, {}
  for i = 1, #dl do
    local rec = dl[i]
    if rec.tri then
      local x = rec.tri
      local c = x[7]
      tris[#tris + 1] = { x[1], x[2], x[3], x[4], x[5], x[6], c[1], c[2], c[3], c[4] }
    elseif rec.txt then
      local x = rec.txt
      local c = x[5]
      texts[#texts + 1] = { x[1], x[2], x[3], x[4], c[1], c[2], c[3], c[4] }
    end
  end
  out[#out + 1] = { name = cls.name, tris = tris, texts = texts }
end

-- hand-rolled JSON (stable, no deps)
local function esc(s) return s end
local function num(v)
  if v == nil then return '0' end
  if type(v) == 'number' then return string.format('%.3f', v) end
  return '"' .. esc(tostring(v)) .. '"'
end
local function arrjoin(items) return table.concat(items, ',') end
local classparts = {}
for _, cls in ipairs(out) do
  local tris = {}
  for _, q in ipairs(cls.tris) do
    local pts = {}
    for i = 1, 10 do pts[i] = num(q[i]) end
    tris[#tris + 1] = '[' .. arrjoin(pts) .. ']'
  end
  local texts = {}
  for _, q in ipairs(cls.texts) do
    local pts = {}
    for i = 1, 8 do pts[i] = num(q[i]) end
    texts[#texts + 1] = '[' .. arrjoin(pts) .. ']'
  end
  classparts[#classparts + 1] = '{"name":"' .. cls.name .. '","tris":[' .. arrjoin(tris)
    .. '],"texts":[' .. arrjoin(texts) .. ']}'
end
print('{"classes":[' .. arrjoin(classparts) .. ']}')
