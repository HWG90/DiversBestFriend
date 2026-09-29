-- hd2ui/tests/test_core.lua
-- Headless verification of the hd2ui stingray-backed core under the game's LuaJIT.
-- No game process, no FFI: exercises colors, geometry, layout, scene and the
-- demo counter against a recording fake backend. Fails (assert) on any error.
--
-- Run: python scripts/test.py (auto) OR directly:
--   HD2_LUA51_DLL=... python run_lua.py hd2ui/tests/test_core.lua

-- Resolve modules from the repo root (run_lua.py / test.py chdir to repo root).
package.path = './?.lua;' .. package.path

local colors   = require('hd2ui.core.colors')
local geometry = require('hd2ui.core.geometry')
local layout   = require('hd2ui.core.layout')
local scene    = require('hd2ui.scene')
local counter  = require('hd2ui.demo_counter')

local checks = 0
local function ok(cond, msg)
  checks = checks + 1
  if not cond then
    error('FAILED: ' .. tostring(msg) .. ' (check #' .. checks .. ')', 2)
  end
end
local function near(a, b, eps, msg)
  eps = eps or 1e-6
  ok(type(a) == 'number' and math.abs(a - b) < eps,
     (msg or 'near') .. ' (got ' .. tostring(a) .. ' want ' .. tostring(b) .. ')')
end

-- --- colors ---
local c = colors.rgba(255, 255, 255)
ok(c[1] == 255 and c[2] == 255 and c[3] == 255 and c[4] == 255, 'rgba full')
local h = colors.from_hex('#f2f2f2')
ok(h[1] == 242 and h[2] == 242 and h[3] == 242, 'from_hex 6-digit')
local h3 = colors.from_hex('#fff')
ok(h3[1] == 255 and h3[2] == 255 and h3[3] == 255, 'from_hex 3-digit')
local m = colors.mix({0, 0, 0, 255}, {255, 255, 255, 255}, 0.5)
ok(m[1] >= 127 and m[1] <= 128, 'mix midpoint red')
local a = colors.alpha({255, 255, 255, 255}, 0.5)
ok(a[4] == 127 or a[4] == 128, 'alpha 0.5')
local l = colors.lighten({0, 0, 0, 255}, 1.0)
ok(l[1] == 255 and l[2] == 255 and l[3] == 255, 'lighten full')
local d = colors.darken({255, 255, 255, 255}, 1.0)
ok(d[1] == 0 and d[2] == 0 and d[3] == 0, 'darken full')
local cc = colors.rgba(300, -10, 128, 999)
ok(cc[1] == 255 and cc[2] == 0 and cc[3] == 128 and cc[4] == 255, 'rgba clamps')

-- --- geometry: display-list emission ---
local dl = {}
geometry.rect(dl, 0, 0, 10, 5, c)
ok(#dl == 2 and dl[1].tri and dl[2].tri, 'rect -> 2 tris')
ok(dl[1].tri[7] == c, 'tri carries color')
near(dl[1].tri[1], 0); near(dl[1].tri[2], 0)
near(dl[1].tri[3], 10); near(dl[1].tri[4], 0)
near(dl[1].tri[5], 10); near(dl[1].tri[6], 5)
geometry.hline(dl, 0, 0, 20, 4, c, true)
ok(#dl == 4, 'hline -> 2 tris (with cap)')
geometry.vline(dl, 5, 0, 10, 4, c, false)
ok(#dl == 6, 'vline -> 2 tris')
local n0 = #dl
geometry.arc(dl, 0, 0, 10, 4, 0, math.pi / 2, c, 0.1)
ok(#dl > n0, 'arc adds tris')
n0 = #dl
geometry.circle(dl, 0, 0, 10, c, 0.05)
ok(#dl > n0, 'circle adds tris')
n0 = #dl
geometry.ring(dl, 0, 0, 10, 14, 0, 2 * math.pi, c, 0.1)
ok(#dl > n0, 'ring adds tris')
n0 = #dl
geometry.diamond(dl, 0, 0, 10, c)
ok(#dl == n0 + 4, 'diamond -> 4 tris')
n0 = #dl
local w = geometry.text(dl, '45', 100, 50, 22, c, 'center')
ok(#dl == n0 + 1 and dl[#dl].txt, 'text adds 1 txt')
ok(w > 0, 'text returns width')
local t = dl[#dl].txt
ok(t[1] == '45' and t[6] == 'center', 'text fields')
ok(t[2] < 100, 'center align shifts x left')

-- --- layout ---
near(layout.scale_factor(1080, 1.0), 1.0, 1e-12, 'scale at 1080p = 1.0')
near(layout.scale_factor(1440, 1.0), 4 / 3, 1e-12, 'scale at 1440p = 4/3')
near(layout.scale_factor(2160, 0.5), 1.0, 1e-12, 'scale 2160p @ 50% = 1.0')
local sx, sy = layout.place(1920, 1080, 960, 540, 1.0)
ok(sx == 960 and sy == 540, 'place center = center')
sx, sy = layout.place(1920, 1080, 1080, 540, 1.0)
ok(sx == 1080 and sy == 540, 'place right offset')
sx, sy = layout.place(2560, 1080, 960, 540, 1.0)
ok(sx == 1280 and sy == 540, 'place center on ultrawide')
-- anchor returns {x, y}
local ab = layout.anchor(1920, 1080, 0, 0, 'br')
ok(ab[1] == 1920 and ab[2] == 1080, 'anchor br = (1920,1080)')
local ac = layout.anchor(1920, 1080, 10, 10, 'center')
ok(ac[1] == 970 and ac[2] == 550, 'anchor center + (10,10) = (970,550)')
local al = layout.anchor(1920, 1080, 0, 0, 'left')
ok(al[1] == 0 and al[2] == 540, 'anchor left = (0,540)')
local atr = layout.anchor(1920, 1080, 0, 0, 'tr')
ok(atr[1] == 1920 and atr[2] == 0, 'anchor tr = (1920,0)')
local abl = layout.anchor(1920, 1080, 0, 0, 'bl')
ok(abl[1] == 0 and abl[2] == 1080, 'anchor bl = (0,1080)')
local adef = layout.anchor(1920, 1080, 0, 0, nil)
ok(adef[1] == 960 and adef[2] == 540, 'anchor default = center')
near(layout.scale_factor(1080, 999), 16, 1e-12, 'user scale clamps to 16')
near(layout.scale_factor(1080, 0.001), 0.05, 1e-12, 'user scale clamps to 0.05')

-- --- scene ---
local sc = scene.new()
ok(sc:count() == 0, 'scene starts empty')
sc:add('rect', { x = 0, y = 0, w = 10, h = 5 }, c)
sc:add('text', { str = '12', x = 0, y = 0, size = 20, align = 'center' }, c)
ok(sc:count() == 2, 'scene adds 2')
local sdl = {}
sc:render(sdl, 100, 200, 2.0)
ok(#sdl == 3, 'scene renders 2 tris + 1 txt')
ok(sdl[1].tri[1] == 100, 'scene applies origin x')
ok(sdl[1].tri[2] == 200, 'scene applies origin y')
near(sdl[1].tri[3], 100 + 10 * 2, 1e-9, 'scene scales width')
sc:clear()
ok(sc:count() == 0, 'scene clears')
local err = pcall(function()
  local s2 = scene.new()
  s2:add('bogus', {}, c)
  local d = {}
  s2:render(d, 0, 0, 1)
end)
ok(not err, 'unknown kind raises')

-- --- demo_counter (headless with a fake stingray backend) ---
local fake = { calls = 0 }
function fake.ensure() return true end
function fake.clear() end
function fake.release() end
function fake.emit(dl, a)
  fake.calls = fake.calls + 1
  fake.last_dl = dl
  fake.last_a = a
end
local counter_right = counter.new({ side = 'right', offset_x = 120, scale = 1.0, opacity = 0.8, color = '#ffffff' })
local ox, oy, s = counter_right.origin(1920, 1080)
near(ox, 960 + 120, 1e-9, 'right counter x')
near(oy, 540, 1e-9, 'right counter y')
near(s, 1.0, 1e-12, 'right counter scale')
local model = { count = 45, label = '45', capacity = 45 }
counter_right.frame(model, fake, 1920, 1080)
ok(fake.calls == 1, 'frame emits once')
ok(fake.last_a == 0.8, 'frame passes opacity')
local dl_r = fake.last_dl
ok(#dl_r >= 3, 'frame produces backing tri + pip tri + txt')
local txt = dl_r[#dl_r]
ok(txt.txt, 'last record is text')
ok(txt.txt[1] == '45', 'counter label text')
ok(math.abs(txt.txt[2] - ox) <= 40, 'text near origin x')
near(txt.txt[3], oy, 1e-9, 'text at origin y')
ok(dl_r[1].tri[1] == ox - 14, 'backing x = origin - 14')
local counter_left = counter.new({ side = 'left', offset_x = 120 })
local lx, ly = counter_left.origin(1920, 1080)
near(lx, 960 - 120, 1e-9, 'left counter x')
near(ly, 540, 1e-9, 'left counter y')
local ox3, _, s3 = counter_right.origin(1920, 1440)
near(s3, 4 / 3, 1e-12, 'counter scale at 1440p')
near(ox3, 960 + 120 * (4 / 3), 1e-9, 'counter x scales at 1440p')
local oxu, _, su = counter_right.origin(2560, 1080)
near(su, 1.0, 1e-12, 'counter scale ultrawide')
near(oxu, 1280 + 120, 1e-9, 'counter x ultrawide (center + offset)')

print('hd2ui core: ' .. checks .. ' checks passed')
print('OK-CORE')
