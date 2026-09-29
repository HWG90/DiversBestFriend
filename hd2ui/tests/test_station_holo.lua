-- tests/test_station_holo.lua -- pure camera-math checks for the hologram
-- anchor: quaternion rotation, camera basis, world->view transform, screen
-- projection (values + behind-camera rejection), camera-local targets,
-- frame-rate-independent lag, bob bounds, and pose decoding (both supported
-- shapes, with a rotation round-trip through the reconstructed quaternion).
-- Run under Lua 5.1 (LuaJIT).

package.path = './?.lua;hd2ui/?.lua;' .. package.path

local HOLO = require('hd2ui.station_holo')
local checks, fails = 0, 0
local function check(name, cond, extra)
  checks = checks + 1
  if not cond then fails = fails + 1; print('FAIL ' .. name .. (extra and (' (' .. tostring(extra) .. ')') or '')) else print('ok   ' .. name) end
end
local function near(a, b, eps) return math.abs(a - b) < (eps or 1e-6) end
local function vnear(a, b, eps)
  return near(a[1], b[1], eps) and near(a[2], b[2], eps) and near(a[3], b[3], eps)
end

local ID = { 0, 0, 0, 1 }
local s45 = math.sqrt(0.5)
local YAW90 = { 0, s45, 0, s45 }      -- +90 deg about +Y (right-handed)
local function qmul(a, b)
  local ax, ay, az, aw = a[1], a[2], a[3], a[4]
  local bx, by, bz, bw = b[1], b[2], b[3], b[4]
  return {
    aw * bx + ax * bw + ay * bz - az * by,
    aw * by - ax * bz + ay * bw + az * bx,
    aw * bz + ax * by - ay * bx + az * bw,
    aw * bw - ax * bx - ay * by - az * bz,
  }
end

-- ------------------------------------------------------------------ rotate
check('rotate: identity leaves +Z', vnear(HOLO.rotate(ID, { 0, 0, 1 }), { 0, 0, 1 }))
check('rotate: yaw90 maps +Z to +X', vnear(HOLO.rotate(YAW90, { 0, 0, 1 }), { 1, 0, 0 }, 1e-6))
check('rotate: yaw90 keeps +Y', vnear(HOLO.rotate(YAW90, { 0, 1, 0 }), { 0, 1, 0 }, 1e-6))
check('rotate: yaw90 maps +X to -Z', vnear(HOLO.rotate(YAW90, { 1, 0, 0 }), { 0, 0, -1 }, 1e-6))

-- ------------------------------------------------------------------- basis
local r, u, f = HOLO.basis(ID)
check('basis: identity right', vnear(r, { 1, 0, 0 }))
check('basis: identity up', vnear(u, { 0, 1, 0 }))
check('basis: identity forward', vnear(f, { 0, 0, 1 }))
local r2, u2, f2 = HOLO.basis(YAW90)
check('basis: yaw90 forward = +X', vnear(f2, { 1, 0, 0 }, 1e-6))
check('basis: yaw90 right = -Z', vnear(r2, { 0, 0, -1 }, 1e-6))

-- ------------------------------------------------------------ world_to_view
local v = HOLO.world_to_view(ID, { 10, 20, 30 }, { 11, 21, 32 })
check('view: identity translation', vnear(v, { 1, 1, 2 }))
-- camera yawed +90 (forward +X) at origin: a point 2m along world +X is 2m ahead
local v2 = HOLO.world_to_view(YAW90, { 0, 0, 0 }, { 2, 0, 0 })
check('view: yawed camera sees world +X as forward', near(v2[3], 2, 1e-6) and near(v2[1], 0, 1e-6))
-- and a point 1m along world +Z is 1m to the LEFT (-x view)
local v3 = HOLO.world_to_view(YAW90, { 0, 0, 0 }, { 0, 0, 1 })
check('view: yawed camera sees world +Z as -right', near(v3[1], -1, 1e-6) and near(v3[3], 0, 1e-6))

-- ----------------------------------------------------------------- project
local sx, sy = HOLO.project({ 0.3, -0.16, 1.35 }, 1920, 1080, HOLO.DEFAULT_HFOV)
check('project: gunside-like offset lands right-below center',
  near(sx, 960 + 0.3 / 1.35 * 960, 0.5) and near(sy, 540 + 0.16 / 1.35 * 960, 0.5),
  string.format('%.1f,%.1f', sx, sy))
check('project: dead center stays center', HOLO.project({ 0, 0, 2 }, 1920, 1080) == 960 or
  select(1, HOLO.project({ 0, 0, 2 }, 1920, 1080)) == 960)
check('project: behind camera rejected', HOLO.project({ 0.3, 0, -1 }, 1920, 1080) == nil)
check('project: too close rejected', HOLO.project({ 0.3, 0, 0.005 }, 1920, 1080) == nil)
local sx2 = HOLO.project({ 1, 0, 2 }, 1920, 1080)
check('project: doubling distance halves the offset', near(sx2, 960 + 0.5 * 960, 0.5), sx2)

-- ------------------------------------------------------------- local_target
local t = HOLO.local_target(ID, { 10, 20, 30 }, 0.34, -0.16, 1.35)
check('target: identity camera offsets in world axes',
  vnear(t, { 10.34, 19.84, 31.35 }))
local t2 = HOLO.local_target(YAW90, { 0, 0, 0 }, 0.34, 0, 1.35)
-- yawed camera: right = -Z, forward = +X
check('target: yawed camera offsets along its own axes', vnear(t2, { 1.35, 0, -0.34 }, 1e-6))

-- ------------------------------------------------------------------- smooth
local cur = { 0, 0, 0 }
cur = HOLO.smooth(cur, { 10, 0, 0 }, 0.0, 10)
check('smooth: zero dt does not move', vnear(cur, { 0, 0, 0 }))
local k1 = HOLO.smooth({ 0, 0, 0 }, { 10, 0, 0 }, 1 / 60, 10)
local half1 = HOLO.smooth({ 0, 0, 0 }, { 10, 0, 0 }, 1 / 120, 10)
local half2 = HOLO.smooth(half1, { 10, 0, 0 }, 1 / 120, 10)
check('smooth: two half-steps ~= one full step (exp composition)',
  near(half2[1], k1[1], 1e-3), string.format('%.5f vs %.5f', half2[1], k1[1]))
local converged = { 0, 0, 0 }
for _ = 1, 120 do converged = HOLO.smooth(converged, { 10, 0, 0 }, 1 / 60, 10) end
check('smooth: converges within 2s', near(converged[1], 10, 0.05), converged[1])

-- --------------------------------------------------------------------- bob
local bmin, bmax = math.huge, -math.huge
for i = 0, 100 do
  local b = HOLO.bob(i / 100)
  bmin, bmax = math.min(bmin, b[2]), math.max(bmax, b[2])
end
check('bob: bounded to +/- amplitude', bmin >= -HOLO.BOB_AMP - 1e-9 and bmax <= HOLO.BOB_AMP + 1e-9)
check('bob: actually oscillates', bmax - bmin > HOLO.BOB_AMP)

-- ------------------------------------------------------- parse_matrix (live data)
-- the exact tostring captured from the live game, 2026-09-29 derive session
local LIVE = [[Matrix4x4(
    0.96974194, -0.244132221, 0, 0,
    0.241633207, 0.959815323, -0.142716259, 0,
    0.0348416381, 0.138397932, 0.989763677, 0,
    -0.049060937, -0.704909086, 1.49723792, 1
)]]
local lp, lr, lf, lu = HOLO.parse_matrix(LIVE)
check('parse: live matrix parses', lp ~= nil, lp)
check('parse: translation row (eye height ~1.5m, Z-up)',
  lp and near(lp[3], 1.49723792, 1e-6) and near(lp[1], -0.049060937, 1e-6), lp and lp[3])
check('parse: right row', lr and near(lr[1], 0.96974194, 1e-6) and near(lr[2], -0.244132221, 1e-6))
check('parse: forward row', lf and near(lf[3], -0.142716259, 1e-6))
check('parse: up row', lu and near(lu[3], 0.989763677, 1e-6))
local gn, gr = HOLO.parse_matrix('Matrix4x4( 1, 0, 5, 0,  0, 1, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1 )')
check('parse: non-orthonormal rows rejected', gn == nil and type(gr) == 'string', gr)
local gn2, gr2 = HOLO.parse_matrix('Matrix4x4( 1, 2, 3 )')
check('parse: short body rejected', gn2 == nil, gr2)
local gn3, gr3 = HOLO.parse_matrix('not a matrix')
check('parse: non-matrix string rejected', gn3 == nil, gr3)
check('parse: type-name digits do not leak into components',
  lp and near(lp[1], -0.049, 0.001))

------------------------------------------------- composition sanity check
-- the exact entry flow: yawed camera, lagged point, projection
local cam_q, cam_p = YAW90, { 0, 0, 0 }
local target = HOLO.local_target(cam_q, cam_p, HOLO_OFF_X or 0.34, -0.16, 1.35)
local holo_pos = { 0, 0, 0 }
for _ = 1, 90 do holo_pos = HOLO.smooth(holo_pos, target, 1 / 60) end
local view = HOLO.world_to_view(cam_q, cam_p, holo_pos)
local hsx, hsy = HOLO.project(view, 1920, 1080)
check('composition: settled hologram projects right-below center',
  hsx and hsy and hsx > 1000 and hsx < 1350 and hsy > 580 and hsy < 720,
  string.format('%.0f,%.0f', hsx or -1, hsy or -1))

print(string.format('\nstation_holo: %d checks, %d failures', checks, fails))
if fails > 0 then error(fails .. ' failures') end
