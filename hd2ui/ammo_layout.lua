-- hd2ui/ammo_layout.lua -- Dashboard layout state for the ammo HUD.
--
-- Every graphical element has an id, a default anchor (defined by the style /
-- bars code) and a user offset (dx, dy) in 1080p reference units. A layout
-- mode (toggled by a user-bound key via ModBindingsMenu) turns the HUD into a
-- live editor: select an element, nudge it with bound directions, save. Offsets
-- persist to a plain text file (in-game io is available on the live install).
--
-- Element boxes are used to draw selection brackets; they are coarse on
-- purpose -- the bracket is a grab handle, not a bounding-rect proof.
--
-- Lua 5.1 / LuaJIT.

local M = {}

M.active = false        -- dashboard mode on/off
M.sel = 1               -- index into M.order
M.order = { 'label', 'mag', 'pack', 'heat', 'fuel', 'charge' }   -- 'pips' folded into 'label' module
-- station geometry (y-down, 1080p units): the unified panel lives at x=34..
M.box = {
  label  = { x = 34, y = -17, w = 120, h = 46 },   -- charcoal plate + tray
  mag    = { x = 34, y = -17, w = 30, h = 34 },    -- AC column + count zone
  pack   = { x = 90, y = -12, w = 72, h = 26 },    -- AC magazine bars area
  heat   = { x = 34, y = -17, w = 120, h = 46 },   -- plate w/ heat bar + sinks
  fuel   = { x = 34, y = -17, w = 128, h = 34 },   -- plate w/ integrated dial
  charge = { x = 36, y = 21, w = 116, h = 13 },    -- sub-tray strip
  pips   = { x = 88, y = -12, w = 62, h = 26 },    -- legacy: rifle pip area
}
M.names = {
  label = 'COUNTER TEXT', mag = 'MAG COLUMN', pack = 'BACKPACK PANEL',
  heat = 'HEAT GAUGE', fuel = 'FUEL DIAL', charge = 'CHARGE BAR', pips = 'SPARE PIPS',
}

local offsets = {}
for _, id in ipairs(M.order) do offsets[id] = { x = 0, y = 0 } end

function M.get(id)
  local o = offsets[id]
  if not o then return 0, 0 end
  return o.x, o.y
end

function M.nudge(id, dx, dy)
  local o = offsets[id]
  if o then o.x = o.x + dx; o.y = o.y + dy end
end

function M.cycle(dir)
  M.sel = M.sel + (dir or 1)
  if M.sel > #M.order then M.sel = 1 end
  if M.sel < 1 then M.sel = #M.order end
end

function M.current() return M.order[M.sel] end

------------------------------------------------------------------------------
-- persistence: one line per element 'id dx dy' (integers, reference units)
------------------------------------------------------------------------------
function M.load(path)
  if not path then return false end
  local ok, f = pcall(io.open, path, 'r')
  if not ok or not f then return false end
  local n = 0
  for line in f:lines() do
    local id, x, y = line:match('^(%w+)%s+(-?%d+)%s+(-?%d+)$')
    if id and offsets[id] then
      offsets[id].x = tonumber(x); offsets[id].y = tonumber(y); n = n + 1
    end
  end
  f:close()
  return n > 0, n
end

function M.save(path)
  if not path then return false end
  local ok, f = pcall(io.open, path, 'w')
  if not ok or not f then return false end
  f:write('# dbf ammo hud layout (1080p reference units)\n')
  for _, id in ipairs(M.order) do
    f:write(id .. ' ' .. math.floor(offsets[id].x) .. ' ' .. math.floor(offsets[id].y) .. '\n')
  end
  f:close()
  return true
end

------------------------------------------------------------------------------
-- input pump: pure logic over an injected down(vk) predicate -- unit-testable
-- and independent of ffi/binding availability. arrows+WASD move, TAB cycles,
-- ENTER saves, ESC exits (auto-saves).
M.prev = {}
M.nat = 0
function M.poll(clock, down)
  if not M.active then M.prev = {} return nil end
  local id = M.current()
  local function edge(vk)
    local d = down(vk)
    local e = d and not M.prev[vk]
    M.prev[vk] = d
    return e
  end
  local function hold(vk, dx, dy)
    local d = down(vk)
    if d and (not M.prev[vk] or clock >= M.nat) then
      M.nat = clock + 0.07
      M.nudge(id, dx, dy)
    end
    M.prev[vk] = d
  end
  hold(0x25, -3, 0)  -- left
  hold(0x27, 3, 0)   -- right
  hold(0x26, 0, -3)  -- up   (positive y = DOWN on screen, field-confirmed)
  hold(0x28, 0, 3)   -- down
  hold(0x41, -3, 0)  -- a
  hold(0x44, 3, 0)   -- d
  hold(0x57, 0, -3)  -- w
  hold(0x53, 0, 3)   -- s
  if edge(0x09) then M.cycle(1) end
  if edge(0x0D) then return 'save' end
  if edge(0x1B) then
    M.active = false
    return 'exit'
  end
  return nil
end

return M
