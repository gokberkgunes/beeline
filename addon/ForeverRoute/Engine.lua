-- Step engine: decides which step is current from live quest state, like a hand-written guide's conditions.
-- Steps (from Route.lua): { id, k = kind, q = questID, name, npc, m = uiMapID, x, y (0-1), r = arrive radius, match = objective
--   text, text, note, warn, minLevel, level, lvl (planned level here), xp, to (destination map), bind, fp, item, target, sec }
local _, ns = ...
local Engine = {}
ns.Engine = Engine
local State = ns.State -- (State.lua loads first: the .toc)

Engine.current = nil  -- index of the first step that still needs doing
Engine.view = nil     -- an earlier/later step being looked at (Back, list); never changes progress
local quiet = true    -- no completion animation for the catch-up refresh at login

local function steps() return ForeverRouteData and ForeverRouteData.steps or {} end
-- Ticks and skips are stored against the step itself, not its number: kind + quest + what it targets, plus which
-- occurrence it is. Regenerating the route shifts step numbers; these keys stay on the same step.
local keyCache = setmetatable({}, { __mode = "k" })
Engine._keyCache = keyCache -- (Engine/Inserts.lua)
function Engine.Key(i)
  local list = steps()
  local c = keyCache[list]
  if not c then
    c = {}; local seen = {}
    for j, s in ipairs(list) do
      local base = (s.k or "?") .. ":" .. tostring(s.q or "") .. ":" .. tostring(s.match or s.text or s.dest or s.name or s.npc or s.fp or s.bind or "")
      seen[base] = (seen[base] or 0) + 1
      c[j] = base .. "#" .. seen[base]
    end
    keyCache[list] = c
  end
  return c[i]
end
local function key(i) return Engine.Key(i) end

-- noElim: without the elimination pass (it asks about the quest's other steps, which would ask about this one)
function Engine.ObjectiveFor(step, noElim)
  local q = State.Quest(step.q)
  if not q or not q.on then return nil end
  if step.unknown then return nil end -- (the quest's own words, no objective's: the card shows all of the quest's lines)
  if step.match then
    -- the exact name first ("Murloc slain" for "Murloc"), then any objective containing it: "Murloc" alone matched
    -- "Murloc Streamrunner slain" and the card waited on the wrong objective
    local m = step.match:lower()
    local loose
    for _, o in ipairs(q.objectives) do
      local t = o.text:lower()
      if t:sub(1, #m) == m and (t:sub(#m + 1, #m + 1) == ":" or t:sub(#m + 1, #m + 6) == " slain") then return o end
      if not loose and t:find(m, 1, true) then loose = o end
    end
    if loose then return loose end
  end
  if step.o and q.objectives[step.o] then return q.objectives[step.o] end
  -- no match word from the planner (objects to use, places to explore: the quest data has no text the game shows for
  -- them): the objective sharing the most distinctive words with the step ("Read the Lay of Ameth'Aran" -> "Lay of
  -- Ameth'Aran read"), when exactly one does best. Otherwise the card couldn't tell that objective was done and sat on
  -- it until the whole quest was (you ticked it by hand).
  if not step.match and step.text then
    local want = Engine.Words(step.text)
    local best, bestN, tie = nil, 0, false
    for _, o in ipairs(q.objectives) do
      local n = 0
      for w in pairs(Engine.Words(o.text)) do if want[w] then n = n + 1 end end
      if n > bestN then best, bestN, tie = o, n, false elseif n == bestN and n > 0 then tie = true end
    end
    if best and not tie then return best end
  end
  if not noElim and not step.match and step.text then
    -- by elimination: every other objective of the quest belongs to another step of the route ("Explore" says
    -- nothing; Alther's Mill's other objective is "Use Tarantula Egg"): the one left is this step's
    local claimed, list = {}, steps()
    for _, j in ipairs(Engine.ObjStepsOf(step.q)) do
      local t = list[j]
      if t ~= step then local o2 = (t.match or Engine.Words(t.text) and next(Engine.Words(t.text))) and Engine.ObjectiveFor(t, true) or nil; if o2 then claimed[o2] = true end end
    end
    local left
    for _, o in ipairs(q.objectives) do if not claimed[o] then if left then return nil end; left = o end end
    return left
  end
end
-- the words that tell objectives apart (not "the", "of", the verb, or counts)
local COMMON = { the = 1, ["and"] = 1, ["for"] = 1, ["from"] = 1, ["with"] = 1, ["into"] = 1, ["your"] = 1, use = 1, read = 1, free = 1, locate = 1,
  collect = 1, kill = 1, investigate = 1, explore = 1, find = 1, slain = 1, ["get"] = 1, bring = 1, place = 1, open = 1 }
function Engine.Words(t)
  local out = {}
  if type(t) ~= "string" then return out end
  for w in t:lower():gmatch("[%a'][%a']+") do if #w > 2 and not COMMON[w] then out[w] = true end end
  return out
end

-- dungeons: a "Run <X> with a group" step and the objective steps done inside ("Collect 10 Twilight Pendant (in
-- Blackfathom Deeps)"). Once you've been inside (any visit is your run - ns.char.dungeonsVisited) or skipped the run,
-- what's left inside waits ("later") instead of holding up the card: half a run (drops that didn't drop), skipping
-- dungeons, or running one twice all leave the route moving. Back inside, it's current again.
function Engine.RunDungeon(s) return s and s.k == "goto" and (s.dungeon or tostring(s.text or ""):match("^Run (.-) with a group") or tostring(s.text or ""):match("^Run (.+)$")) or nil end
function Engine.InsideOf(s) return s and s.k == "obj" and tostring(s.text or ""):match("%(in (.-)%)$") or nil end
-- each quest's objective steps, by index - built once per step list (a hand-in's check scanned the whole plan for
-- every unfinished hand-in: on a 2300-step plan that was most of a refresh)
local objIndex, objIndexFor, objIndexN = nil, nil, 0
function Engine.ObjStepsOf(q)
  local list = steps()
  if objIndexFor ~= list or objIndexN ~= #list then
    objIndex, objIndexFor, objIndexN = {}, list, #list
    for j, t in ipairs(list) do if t.k == "obj" and t.q then local l = objIndex[t.q]; if not l then l = {}; objIndex[t.q] = l end; l[#l + 1] = j end end
  end
  return objIndex[q] or {}
end
-- a visit marks one Run step (ns.char.ranRun[key]): the first one of that dungeon not run or skipped yet - a second
-- planned run of the same dungeon later on the route stays to do
-- the mark is for the plan you were on (its stamp): a new plan made after the run (the planner saw drops still missing -
-- 5 of 8 brain stems - and planned another run) has a run of its own to do
local function planStamp() return (ForeverRoutePlan and ForeverRoutePlan.generated) or (ForeverRouteData and ForeverRouteData.id) or 0 end
local function ran(i) local v = ns.char.ranRun and ns.char.ranRun[key(i)]; return v ~= nil and v == planStamp() end
-- the Run step an inside objective belongs to: the nearest one before it for that dungeon
local function runFor(j, name)
  local list = steps()
  for i = j - 1, 1, -1 do local d = Engine.RunDungeon(list[i]); if d and Engine.SamePlace(d, name) then return i end end
end
-- an inside objective (step j) waits for now: its run is done or skipped, and you're not in that dungeon
function Engine.DungeonLater(name, j)
  if not name or Engine.InDungeon(name) then return false end
  local r = j and runFor(j, name)
  return r and (ran(r) or ns.char.skipped[key(r)] or false) or false
end
local function recordDungeon()
  local name = ns.Dungeon.Here() -- which dungeon, by its instance id or the game's name for it (Dungeon.lua)
  if not name then return end
  -- the run the card shows, if it's this dungeon's; else the first of its runs not done yet (one already passed - you
  -- went ahead of it - is not the run you're starting: marking it once took the card back to two old runs)
  ns.char.ranRun = ns.char.ranRun or {}
  local shown = Engine.Shown and Engine.Shown()
  local list = steps()
  local s0 = shown and list[shown]
  local d0 = s0 and Engine.RunDungeon(s0)
  if d0 and Engine.SamePlace(d0, name) and not ran(shown) then ns.char.ranRun[key(shown)] = planStamp(); return end
  for i, s in ipairs(list) do
    local d = Engine.RunDungeon(s)
    if d and Engine.SamePlace(d, name) and not ran(i) and not ns.char.skipped[key(i)] and Engine.Status(i) ~= "done" then
      ns.char.ranRun[key(i)] = planStamp()
      return
    end
  end
end
Engine.RecordDungeon = recordDungeon
ns.On("ZONE_CHANGED_NEW_AREA", function() pcall(recordDungeon) end)
ns.On("PLAYER_ENTERING_WORLD", function() pcall(recordDungeon) end)

-- status: "done", "todo", "blocked" (quest not in log), "wait" (level too low), "full" (a pick-up with your quest log
-- full: passed over like "wait", so the card goes to hand-ins and objectives first), "notready" (turn-in with objectives left),
-- "later" (left for your next run of a dungeon you've been in or skipped: passed over, like "wait")
-- a quest more than this many levels below you is left out: tools/campaign.js plans each zone with
-- minQuestLevel = level - 6 (it never sends you to one), and the route in game drops the same ones
Engine.OUTLEVEL = 6
-- the game's gray line: a quest this level or lower gives (next to) no XP at level L - 5 below you early on, 6-12
-- below later (the client's GetQuestGreenRange table). A fixed 6 kept a level 1 quest on the route of a level 7.
function Engine.GrayAt(L)
  return L - (L < 6 and L or L < 40 and (math.floor(L / 10) + 5) or (math.floor(L / 5) + 1))
end
-- are you bound at this bind step's place? (the bind's own name, the zone, or the map you were on when you bound)
function Engine.BoundAt(s, b)
  if not b then return false end
  if (s.bind and b == s.bind) or Engine.SamePlace(b, s.zone) then return true end
  local at = ns.char and ns.char.boundAt
  return at and at.name == b and at.m == s.m or false
end
-- Is your hearthstone set on map m, going by the name the game gives your bind (b)? The game names the place - the
-- town or inn ("Darkshire", "Menethil Harbor"), a capital by its own name ("Stormwind City") - never the map, so:
-- where you set it while the addon watched (ns.char.boundAt: that name on that map, and then no other map), else the
-- names this map's inn goes by: the step's own, the zone's, a bind stop of the plan there, the flight point's town
-- ("Darkshire, Duskwood"). No match is "not there": a hearth that isn't yours is never offered.
function Engine.BoundOn(m, b, s)
  if not (m and type(b) == "string" and b ~= "") then return false end
  local at = ns.char and ns.char.boundAt
  if at and at.m and at.name == b then return at.m == m end
  if s and (s.dest == b or s.text == b) then return true end
  local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(m)
  if info and info.name and Engine.SamePlace(b, info.name) then return true end
  for _, t in ipairs(steps()) do if t.k == "bind" and t.m == m and Engine.BoundAt(t, b) then return true end end
  for _, byMap in pairs(ns.FLIGHT_BY or {}) do
    for _, f in ipairs(byMap[m] or {}) do if f[4] and f[4]:match("^(.-),") == b then return true end end
  end
  return false
end
-- Can you take this hearth step? Only when the game says so: your hearthstone is set where the step goes (the plan
-- only assumed you set it at its bind stop - a level 31 was told "Hearth to Darkshire" while bound in Stormwind) and it
-- is off cooldown. Otherwise the step is passed and the way to the stops after it is planned like any other trip
-- (Engine.TravelFor). -> true, or false and why
local hearthMemo = setmetatable({}, { __mode = "k" })
function Engine.HearthUsable(i)
  local list = steps()
  local s = list[i]
  if not s then return false, "no such step" end
  local okB, b = pcall(GetBindLocation)
  if not okB or type(b) ~= "string" or b == "" then return false, "the game does not say where your hearthstone is set" end
  -- whether the step goes where the stone is set: worked out once per step and bind location (the route list asks
  -- about every hearth step on every refresh, and this walks the steps and the flight tables)
  local memo = hearthMemo[s]
  local there
  local at = ns.char and ns.char.boundAt -- (what the addon has learned about where the stone is set counts too)
  if memo and memo.b == b and memo.list == list and memo.at == at then there = memo.there else
    -- where the step goes: the plan says (bindMap), else the bind stop before it (plans from before that field)
    local m = s.bindMap
    if not m then for j = i - 1, 1, -1 do if list[j].k == "bind" then m = list[j].m; break end end end
    if m then there = Engine.BoundOn(m, b, s) else there = s.dest == b or Engine.SamePlace(b, s.dest or s.text) end
    hearthMemo[s] = { b = b, list = list, at = at, there = there }
  end
  if not there then return false, "your hearthstone is set in " .. b .. ", not there" end
  local cd = ns.HearthCooldown and ns.HearthCooldown()
  if type(cd) == "number" and cd > 0 then return false, "your hearthstone is on cooldown (" .. math.ceil(cd / 60) .. " min)" end
  return true
end
-- (said once per step and reason, and only for a step the card is about to reach: the list asks about every step)
local hearthSaid = setmetatable({}, { __mode = "k" })
local function hearthPassed(i, s, why)
  local c = Engine.current
  if hearthSaid[s] == why or not (c and i >= c and i <= c + 3) then return end
  hearthSaid[s] = why
  if ns.Why then ns.Why("hearth", "passed \"Hearth to " .. tostring(s.dest or s.text or "your inn") .. "\": " .. why .. "; the way there is planned like any other trip") end
end
-- the level a training stop is for: "level 8/10 spells" -> 10
function Engine.TrainLevel(s)
  if s.until_ then return tonumber(s.until_) end
  local best
  for n in tostring(s.text or ""):gmatch("%d+") do n = tonumber(n); if not best or n > best then best = n end end
  return best
end
-- does this quest lead to one still worth XP to you? A quest is worth what it opens (a chain's best quests are often
-- at its end, levels above its start): a link of a chain whose later quests you'd still get XP for is never cut for
-- being gray itself. A quest the chain leads to that isn't on this plan counts as worth it - the chain goes on past
-- what this plan knows (better to keep a link than to lose a chain).
local levelOfQ, levelSrc = {}, nil
function Engine.LeadsToWorth(q, lvl)
  local deps = ForeverRouteUnlocks and ForeverRouteUnlocks[q]
  if not deps or #deps == 0 then return false end
  local list = steps()
  if levelSrc ~= list then
    levelOfQ, levelSrc = {}, list
    for _, t in ipairs(list) do if t.q and tonumber(t.level) and not levelOfQ[t.q] then levelOfQ[t.q] = t.level end end
  end
  for _, d in ipairs(deps) do
    if not State.IsCompleted(d) then
      local L = levelOfQ[d]
      if not L or L > Engine.GrayAt(lvl) then return true end
    end
  end
  return false
end
function Engine.Outlevelled(s)
  if not (s and s.q and tonumber(s.level) and s.level > 0) then return false end
  local lvl = UnitLevel("player") or 1
  return s.level <= Engine.GrayAt(lvl) and not State.OnQuest(s.q) and not State.IsCompleted(s.q) and not Engine.LeadsToWorth(s.q, lvl)
end
-- a hand-in you've outgrown: the quest is finished in your log, far below you (Messenger to Westfall at 26: 250 XP),
-- and opens nothing on the route (ForeverRouteUnlocks) - not worth the trip, on any plan (the built-in one from level 1
-- most of all: no planner reworks it for you). A stop added because it's right on the way stays.
function Engine.GrayHandIn(s)
  if not (s and s.k == "turnin" and s.q and not s.inserted and tonumber(s.level) and s.level > 0) then return false end
  if s.level > Engine.GrayAt(UnitLevel("player") or 1) then return false end
  if not State.QuestReady(s.q) then return false end
  -- (kept when what it opens is still worth XP to you - not merely because something it opens is undone: a chain of
  -- gray quests is gray all the way)
  return not Engine.LeadsToWorth(s.q, UnitLevel("player") or 1)
end
-- Your place in the built-in plan. It is one path from level 1 to 60, and every step has a level: the level the plan
-- has you at when you get there (lvl; a step without one - a flight, a flight path, a hearth - takes the level of the
-- next step that has one: travel belongs to what it leads to). What the plan does below your place is behind you:
-- passed, whatever kind of step it is. Your place is the higher of two things:
--   where you joined: someone who meets the plan at 30 (installed the addon then, or came back to it) joins at the
--     trip during which the plan reaches 30. Everything before that trip is behind them for good, quests in their log
--     included - those are theirs to finish or drop, like any quest that is not on the route (a finished one gets a
--     hand-in stop where the route passes its NPC, and the quest log check lists them all). Kept in ns.char.join.
--   JOIN_GAP levels below you: rested XP and dungeons put you ahead of the plan, and up to 3 levels ahead you are
--     still doing what it says. Further ahead than that, what it does down there is passed - but a quest in your log
--     stays, here: you picked it up on the plan.
-- A quest goes as a whole: with its pick-up behind you (and the quest not yours), its other steps are too; a pick-up
-- that needs a quest whose hand-in is behind you is not offered; and a quest in your log goes when something still to
-- do for it lies before the trip you joined at. Your own plan (the companion's) is made from your save: none of this.
-- (A level 30 trying the addon was sent to Redridge for a flight path, to Elwynn for errands, then through Duskwood
-- and Ashenvale: travel steps carried no level, and quests in the log pulled the card back to each of those zones.)
Engine.JOIN_GAP = 3
local planCache = setmetatable({}, { __mode = "k" })
local function isTrip(s) return s.k == "fly" or s.k == "hearth" or s.k == "boat" end
local function planIndex()
  local list = steps()
  local c = planCache[list]
  if c and c.n == #list then return c, list end
  -- (binds: the bind stops in order; trainAfter[i]: the lowest level a training stop after step i is for - statusRaw
  -- walked the rest of the plan for each, on every refresh)
  c = { n = #list, idx = {}, eff = {}, accept = {}, turnin = {}, at = {}, binds = {}, trainAfter = {} }
  local nxt, train
  for i = #list, 1, -1 do
    local s = list[i]
    c.trainAfter[i] = train
    if s.k == "train" then local L = Engine.TrainLevel(s); if L and (not train or L < train) then train = L end end
    if s.k == "bind" then table.insert(c.binds, 1, i) end
    c.idx[s] = i
    if tonumber(s.lvl) then nxt = s.lvl end
    c.eff[i] = nxt
    if s.q and s.q > 0 then
      if s.k == "accept" then c.accept[s.q] = i elseif s.k == "turnin" and not s.inserted then c.turnin[s.q] = i end -- (the first of each: this runs backwards)
    end
  end
  local last -- the last steps of a plan, with no stamped step after them: the level before
  for i = 1, #list do if c.eff[i] then last = c.eff[i] else c.eff[i] = last end end
  planCache[list] = c
  return c, list
end
-- the level the plan has you at, at step i (nil on a plan without levels)
function Engine.PlanLevel(i) return (planIndex()).eff[i] end
-- the step you joined at: the trip (flight, hearth, boat) into the stretch where the plan first reaches that level,
-- so you start a stretch from its beginning - its pick-ups before the things they are for. nil: nothing to pass
local function joinStep(level)
  local c, list = planIndex()
  local at = c.at[level]
  if at == nil then
    at = false
    for i = 1, #list do
      if tonumber(list[i].lvl) and list[i].lvl >= level then
        at = 1
        for j = i, 1, -1 do if isTrip(list[j]) then at = j; break end end
        break
      end
    end
    c.at[level] = at
  end
  return at or nil
end
-- the level you joined the built-in plan at, and the step that goes with it (nil, nil: you follow it from the start,
-- or it isn't known yet - Engine.FindPlace)
function Engine.Place()
  local key = ns.planKey and ns.planKey.starter
  local j = key and ns.char and ns.char.join
  if Engine.noPlace or not (j and j.plan == key and tonumber(j.level) and j.level > 1) then return nil end
  return j.level, joinStep(j.level)
end
-- Where you start. The trip you join at is the plan at your level; but the plan's stretches of the JOIN_GAP levels
-- before it are still good for you, and one of them may be worth more than that trip from where you stand: someone
-- who meets the plan at 30 in Darkshire has Duskwood's level 27-31 stretch around them, and the plan's own next
-- stretch a flight away. So when you join, each of those stretches (a stretch: the steps between two trips) is priced
-- like the planner prices a zone - the XP of the quests you can still do in it, over the time they take plus the trip
-- there from where you stand - and the best one is where you start (ns.char.join.first), before the trip you joined
-- at. Value decides, not distance: staying put wins only if its quests beat the alternative with its trip.
-- The numbers are rough and say so: quest XP from the quest's level (less for one far below you), a pick-up or hand-in
-- 10 s, an objective 2 min, the walk between steps at running or riding speed, the trip from Travel.Plan.
Engine.START_HORIZON = 3600 -- stretches are compared by the XP they bring in this many seconds (a short one, then the plan)
Engine.START_MIN_TURNINS = 5 -- a stretch with fewer hand-ins is no place to start (the planner's own floor for a zone)
local function firstTrip(c, list)
  if not c.trip1 then c.trip1 = #list + 1; for j = 1, #list do if isTrip(list[j]) then c.trip1 = j; break end end end
  return c.trip1
end
local function stretchEnd(list, from) for j = from + 1, #list do if isTrip(list[j]) then return j - 1 end end return #list end
local function questXP(ql, L)
  local xp = 100 + 60 * ql + 0.9 * ql * ql
  local d = L - ql
  return xp * (d <= 5 and 1 or d == 6 and 0.8 or d == 7 and 0.6 or d == 8 and 0.4 or d == 9 and 0.2 or 0.1)
end
Engine.QuestXP = questXP
-- the next thing to do for a quest in your log: its first unfinished objective on the route, else its hand-in
local function nextStep(q, c, list)
  if not State.QuestReady(q) then
    for _, j in ipairs(Engine.ObjStepsOf(q)) do
      local o = Engine.ObjectiveFor(list[j])
      if not (o and o.finished) then return j end
    end
    return nil
  end
  return c.turnin[q]
end
-- what a stretch is worth to you now: XP, seconds of work, hand-ins, the first step with a place
function Engine.StretchWorth(from, to)
  local c, list = planIndex()
  local L = UnitLevel("player") or 1
  local speed = (ns.Travel and ns.Travel.Speed and ns.Travel.Speed()) or 7
  local xp, secs, n, spot = 0, 0, 0, nil
  -- a quest you can do there: in your log with its next step there, or picked up in this stretch with every quest it
  -- needs handed in by then
  local can = {}
  local function doable(q)
    if can[q] == nil then
      local a = c.accept[q]
      if State.OnQuest(q) then
        local n = nextStep(q, c, list)
        can[q] = n ~= nil and n >= from and n <= to
      else
        can[q] = a ~= nil and a >= from and a <= to
      end
      if can[q] and not State.OnQuest(q) then
        for _, p in ipairs(Engine.PrereqsOf(q)) do
          local t = c.turnin[p]
          if not State.IsCompleted(p) and not (t and t >= from and t <= to and (State.OnQuest(p) or (c.accept[p] or 0) >= from)) then can[q] = false; break end
        end
      end
    end
    return can[q]
  end
  for j = from, to do
    local s = list[j]
    local q = s.q and s.q > 0 and s.q or nil
    if q and not State.IsCompleted(q) and not Engine.Outlevelled(s) then
      if doable(q) then
        if not (s.k == "accept" and State.OnQuest(q)) then
          spot = spot or (s.m and s.x and not s.unknown and s) or nil
          secs = secs + (tonumber(s.walk) or 80) / speed + (s.k == "obj" and 120 or 10)
          if s.k == "turnin" and tonumber(s.level) and s.level > 0 then xp = xp + questXP(s.level, L); n = n + 1 end
        end
      end
    end
  end
  return xp, secs, n, spot
end
-- the stretch to start in, for someone joining at this level: its first step's key (nil: the trip you joined at), and
-- the stretches priced { from, to, zone, xph, extra (s of travel it adds), work (s), turnins, plan }, best first.
-- Priced: the plan's trip at your level (its XP over its work and the trip there), and every other stretch the plan
-- has within reach of your level - from OUTLEVEL levels below you (the planner's own line for a quest worth doing) up
-- to your level - with START_MIN_TURNINS hand-ins you can still do: its XP over its work and the travel it ADDS (the
-- trip there, then on to the plan's trip, less the trip you'd make anyway). So a stretch around you costs nothing to
-- reach, and one across the world has to be worth the detour.
function Engine.ChooseStart(level)
  local c, list = planIndex()
  local at = joinStep(level)
  local m, x, y = State.Position()
  if not (at and at > 1 and m and x and ns.Travel and ns.Travel.Plan) then return nil, {} end
  local L = UnitLevel("player") or 1
  local function trip(a, b)
    local ok, _, secs = pcall(ns.Travel.Plan, { m = a.m, x = a.x, y = a.y }, { m = b.m, x = b.x, y = b.y, name = b.zone })
    return ok and tonumber(secs) or nil
  end
  local me = { m = m, x = x, y = y }
  local priced = {}
  -- the plan's trip at your level
  local to = stretchEnd(list, at)
  local xpD, workD, nD, spotD = Engine.StretchWorth(at, to)
  local tripD = spotD and trip(me, spotD)
  if not tripD then return nil, {} end -- no way there from here (or nothing to do there): nothing to compare with
  priced[1] = { from = at, to = to, zone = spotD.zone or list[at].dest or "?", xph = math.floor(xpD / (workD + tripD) * 3600), extra = math.floor(tripD), work = math.floor(workD), turnins = nD, plan = true }
  local function price(from)
    local last = stretchEnd(list, from)
    local xp, work, n, spot = Engine.StretchWorth(from, last)
    if not spot or n < Engine.START_MIN_TURNINS then return end
    local there, on = trip(me, spot), trip(spot, spotD)
    if not (there and on) then return end
    local extra = math.max(0, there + on - tripD)
    priced[#priced + 1] = { from = from, to = last, zone = spot.zone or list[from].dest or "?", xph = math.floor(xp / (work + extra) * 3600), extra = math.floor(extra), work = math.floor(work), turnins = n }
  end
  for j = 1, #list do
    local e = c.eff[j] or 0
    if j > at and e > L then break end
    if j ~= at and (j == 1 or isTrip(list[j])) and e >= L - Engine.OUTLEVEL then price(j) end
  end
  -- compared over the same time (START_HORIZON): a stretch shorter than that is followed by the plan at the plan's own
  -- rate. Rates alone over-praised tiny stretches - five errands in 7 minutes scored 168k XP/h and would beat a real
  -- zone, though they are over before the hour is
  local planRate = priced[1].xph / 3600
  local H = Engine.START_HORIZON
  for _, p in ipairs(priced) do
    local t = p.work + p.extra
    local xp = p.xph / 3600 * t
    p.score = t >= H and p.xph or math.floor((xp + (H - t) * planRate) / H * 3600)
  end
  table.sort(priced, function(a, b) if a.score ~= b.score then return a.score > b.score end return (a.plan and 1 or 0) > (b.plan and 1 or 0) end)
  local best = priced[1]
  if best.plan then return nil, priced end
  return Engine.Key(best.from), priced
end
-- the stretch you start in (nil: none chosen, or it is not on this plan any more): its first and last step
function Engine.FirstStretch()
  local j = ns.char and ns.char.join
  local k = j and ns.planKey and j.plan == ns.planKey.starter and j.first
  if not k or Engine.noPlace then return nil end
  local c, list = planIndex()
  if c.firstKey ~= k then
    c.firstKey, c.firstFrom, c.firstTo = k, false, false
    for i = 1, #list do if Engine.Key(i) == k then c.firstFrom, c.firstTo = i, stretchEnd(list, i); break end end
  end
  return c.firstFrom or nil, c.firstTo or nil
end
-- the zone you are in (nil on a flight, or where the game gives no position): taken once per refresh (Engine.here)
function Engine.HereMap()
  if ns.Is and UnitOnTaxi and ns.Is(UnitOnTaxi, "player") then return nil end
  local ok, m = pcall(State.Position)
  return ok and m or nil
end
function Engine.BehindYou(s)
  if Engine.noPlace or not (s and ns.planKey and ns.planKey.starter) then return false end
  -- (a zone you picked has nothing behind you: you chose to go there - its steps all read "done" when you came back to it)
  if ForeverRouteData and ForeverRouteData.zoneRoute then return false end
  if ns.Next and ns.Next.taken == s then return false end -- (picked up again by the live solve: right here and worth it)
  if s.side then return false end -- (a stop added for a quest giver next to you is where you are, wherever it lands in the plan)
  local c, list = planIndex()
  local i = c.idx[s]
  if not i then return false end
  local L = UnitLevel("player") or 1
  local _, at = Engine.Place()
  local f1, f2 = nil, nil
  if at then f1, f2 = Engine.FirstStretch() end
  -- before the trip you joined at, and not in the stretch you start in
  local function before(j) return at ~= nil and j < at and not (f1 and j >= f1 and j <= f2) end
  -- below your place: that, or more than JOIN_GAP levels below you (not while you are still in the plan's first
  -- stretch, the start zone: its chains lead out of it, and at 5 nothing of it is behind you)
  local start = at == nil and joinStep(L) == 1
  local function low(j)
    if before(j) then return true end
    local e = c.eff[j]
    return (e and e < L - Engine.JOIN_GAP and not (start and j < firstTrip(c, list))) or false
  end
  local q = s.q and s.q > 0 and s.q or nil
  if not q then
    if low(i) then return true end
    if s.k == "hearth" then
      -- a hearth to an inn the plan bound you at in a part that is behind you: you are not bound there
      for j = i - 1, 1, -1 do
        local t = list[j]
        if t.k == "bind" then return Engine.BehindYou(t) and not Engine.BoundAt(t, GetBindLocation and GetBindLocation()) end
      end
    end
    return false
  end
  if State.IsCompleted(q) then return false end
  if State.OnQuest(q) then
    -- in your log. Following the plan, or picked up since you joined it: the plan's, wherever it leads
    local had = at and ns.char.join and ns.char.join.had
    if s.k == "accept" or s.inserted or not (had and had[q]) then return false end -- (a stop added for it is on your way)
    -- yours from before you joined: on the plan if what is left of it is ahead of you - or it is finished and its
    -- hand-in is in the zone you are in (handed in first: The Night Watch, 19 yd from a level 30 in Darkshire)
    local n = nextStep(q, c, list)
    if not n then return before(i) end
    if not before(n) then return false end
    return not (Engine.here ~= nil and list[n].k == "turnin" and list[n].m == Engine.here)
  end
  if s.k ~= "accept" then
    -- a quest goes as a whole: with its pick-up behind you, its other steps are too
    local a = c.accept[q]
    if a and a ~= i then return Engine.BehindYou(list[a]) end
    return low(i)
  end
  if low(i) then return true end
  -- it needs a quest whose hand-in is behind you: not offered. (ForeverRouteUnlocks is the whole chain before it; it
  -- lists "any one of" with "all of", so a quest with two ways in can be passed here though one of them is done)
  for _, p in ipairs(Engine.PrereqsOf(q)) do
    if not State.IsCompleted(p) then
      local t = c.turnin[p]
      if t and t < i and Engine.BehindYou(list[t]) then return true end
    end
  end
  return false
end
-- a breadcrumb whose quest is already yours (in your log or done): the game no longer offers it - The Corruption
-- Abroad from Argos Nightwhisper, with Researching the Corruption in your log (ns.BREADCRUMBS, Breadcrumbs.lua)
-- a quest some other quest you took or did shuts (its breadcrumb's target, or an exclusive alternative): passed over
local function shutBy(tbl, s)
  local others = s and s.q and tbl and tbl[s.q]
  if not others or State.OnQuest(s.q) or State.IsCompleted(s.q) then return false end
  for _, t in ipairs(others) do if State.OnQuest(t) or State.IsCompleted(t) then return true end end
  return false
end
function Engine.Breadcrumbed(s) return shutBy(ns.BREADCRUMBS, s) end
-- a quest one of whose alternatives is yours (in your log or done): one quest given in several towns, and you took it
-- in another - the game no longer offers this one, so none of its steps is left to do (ns.QUEST_EX, QuestData.lua).
-- A warlock who had taken In Search of Menara Voidrender from Demisette Cloyce in Stormwind was sent to Briarthorn
-- in Ironforge for it (tester)
function Engine.Excluded(s) return shutBy(ns.QUEST_EX, s) end
local function statusRaw(i)
  local s = steps()[i]
  if not s then return "done" end
  local id = key(i)
  if ns.char.manualDone[id] or ns.char.skipped[id] then return "done" end
  if s.q and ns.Nope(s.q) then return "done" end -- you said you're not doing this quest
  if s.side and s.away and s.k == "accept" then return "done" end -- a side quest offered at its giver, and you walked on (Engine.SideOffer)
  -- the game did not offer it to you (Availability.lua): off the route until you level up or it is offered
  if s.q and ns.Avail and ns.Avail.Unavailable(s.q) and not State.OnQuest(s.q) and not State.IsCompleted(s.q) then return "done" end
  -- far below you and not in your log: off the route (all its steps), the same cut the planner makes - so a plan made
  -- for someone lower (the built-in plan from level 1, or yours after a dungeon run) passes over what you've outgrown,
  -- and a trip to a zone with nothing left for you is passed too (the "went ahead" rule below)
  if Engine.Outlevelled(s) or Engine.GrayHandIn(s) or Engine.Breadcrumbed(s) or Engine.Excluded(s) or Engine.BehindYou(s) then return "done" end
  local k = s.k
  if k == "hearth" then
    local can, why = Engine.HearthUsable(i)
    if not can then hearthPassed(i, s, why); return "done" end
  end
  if k == "accept" then
    if State.OnQuest(s.q) or State.IsCompleted(s.q) then return "done" end
    if s.minLevel and UnitLevel("player") < s.minLevel then return "wait" end
    -- on a zone you picked, its prerequisites not handed in (ns.QUEST_PRE): it waits, like a level - the giver would
    -- have nothing for you (a zone route is planned from the main route's progress, which a player who hops zones may not
    -- have). Your own plan has its prerequisites earlier in it. A quest the game showed on offer anyway (Availability: a
    -- giver listed it, or the map's "!") is taken as offered
    if ForeverRouteData and ForeverRouteData.zoneRoute and ns.PrereqsMet and not ns.PrereqsMet(s.q) and not (ns.char and ns.char.avail and ns.char.avail.seen and ns.char.avail.seen[s.q]) then return "wait" end
    if State.LogFull and State.LogFull() then return "full" end
    return "todo"
  elseif k == "turnin" then
    if State.IsCompleted(s.q) then return "done" end
    if not State.OnQuest(s.q) then return "blocked" end
    if not State.QuestReady(s.q) then
      -- all that's unfinished is inside a dungeon you've run or skipped: it waits, the card moves on
      -- and so does one whose work the quest data has no place for (an unknown step) once you skipped that step: it
      -- comes back when the quest is ready
      local list, inside, outside, unknown = steps(), false, false, false
      for _, j in ipairs(Engine.ObjStepsOf(s.q)) do
        local t = list[j]
        if t.unknown then
          if ns.char.skipped[key(j)] or ns.char.manualDone[key(j)] then unknown = true elseif j ~= i and Engine.Status(j) ~= "done" then outside = true end
        elseif j ~= i and Engine.Status(j) ~= "done" then
          if Engine.DungeonLater(Engine.InsideOf(t), j) then inside = true else outside = true end
        end
      end
      if (inside or unknown) and not outside then return "later" end
      return "notready"
    end
    return "todo"
  elseif k == "obj" then
    if State.IsCompleted(s.q) then return "done" end
    if not State.OnQuest(s.q) then return "blocked" end
    if State.QuestReady(s.q) then return "done" end
    -- work the quest data has no place for (s.unknown): done only when the quest is ready - no live objective is
    -- matched to it (its words are the quest text's, not an objective's). Skip passes it: the hand-in then waits
    if s.unknown then return "todo" end
    local o = Engine.ObjectiveFor(s)
    if o and o.finished then return "done" end
    if Engine.DungeonLater(Engine.InsideOf(s), i) then return "later" end
    return "todo"
  elseif k == "grind" then
    local lvl = UnitLevel("player")
    if lvl > (s.level or 0) or (lvl == (s.level or 0) and UnitXP("player") >= (s.xp or 0)) then return "done" end
    return "todo"
  elseif k == "fp" then
    if s.fp and State.knownTaxi[s.fp] then return "done" end
    -- (this flight master's own point, by its flight-map name - not "a point whose name has the zone's first word": in a
    -- zone with two points for you, the other one counted as this one)
    if Engine.KnowsThisFlightPoint(s) then return "done" end
  elseif k == "bind" then
    local b = GetBindLocation and GetBindLocation()
    if Engine.BoundAt(s, b) then return "done" end
    -- bound at a later bind stop of the route: that one replaced this one - never back to rebind here (binding in
    -- Menethil once sent you back across the sea to Auberdine's inn, and from there back to Menethil's)
    local c, list = planIndex()
    for _, j in ipairs(c.binds) do if j > i and Engine.BoundAt(list[j], b) then return "done" end end
  elseif k == "bonus" then
    -- a book / collectible: done once it's in your bags or the books addon has it as found
    if s.item and ns.GetItemCount and (ns.GetItemCount(s.item, true) or 0) > 0 then return "done" end
    local found = HandyNotes_ForeverBooksCharDB and HandyNotes_ForeverBooksCharDB.collected
    if s.book and type(found) == "table" and found[s.book] then return "done" end
  elseif k == "train" then
    if s.until_ and UnitLevel("player") < s.until_ then return "wait" end
    -- a later training stop on the route is already due at your level: that visit covers this one (a plan made for
    -- someone lower lists every stop from level 2)
    local lvl = UnitLevel("player") or 1
    local L = planIndex().trainAfter[i]
    if L and L <= lvl then return "done" end
  end
  -- "Run <dungeon>": done while you're inside that dungeon (the entrance check can't see you once you're in, and a
  -- reload inside would otherwise leave it stuck). Leave early and it comes back.
  if k == "goto" and s.text then
    local dname = Engine.RunDungeon(s)
    -- inside: the run you're on is done - the first of that dungeon's runs not run yet; a second and third XP run
    -- stay to do (all of them read done while inside, so the card ran ahead to the next zone mid-run)
    if dname and Engine.InDungeon(dname) then
      -- the run you're on is the one going in marked (recordDungeon); none marked yet (you were inside when the plan
      -- loaded): the first of that dungeon's runs not run yet
      if ran(i) then return "done" end
      local list, marked, first = steps(), false, nil
      for j = 1, #list do
        local d2 = Engine.RunDungeon(list[j])
        if d2 and Engine.SamePlace(d2, dname) then
          if ran(j) then marked = true elseif not first and not ns.char.skipped[key(j)] then first = j end
        end
      end
      if not marked and first == i then return "done" end
      -- any other run of it: the usual rules (one passed by "you went ahead" stays passed)
    end
    -- been in it (this run, or one before): done; or nothing you're on is left inside: done
    if dname and ran(i) then return "done" end
    -- (a run for its XP - s.xpRun - has nothing to do inside: only going in, or skipping it, passes it)
    if dname and not s.xpRun then
      local list, left = steps(), false
      for j = i + 1, #list do local t = list[j]; local x = Engine.InsideOf(t); if x and Engine.SamePlace(x, dname) and State.OnQuest(t.q) and Engine.Status(j) ~= "done" then left = true; break end end
      if not left then return "done" end
    end
  end
  -- goto / fly / hearth / note: completed by events, arrival or a click, or passed: if the next few quest steps
  -- after it are already done (you went ahead, or did things in another order), the travel was clearly made
  if (k == "goto" or k == "fly" or k == "hearth" or k == "note" or k == "fp" or k == "bind" or k == "train" or k == "bonus") and not (k == "fly" and ns.ChoiceFor and ns.ChoiceFor(i)) then
    local list, seen, done = steps(), 0, 0
    for j = i + 1, math.min(#list, i + 15) do
      local t = list[j]
      if t.k == "turnin" or t.k == "obj" then -- real progress only: accepts can be done long before you get there
        seen = seen + 1
        if Engine.Status(j) == "done" then done = done + 1 else break end
        if seen >= 2 then break end
      end
    end
    if seen >= 2 and done == seen then return "done" end
  end
  -- a flight (or hearth) to nothing: every step from it to the next travel is already done - the safety-net pick-up of
  -- a quest you already have (ensure-steps) sat in the Wetlands between two Stormwind stops, and the list read "Fly to
  -- Wetlands, Fly to Stormwind" twice over
  if (k == "fly" or k == "hearth" or k == "boat") and not (ns.ChoiceFor and ns.ChoiceFor(i)) then
    local list, any = steps(), false
    for j = i + 1, math.min(#list, i + 40) do
      local t = list[j]
      if t.k == "fly" or t.k == "hearth" or t.k == "boat" then break end
      any = true
      if Engine.Status(j) ~= "done" then any = nil; break end
    end
    if any then return "done" end
  end
  return "todo"
end
-- during a refresh (and the card / list redraw it triggers) each step's status is worked out once and reused
local batch = nil
function Engine.Status(i)
  if batch then local c = batch[i]; if c then return c end end
  local st = statusRaw(i)
  if batch then batch[i] = st end
  return st
end
function Engine.IsDone(i) return Engine.Status(i) == "done" end

-- Finding your place in the built-in plan (see Engine.BehindYou): the first time this character meets it, and again
-- when you come back to it more than JOIN_GAP levels on (the addon was off, or you were on a plan of your own).
-- Where the plan stands for you without any of that - the first step still to do - tells which you are: within
-- JOIN_GAP levels of you, you are following it, and nothing changes; further back, you join at your level.
-- force (/fr rejoin): join at your level whatever the plan says.
function Engine.PlaceDue()
  local key = ns.planKey and ns.planKey.starter
  if not (key and ns.char) then return false end
  -- (on the plan's path only: a side trip or a dungeon route has no levels to tell by)
  local d = ForeverRouteData
  if not d or d.branch or d.dungeon or d.zoneRoute or d.special then return false end
  -- not before the game has told us the quests you've done: on a cold login it may not have yet, and a player
  -- following the plan would read as one joining it (and lose up to JOIN_GAP levels of it, quests in the log too)
  if (UnitLevel("player") or 1) > 5 then
    if not next(State.completed or {}) and State.RefreshCompleted then State.RefreshCompleted() end
    if not next(State.completed or {}) then return false end
  end
  local j = ns.char.join
  if not (j and j.plan == key) then return true end
  return (UnitLevel("player") or 1) - (tonumber(j.seen) or 0) > Engine.JOIN_GAP
end
-- the quests of the plan that were in your log when you joined it (a join made before this was kept: as of now)
function Engine.JoinHad()
  local j = ns.char and ns.char.join
  if not (j and ns.planKey and j.plan == ns.planKey.starter and tonumber(j.level) and j.level > 1) or j.had then return end
  local had = {}
  for _, s in ipairs(steps()) do if s.q and s.q > 0 and not had[s.q] and State.OnQuest(s.q) then had[s.q] = true end end
  j.had = had
end
function Engine.FindPlace(force)
  Engine.ForgetDone()
  local key = ns.planKey and ns.planKey.starter
  if not (key and ns.char) then return nil end
  local L = UnitLevel("player") or 1
  local old = ns.char.join and ns.char.join.plan == key and ns.char.join or nil
  local level, fresh = L, true
  if not force then
    local saved = batch
    batch, Engine.noPlace = nil, true -- (no reuse: these are the statuses without a place)
    local ok, first = pcall(Engine.Compute)
    batch, Engine.noPlace = saved, nil
    local e = ok and first and Engine.PlanLevel(first)
    -- within JOIN_GAP levels of where the plan stands for you, or the plan reaches your level in its first stretch
    -- (you are still in the start zone): you are following it
    local at = joinStep(L)
    if not e or e >= L - Engine.JOIN_GAP or at == 1 then level, fresh = old and old.level or 0, false end
  end
  if not fresh then
    ns.char.join = { plan = key, level = level, seen = L, first = old and old.first, had = old and old.had }
    if batch then wipe(batch) end
    return level
  end
  -- joining: where to start (Engine.ChooseStart), and the quests you bring along
  local first, priced = nil, {}
  if L > 1 then
    local ok, a, b = pcall(Engine.ChooseStart, L)
    if ok then first, priced = a, b or {} elseif ns.LogError then ns.LogError("join", a) end
  end
  ns.char.join = { plan = key, level = level, seen = L, first = first }
  Engine.JoinHad()
  if batch then wipe(batch) end
  if L > 1 and not (old and old.level == L and old.first == first and not force) then
    local _, at = Engine.Place()
    local function k(n) return string.format("%.1fk", n / 1000) end
    local function one(p) return p.zone .. " (step " .. p.from .. (p.plan and ", the plan's trip at your level" or "") .. "): about " .. k(p.score or p.xph) .. " XP in the next hour - " .. p.turnins .. " hand-ins, " .. math.floor(p.work / 60 + 0.5) .. " min of work, " .. math.floor(p.extra / 60 + 0.5) .. (p.plan and " min to get there" or " min of travel added") end
    local won = priced[1] and ("start in " .. one(priced[1]) .. (priced[2] and ("; next best " .. one(priced[2])) or "; nothing else priced")) or "nothing to price (no position, or no stretch near your level): the plan's trip at your level"
    if ns.Why then ns.Why("join", "joined the built-in plan at level " .. L .. (at and (", its step " .. at) or "") .. ": " .. won) end
    local say = function()
      ns.Print("You join the built-in plan at level " .. L .. ": what it does before that is behind you" .. (at and at > 1 and (" (" .. (at - 1) .. " steps)") or "") .. "."
        .. (first and priced[1] and (" You start in " .. priced[1].zone .. ": worth more from where you stand (about " .. k(priced[1].score or priced[1].xph) .. " XP in the next hour" .. (priced[2] and (" against " .. k(priced[2].score or priced[2].xph) .. " in " .. priced[2].zone) or "") .. ").") or "")
        .. " Quests in your log from the parts behind you are yours to finish or drop - /fr logcheck lists them. (/fr rejoin does this again at your level.)")
    end
    if force then say() else C_Timer.After(7, say) end
  end
  return level
end
function Engine.Rejoin()
  Engine.ForgetDone()
  if not (ns.planKey and ns.planKey.starter) then ns.Print("Only on the built-in plan: a plan of your own is made from your save and starts where you are."); return end
  Engine.FindPlace(true)
  Engine.Refresh()
end
-- your level, each time the addon sees you level on the built-in plan: a gap in it is time spent away from the plan
ns.On("PLAYER_LEVEL_UP", function(level)
  local j = ns.char and ns.char.join
  if j and ns.planKey and j.plan == ns.planKey.starter then j.seen = tonumber(level) or UnitLevel("player") or j.seen end
end)
-- not before you are in the world: the quest log and the quests you have done are known from then on
ns.On("PLAYER_ENTERING_WORLD", function() Engine.placeReady = true end)

-- The run of done steps from the plan's start, remembered (Engine.Compute): at level 50 that is ~2000 steps, each
-- worked out again on every refresh (7-8 ms, the perf battery). A done step comes back only through what resets it
-- here (Engine.ForgetDone: undo, back, a skip or jump, a quest dropped, a level, a bind, a dungeon, another route or
-- place in the plan) - and for anything else, the run is checked again in the background after each refresh that used
-- it (a slice a frame); a step found not done there resets it and refreshes.
local doneRun = { list = nil, k = 0, step = nil, key = nil }
Engine.doneRunMiss = 0 -- (the simulator: times the check found the run wrong)
function Engine.ForgetDone() doneRun.list = nil; doneRun.k = 0 end
local function doneKey(skipFrom, skipTo)
  local c = ns.char or {}
  local j = c.join
  return table.concat({ tostring(c.manualDone), tostring(c.skipped), tostring(c.nope), tostring(j), j and tostring(j.level) or "", j and tostring(j.first) or "",
    tostring(UnitLevel and UnitLevel("player")), tostring(skipFrom), tostring(skipTo), tostring(ForeverRouteData) }, "|")
end
local verify -- the background check: { co }
local vdriver = CreateFrame and CreateFrame("Frame") or nil
local function verifyStep()
  local v = verify
  if not v then if vdriver then vdriver:Hide() end return end
  ns.sliceCo, ns.sliceT0, ns.sliceBudget = v.co, debugprofilestop(), 0.5
  local ok, wrong = coroutine.resume(v.co)
  ns.sliceCo = nil
  if verify ~= v then return end
  if not ok or coroutine.status(v.co) == "dead" then
    verify = nil; if vdriver then vdriver:Hide() end
    if not ok then if ns.LogError then ns.LogError("donerun", wrong) end; Engine.ForgetDone(); return end
    if wrong then
      Engine.doneRunMiss = Engine.doneRunMiss + 1
      if ns.Why then ns.Why("donerun", "step " .. wrong .. " is not done after all: the plan is looked at from its start again") end
      Engine.ForgetDone(); Engine.RefreshBg()
    end
  end
end
if vdriver then vdriver:Hide(); vdriver:SetScript("OnUpdate", function() local ok, err = pcall(verifyStep); if not ok then verify = nil; vdriver:Hide(); if ns.LogError then ns.LogError("donerun", err) end end end) end
Engine._verifyDriver = vdriver -- (the perf battery ticks it)
local function checkRun(list, k)
  local key = doneRun.key
  verify = { co = coroutine.create(function()
    for j = 1, k do
      if j % 16 == 0 then ns.MaybeYield() end
      if doneRun.list ~= list or doneRun.key ~= key then return nil end -- (reset meanwhile)
      if j > doneRun.skipFrom0 and j <= doneRun.skipTo0 then -- (the part of the plan your place in it passes)
      elseif Engine.Status(j) ~= "done" then return j end
    end
    return nil
  end) }
  if vdriver then vdriver:Show() end
end
-- (tests and the simulator: the run checked at once, every time it is used)
Engine.CHECK_RUN_NOW = false
function Engine.SettleDone() while verify do local v = verify; ns.sliceCo, ns.sliceT0, ns.sliceBudget = v.co, debugprofilestop(), math.huge; local ok, wrong = coroutine.resume(v.co); ns.sliceCo = nil; if verify == v and (not ok or coroutine.status(v.co) == "dead") then verify = nil; if wrong or not ok then Engine.doneRunMiss = Engine.doneRunMiss + 1; Engine.ForgetDone() end end end end
function Engine.Compute()
  -- the first step you can act on now. A step that needs a higher level ("wait") or a quest that isn't in your log
  -- ("blocked") doesn't hold up the route: it is passed over and comes back as soon as it can be done.
  local list, fallback = steps(), nil
  local skipFrom, skipTo = nil, nil
  do
    local _, at = Engine.Place()
    local f1, f2 = Engine.FirstStretch()
    if at and f1 and f1 > at then
      for i = f1, f2 do
        local st = Engine.Status(i)
        if st ~= "done" and st ~= "wait" and st ~= "blocked" and st ~= "later" then skipFrom, skipTo = at, f1 - 1; break end
      end
    end
  end
  -- where to start: past the remembered run of done steps, when it is still this plan, place and state
  local key = doneKey(skipFrom, skipTo)
  local start = 1
  local use = not Engine.noPlace and doneRun.list == list and doneRun.key == key and doneRun.k > 0 and list[doneRun.k] == doneRun.step
  if use then start = doneRun.k + 1 end
  if use and Engine.CHECK_RUN_NOW then
    for j = 1, doneRun.k do
      local st = (skipFrom and j >= skipFrom and j <= skipTo) and "done" or Engine.Status(j)
      if st ~= "done" then
        Engine.doneRunMiss = Engine.doneRunMiss + 1; start = 1; use = false
        local t = list[j]; Engine.doneRunWhy = Engine.doneRunWhy or {}
        if #Engine.doneRunWhy < 12 then Engine.doneRunWhy[#Engine.doneRunWhy + 1] = string.format("#%d %s %s now %s", j, tostring(t.k), tostring(t.name or t.text or t.dest or ""):sub(1, 30), st) end
        break
      end
    end
  end
  local run = start - 1
  local found
  for i = start, #list do
    local st = (skipFrom and i >= skipFrom and i <= skipTo) and "done" or Engine.Status(i)
    if st ~= "done" then
      if st == "wait" or st == "full" or st == "blocked" or st == "later" then fallback = fallback or i else found = i; break end
    elseif run == i - 1 then run = i end
  end
  if not Engine.noPlace then
    doneRun.list, doneRun.key, doneRun.k, doneRun.step = list, key, run, list[run]
    doneRun.skipFrom0, doneRun.skipTo0 = skipFrom or 0, skipTo or -1
    if use and run > 0 and not Engine.CHECK_RUN_NOW then checkRun(list, start - 1) end
  end
  return found or fallback
end
function Engine.InDungeon(name)
  local here = ns.Dungeon.Here() -- by the instance id, or the game's name for it (Dungeon.lua)
  return here and Engine.SamePlace(here, name) or false
end
-- "Stormwind City" vs "Stormwind", "Lakeshire" vs "Redridge Mountains": loose place-name match
local function norm(x) return (x or ""):lower():gsub(" city$", ""):gsub("^the ", "") end
function Engine.SamePlace(a, b)
  if not a or not b then return false end
  local A, B = norm(a), norm(b)
  return A == B or A:find(B, 1, true) ~= nil or B:find(A, 1, true) ~= nil
end
-- a known flight path in this zone: node names look like "Sentinel Hill, Westfall" / "Lakeshire, Redridge"
-- the flight point of an "fp" step: by the flight master (Travel.KnowsFlightPoint: the flight map's own names); a step
-- without one, by its zone's name as before
function Engine.KnowsThisFlightPoint(s)
  if s.m and s.npc and ns.Travel and ns.Travel.KnowsFlightPoint then return ns.Travel.KnowsFlightPoint(s.m, s.npc) and true or false end
  return s.zone and Engine.KnowsFlightIn(s.zone) or false
end
function Engine.KnowsFlightIn(zone)
  local z = norm(zone); local first = z:match("^(%S+)")
  for name in pairs(State.knownTaxi or {}) do
    local n = name:lower()
    if n:find(z, 1, true) or (first and #first >= 5 and n:find(first, 1, true)) then return true end
  end
  return false
end

function Engine.Upcoming(from, n)
  local out, list = {}, steps()
  for i = (from or 0) + 1, #list do
    if #out >= n then break end
    if not Engine.IsDone(i) then out[#out + 1] = i end
  end
  return out
end

function Engine.Progress()
  local list = steps(); local done = 0
  for i = 1, #list do if Engine.IsDone(i) then done = done + 1 end end
  return done, #list
end

function Engine.Shown() return Engine.view or Engine.current end
-- progress through the zone you're in: the stretch between the travel steps around the shown step
-- where you are on your plan: its own step, not a stop shown ahead of it (a hand-in you chose with "Do it now", the
-- solve's pick) - the card's "Base:" count and the zones ahead said Burning Steppes, level 59, while a Stormwind hand-in
-- filed there was on the card (tester)
function Engine.PlanAt()
  local p, list = Engine.planned, steps()
  if p and list[p] and not Engine.view then return p end
  return Engine.Shown()
end
function Engine.LegProgress(i)
  local list = steps(); i = i or Engine.PlanAt()
  if not i or not list[i] then return 0, 0, nil end
  local a, b = i, i
  while a > 1 and list[a].k ~= "fly" do a = a - 1 end
  if list[a].k == "fly" and a < i then a = a + 1 end
  while b < #list and list[b + 1].k ~= "fly" do b = b + 1 end
  local done = 0
  for j = a, b do if Engine.IsDone(j) then done = done + 1 end end
  local zone = list[i].zone or (list[a] and list[a].zone)
  return done, b - a + 1, zone
end

-- The zones ahead, from step i (default: where you are on the route) on, in order: { zone, quests = quests with something
-- still to do there on this visit (pick up, work or hand in), names = their quest names, first = its first step }. A zone you only pass through (no
-- hand-in, a flight path or two) is left out; travel steps belong to no zone. Up to n visits (default 8).
-- (the card's "why go there" line, the zones panel, the route list's chips - tester: they showed the plan from the start)
function Engine.ZonesAhead(i, n)
  local list, out = steps(), {}
  n = n or 8
  if not i then i = Engine.PlanAt() or Engine.current or 1 end
  local cur
  local function close()
    if cur and (cur.quests > 0 or cur.grind) then
      -- (a zone only passed through between two visits to one zone is left out: one visit then, not "Riverglades"
      -- twice in a row - tester)
      local last = out[#out]
      if last and last.zone == cur.zone then
        for k, q in pairs(cur.seen) do if not last.seen[k] then last.seen[k] = true; last.quests = last.quests + 1; if type(q) == "string" then last.names[#last.names + 1] = q end end end
        last.grind = last.grind or cur.grind
      else out[#out + 1] = cur end
    end
    cur = nil
  end
  local TRAVEL = { fly = true, hearth = true, boat = true, fp = true, bind = true }
  for j = i, #list do
    local s = list[j]
    if not TRAVEL[s.k] and s.zone and not Engine.IsDone(j) then
      if not cur or cur.zone ~= s.zone then
        close()
        if #out >= n then break end
        cur = { zone = s.zone, quests = 0, names = {}, seen = {}, first = j }
      end
      if s.q and s.q > 0 and not cur.seen[s.q] then cur.seen[s.q] = s.name or true; cur.quests = cur.quests + 1; cur.names[#cur.names + 1] = s.name end
      if s.k == "grind" then cur.grind = true end
    end
  end
  if #out < n then close() end
  return out
end

-- objective steps done in the same spot right after this one: shown together on the card
function Engine.Group(i)
  local list, out = steps(), {}
  local s = list[i]
  if not s or s.k ~= "obj" or s.unknown then return out end -- (work with no known place is not "here")
  for j = i + 1, math.min(#list, i + 8) do
    local t = list[j]
    if t.k ~= "obj" or t.unknown or t.m ~= s.m or math.abs((t.x or 0) - (s.x or 0)) > 0.02 or math.abs((t.y or 0) - (s.y or 0)) > 0.02 then break end
    if not Engine.IsDone(j) then out[#out + 1] = j end
  end
  return out
end

-- One refresh for one change: while the addon takes in a change (Engine.Coalesce: the log's full look, FR_STATE), the
-- refreshes its parts ask for - the plan's own, a hand-in added, a side trip's stop, a focus - are one, run when
-- they are all done. An objective finished ran three back to back (15 ms each at level 50: the perf battery)
local held -- nil, or true while a change is taken in; "due" once a refresh was asked for
function Engine.Coalesce(fn)
  if held then return fn() end
  held = true
  local ok, err = pcall(fn)
  local due = held == "due"
  held = nil
  if due then Engine.bgSolve = true; local ok2, e2 = pcall(Engine.Refresh); Engine.bgSolve = nil; if not ok2 then error(e2, 0) end end
  if not ok then error(err, 0) end
end
for _, e in ipairs({ "QUEST_REMOVED", "HEARTHSTONE_BOUND", "PLAYER_ENTERING_WORLD", "FR_ROUTE_CHANGED", "FR_NOPE" }) do
  ns.On(e, function() Engine.ForgetDone() end)
end
-- (a new zone matters only going into or out of a dungeon: a run there is done while you are inside)
local wasInside
ns.On("ZONE_CHANGED_NEW_AREA", function() local inside = ns.Is(IsInInstance); if inside ~= wasInside then wasInside = inside; Engine.ForgetDone() end end)
-- what you're plainly doing holds the card: a step you chose (Do it now), or one your kills count for (for
-- PROGRESS_HOLD seconds after the last one). anyStatus: the hold whatever the step's status (the refresh checks it itself)
function Engine.Holding(anyStatus)
  local fi, why = Engine.focus, Engine.focusWhy
  if not (fi and (why == "chosen" or (why == "progress" and GetTime() - (Engine.focusAt or 0) < Engine.PROGRESS_HOLD))) then return false end
  return anyStatus or Engine.Status(fi) == "todo"
end
-- a refresh for something the game said (a new zone, logging in): its solve in the background, like the log's
function Engine.RefreshBg() Engine.Coalesce(Engine.Refresh) end
-- remove the steps pred says from the route (inserted stops only): numbers, keys and the remembered run follow
function Engine.RemoveSteps(pred)
  local list = steps()
  local n = 0
  for j = #list, 1, -1 do
    if list[j].inserted and pred(list[j]) then
      table.remove(list, j); n = n + 1
      if Engine.current and Engine.current > j then Engine.current = Engine.current - 1 end
      if Engine.planned and Engine.planned > j then Engine.planned = Engine.planned - 1 end
    end
  end
  if n == 0 then return 0 end
  for j = 1, #list do list[j].id = j end
  keyCache[list] = nil
  Engine.focus, Engine.focusWhy, Engine.view = nil, nil, nil
  if Engine.ForgetDone then Engine.ForgetDone() end
  return n
end
-- a background solve's pick on the card (no rescan of the plan: nothing but the order changed)
function Engine.ShowPick(pick)
  if not pick or pick == Engine.current or Engine.Status(pick) ~= "todo" then return end
  local fi, why = Engine.focus, Engine.focusWhy
  if Engine.Holding() then return end
  Engine.focus = nil
  Engine.current = pick
  if Engine.view and Engine.view == Engine.current then Engine.view = nil end
  ns.Fire("FR_STEP", Engine.Shown())
end
function Engine.Refresh()
  if held then held = "due"; return end
  local outer = batch == nil
  if outer then batch = {} else wipe(batch) end -- a nested refresh follows a change: start the reuse over
  local t0 = outer and debugprofilestop and debugprofilestop()
  local ok, err = pcall(Engine.RefreshInner)
  if outer then batch = nil end
  if t0 then ns.Time("refresh", debugprofilestop() - t0) end
  if not ok then error(err, 0) end
end
-- the login catch-up stays quiet; tests switch it to see the completion cue
function Engine.SetQuiet(q) local was = quiet; quiet = q and true or false; return was end
function Engine.RefreshInner()
  Engine.here = Engine.HereMap() -- the zone you are in, for this refresh (Engine.BehindYou)
  if Engine.placeReady and Engine.PlaceDue() then Engine.FindPlace() end
  if Engine.placeReady then Engine.JoinHad() end
  local before = Engine.current
  local beforeStep = before and steps()[before]
  if not Engine.bgSolve then Engine.holdShow = nil end -- (a refresh you asked for shows at once: no hold from a solve before it)
  local tc = debugprofilestop and debugprofilestop()
  Engine.current = Engine.Compute()
  if tc and ns.Time then ns.Time("compute", debugprofilestop() - tc) end
  -- already standing in a travel step's destination (switched routes there, logged in there, rode in): it's done
  for _ = 1, 5 do
    local s = Engine.current and steps()[Engine.current]
    if not (s and s.k == "fly" and s.to and Engine.InZone and Engine.InZone(s.to)) then break end
    ns.char.manualDone[key(Engine.current)] = true
    if batch then wipe(batch) end
    Engine.current = Engine.Compute()
  end
  -- what to do next: the live solver's pick among the next stops you can do and finished quests near you (Next.lua),
  -- or, with it off, the old reordering - a later step you're working on or standing at (Engine.UpdateFocus)
  Engine.planned = Engine.current
  -- On a flight nothing on the ground is in reach: the step you took off with holds until you land, instead of the
  -- card re-picking as you pass over zones - a hand-in in Elwynn came up while flying over Stranglethorn (tester:
  -- "it can be a bit confusing to see it constantly updating"). Kept by the step itself (a stop inserted meanwhile
  -- moves its number). Landing plans again from where you are
  local aloft = ns.Is and UnitOnTaxi and ns.Is(UnitOnTaxi, "player")
  local holdAt
  if aloft then
    if not Engine.taxiHold then Engine.taxiHold = (before and steps()[before]) or (Engine.current and steps()[Engine.current]) end
    holdAt = Engine.taxiHold and planIndex().idx[Engine.taxiHold]
    if holdAt and Engine.Status(holdAt) ~= "done" then Engine.current = holdAt else holdAt = nil end
  else
    Engine.taxiHold = nil
  end
  if holdAt then
    -- (held for the flight: no solve, no reordering)
  elseif ns.Next and ns.Next.Enabled() then
    -- what you're plainly doing wins over any solve: a step your kills count for (for Engine.PROGRESS_HOLD seconds
    -- after the last one), or one you chose (Do it now)
    local fi, why = Engine.focus, Engine.focusWhy
    local held = Engine.Holding(true)
    if held and Engine.Status(fi) == "todo" then
      Engine.current = fi
    elseif Engine.RecentProgress(Engine.current) then
      Engine.focus = nil -- (farming the plan's own step: your kills count for it - it stays, whatever circle you wander into)
    else
      Engine.focus = nil
      if Engine.bgSolve and ns.Next.PickAsync then
        -- taking in a change from the game (Engine.Coalesce): the solve runs in the background (it was 20-40 ms of a
        -- 50 ms refresh at level 50); meanwhile the card keeps the last pick while it is still to do, else the plan's
        -- step, and moves only if the solve picks another (Engine.ShowPick)
        local keep = ns.Next.LastPick()
        local planned, list = Engine.current, steps()
        if keep then Engine.current = keep end
        -- the card holds while the solve settles (at most Engine.HOLD_SECS): it showed the plan's step, then a moment
        -- later the solve's pick - two slides for one hand-in (persona review). Only when the card would change at all
        local token = {}
        if beforeStep and steps()[Engine.current] ~= beforeStep then
          Engine.holdShow = token
          if C_Timer and C_Timer.After then C_Timer.After(Engine.HOLD_SECS, function() if Engine.holdShow == token then Engine.holdShow = nil; ns.Fire("FR_STEP", Engine.Shown()) end end) end
        end
        ns.Next.PickAsync(planned, function(pick)
          local held = Engine.holdShow == token
          if held then Engine.holdShow = nil end
          if Engine.planned ~= planned or steps() ~= list then if held then ns.Fire("FR_STEP", Engine.Shown()) end return end
          local was = Engine.current
          Engine.ShowPick(pick or planned)
          if held and Engine.current == was then ns.Fire("FR_STEP", Engine.Shown()) end
        end)
      else
        local ok, pick = pcall(ns.Next.Pick, Engine.current)
        if ok and pick then Engine.current = pick elseif not ok and ns.LogError then ns.LogError("next", pick) end
      end
    end
  else
    local fi = Engine.focus
    if fi and fi ~= Engine.current then
      local st = Engine.Status(fi)
      if st == "todo" and fi > (Engine.current or 0) then Engine.current = fi else Engine.focus = nil end
    end
  end
  if Engine.view and Engine.view == Engine.current then Engine.view = nil end
  -- the "done" cue only when the step you were on really got done: the current step also moves when live reordering
  -- picks another step, when you abandon a quest, when a level-up opens an earlier step, or after a jump
  if before and Engine.current ~= before and not quiet and beforeStep then
    local list, at = steps(), before
    if list[at] ~= beforeStep then at = planIndex().idx[beforeStep] end -- a stop was inserted before it, or another route
    -- skipped or "not doing" isn't done: no tick for those either
    local dropped = ns.char.skipped[key(at or 0) or ""] or (beforeStep.q and ns.Nope(beforeStep.q))
    if at and Engine.Status(at) == "done" and not dropped then ns.Fire("FR_STEP_DONE", at) end
  end
  if not Engine.holdShow then ns.Fire("FR_STEP", Engine.Shown()) end
end
Engine.HOLD_SECS = 0.3

-- Look at step i (a click on its row in the card, the route window, a map pin or the zones tab): right-click shows it
-- on the map, shift-click jumps there (noJump: not from here), a click looks at it - the step you are on ends looking.
-- One rule for every row (the card's used to differ from the route window's - code review)
function Engine.Look(i, btn, noJump)
  if not i then return end
  if btn == "RightButton" then ns.ShowOnMap(i) return end
  if IsShiftKeyDown() and not noJump then Engine.Jump(i) return end
  Engine.view = (i ~= Engine.current) and i or nil
  ns.Fire("FR_STEP", Engine.Shown())
end
-- history entries let Undo restore accidental skips/dones; one entry may cover several steps
local function remember(kind, ids) table.insert(ns.char.history, { kind = kind, ids = ids }); if #ns.char.history > 50 then table.remove(ns.char.history, 1) end end
Engine._remember = remember -- (Engine/Worth.lua)

local function markDone(i)
  i = i or Engine.Shown(); local id = key(i); if not id then return end
  ns.char.manualDone[id] = true
  remember("done", { id })
  Engine.view = nil
  Engine.Refresh()
end
-- you clicked done (the card's check, a slash command): Learn.lua records it as "ticked by hand"
function Engine.MarkDone(i) return markDone(i) end
-- the game told us (you arrived, landed, set your hearth, took the flight, trained): the same tick, not a hand tick -
-- through MarkDone these went into the learning data as things the route got wrong
function Engine.AutoDone(i) return markDone(i) end
function Engine.Skip(i)
  Engine.ForgetDone()
  i = i or Engine.Shown(); local s = steps()[i]; if not s then return end
  local ids = { key(i) }
  ns.char.skipped[key(i)] = true
  -- skipping a quest you don't have: its later objective / turn-in steps go too
  if s.q and (s.k == "accept" or not State.OnQuest(s.q)) and not State.IsCompleted(s.q) then
    for j = i + 1, #steps() do local t = steps()[j]; if t.q == s.q and not ns.char.skipped[key(j)] then ns.char.skipped[key(j)] = true; ids[#ids + 1] = key(j) end end
  end
  remember("skip", ids)
  Engine.view = nil
  Engine.Refresh()
end
function Engine.Undo()
  Engine.ForgetDone()
  local h = table.remove(ns.char.history)
  if not h then ns.Print("nothing to undo."); return end
  for _, id in ipairs(h.ids) do ns.char.skipped[id] = nil; ns.char.manualDone[id] = nil end
  for _, q in ipairs(h.nope or {}) do if ns.char.nope then ns.char.nope[q] = nil end end
  Engine.view = nil
  Engine.Refresh()
  ns.Print(h.kind == "skip" and "skip undone." or h.kind == "nope" and "back on your route." or "undone.")
end
-- look at the previous step (view only; progress is unchanged)
function Engine.Back()
  Engine.ForgetDone()
  local cur = Engine.Shown() or (#steps() + 1)
  if cur <= 1 then return end
  Engine.view = cur - 1
  ns.Fire("FR_STEP", Engine.view)
end
function Engine.Forward()
  if not Engine.view then return end
  local nxt = Engine.view + 1
  Engine.view = (Engine.current and nxt < Engine.current) and nxt or nil
  ns.Fire("FR_STEP", Engine.Shown())
end
-- jump: backwards = view it; forwards = skip what's in between (undoable)
function Engine.Jump(i)
  Engine.ForgetDone()
  local list = steps()
  if not list[i] then return end
  if not Engine.current or i <= Engine.current then
    Engine.view = (i ~= Engine.current) and i or nil
    ns.Fire("FR_STEP", Engine.Shown())
    return
  end
  local ids = {}
  for j = Engine.current, i - 1 do if not Engine.IsDone(j) then local id = key(j); ns.char.skipped[id] = true; ids[#ids + 1] = id end end
  remember("skip", ids)
  Engine.view = nil
  Engine.Refresh()
end

function Engine.Arrived(i)
  local s = steps()[i]
  if s and s.k == "goto" and i == Engine.current then Engine.AutoDone(i) end
end

local function currentStep() local i = Engine.current; return i, i and steps()[i] end
local function nearCurrent(kind, within)
  -- the first not-done step of this kind among the next few (lets you do things a little early)
  local i = Engine.current
  if not i then return nil end
  for j = i, math.min(#steps(), i + (within or 0)) do
    local s = steps()[j]
    if s.k == kind and not Engine.IsDone(j) then return j end
  end
end

ns.On("FR_STATE", function() Engine.Refresh() end)
ns.On("PLAYER_ENTERING_WORLD", function()
  quiet = true
  C_Timer.After(1, function() Engine.RefreshBg() end)
  C_Timer.After(3, function() Engine.RefreshBg(); quiet = false end)
end)
ns.On("PLAYER_XP_UPDATE", function() local _, s = currentStep(); if s and s.k == "grind" then Engine.Refresh() end end)
-- fly steps carry no coordinates, so the arrow and pins point at the nearest flight master in your zone (FlightMasters.lua)
local function inZone(to)
  local m = ns.State.Position()
  local guard = 0
  while m and guard < 6 do
    if m == to then return true end
    local info = C_Map.GetMapInfo(m); m = info and info.parentMapID; guard = guard + 1
  end
  return false
end
-- where a travel step without coordinates should point: the flight master in the zone you're in
function Engine.TravelTarget(s)
  if not s or s.x or s.k ~= "fly" then return nil end
  local m, px, py = ns.State.Position()
  local plan = Engine.TravelPlan(s)
  if plan and (plan.ride or not plan.via or plan.via == m) then return plan.m, plan.x, plan.y, nil end
  local list = m and ns.FLIGHT and ns.FLIGHT[m]
  if not list then return nil end
  local best, bd
  for _, fm in ipairs(list) do
    local d = (px and py) and ((fm[1] - px) ^ 2 + (fm[2] - py) ^ 2) or 0
    if not bd or d < bd then best, bd = fm, d end
  end
  return m, best[1], best[2], best[3]
end
-- how to get to a travel step's destination, from the flight paths you actually have. Aims at the first stop there
-- (where you're really going), and compares riding straight there with flying: walk to a flight master on your map,
-- the flight, then walk from where you land. nil = just fly as usual.
-- -> { ride = true (ride straight there) | via = uiMap to fly to first, viaName, m, x, y = where to go, stop = step }
Engine.FLIGHT_YARDS = 700 -- a flight costs about this much walking (take-off, the flight, landing)
local function stepIndex(s) if not s then return nil end return planIndex().idx[s] end
local function firstStop(s)
  if s._stop then return s._stop end
  local i = stepIndex(s); if not i then return nil end
  local list = steps()
  for j = i + 1, #list do
    local t = list[j]
    if t.k == "fly" or t.k == "hearth" then return nil end
    if t.m and t.x and not t.unknown and t.m == s.to then return t end
  end
end
function Engine.TravelPlan(s)
  local HBD = LibStub("HereBeDragons-2.0")
  if not (s and s.k == "fly" and s.to and not s.boat and ns.FLIGHT and HBD) then return nil end
  local destName = s.dest or s.text
  if not destName then return nil end
  local fm = ns.FLIGHT[s.to] and ns.FLIGHT[s.to][1]
  local stop = firstStop(s)
  local tx, ty = (stop and stop.x) or (fm and fm[1]) or 0.5, (stop and stop.y) or (fm and fm[2]) or 0.5
  local wx, wy, inst = HBD:GetWorldCoordinatesFromZone(tx, ty, s.to)
  if not wx then return nil end
  local d = function(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end
  local pm, px, py = ns.State.Position()
  local hx, hy, hinst
  if pm and px then hx, hy, hinst = HBD:GetWorldCoordinatesFromZone(px, py, pm) end
  local rideYd = (hx and hinst == inst) and d(hx, hy, wx, wy) or nil
  -- the nearest flight master on your map (where a flight would start)
  local startYd
  for _, f in ipairs((pm and ns.FLIGHT[pm]) or {}) do
    local fx, fy, finst = HBD:GetWorldCoordinatesFromZone(f[1], f[2], pm)
    if fx and hx and finst == hinst then local dd = d(hx, hy, fx, fy); if not startYd or dd < startYd then startYd = dd end end
  end
  local plan = { m = s.to, x = tx, y = ty, stop = stop }
  if Engine.KnowsFlightIn(destName) then
    -- you can fly right there: only worth riding if the first stop is closer than the flight would make it
    if not (rideYd and fm) then return nil end
    local lx, ly = HBD:GetWorldCoordinatesFromZone(fm[1], fm[2], s.to)
    local flyYd = (startYd or 0) + Engine.FLIGHT_YARDS + (lx and d(lx, ly, wx, wy) or 0)
    if rideYd < flyYd then plan.ride = true; plan.yards = rideYd; return plan end
    return nil
  end
  -- no flight path there: fly to the one you have that lands closest to the first stop, unless riding is shorter
  local best
  for m, list in pairs(ns.FLIGHT) do
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(m)
    if info and info.name and m ~= s.to and Engine.KnowsFlightIn(info.name) then
      local fx, fy, finst = HBD:GetWorldCoordinatesFromZone(list[1][1], list[1][2], m)
      if fx and finst == inst then
        local dd = d(fx, fy, wx, wy)
        if not best or dd < best.d then best = { d = dd, m = m, name = info.name } end
      end
    end
  end
  if best and best.m ~= pm and not (rideYd and rideYd <= (startYd or 0) + Engine.FLIGHT_YARDS + best.d) then plan.via, plan.viaName = best.m, best.name
  else plan.ride = true; plan.yards = rideYd end
  return plan
end

-- any step: how to get there, when it is more than a walk.
-- -> nil (a walk in the zone you are in, or unknown), or { how = "fly" | "via" | "ride", m, x, y = where the arrow
--    points now, text = what to do, fm = flight master name when the arrow points at one }
-- One trip planner for every trip (ns.Travel): another zone or continent is always planned; a step in your own zone
-- is planned too when the walk is long, and comes back as a trip only when a flight you know is clearly quicker
-- (ns.Travel.Shortcut - shortcut = true on the trip: Darkshire to the west end of Duskwood by way of Sentinel Hill).
-- the same trip is asked for by the card, the arrow and the pins on every refresh: worked out once for the same step and
-- the same situation (where you are to a few yards, your level, the flight paths you know, flying or sailing, your
-- hearthstone, the trip you're on). A trip took ~15 ms; three of them made up most of a refresh on a long plan.
local tripMemo = {}
local function tripKey(s)
  local pm, px, py = ns.State.Position()
  local n = State.KnownTaxiCount()
  local okB, b = pcall(GetBindLocation)
  return table.concat({ tostring(pm), px and math.floor(px * 400) or "-", py and math.floor(py * 400) or "-", UnitLevel("player") or 0, n,
    tostring(ns.Is(UnitOnTaxi, "player")), tostring(ns.Arrow and ns.Arrow.aboard), tostring(okB and b), tostring(Engine.lastTripStep == s), (ns.char and ns.char.boundAt and ns.char.boundAt.m) or "-" }, "|")
end
function Engine.TravelFor(s)
  if not s then return nil end
  local k = tripKey(s)
  local m = tripMemo[s]
  if m and m.k == k then return m.v end
  local v = Engine.TravelForUncached(s)
  tripMemo[s] = { k = k, v = v }
  return v
end
function Engine.TravelForUncached(s)
  if not s or s.k == "hearth" or s.unknown then return nil end -- (no known place: no trip to plan)
  -- on a flight the taxi is taking you: nothing to plan from the sky. (Crossing a zone mid-air would otherwise
  -- plan a fresh trip from wherever you are above the ground - "Ride to Wetlands", an arrow at some town below.)
  -- The way on is planned again when you land.
  if ns.Is(UnitOnTaxi, "player") then
    local l = { how = "onflight", text = "On the flight - sit tight, the way on is planned when you land" }
    return { how = "aboard", text = l.text, legs = { l } }
  end
  if s.boat then
    -- the route's own "Boat to X" step, once the ship has sailed: the pier is behind you, nothing to point at
    -- until you land (the step ticks on arrival)
    if ns.Arrow and ns.Arrow.aboard then
      local l = { how = "aboard", text = "On the boat to " .. ((s.text or ""):match("^Boat to (.+)$") or s.dest or "the other side") .. " - sit tight" }
      return { how = "aboard", text = l.text, legs = { l } }
    end
    -- not sailing yet: in the pier's zone the step's own pier is the target (nil below); from anywhere else, the
    -- way to that pier is planned like any other stop (not a straight line from Goldshire or the tram)
    if not (s.m and s.x) then return nil end
  end
  local pm, px, py = ns.State.Position()
  -- another continent: boats, flights you know and rides, as one planned trip (ns.Travel)
  local HBD = LibStub("HereBeDragons-2.0")
  if pm and px and ns.Travel then
    local tm, tx, ty, tname
    if s.k == "fly" and s.to and not s.boat then
      local st = firstStop(s); local fm = ns.FLIGHT and ns.FLIGHT[s.to] and ns.FLIGHT[s.to][1]
      tm, tx, ty, tname = s.to, (st and st.x) or (fm and fm[1]) or 0.5, (st and st.y) or (fm and fm[2]) or 0.5, s.dest or s.text
    elseif s.m and s.x then tm, tx, ty, tname = s.m, s.x, s.y, s.zone end
    if tm then
      local a1, a2, ai = HBD:GetWorldCoordinatesFromZone(px, py, pm)
      local b1, b2, bi = HBD:GetWorldCoordinatesFromZone(tx, ty, tm)
      -- somewhere no trip can start from (on the Deeprun Tram, in a dungeon) and the step is out in the world: the trip
      -- you were on carries on (the tram leg is under way); with none, it is planned when you come out. A trip planned
      -- from here would start from coordinates that mean nothing outside (it pointed "down 98 yd" from the tram).
      if pm ~= tm and ns.Travel.OnNetwork and not ns.Travel.OnNetwork(pm, px, py) and not (a1 and b1 and ai == bi) then
        local last = Engine.lastTripStep == s and Engine.lastTrip
        if last and last[1] then
          local legs = {}
          for k, l in ipairs(last) do legs[k] = l end
          if ns.Travel.IsTram(legs[1]) then legs[1] = { how = "aboard", text = (legs[1].text:gsub("^Take the", "On the")) .. " - sit tight" } end
          return { how = "aboard", text = ns.Travel.Describe(legs), legs = legs }
        end
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(pm)
        local l = { how = "aboard", text = "In " .. ((info and info.name) or "here") .. ": the way on is planned when you come out" }
        return { how = "aboard", text = l.text, legs = { l } }
      end
      -- any other zone (or continent): the trip planner weighs riding, your flight paths and boats together.
      -- Your own zone: the same planner, asked only whether something beats the walk by a margin (nil: walk)
      if a1 and b1 then
        local legs
        local shortcut = ai == bi and pm == tm
        if not shortcut then legs = ns.Travel.Plan({ m = pm, x = px, y = py }, { m = tm, x = tx, y = ty, name = tname })
        elseif s.k ~= "fly" and ns.Travel.Shortcut then
          legs = ns.Travel.Shortcut({ m = pm, x = px, y = py }, { m = tm, x = tx, y = ty, name = s.npc or tname })
        end
        if legs and legs[1] then
          -- already on the boat of the first leg: that leg is done, sit tight
          if legs[1].how == "boat" and ns.Arrow and ns.Arrow.aboard then
            local dest = legs[1].text:match(".* to (.+)$") or "the other side" -- the last "to": the boat's destination
            legs[1] = { how = "aboard", text = "On the boat to " .. dest .. " - sit tight" }
            return { how = "aboard", text = ns.Travel.Describe(legs), legs = legs }
          end
          -- which step it is for: a trip worked out for a step you only looked at must not teach the boat's pier
          Engine.lastTrip, Engine.lastTripStep = legs, s
          local text = ns.Travel.Describe(legs)
          if ns.Why then ns.Why("travel", "to " .. (tname or "another continent") .. ": " .. text) end
          return { how = legs[1].how, m = legs[1].m, x = legs[1].x, y = legs[1].y, text = text, legs = legs, shortcut = shortcut or nil }
        end
      end
    end
  end
  if not (s.m and s.x) or s.k == "fly" then return nil end
  if not pm or pm == s.m then return nil end
  local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(s.m)
  local destName = (info and info.name) or s.zone or "there"
  local plan = Engine.TravelPlan({ k = "fly", to = s.m, dest = destName, text = destName, _stop = s })
  local function atFlightMaster(goal)
    local list = ns.FLIGHT and ns.FLIGHT[pm]; if not list then return nil end
    local best, bd; for _, f in ipairs(list) do local dd = (f[1] - px) ^ 2 + (f[2] - py) ^ 2; if not bd or dd < bd then best, bd = f, dd end end
    local m, x, y, fm = pm, best[1], best[2], best[3]
    return { how = "fly", m = m, x = x, y = y, fm = fm, text = "Fly to " .. goal .. (fm and (" - flight master " .. fm) or "") }
  end
  if not plan then return atFlightMaster(destName) end -- you have its flight path and flying is quicker
  if plan.ride then return { how = "ride", m = s.m, x = s.x, y = s.y, text = ns.RideWord() .. " to " .. destName .. (plan.yards and (" - " .. ns.Style.Distance(plan.yards)) or "") } end
  if plan.via and plan.via ~= pm then
    local t = atFlightMaster(plan.viaName); if t then t.how = "via"; t.text = "No " .. destName .. " flight path yet: fly " .. (t.fm and ("from " .. t.fm .. " ") or "") .. "to " .. plan.viaName .. ", then ride" end
    return t
  end
  return { how = "ride", m = s.m, x = s.x, y = s.y, text = ns.RideWord() .. " to " .. destName }
end

-- arriving in the destination zone completes a fly step, however you got there (flew, rode, or were already there)
Engine.InZone = inZone
local function travelDone()
  local i, s = currentStep()
  if s and s.k == "fly" and s.to and inZone(s.to) then Engine.AutoDone(i) end
end
ns.On("ZONE_CHANGED_NEW_AREA", function() C_Timer.After(1, function() travelDone(); Engine.RefreshBg() end) end)
ns.On("PLAYER_ENTERING_WORLD", function() C_Timer.After(4, travelDone) end)
ns.On("HEARTHSTONE_BOUND", function()
  -- remember where you bound (the map you were on and the name the game gives it); every hearth step on that map
  -- counts as done while you stay bound there
  local m = ns.State.Position()
  -- (bound at one of the plan's bind stops - its innkeeper within 100 yd: that stop's own map, so the bind step and
  -- every hearth to it match whatever map id the game hands out indoors. A tester's bind went unnoticed)
  local HBDx = LibStub("HereBeDragons-2.0")
  local px, py, pinst = HBDx:GetPlayerWorldPosition()
  if px then
    for _, t in ipairs(steps()) do
      if t.k == "bind" and t.m and t.x then
        local x, y, inst = HBDx:GetWorldCoordinatesFromZone(t.x, t.y, t.m)
        if x and inst == pinst and (x - px) ^ 2 + (y - py) ^ 2 <= 100 * 100 then m = t.m; break end
      end
    end
  end
  ns.char.boundAt = { m = m, name = GetBindLocation and GetBindLocation() or nil }
  C_Timer.After(0.5, function() ns.char.boundAt.name = GetBindLocation and GetBindLocation() or ns.char.boundAt.name; Engine.Refresh() end)
  Engine.Refresh()
end)
-- standing in the place your hearthstone is set (the game's name for it is the name of where you are): that is the
-- map it is on, whenever you set it - before the addon, or while it was off
local function learnBind()
  local okB, b = pcall(GetBindLocation)
  if not okB or type(b) ~= "string" or b == "" or not ns.char then return end
  local at = ns.char.boundAt
  if at and at.name == b and at.m then return end
  local okS, sub = pcall(GetSubZoneText); local okZ, zone = pcall(GetRealZoneText)
  if not ((okS and sub == b) or (okZ and zone == b)) then return end
  local m = ns.State.Position()
  if not m then return end
  ns.char.boundAt = { m = m, name = b }
  if ns.Why then ns.Why("hearth", "your hearthstone is set here (" .. b .. "): noted") end
end
Engine.LearnBind = learnBind
for _, ev in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do ns.On(ev, function() pcall(learnBind) end) end
ns.On("PLAYER_ENTERING_WORLD", function() C_Timer.After(2, function() pcall(learnBind) end) end)
-- opening a flight map ticks a "get the flight path" step only at that flight master (same map) - not when you
-- open the map somewhere else to fly toward it (the zone check in the step status covers learning it normally)
ns.On("FR_TAXI_OPENED", function()
  local j = nearCurrent("fp", 3); if not j then return end
  local s = steps()[j]; local m = ns.State.Position()
  if s and (not s.m or s.m == m) then Engine.AutoDone(j) end
end)
-- once: undo "got the flight path" ticks from before that fix, where you still have no flight path in that zone
ns.On("FR_LOADED", function()
  if ns.char.fixFpTicks then return end
  ns.char.fixFpTicks = true
  C_Timer.After(2, function()
    local undone = 0
    for i, s in ipairs(steps()) do
      local k = s.k == "fp" and key(i)
      if k and ns.char.manualDone[k] and s.zone and not Engine.KnowsThisFlightPoint(s) then ns.char.manualDone[k] = nil; undone = undone + 1 end
    end
    if undone > 0 then ns.Print("Un-ticked " .. undone .. " \"get the flight path\" step" .. (undone == 1 and "" or "s") .. " you don't actually have yet."); Engine.Refresh() end
  end)
end)
-- hearthstone cast: complete a hearth step
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
  if unit ~= "player" then return end
  if spellID == 8690 then local j = nearCurrent("hearth", 1); if j then Engine.AutoDone(j) end end
end)
-- landing from a flight: complete a fly step (if it names a destination map, be in it)
local onTaxi = false
ns.On("PLAYER_CONTROL_LOST", function() C_Timer.After(0.5, function() onTaxi = ns.Is(UnitOnTaxi, "player") end) end)
ns.On("PLAYER_CONTROL_GAINED", function()
  if not onTaxi then return end
  onTaxi = false
  local j = nearCurrent("fly", 1)
  if j then
    local s = steps()[j]
    local m = ns.State.Position()
    if not s.to or s.to == m or (C_Map.GetMapInfo(m) and C_Map.GetMapInfo(m).parentMapID == s.to) then Engine.AutoDone(j) end
  end
end)
-- class trainer visits complete a train step (profession trainers don't)
local atClassTrainer = false
ns.On("TRAINER_SHOW", function() atClassTrainer = not (IsTradeskillTrainer and IsTradeskillTrainer()) end)
ns.On("TRAINER_CLOSED", function()
  if not atClassTrainer then return end
  atClassTrainer = false
  local j = nearCurrent("train", 4); if j then Engine.AutoDone(j) end
end)
