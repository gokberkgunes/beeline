-- What your play really takes, from the game itself, kept in your character's save (BeelineChar.timings) - so the plan's
-- own numbers (a flight's minutes, a quest's work, a zone's stay) can be checked against real play (tools/timings.js).
-- Nothing leaves your machine. Small and capped: the oldest entries go first.
--   fl  flights:  { t, from, to, secs, lvl }    from / to: the flight masters' node names ("Thorium Point, Searing Gorge")
--   q   quests:   { id, acc, ready, tin, lvl }  acc / ready / tin: when picked up, its objectives done, handed in (time())
--   z   zones:    { t, map, lvl }               each zone you enter, when (a stay is the gap to the next)
--   lv  levels:   { t, lvl }                    each ding
-- (t and the quest times are time(): seconds, comparable across sessions; a flight's secs is GetTime(), to 0.1 s)
local _, ns = ...
local T = {}
ns.Timings = T

T.CAP = { fl = 400, q = 800, z = 600, lv = 80 }
T.OPEN_MAX = 60 -- quests picked up and not handed in, followed at most (a long-held quest is still one entry)

local function db()
  local c = ns.char
  if not c then return nil end
  local t = c.timings
  if type(t) ~= "table" or t.v ~= 1 then t = { v = 1, fl = {}, q = {}, z = {}, lv = {}, open = {} }; c.timings = t end
  return t
end
local function push(list, cap, e)
  list[#list + 1] = e
  local over = #list - cap
  if over > 0 then for _ = 1, over do table.remove(list, 1) end end
end
local function now() return time and time() or 0 end
local function level() return (UnitLevel and UnitLevel("player")) or 0 end

-- flights: the node you asked for (TakeTaxiNode) and the one you stand at, then the time from control lost on the
-- taxi to control back
local want -- { from, to } chosen at the flight master
local flying -- { t0 (GetTime), at (time()), from, to }
local function taxiName(i) return TaxiNodeName and TaxiNodeName(i) or nil end
local function currentNode()
  if not (NumTaxiNodes and TaxiNodeGetType) then return nil end
  for i = 1, NumTaxiNodes() do if TaxiNodeGetType(i) == "CURRENT" then return taxiName(i) end end
  return nil
end
function T.Chose(i)
  want = { from = currentNode(), to = taxiName(i) }
end
if hooksecurefunc and TakeTaxiNode then hooksecurefunc("TakeTaxiNode", function(i) pcall(T.Chose, i) end) end
ns.On("PLAYER_CONTROL_LOST", function()
  if not want then return end
  local w = want
  C_Timer.After(0.5, function()
    if ns.Is(UnitOnTaxi, "player") then flying = { t0 = GetTime(), at = now(), from = w.from, to = w.to } end
  end)
  want = nil
end)
ns.On("PLAYER_CONTROL_GAINED", function()
  local f = flying
  flying = nil
  local d = f and db()
  if not d then return end
  local secs = math.floor((GetTime() - f.t0) * 10 + 0.5) / 10
  if secs > 5 then push(d.fl, T.CAP.fl, { f.at, f.from or "?", f.to or "?", secs, level() }) end
end)

-- quests: picked up, objectives done (seen at the state's full look), handed in
ns.On("QUEST_ACCEPTED", function(a, b)
  local id = tonumber(b) or tonumber(a) -- (Classic: index, questID; some builds: questID)
  local d = id and db()
  if not d then return end
  local n = 0
  for _ in pairs(d.open) do n = n + 1 end
  if n >= T.OPEN_MAX or d.open[id] then return end
  d.open[id] = { now(), false, level() }
end)
ns.On("FR_STATE", function()
  local d = ns.char and ns.char.timings
  if not (d and d.open and next(d.open)) then return end
  local St = ns.State
  for id, o in pairs(d.open) do
    if not o[2] and St.QuestReady(id) then o[2] = now() end
  end
end)
ns.On("QUEST_TURNED_IN", function(id)
  id = tonumber(id)
  local d = id and db()
  if not d then return end
  local o = d.open[id]
  d.open[id] = nil
  push(d.q, T.CAP.q, { id, o and o[1] or false, o and o[2] or false, now(), o and o[3] or level() })
end)
ns.On("QUEST_REMOVED", function(id)
  -- (abandoned, or handed in - QUEST_TURNED_IN comes first then): no longer followed
  id = tonumber(id)
  local d = id and ns.char and ns.char.timings
  if d and d.open then C_Timer.After(1, function() if d.open[id] and not (ns.State.OnQuest(id)) then d.open[id] = nil end end) end
end)

-- zones and levels
local lastMap
local function zoneIn()
  local m = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  local d = m and db()
  if not d or m == lastMap then return end
  lastMap = m
  push(d.z, T.CAP.z, { now(), m, level() })
end
ns.On("ZONE_CHANGED_NEW_AREA", function() pcall(zoneIn) end)
ns.On("FR_LOADED", function() C_Timer.After(2, function() pcall(zoneIn) end) end)
ns.On("PLAYER_LEVEL_UP", function(L)
  local d = db()
  if d then push(d.lv, T.CAP.lv, { now(), tonumber(L) or level() }) end
end)

return T
