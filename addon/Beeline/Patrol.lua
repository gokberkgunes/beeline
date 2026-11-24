-- Quest givers and hand-ins that walk a route instead of standing at one spot (the Centaur Pariah's loop in southern
-- Desolace, the Gizelton caravan down Desolace's road, Crier Goodman). The plan's spot for them is only where they
-- spawn, so the arrow said "8 yd to go" to an empty field. ns.PATROLS (QuestData.lua, tools/gen-quest-data.js) has
-- every such NPC's route from QuestieDB, none picked by hand; here a step finds its NPC's route:
--   the card says the NPC walks a route, the arrow points at the nearest point of it, the world map draws it (Pins).
-- Routes shorter than Patrol.MIN_YD are ignored: the NPC shuffles about its spot and the spot is right.
local _, ns = ...
local Patrol = {}
ns.Patrol = Patrol
local HBD = LibStub("HereBeDragons-2.0")

Patrol.MIN_YD = 25  -- a route that stays within this of its middle is a spot
Patrol.NEAR_YD = 150 -- a route of another NPC of the same name: none of it this near the step's spot

local parsed = {} -- [name] = { raw = the string it was read from, list = { { m, pts = { {x, y}... } }... } or false }
local function routes(name)
  local raw = ns.PATROLS and ns.PATROLS[name]
  local c = parsed[name]
  if c and c.raw == raw then return c.list end -- (read again when the data changes: a test's own routes)
  local r = false
  if raw then
    r = {}
    for seg in raw:gmatch("[^|]+") do
      local m, rest = seg:match("^(%d+):(.+)$")
      if m then
        local pts = {}
        for x, y in rest:gmatch("([%d.]+),([%d.]+)") do pts[#pts + 1] = { tonumber(x), tonumber(y) } end
        if #pts >= 2 then r[#r + 1] = { m = tonumber(m), pts = pts } end
      end
    end
  end
  parsed[name] = { raw = raw, list = r }
  return r
end

-- the world-coordinate form of a route, its middle and how far it reaches from it (yards); cached on the route
local function measure(R)
  if R.w ~= nil then return R.w end
  local w, sx, sy, inst = {}, 0, 0, nil
  for k, p in ipairs(R.pts) do
    local wx, wy, i = HBD:GetWorldCoordinatesFromZone(p[1], p[2], R.m)
    if not wx then R.w = false; return false end
    w[k] = { wx, wy }; sx, sy, inst = sx + wx, sy + wy, i
  end
  local cx, cy = sx / #w, sy / #w
  local reach = 0
  for _, p in ipairs(w) do reach = math.max(reach, math.sqrt((p[1] - cx) ^ 2 + (p[2] - cy) ^ 2)) end
  R.w, R.inst, R.cx, R.cy, R.reach = w, inst, cx, cy, reach
  return w
end

-- the route step s's NPC walks: { m, pts (map), w (world), inst, reach }, or nil (the NPC stands still, or the step
-- is not about meeting one)
function Patrol.For(s)
  if not (s and s.npc and s.m and s.x and (s.k == "accept" or s.k == "turnin")) then return nil end
  local list = routes(s.npc)
  if not list then return nil end
  local sx, sy = HBD:GetWorldCoordinatesFromZone(s.x, s.y, s.m)
  local best, bestD
  for _, R in ipairs(list) do
    if R.m == s.m and measure(R) and R.reach >= Patrol.MIN_YD then
      local d = math.huge
      if sx then for _, p in ipairs(R.w) do d = math.min(d, (p[1] - sx) ^ 2 + (p[2] - sy) ^ 2) end end
      if d <= Patrol.NEAR_YD ^ 2 and (not bestD or d < bestD) then best, bestD = R, d end
    end
  end
  return best
end

-- the point of route R nearest to world position (px, py), on its segments: map x, y (on R.m), world x, y
function Patrol.Nearest(R, px, py)
  local w, pts = R.w, R.pts
  local bx, by, bt, bk, bd = w[1][1], w[1][2], 0, 1, math.huge
  for k = 1, #w - 1 do
    local a, b = w[k], w[k + 1]
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local len2 = dx * dx + dy * dy
    local t = len2 > 0 and ((px - a[1]) * dx + (py - a[2]) * dy) / len2 or 0
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local x, y = a[1] + dx * t, a[2] + dy * t
    local d = (px - x) ^ 2 + (py - y) ^ 2
    if d < bd then bx, by, bt, bk, bd = x, y, t, k, d end
  end
  local a, b = pts[bk], pts[math.min(bk + 1, #pts)]
  return a[1] + (b[1] - a[1]) * bt, a[2] + (b[2] - a[2]) * bt, bx, by
end
