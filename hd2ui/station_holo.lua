-- hd2ui/station_holo.lua -- camera math for the Dead Space-style hologram
-- anchor. Pure Lua (no FFI, no game): the entry feeds it the live camera
-- pose each frame; everything here is headless-testable.
--
-- The station's target point is defined in CAMERA-LOCAL space (right/up/
-- forward meters), so it rides the weapon line. It is tracked in WORLD space
-- with an exponential lag, so fast aim sweeps make the hologram trail and
-- settle -- the "floating in space" cue -- plus a slow idle bob. The world
-- point is transformed back into view space and perspective-projected every
-- frame, giving natural parallax and a little scale breathing.
--
-- Conventions: view space is x=right, y=up, z=FORWARD-positive (see
-- M.FORWARD_SIGN); screen space is y-down; projection assumes square pixels.
--
-- Lua 5.1 / LuaJIT.

local M = {}
M.DEFAULT_HFOV = math.rad(90)   -- horizontal fov fallback until the live
                                -- setting is read; parallax strength only
M.FORWARD_SIGN = 1              -- stingray convention check happens live;
                                -- flip to -1 if the hologram projects behind
M.LAG_RATE = 10.0               -- exp smoothing rate (higher = tighter)
M.BOB_AMP = 0.008               -- idle bob, meters along camera up
M.BOB_HZ = 0.7                  -- slow breathing, not a jelly effect

local sin, cos, exp = math.sin, math.cos, math.exp
local V = { x = 1, y = 2, z = 3 }

local function add(a, b) return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
local function scale(a, s) return { a[1] * s, a[2] * s, a[3] * s } end
M.add, M.scale = add, scale

------------------------------------------------------------------------------
-- quaternion: stingray order assumed {x, y, z, w}; normalize defensively
------------------------------------------------------------------------------
local function qnorm(q)
  local n = math.sqrt(q[1] ^ 2 + q[2] ^ 2 + q[3] ^ 2 + q[4] ^ 2)
  if n < 1e-9 then return { 0, 0, 0, 1 } end
  return { q[1] / n, q[2] / n, q[3] / n, q[4] / n }
end

-- rotate vector v by unit quaternion q (x,y,z,w)
function M.rotate(q, v)
  local qx, qy, qz, qw = q[1], q[2], q[3], q[4]
  -- t = 2 * cross(q.xyz, v)
  local tx = 2 * (qy * v[3] - qz * v[2])
  local ty = 2 * (qz * v[1] - qx * v[3])
  local tz = 2 * (qx * v[2] - qy * v[1])
  -- v + qw*t + cross(q.xyz, t)
  return {
    v[1] + qw * tx + (qy * tz - qz * ty),
    v[2] + qw * ty + (qz * tx - qx * tz),
    v[3] + qw * tz + (qx * ty - qy * tx),
  }
end

-- camera basis vectors from the orientation quaternion
function M.basis(q)
  q = qnorm(q)
  local r = M.rotate(q, { 1, 0, 0 })
  local u = M.rotate(q, { 0, 1, 0 })
  local f = M.rotate(q, { 0, 0, M.FORWARD_SIGN })
  return r, u, f
end

-- world point -> view space: v = R^T * (p - cam_pos)
function M.world_to_view(q, cam_pos, p)
  local d = { p[1] - cam_pos[1], p[2] - cam_pos[2], p[3] - cam_pos[3] }
  local r, u, f = M.basis(q)
  return {
    d[1] * r[1] + d[2] * r[2] + d[3] * r[3],
    d[1] * u[1] + d[2] * u[2] + d[3] * u[3],
    d[1] * f[1] + d[2] * f[2] + d[3] * f[3],
  }
end

-- view-space point (z forward) -> screen pixels; nil when behind the camera
function M.project(v, w, h, hfov)
  hfov = hfov or M.DEFAULT_HFOV
  if v[3] <= 0.01 then return nil end
  local fx = (w / 2) / math.tan(hfov / 2)
  local sx = w / 2 + (v[1] / v[3]) * fx
  local sy = h / 2 - (v[2] / v[3]) * fx      -- square pixels; screen y-down
  return sx, sy
end

-- camera-local offset (meters) -> world target for the hologram anchor
function M.local_target(q, cam_pos, dx, dy, dz)
  local r, u, f = M.basis(q)
  return add(cam_pos, add(add(scale(r, dx), scale(u, dy)), scale(f, dz)))
end

-- exponential lag: cur eases toward target, frame-rate independent
function M.smooth(cur, target, dt, rate)
  local k = 1 - exp(-(rate or M.LAG_RATE) * (dt or 0))
  return { cur[1] + (target[1] - cur[1]) * k,
           cur[2] + (target[2] - cur[2]) * k,
           cur[3] + (target[3] - cur[3]) * k }
end

-- idle bob offset (meters) along camera up
function M.bob(t)
  return scale(M.rotate({ 0, 0, 0, 1 }, { 0, 1, 0 }), M.BOB_AMP * sin(t * M.BOB_HZ * 2 * math.pi))
end

------------------------------------------------------------------------------
-- parse the camera world Matrix4x4 from its stingray tostring form:
--   "Matrix4x4( a,b,c,d,  e,f,g,h,  i,j,k,l,  m,n,o,p )"  (4 rows of 4)
-- Row semantics (live-verified 2026-09-29): rows = right/forward/up,
-- translation = row 4, world Z-up. Gated on orthonormality so a format
-- change can never feed garbage into the hologram.
-- Returns pos, right, fwd, up -- or nil, reason.
------------------------------------------------------------------------------
local MAT_NUM = '-?%d*%.?%d+[eE%-+]?%d*'
function M.parse_matrix(s)
  if type(s) ~= 'string' or not s:find('Matrix4x4') then return nil, 'not a matrix string' end
  -- parse only the parenthesized body: the type name itself contains digits
  local body = s:match('Matrix4x4%((.*)%)')
  if not body then return nil, 'no matrix body' end
  local f = {}
  for num in body:gmatch(MAT_NUM) do f[#f + 1] = tonumber(num) end
  if #f < 16 then return nil, 'expected 16 components, got ' .. #f end
  local right = { f[1], f[2], f[3] }
  local fwd = { f[5], f[6], f[7] }
  local up = { f[9], f[10], f[11] }
  local pos = { f[13], f[14], f[15] }
  local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
  if math.abs(dot(right, right) - 1) > 0.01 then return nil, 'right row not unit' end
  if math.abs(dot(fwd, fwd) - 1) > 0.01 then return nil, 'forward row not unit' end
  if math.abs(dot(right, fwd)) > 0.01 or math.abs(dot(right, up)) > 0.01 or math.abs(dot(fwd, up)) > 0.01 then
    return nil, 'rows not orthogonal'
  end
  return pos, right, fwd, up
end

------------------------------------------------------------------------------
-- defensive decode of the live camera pose. stingray bindings were never
-- probed for debug_camera_pose's exact return shape; support the plausible
-- ones and let the entry log what worked.
-- Returns pos {x,y,z}, quat {x,y,z,w}, shape_name -- or nil, err.
------------------------------------------------------------------------------
local function v3(v)
  if type(v) ~= 'userdata' and type(v) ~= 'table' then return nil end
  local ok, x, y, z = pcall(function() return v.x, v.y, v.z end)
  if ok and type(x) == 'number' and type(y) == 'number' and type(z) == 'number' then
    return { x, y, z }
  end
  return nil
end
local function quat(q)
  if type(q) ~= 'userdata' and type(q) ~= 'table' then return nil end
  local ok, x, y, z, w = pcall(function() return q.x, q.y, q.z, q.w end)
  if ok and type(x) == 'number' and type(y) == 'number' and type(z) == 'number' and type(w) == 'number' then
    return { x, y, z, w }
  end
  return nil
end

function M.decode_pose(a, b, c)
  -- (Vector3 pos, Quaternion rot)
  local p, q = v3(a), quat(b)
  if p and q then return p, q, 'vec3+quat' end
  -- (Camera handle) with sr.Camera accessors -- handled by the entry, which
  -- knows the sr table; here: (pos, fwd, up) basis triple
  p = v3(a)
  local f, u = v3(b), v3(c)
  if p and f and u then
    -- rebuild a rotation quaternion from the orthonormal basis. With rows
    -- right/up/forward, the quat-recovery matrix (v'=Mv) is the transpose:
    --   M11=rx M12=u1 M13=f1 / M21=ry M22=u2 M23=f2 / M31=rz M32=u3 M33=f3
    -- Shepperd's method, branch on the largest diagonal.
    -- right = up x forward (right-handed: facing +X with +Y up, right is -Z)
    local rx = u[2] * f[3] - u[3] * f[2]
    local ry = u[3] * f[1] - u[1] * f[3]
    local rz = u[1] * f[2] - u[2] * f[1]
    local m = { rx, ry, rz, u[1], u[2], u[3], f[1], f[2], f[3] }
    local tr = m[1] + m[5] + m[9]
    local out
    if tr > 0 then
      local s = math.sqrt(tr + 1) * 2
      out = { (m[6] - m[8]) / s, (m[7] - m[3]) / s, (m[2] - m[4]) / s, 0.25 * s }
    elseif m[1] > m[5] and m[1] > m[9] then
      local s = math.sqrt(1 + m[1] - m[5] - m[9]) * 2
      out = { 0.25 * s, (m[4] + m[2]) / s, (m[7] + m[3]) / s, (m[6] - m[8]) / s }
    elseif m[5] > m[9] then
      local s = math.sqrt(1 + m[5] - m[1] - m[9]) * 2
      out = { (m[4] + m[2]) / s, 0.25 * s, (m[8] + m[6]) / s, (m[7] - m[3]) / s }
    else
      local s = math.sqrt(1 + m[9] - m[1] - m[5]) * 2
      out = { (m[7] + m[3]) / s, (m[8] + m[6]) / s, 0.25 * s, (m[2] - m[4]) / s }
    end
    return p, qnorm(out), 'pos+fwd+up'
  end
  return nil, 'unrecognized pose shape'
end

return M
