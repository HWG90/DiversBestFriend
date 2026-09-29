-- ammo_layout: offsets, persistence, and the keyboard pump
package.path = 'hd2ui/?.lua;hd2ui/tests/?.lua;' .. package.path
local LAY = require('hd2ui.ammo_layout')
local checks, fails = 0, 0
local function ok(c, m) checks = checks + 1; if not c then fails = fails + 1; print('FAIL: ' .. m) end end

-- pump with fake key state
LAY.active = true
LAY.sel = 1
local held = {}
local function dn(vk) return held[vk] == true end
local before_x = { LAY.get(LAY.current()) }
held[0x27] = true                       -- right held
LAY.poll(0.0, dn)
local ax, ay = LAY.get(LAY.current())
ok(ax == before_x[1] + 3, 'pump: right key nudges +x')
LAY.poll(0.03, dn)                      -- still held, before repeat gate
ok(select(1, LAY.get(LAY.current())) == ax, 'pump: held key rate-limited')
LAY.poll(0.10, dn)                      -- past 0.07 gate
ok(select(1, LAY.get(LAY.current())) == ax + 3, 'pump: held key repeats past gate')
held[0x27] = false
held[0x26] = true                       -- up
local by = select(2, LAY.get(LAY.current()))
LAY.poll(0.2, dn)
ok(select(2, LAY.get(LAY.current())) == by - 3, 'pump: up moves NEGATIVE y (screen down = +)')
held[0x26] = false
held[0x09] = true
local sel0 = LAY.sel
LAY.poll(0.3, dn)
ok(LAY.sel == sel0 + 1, 'pump: tab cycles selection')
held[0x09] = false
held[0x1B] = true
local ev = LAY.poll(0.4, dn)
ok(ev == 'exit' and LAY.active == false, 'pump: esc exits')

-- persistence round trip
local path = os and (os.getenv('TMPDIR') or './_lay_test.txt') or './_lay_test.txt'
LAY.active = true
LAY.sel = 2
LAY.nudge(LAY.current(), 12, -9)
ok(LAY.save(path), 'save writes file')
LAY.nudge(LAY.current(), 99, 99)
ok(LAY.load(path), 'load reads back')
local rx, ry = LAY.get(LAY.order[2])
ok(rx == 12 and ry == -9, 'round-trip offsets exact: ' .. rx .. ',' .. ry)
os.remove(path)
LAY.active = false

print(string.format('ammo_layout: %d checks, %d failures', checks, fails))
if fails > 0 then error('layout pump broken') end
