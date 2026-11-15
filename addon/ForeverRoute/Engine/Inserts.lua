-- The route engine, adding a stop where it costs least, and side trips merged into your route. Part of Engine.lua, split out as is (the code review: Engine.lua was 13 features in
-- one file); loaded right after it, so its event handlers run in the same order as before.
local _, ns = ...
local Engine = ns.Engine
local State = ns.State
local function steps() return ForeverRouteData and ForeverRouteData.steps or {} end
local function key(i) return Engine.Key(i) end
local keyCache = Engine._keyCache
local HBD = LibStub("HereBeDragons-2.0")
local wpos = ns.Util.WPos

----------------------------------------------------------------------------------------------------------------
-- Adding a stop (like adding a stop in a maps app): a quest you finished that the route has no hand-in for gets one,
-- slotted into the cheapest gap between two neighbouring stops - cost d(a,X) + d(X,b) - d(a,b) - or made the very next
-- step if "from where you are" is the cheapest gap. One pass over the stops; no replan. Only after the current step,
-- and only on the stop's continent. Hand-in spots: ForeverRouteEnders from the plan.
-- A gap is priced as a walk only when it is one. The straight-line detour d(a,X) + d(X,b) - d(a,b) means something
-- when you cover a -> b on the ground; when the way from a to b is a flight, a boat or your hearthstone (you are in
-- Southshore and the step is in Duskwood; a hand-in added in another zone), nothing between the two ends is "on the
-- way" - Thorium Point lies under the line from Southshore to Duskwood, and a level 30 was sent there for its flight
-- path as the very next step. Such a gap takes a stop only at one of its ends: there and back from where you leave
-- or from where you arrive, if the stop is ground travel from that end.
----------------------------------------------------------------------------------------------------------------
local function wd(a, b) return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2) end
-- do you cover a -> b on the ground? The same zone: yes. Another zone: what the trip planner says (ns.Travel.Plan, the
-- one the card's travel line comes from) - rides only. A place whose zone is unknown: no.
local groundMemo = {}
function Engine.OnFoot(am, ax, ay, bm, bx, by)
  if not (am and bm) then return false end
  if am == bm then return true end
  if not (ax and ay and bx and by and ns.Travel and ns.Travel.Plan) then return false end
  local n = State.KnownTaxiCount()
  local okB, bind = pcall(GetBindLocation)
  local k = table.concat({ am, math.floor(ax * 400), math.floor(ay * 400), bm, math.floor(bx * 400), math.floor(by * 400), n, UnitLevel("player") or 0, tostring(okB and bind) }, ":")
  local v = groundMemo[k]
  if v == nil then
    local ok, legs = pcall(ns.Travel.Plan, { m = am, x = ax, y = ay }, { m = bm, x = bx, y = by })
    v = ok and type(legs) == "table" and legs[1] ~= nil or false
    if v then for _, l in ipairs(legs) do if l.how ~= "ride" then v = false; break end end end
    groundMemo[k] = v
  end
  return v
end

-- opts.at: at this step, no search (a quest giver you stand next to: now). opts.dry: nothing is added; -> where, cost
-- opts.maxIndex: only before this step (a side quest's objective: while the quest still gives XP)
function Engine.InsertStop(new, px, py, pinst, opts)
  opts = opts or {}
  local list = steps()
  local cur = Engine.current
  if not cur then return nil end
  local from = math.max(cur, opts.minIndex or cur)
  local X = wpos(new); if not X then return nil end
  -- gaps: (you -> current step) when you're on the same map, then each pair of neighbouring stops after it
  local best, bestCost = opts.at, nil
  local prev = nil -- the near end of the gap: { w = world position, m, x, y = its zone position }
  if px and pinst == X[3] and from == cur then local pm, zx, zy = ns.State.Position(); prev = { w = { px, py, pinst }, m = pm, x = zx, y = zy } end
  -- chained stops start after a given step: the gap right after it counts too
  if from > cur and list[from - 1] then local t = list[from - 1]; local w = wpos(t); if w and w[3] == X[3] then prev = { w = w, m = t.m, x = t.x, y = t.y } end end
  -- opts.onMap: only a gap with an end in that zone (straight lines say nothing across a zone border: mountains)
  local function touches(a, bm) return not opts.onMap or (a and a.m == opts.onMap) or bm == opts.onMap end
  -- what the stop costs in the gap a -> s (nil: this gap can't take it)
  local function gapCost(a, s, w)
    if not touches(a, s.m) then return nil end
    if Engine.OnFoot(a.m, a.x, a.y, s.m, s.x, s.y) then return wd(a.w, X) + wd(X, w) - wd(a.w, w) end
    local c
    if Engine.OnFoot(a.m, a.x, a.y, new.m, new.x, new.y) then c = 2 * wd(a.w, X) end
    if Engine.OnFoot(new.m, new.x, new.y, s.m, s.x, s.y) then local c2 = 2 * wd(X, w); if not c or c2 < c then c = c2 end end
    return c
  end
  -- riding the current travel step (no flight path there yet): the road from you to the first stop at the other end
  -- is a real stretch - a stop on it goes before the travel step, i.e. you do it on the way
  local ride = nil
  if prev and from == cur and list[cur] and list[cur].k == "fly" and Engine.TravelPlan then -- not for stops that must come after an earlier one
    local plan = Engine.TravelPlan(list[cur])
    local m = ns.State.Position()
    -- only a real ride: if the trip there involves boats or flights, stops at the other end go after the travel step
    local trip = Engine.TravelFor and Engine.TravelFor(list[cur])
    local riding = not trip or (trip.how == "ride" and not (trip.legs and #trip.legs > 1))
    if riding and plan and (plan.ride or not plan.via or plan.via == m) then ride = prev end
  end
  for i = from, opts.at and from - 1 or math.min(#list, opts.maxIndex or #list) do
    local s = list[i]
    if s.k == "fly" or s.k == "hearth" then prev = nil -- a flight in between: the gap doesn't count
    else
      local w = wpos(s)
      if w and w[3] == X[3] then
        if ride then
          if touches(ride, s.m) then
            local c = wd(ride.w, X) + wd(X, w) - wd(ride.w, w)
            if not bestCost or c < bestCost then bestCost, best = c, cur end -- before the travel step: on the way
          end
          ride = nil
        end
        -- never between two steps at the same NPC (turn in to Takar, accept from Takar): do both while you are there
        local split = list[i - 1] and list[i - 1].npc and list[i - 1].npc == s.npc
        if prev and not split then
          local c = gapCost(prev, s, w)
          if c and (not bestCost or c < bestCost) then bestCost, best = c, i end -- insert before step i
        end
        prev = { w = w, m = s.m, x = s.x, y = s.y }
      end
    end
  end
  -- after the last stop on that map, as the next one (if there was a stretch there at all)
  if not best and prev and not opts.maxIndex then best = #list + 1 end
  if not best then return nil end
  Engine.lastInsertCost = bestCost
  if opts.maxCost and (bestCost or math.huge) > opts.maxCost then return nil end
  if opts.dry then return best, bestCost end
  -- the current step stays current: a stop that goes "before the current step" becomes the step right after it,
  -- unless it\x27s cheapest to do first, in which case it\x27s inserted at the current position (shown next)
  -- the stop belongs to the stretch it lands in: the hub of the step it goes before (or the one before it, at the end).
  -- Whatever sec it carried (a copy from another side trip points into that trip's sections) would put the wrong hub
  -- on the card and a stray header in the list.
  local around = list[best] or list[best - 1]
  if around then new.sec = around.sec end
  table.insert(list, best, new)
  -- everything after it moved down one: step numbers, and the "where next?" choices (they are kept by position)
  for i = best, #list do list[i].id = i end
  local d = ForeverRouteData
  if d and list == d.steps then for _, c in ipairs(d.choices or {}) do if c.at and c.at >= best then c.at = c.at + 1 end end end
  if ns.Why then ns.Why("insert", "added " .. (new.k or "") .. " " .. (new.name or (new.k == "fp" and ((new.zone or "?") .. " (" .. tostring(new.npc) .. ")")) or new.npc or "") .. " as step " .. best .. " (" .. (opts.why or "you finished it; this is where it costs least") .. ")") end
  keyCache[list] = nil
  if Engine.focus and Engine.focus >= best then Engine.focus = Engine.focus + 1 end
  if Engine.view and Engine.view >= best then Engine.view = Engine.view + 1 end
  return best
end

-- side trips merge: the next stops of unfinished side trips (class quests, the sleeping bag), where they cost least,
-- if the detour is small. On a side trip, the other side trips join it; on your leveling path they join it too, but
-- only where the path really passes by (the player's choice, 2026-11-08: fold them in, and keep them as side trips)
Engine.MERGE_MAX_YARDS = 3000
Engine.MERGE_PATH_YARDS = 600
Engine.FP_DETOUR_YARDS = 600
function Engine.MergeSideTrips()
  local d = ForeverRouteData
  -- the flag lives on the step list: switching to the trip again unpacks a fresh list, which needs merging again
  if not (d and d.steps) or d.steps._merged or not ns.DungeonRoutes then return false end
  if d.branch or (d.dungeon and not d.special) then return false end -- a dungeon route stays about its dungeon
  local maxCost = d.special and Engine.MERGE_MAX_YARDS or Engine.MERGE_PATH_YARDS
  d.steps._merged = true
  local px, py, pinst = HBD:GetPlayerWorldPosition()
  local added = 0
  -- what the route already does (the planner puts some of these quests in your path itself): never twice
  local onRoute
  local function index() -- rebuilt after each insert: later steps move down one
    onRoute = {}
    for i, s in ipairs(d.steps) do if s.q and s.q > 0 and not onRoute[s.k .. ":" .. s.q] then onRoute[s.k .. ":" .. s.q] = i end end
  end
  index()
  for _, r in ipairs(ns.DungeonRoutes()) do
    if r.special and r.id ~= d.id and (UnitLevel("player") or 1) >= (tonumber(r.needsLevel) or 1) then
      local minI = Engine.current or 1
      for _, s in ipairs(ns.Steps(r)) do
        local skip = s.k == "fly" or s.k == "hearth" or s.unknown or not (s.q and s.q > 0 and s.m and s.x)
          or State.IsCompleted(s.q) or (s.k == "accept" and State.OnQuest(s.q)) or onRoute[s.k .. ":" .. s.q]
        -- a chain step the route already has: the rest of the chain goes after it
        local there = s.q and onRoute[s.k .. ":" .. s.q]
        if there then minI = math.max(minI, there + 1) end
        if not skip then
          local copy = {}; for k, v in pairs(s) do copy[k] = v end
          copy.inserted, copy.id, copy.wp = true, nil, nil
          copy.note = "On the way: " .. (r.dungeonName or r.title) .. "."
          local at = Engine.InsertStop(copy, px, py, pinst, { minIndex = minI, maxCost = maxCost, why = "on the way for " .. (r.dungeonName or r.title) })
          if not at then
            if ns.Why then ns.Why("merge", "left " .. (copy.k or "") .. " " .. (copy.name or "") .. " (" .. (r.dungeonName or r.title) .. ") for later: " .. (Engine.lastInsertCost and string.format("a %d yd detour, over the %d yd limit", Engine.lastInsertCost, Engine.MERGE_MAX_YARDS) or "another continent or nowhere near this trip")) end
            break -- the rest of that chain waits
          end
          minI = at + 1; added = added + 1; index()
        end
      end
    end
  end
  -- flight paths you do not have, close to the trip (a small detour now saves trips later): only where the trip has
  -- you in the flight master's own zone, on a stretch you cover on the ground
  local have = {}; for _, s in ipairs(steps()) do if s.k == "fp" and s.m then have[s.m] = true end end
  for m, list in pairs(ns.FLIGHT or {}) do
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(m)
    local zn = info and info.name
    if zn and not have[m] and not Engine.KnowsFlightIn(zn) then
      local f = list[1]
      local at = Engine.InsertStop({ k = "fp", npc = f[3], m = m, x = f[1], y = f[2], zone = zn, r = 8, inserted = true, note = "A flight path you do not have yet - saves trips later." }, px, py, pinst, { maxCost = Engine.FP_DETOUR_YARDS, onMap = m, why = "a flight path close to this trip" })
      if at then added = added + 1 end
    end
  end
  if added > 0 then ns.Print(added .. " stop" .. (added == 1 and "" or "s") .. " added on the way: other side trips and flight paths you do not have (see the list).") end
  return added > 0
end
ns.On("FR_ROUTE_CHANGED", function() C_Timer.After(0.6, function() if Engine.MergeSideTrips() then Engine.Refresh() end end) end)
ns.On("FR_LOADED", function() C_Timer.After(3.5, function() if Engine.MergeSideTrips() then Engine.Refresh() end end) end)

-- the hand-in spots (ForeverRouteEnders) of the quests in your log: the list covers every quest you could take
-- (~1000), so walk your log (at most 40) and look each one up instead of asking the game about all of them
function Engine.LogEnders()
  local enders = ForeverRouteEnders
  if not enders then return {} end
  local inLog = {}
  Engine.logLevels = {} -- quest level by id, for the gray check below
  local n = C_QuestLog and C_QuestLog.GetNumQuestLogEntries and select(2, pcall(C_QuestLog.GetNumQuestLogEntries))
  if type(n) == "number" and n > 0 and C_QuestLog.GetInfo then
    for i = 1, n do
      local ok, info = pcall(C_QuestLog.GetInfo, i)
      if ok and info and not info.isHeader and info.questID and enders[info.questID] then inLog[info.questID] = enders[info.questID]; Engine.logLevels[info.questID] = info.level end
    end
    return inLog
  end
  return enders -- no quest log to read (tests): every spot, each checked with QuestReady
end
-- finished quests in your log with no hand-in on the route: add one where it costs least
-- how far out of the way (yards, there and back) a gray hand-in may take you: about a 20-second walk
Engine.GRAY_DETOUR_YD = 150
-- Where it costs least by the walk can be where the plan next passes the hand-in, levels later: the quest is gray by
-- then and pays a tenth (The Perenolde Tiara, finished at 37, filed under the plan's Stormwind visit at 59 - tester).
-- The XP it would lose by waiting is weighed against going now, there and back, at half a level an hour (as a
-- leftover's trip is, Engine/Worth.lua); worth more than that trip, the hand-in is your next stop.
-- -> the step the hand-in goes before now (nil: where the walk says), the XP it would lose, the trip's seconds
function Engine.HandInNow(step, ql, at)
  local list = steps()
  local me = UnitLevel and UnitLevel("player") or 1
  if type(ql) ~= "number" or not at or not Engine.current then return nil end
  local t = list[at] or list[at - 1] or list[#list]
  local then_ = math.max(me, tonumber(t and t.lvl) or me)
  local lost = Engine.QuestXP(ql, me) - Engine.QuestXP(ql, then_)
  if lost <= 0 then return nil end
  local pm, px, py = ns.State.Position()
  if not (pm and step.m and step.x) or not (ns.Travel and ns.Travel.Plan) then return nil end
  local _, secs = ns.Travel.Plan({ m = pm, x = px, y = py }, { m = step.m, x = step.x, y = step.y, name = step.npc }, { hearth = false })
  if not secs then return nil end
  local perLevel = (UnitXPMax and UnitXPMax("player")) or 0
  if perLevel <= 0 then return nil end
  local tripCost = perLevel / ((Engine.WORTH_LEVEL_HOURS or 2) * 3600) * (2 * secs) -- there and back
  if lost <= tripCost then return nil end
  return Engine.current, lost, secs
end
local function applyInserts()
  local list = steps()
  if not (ForeverRouteEnders and ForeverRouteData and #list > 0) then return false end
  -- side trips (special rewards, dungeon routes) are their own short list: your leveling path handles the extras
  if ForeverRouteData.dungeon or ForeverRouteData.special then return false end
  local have = {}
  -- (a hand-in behind you in the built-in plan is not on the route: Engine.BehindYou)
  local behind = {}
  for _, s in ipairs(list) do if s.k == "turnin" and s.q then if Engine.BehindYou(s) then behind[s.q] = true else have[s.q] = true end end end
  local px, py, pinst = HBD:GetPlayerWorldPosition()
  local added = false
  for q, e in pairs(Engine.LogEnders()) do
    if not have[q] and not (ns.Nope(q)) and ns.State.QuestReady(q) and not ns.State.IsCompleted(q) then
      local step = { k = "turnin", q = q, name = e.name, npc = e.npc, m = e.m, x = e.x, y = e.y, r = 6, inserted = true,
        note = "Added: you finished this one on the way." }   -- its sec comes from where InsertStop puts it
      -- a gray quest (Messenger to Westfall at 26: 250 XP) gets a stop only right on the way: never a detour for it
      local ql, me = Engine.logLevels and Engine.logLevels[q], UnitLevel and UnitLevel("player")
      local okG, green = pcall(function() return GetQuestGreenRange and GetQuestGreenRange() end)
      local gray = type(ql) == "number" and type(me) == "number" and (me - ql) > ((okG and type(green) == "number" and green) or 8)
      local opts = gray and { maxCost = Engine.GRAY_DETOUR_YD, why = "gray, but right on the way" }
        or (behind[q] and { maxCost = Engine.MERGE_PATH_YARDS, why = "its hand-in is behind you in the plan, and the route passes by" }) or nil
      -- (not gray, not behind you: would waiting for the cheapest spot cost more XP than going now?)
      if not opts and type(ql) == "number" then
        local at = Engine.InsertStop(step, px, py, pinst, { dry = true })
        local now, lost, secs = Engine.HandInNow(step, ql, at)
        if now then opts = { at = now, why = string.format("worth going now: waiting would lose ~%d XP, ~%d min there and back", lost, math.floor(2 * secs / 60 + 0.5)) } end
      end
      if Engine.InsertStop(step, px, py, pinst, opts) then added = true; have[q] = true end
    end
  end
  return added
end
Engine.ApplyInserts = applyInserts
ns.On("FR_STATE", function() if applyInserts() then Engine.Refresh() end end)
ns.On("FR_LOADED", function() C_Timer.After(3, function() if applyInserts() then Engine.Refresh() end end) end)
ns.On("FR_ROUTE_CHANGED", function() C_Timer.After(0.5, function() if applyInserts() then Engine.Refresh() end end) end)
