-- Small shared helpers.
--   ns.Util.WPos(s)       a step's world position { x, y, instance } (cached per step), or nil (no place, or unknown)
--   ns.Util.ForgetWPos(s) drops that cache for a step whose spot changed
--   ns.Util.MapName(m)    a map's name ("map <id>" when the game has none)
--   ns.Util.PlanRoute()   your plan: the path you return to, else the first main route
--   ns.Util.Plain(v)      v, or nil when it is nil or one of Forever's secret values (hidden from addons)
--   ns.Util.Call(fn, ...) fn's values under pcall (every one), nothing when fn isn't a function or errors
--   ns.Util.PlainCall(fn, ...)  the same with each value through Plain (nil when fn isn't a function or errors)
--   ns.Util.Sub(t, key)   t[key], made an empty table when it isn't one (a saved sub-table)
--   ns.Nope(q)            you said you won't do quest q (its value: true, or how)
local _, ns = ...
local pcall = ns.PCall or pcall -- (a job never pauses under it: Core.lua)
local Util = {}
ns.Util = Util
local HBD = LibStub("HereBeDragons-2.0")

local worldOf = setmetatable({}, { __mode = "k" })
function Util.WPos(s)
  if not (s and s.m and s.x and s.y) or s.unknown then return nil end -- (an unknown step's spot is only its place in the order)
  local w = worldOf[s]
  if w == nil then local x, y, inst = HBD:GetWorldCoordinatesFromZone(s.x, s.y, s.m); w = x and { x, y, inst } or false; worldOf[s] = w end
  return w or nil
end
-- (a step whose spot changed, e.g. a learned pier: recompute its WPos)
function Util.ForgetWPos(s) worldOf[s] = nil end

-- (names cached per map, reset when tests swap the lookup function)
local nameOf, nameFn = {}, nil
function Util.MapName(m)
  local fn = C_Map and C_Map.GetMapInfo
  if fn ~= nameFn then nameOf, nameFn = {}, fn end
  local n = m ~= nil and nameOf[m]
  if n then return n end
  local i = fn and fn(m)
  if i and i.name then if m ~= nil then nameOf[m] = i.name end; return i.name end
  return "map " .. tostring(m)
end

function Util.PlanRoute()
  return (ns.ResolvePath and ns.ResolvePath(ns.char and ns.char.returnTo)) or (ns.MainRoutes and ns.MainRoutes()[1])
end

function ns.Nope(q) return q and ns.char and ns.char.nope and ns.char.nope[q] end

function Util.Plain(v)
  if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
  return v
end
local Plain = Util.Plain
local function pass(ok, ...) if ok then return ... end end
function Util.Call(fn, ...) if type(fn) == "function" then return pass(pcall(fn, ...)) end end
-- (each value in turn: no table per call)
local function plainN(n, v, ...)
  if n <= 1 then return Plain(v) end
  return Plain(v), plainN(n - 1, ...)
end
local function plainPass(ok, ...)
  if not ok then return nil end
  local n = select("#", ...)
  if n == 0 then return end
  return plainN(n, ...)
end
function Util.PlainCall(fn, ...)
  if type(fn) ~= "function" then return nil end
  return plainPass(pcall(fn, ...))
end
function Util.Sub(t, key)
  local v = t[key]
  if type(v) ~= "table" then v = {}; t[key] = v end
  return v
end
