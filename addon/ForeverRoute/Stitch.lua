-- Chain starts for a zone you picked (the design for zones and chains, stage 3): when a quest there needs an earlier
-- quest you haven't handed in, the steps for it are cut from your own plan (it already has them, in order) and put in
-- front of that quest when the detour is small; otherwise the quest waits and you are told what it needs and where.
-- Nothing is saved: the splice is made again each time the zone's route is unpacked.
--   ns.Stitch.Closure(q, isDone, onPlan)  the quests q needs first, not done, prerequisites before what needs them
--   ns.Stitch.Packet(steps, ids, isDone, onQuest)  the steps of those quests cut from a route -> copies, missing ids
--   ns.Stitch.Splice()  on a zone route: the chain starts it needs, spliced or noted
--   ns.STITCH  the limits (the simulator can set them: FR_SIM_STITCH)
local _, ns = ...
local Stitch = {}
ns.Stitch = Stitch

-- maxYards: the most a chain start may add to the trip (Engine.InsertStop, per stop); maxSteps: the most steps one
-- chain start may add; minShare: the least XP it must pay (its own quests and the one it opens), as a share of your
-- level; grayMargin: a quest it opens that is gray within this many levels isn't worth it
ns.STITCH = ns.STITCH or { maxYards = 3000, maxSteps = 14, minShare = 0.03, grayMargin = 1 }

-- the quests q needs handed in first (QUEST_PRE: g all of, s any one of - the one on your plan when there is one),
-- those not done, each after its own prerequisites. A loop in the data stops where it closes.
function Stitch.Closure(q, isDone, onPlan)
  local out, seen = {}, {}
  local function visit(id, depth)
    if seen[id] or depth > 40 then return end
    seen[id] = true
    local pre = ns.QUEST_PRE and ns.QUEST_PRE[id]
    if pre then
      for _, p in ipairs(pre.g or {}) do if not isDone(p) then visit(p, depth + 1) end end
      if pre.s and #pre.s > 0 then
        local any = false
        for _, p in ipairs(pre.s) do if isDone(p) then any = true; break end end
        if not any then
          local pick = pre.s[1]
          if onPlan then for _, p in ipairs(pre.s) do if onPlan[p] then pick = p; break end end end
          visit(pick, depth + 1)
        end
      end
    end
    if id ~= q then out[#out + 1] = id end
  end
  visit(q, 0)
  return out
end

local PACKET_KIND = { accept = true, obj = true, turnin = true }
-- the steps of quests ids, in the route's order: pick-ups, objectives, hand-ins with a place (no flights or hearths:
-- the trip between is the card's). missing: a quest whose pick-up the route doesn't have (and you don't carry)
function Stitch.Packet(list, ids, isDone, onQuest)
  local want, has = {}, {}
  for _, id in ipairs(ids) do want[id] = true end
  local out = {}
  for _, s in ipairs(list or {}) do
    local q = s.q
    if q and want[q] and PACKET_KIND[s.k] and s.m and s.x and not s.unknown and not isDone(q) then
      if s.k == "accept" then has[q] = true end
      if not (s.k == "accept" and onQuest(q)) then
        local copy = {}; for k, v in pairs(s) do copy[k] = v end
        copy.inserted, copy.id, copy.wp = true, nil, nil
        out[#out + 1] = copy
      end
    end
  end
  local missing = {}
  for _, id in ipairs(ids) do if not has[id] and not onQuest(id) then missing[#missing + 1] = id end end
  return out, missing
end

local function questName(q, list)
  for _, s in ipairs(list or {}) do if s.q == q and s.name then return s.name, s.zone end end
  local d = ns.SIDE_QUESTS and ns.SIDE_QUESTS[q]
  if d and d.n then return d.n, nil end
  local n = ns.Engine and ns.Engine.QuestName and ns.Engine.QuestName(q)
  if n and not n:find("^quest %d") then return n, nil end
  -- (a quest the plan and the game's cache don't name: by its chain, where it is)
  local ch = ns.ChainOf and ns.ChainOf(q)
  local z = ch and ns.AREA_NAME and ns.AREA_NAME[ch.z[ch.at]]
  if ch then return "an earlier part of " .. ch.name, z end
  return "an earlier quest", nil
end

-- the last splice's outcome, for the simulated player's report and /fr why: { spliced = n, notes = { text } }
Stitch.last = nil

function Stitch.Splice()
  local d, E, S = ForeverRouteData, ns.Engine, ns.State
  if not (d and d.zoneRoute and d.steps) or d.steps._stitched or not (E and E.InsertStop and E.current) then return false end
  d.steps._stitched = true
  local P = ns.STITCH
  local main = (ns.ResolvePath and ns.ResolvePath(ns.char.returnTo)) or (ns.MainRoutes and ns.MainRoutes()[1])
  local mainSteps = main and ns.Steps(main) or {}
  local onPlan = {}; for _, s in ipairs(mainSteps) do if s.q and s.k == "accept" then onPlan[s.q] = true end end
  local isDone = function(q) return S.IsCompleted(q) end
  local onQuest = function(q) return S.OnQuest(q) end
  local L = (UnitLevel and UnitLevel("player")) or 1
  local px, py, pinst
  local HBD = LibStub and LibStub("HereBeDragons-2.0", true)
  if HBD then px, py, pinst = HBD:GetPlayerWorldPosition() end
  local res = { spliced = 0, notes = {} }
  local done = {} -- quests already spliced (two quests here needing the same start)
  local i = E.current
  while i <= #d.steps do
    local s = d.steps[i]
    if s.k == "accept" and s.q and not s.inserted and not isDone(s.q) and not onQuest(s.q) and ns.PrereqsMet and not ns.PrereqsMet(s.q) then
      local ids = Stitch.Closure(s.q, function(q) return isDone(q) or done[q] end, onPlan)
      local packet, missing = Stitch.Packet(mainSteps, ids, isDone, onQuest)
      local name = s.name or questName(s.q)
      local why
      local ql = tonumber(s.level) or (ns.QuestLevel and ns.QuestLevel(s.q))
      local xp = ns.QuestXp and (ns.QuestXp(s.q, L) or 0) or 0
      for _, id in ipairs(ids) do xp = xp + (ns.QuestXp and ns.QuestXp(id, L) or 0) end
      local need = (P.minShare or 0) * ((ns.XP_TO_LEVEL and ns.XP_TO_LEVEL[L]) or 0)
      if #missing > 0 then
        local mn, mz = questName(missing[1], mainSteps)
        why = name .. " - needs " .. mn .. (mz and (" (" .. mz .. ")") or "") .. " first"
      elseif #packet == 0 then
        why = nil -- (everything it needs is in your log: its hand-ins are on the route already)
      elseif #packet > P.maxSteps then
        why = name .. " - its chain start is " .. #packet .. " steps, too long a detour"
      elseif ql and E.GrayAt and ql <= E.GrayAt(L + P.grayMargin) then
        why = name .. " - gray before you'd get to it"
      elseif xp < need then
        why = name .. " - not worth the detour"
      else
        -- in order, each after the one before, all before the quest that needs them
        local added, minI, ok = {}, E.current, true
        for _, c in ipairs(packet) do
          local target; for j = minI, #d.steps do if d.steps[j] == s then target = j; break end end
          local at = target and E.InsertStop(c, px, py, pinst, { minIndex = minI, maxIndex = target, maxCost = P.maxYards, why = "a chain start for " .. name })
          if not at then ok = false; break end
          c.note = "Chain start for " .. name .. "."
          added[#added + 1] = c; minI = at + 1
        end
        if ok then
          res.spliced = res.spliced + #added
          for _, id in ipairs(ids) do done[id] = true end
        else
          -- (all or nothing: half a chain start is a walk for nothing)
          for _, c in ipairs(added) do for j = #d.steps, 1, -1 do if d.steps[j] == c then table.remove(d.steps, j); break end end end
          local mn, mz = questName(ids[1], mainSteps)
          why = name .. " - needs " .. mn .. (mz and (" (" .. mz .. ")") or "") .. " first, too far from here"
        end
      end
      if why then res.notes[#res.notes + 1] = why; if ns.Why then ns.Why("stitch", "left out: " .. why) end end
    end
    i = i + 1
  end
  Stitch.last = res
  if res.spliced > 0 then ns.Print(res.spliced .. " step" .. (res.spliced == 1 and "" or "s") .. " added first: the start of a chain this zone needs (marked on the card).") end
  if #res.notes > 0 then ns.Print("Left out here: " .. res.notes[1] .. (#res.notes > 1 and (" (+" .. (#res.notes - 1) .. " more: /fr why)") or "") .. ".") end
  return res.spliced > 0
end

ns.On("FR_ROUTE_CHANGED", function() C_Timer.After(0.7, function() if Stitch.Splice() then ns.Engine.Refresh() end end) end)
