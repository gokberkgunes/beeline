-- Why the card sends you where it does, in plain words: the card's "?" (Card.lua) and the one line under a trip that
-- leaves your zone. Players don't read paragraphs, so it leads with one line that
-- says it's the quickest way and why, backed by a number where the engine has one (minutes saved, XP), and "the fastest
-- route the planner found" where it has none - never a made-up number. The facts follow on a second line; a trip's
-- legs, in full, after that.
-- Built only when asked (a click on "?"): nothing here runs per frame. The card's line is memoized per step.
local _, ns = ...
local pcall = ns.PCall or pcall -- (a job never pauses under it: Core.lua)
local Explain = {}
ns.Explain = Explain

local function steps() return BeelineData and BeelineData.steps or {} end
local function cap(t) return t and (t:sub(1, 1):upper() .. t:sub(2)) or t end
local function plural(n, one, many) return n .. " " .. (n == 1 and one or (many or (one .. "s"))) end
function Explain.Xp(xp)
  xp = math.floor(tonumber(xp) or 0)
  if xp >= 1000 then return (string.format("%.1fk", xp / 1000):gsub("%.0k$", "k")) end
  return tostring(xp)
end
local function minutes(secs) return math.max(1, math.floor((tonumber(secs) or 0) / 60 + 0.5)) end

-- the zone you are in, by the plan's names ("Stormwind City")
function Explain.HereZone()
  local pm = ns.State and ns.State.Position and ns.State.Position()
  local info = pm and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(pm)
  return info and info.name or nil, pm
end

-- the trip the card leads with for step s: { trip, legs }, or nil (a walk, or no trip). Card.TripHead decides when.
local function tripOf(s)
  local t = s and ns.Engine.TravelFor and ns.Engine.TravelFor(s)
  if not t then return nil end
  return t, t.legs or { t }
end

-- the stretch of the plan step i takes you to: the zone's visit from ZonesAhead and what it is worth at your level
-- (Engine.StretchWorth) -> { zone, after (the zone after it), quests, name (its first quest), n (quests at your
-- level), hand (hand-ins), xp, secs (work), first, last } or nil
function Explain.Stretch(i)
  local s = steps()[i]
  if not (s and ns.Engine.ZonesAhead) then return nil end
  local z = ns.Engine.ZonesAhead(i, 3)
  local want = (s.k == "fly" and (s.dest or s.text)) or s.zone
  local a, b
  for k = 1, #z do if z[k].zone == want or (s.k == "fly" and k == 1) then a, b = z[k], z[k + 1]; break end end
  if not a then return nil end
  local list = steps()
  local last = (b and b.first - 1) or #list
  local out = { zone = a.zone, after = b and b.zone or nil, quests = a.quests, name = a.names and a.names[1], first = a.first, last = last, grind = a.grind }
  if ns.Engine.StretchWorth then
    local ok, xp, secs, n = pcall(ns.Engine.StretchWorth, a.first, last)
    if ok then out.xp, out.secs, out.n = xp, secs, n end
  end
  local hand = 0
  for j = a.first, last do local t = list[j]; if t and t.k == "turnin" and not ns.Engine.IsDone(j) then hand = hand + 1 end end
  out.hand = hand
  return out
end

-- does the trip to step i take you out of the zone you are in?
local function leaves(i)
  local s = steps()[i]
  local here, pm = Explain.HereZone()
  if not (s and pm) then return false end
  if s.k == "fly" then return (s.to and s.to ~= pm) or false end
  return (s.m and s.m ~= pm) or false
end

-- A trip out of the zone you picked that the planner kept because it pays (tools/zone-confine.js marks it: detour = giver,
-- hand-in or work, with the quest, the zone, the work that stays here and a quest of this zone it goes alongside). It
-- looks odd but pays, so the "?" leads with that and the reason, and the card's one line says what the trip is for.
-- -> the marked step (this one, or the step the flight goes to), or nil
local function detourOf(i)
  local list = steps()
  local s = list[i]
  if s and s.detour then return s end
  if s and s.k == "fly" then
    for j = i + 1, math.min(#list, i + 4) do
      local t = list[j]
      if t and t.detour then return t end
      if t and t.k ~= "fly" and t.k ~= "hearth" then break end
    end
  end
end
-- "Badlands" reads "the Badlands" in a sentence
local THE = { ["Badlands"] = true, ["Hinterlands"] = true, ["Barrens"] = true, ["Western Plaguelands"] = true, ["Eastern Plaguelands"] = true }
local function inZone(z) local n = ns.Style.ShortZone(z or "") return (THE[n] and "the " or "") .. n end
-- -> why, fact for a marked trip
function Explain.Detour(d)
  local name, there, home = d.detourName or "this quest", inZone(d.detourZone), inZone(d.detourHome)
  local why, fact
  if d.detour == "giver" then
    why = string.format("Looks odd, but it's the quickest way: %s's giver is in %s, and %s here in %s.", name, there,
      d.detourWork and ("the " .. d.detourWork .. " are") or "its work is", home)
    fact = d.detourWith and string.format("One flight picks it up, then you do it alongside %s.", d.detourWith) or "One flight picks it up, then you're back here for it."
  elseif d.detour == "hand-in" then
    why = string.format("Looks odd, but it's the quickest way: %s is handed in in %s, and its work is done here in %s.", name, there, home)
    fact = "One flight hands it in, then you're back here."
  else
    why = string.format("Looks odd, but it's the quickest way: %s's work is in %s, close to your quests in %s.", name, there, home)
    fact = "One trip there for it, then back here."
  end
  if tonumber(d.detourXp) and tonumber(d.detourMin) then
    fact = fact .. string.format(" Worth ~%s XP for about %d min of travel.", Explain.Xp(d.detourXp), d.detourMin)
  end
  return why, fact
end

-- The card's line under a trip that leaves your zone: "For Pearl Diving and 6 more quests at your level". Facts, not
-- a why (the "?" has the why). Memoized per step and what it depends on, so a card refresh pays for it once.
local cardMemo = setmetatable({}, { __mode = "k" })
function Explain.CardLine(i)
  local s = steps()[i]
  if not (s and leaves(i)) then return nil end
  local z = ns.Engine.ZonesAhead and ns.Engine.ZonesAhead(i, 3)
  local a = z and z[1]
  local key = table.concat({ (UnitLevel and UnitLevel("player")) or 0, a and a.first or "-", a and a.quests or "-", tostring(ns.Engine.planned) }, "|")
  local m = cardMemo[s]
  if m and m.key == key then return m.v end
  local st = Explain.Stretch(i)
  local v
  local d = detourOf(i)
  if d then
    v = (d.detour == "giver" and "Pick up " or d.detour == "hand-in" and "Hand in " or "For ") .. (d.detourName or "a quest") .. ", then back"
  elseif st then
    local n = st.n or st.quests or 0
    if st.name and n >= 2 then v = string.format("For %s and %s at your level", st.name, plural(n - 1, "more quest"))
    elseif st.name and n == 1 then v = "One quest in " .. ns.Style.ShortZone(st.zone or "") .. ": " .. st.name
    elseif n > 0 then v = "For " .. plural(n, "quest") .. " at your level"
    elseif st.grind then v = "To level up there" end
  end
  cardMemo[s] = { key = key, v = v }
  return v
end

-- the solver's pick (a step out of the plan's order): its tag (Next.Tag) in words. -> why, fact
local PICK = {
  ["while you're here"] = "Looks odd, but it's the fastest way: doing it now saves a trip back later",
  ["saves a trip back"] = "Looks odd, but it's the fastest way: doing it now saves a trip back later",
  ["on the way"] = "Quickest from here: it's on the way",
  ["before you head out"] = "Pick it up before you leave: its work fits on the same trip",
  ["chain continues"] = "Quickest from here: the chain goes on right here",
  ["before the trip"] = "Quickest from here: your plan quests here right after a short trip, so these come first and the trip waits",
  ["close by first"] = "Quickest from here: these quests of your plan are right around you, so they come first",
  ["right here"] = "Worth it: right here, and still XP at your level",
  ["nearby"] = "Worth it: close by, and still XP at your level",
  ["in this zone"] = "Worth it: still XP at your level, done before you leave this zone",
}
local NO_NUMBER = { ["while you're here"] = true, ["saves a trip back"] = true, ["on the way"] = true }
local function pickWhy(i)
  local tag = ns.Next and ns.Next.Enabled and ns.Next.Enabled() and ns.Next.Tag and ns.Next.Tag(i)
  if not tag then return nil end
  local base = (tag:match("^(.-)%s*·") or tag):gsub("%s+$", "")
  local min = tonumber(tag:match("saves ~(%d+) min"))
  local xp = tag:match("%+(%S+) XP")
  local why = PICK[base] or PICK["on the way"]
  if min then why = why .. string.format(" (~%d min)", min)
  elseif xp then why = why .. " (+" .. xp .. " XP)"
  elseif NO_NUMBER[base] or not PICK[base] then why = why .. " (the fastest route the planner found)" end
  return why .. "."
end

-- Grounded lines (docs/research/route-feel.md, part 3): a step that looks odd says, in one short line, what it connects
-- to later and what it saves - facts the player can check (a zone, a level, minutes, XP), never a bare "it's faster".
-- The headline already names the step, so the line only grounds it. Explain.Ground(i) is the card's one line, in this
-- order: why the card left the plan's step (Next.Ground), the plan's own odd step (its g, tools/why-lines.js), the trip
-- out of the zone (Explain.CardLine). Explain.GroundLong(i) is the "?": the same in a sentence, numbers on both sides.
Explain.LINE_MAX = 68
local function short(t, n) t = tostring(t or ""); if #t <= n then return t end return (t:sub(1, n - 3):gsub("%s+%S*$", "")) .. "..." end
local function zoneOf(t) return t and (t.zone or (t.m and ns.Util and ns.Util.MapName and ns.Util.MapName(t.m))) or nil end
local function nameOf(t) return t and (t.name or t.dest or t.text or t.npc) or "your plan's step" end
-- the line, shortened to fit: its " · ..." tail goes first, then the words
local function fit(t)
  if not t or #t <= Explain.LINE_MAX then return t end
  local head = t:match("^(.-) · ") or t
  return #head <= Explain.LINE_MAX and head or short(head, Explain.LINE_MAX)
end
-- the step a plan step's g connects to (by its id, after it in the route)
local function gTarget(i, g)
  local list = steps()
  for j = i + 1, #list do local t = list[j]; if t.id == g.to and not t.inserted then return t, j end end
end
local function saves(secs) return (tonumber(secs) or 0) >= 60 and (" · saves ~" .. minutes(secs) .. " min") or "" end

-- the plan's own odd step: its g -> short, why, fact
local function planGround(i)
  local s = steps()[i]
  local g = s and s.g
  if type(g) ~= "table" or not g.k then return nil end
  local t = gTarget(i, g)
  local z = ns.Style.ShortZone(zoneOf(t) or "")
  local lv, sec, n = tonumber(g.lv), tonumber(g.s) or 0, tonumber(g.n) or 0
  local here = zoneOf(s) and ns.Style.ShortZone(zoneOf(s))
  if g.k == "carry" and t and lv then
    return "For later: its work is in " .. z .. " at " .. lv .. saves(sec),
      "Picked up now, on your way: its work is in " .. z .. " at level " .. lv .. ".",
      string.format("Now: a stop on your way (~%d s). Later: a trip back here for it, ~%d min.", math.floor((tonumber(s.dd) or 0) + 8), minutes(sec))
  elseif g.k == "later" and lv then
    return "You're back here at level " .. lv .. " for it" .. saves(sec),
      "Your plan comes back " .. (here and ("to " .. here) or "here") .. " at level " .. lv .. " for its work.",
      string.format("Now: a stop on your way. Picked up then: ~%d min more of walking to the giver.", minutes(sec))
  elseif g.k == "opens" and t and lv then
    local q2 = (t.name == s.name) and "its next part" or short(t.name, 30)
    local away = (t.m and s.m and t.m ~= s.m) and (" in " .. z) or ""
    return "Hand-in opens " .. q2 .. away .. " at level " .. lv,
      "Handed in now, it opens " .. (t.name or "a quest") .. ", which your plan takes at level " .. lv .. (away ~= "" and (" in " .. z) or "") .. ".",
      string.format("Now: ~%d s off your way. Later: the hand-in on its own, before %s can start.", math.floor(sec), t.name or "it")
  elseif g.k == "transit" and t then
    return "On the way to " .. z .. saves(sec),
      "Done here on your way to " .. z .. ".",
      string.format("Now: ~%d min off your way. A trip back for it later: ~%d min.", math.max(0, minutes(tonumber(s.dd) or 0)), minutes(sec + (tonumber(s.dd) or 0)))
  elseif g.k == "hearth" and sec >= 60 then
    return (n > 0 and (n .. (n == 1 and " hand-in" or " hand-ins") .. " there · ") or "") .. "~" .. minutes(sec) .. " min quicker than the trip",
      "Your hearthstone takes you " .. (z ~= "" and ("to " .. z) or "back") .. (n > 0 and (" for " .. n .. (n == 1 and " hand-in" or " hand-ins")) or "") .. ".",
      string.format("The hearth: ~%d min sooner there than the trip.", minutes(sec))
  elseif g.k == "bind" and lv then
    return "You hearth back here at level " .. lv .. (n > 0 and (" to hand in " .. n) or ""),
      "Your plan hearths back here at level " .. lv .. (n > 0 and (" to hand in " .. n .. " quests") or "") .. ".", nil
  elseif g.k == "fp" and lv then
    return "You fly back here at level " .. lv, "Your plan flies back here at level " .. lv .. ": this flight path makes that a flight.", nil
  end
end

-- the card left the plan's step (Next.Ground) -> short, why, fact
local function devGround(i)
  local g = ns.Next and ns.Next.Ground and ns.Next.Ground(i)
  if not g then return nil end
  local list = steps()
  local s, p = list[i], list[g.plan]
  local pn = short(nameOf(p), 26)
  local sv = saves(g.saves)
  local both = (g.pickSecs and g.planSecs) and string.format("This way: ~%d min for the stops ahead. In your plan's order: ~%d min.", minutes(g.pickSecs), minutes(g.planSecs)) or nil
  local k = g.k
  if g.behind and g.away then
    local z = ns.Style.ShortZone(zoneOf(s) or "another zone")
    local trip = g.trip and (", ~" .. minutes(g.trip) .. " min there") or ""
    return "In " .. z .. ": +" .. Explain.Xp(g.xp or 0) .. " XP" .. trip,
      "A quest you skipped earlier, still worth XP at your level, in " .. z .. ".",
      string.format("~%d min there and ~%d min of work, for ~%s XP. Then: %s.", minutes(g.trip or 0), minutes(g.work or 0), Explain.Xp(g.xp or 0), nameOf(p))
  elseif g.behind or k == "here" or k == "nearby" or k == "zone" then
    return "Skipped earlier: +" .. Explain.Xp(g.xp or 0) .. " XP for ~" .. minutes(g.work or 0) .. " min",
      "A quest you skipped earlier, still worth XP at your level" .. (k == "zone" and ": done before you leave the zone." or ", close by."),
      string.format("~%d min of work for ~%s XP. Then: %s.", minutes(g.work or 0), Explain.Xp(g.xp or 0), nameOf(p))
  elseif (k == "visit" or k == "early") and g.later and (g.ahead or 0) > 0 then
    return "Your plan comes back here for it at " .. g.later .. sv,
      "Your plan has this later, at level " .. g.later .. ": done now, that trip back goes.", both
  elseif k == "visit" or k == "early" then
    return "Done now: no trip back here for it later" .. sv, "While you're here: no trip back for it later.", both
  elseif k == "chain" then
    return "Opens the next part right here" .. sv, "The chain goes on right here: hand it in and take the next.", both
  elseif k == "pickupFirst" then
    return "Its work is on your way: no trip back for it", "Picked up before you head out: its work fits on the same trip.", both
  elseif k == "rejoin-trip" then
    return "The " .. short(g.dest or "next", 18) .. " trip comes back here: these first" .. sv,
      "Your plan's next step is a trip to " .. (g.dest or "another zone") .. ", then it quests here: these come first.", both
  elseif k == "rejoin-near" then
    return pn .. " is across the zone: this is close" .. sv, "Your plan's next step, " .. nameOf(p) .. ", is across the zone; these are right around you.", both
  elseif k == "opt" then
    return "In your log: handed in where it costs least" .. sv, "A quest you picked up on the way, handed in where it costs least.", both
  elseif k == "insert" then
    if s.k == "fp" then return "A flight path on your way, for later", "A flight path on your way: the plan flies from here later.", nil end
    if s.k == "turnin" then return "Finished: hand it in as you pass" .. sv, "A quest you finished: handed in as you pass.", both end
    return "Added on your way" .. sv, "A stop added to your route where it costs least.", both
  elseif k == "focus" then
    return "You're already working on it", "Your kills and loot count for it: it stays until you're done or move on.", nil
  elseif k == "extra" then
    return pn .. " is an extra stop: your plan goes on",
      nameOf(p) .. " is a stop added to your route for later (your quest log says where); your plan's own steps go on.", nil
  elseif k == "waits" then
    if g.why == "level" and g.lv then return pn .. " opens at level " .. g.lv .. ": this first", "Your plan's step, " .. nameOf(p) .. ", opens at level " .. g.lv .. ": the next one you can do comes first.", nil end
    return pn .. " isn't ready yet: this first", "Your plan's step, " .. nameOf(p) .. ", can't be done yet (an earlier quest, or room in your log): the next one you can do comes first.", nil
  elseif k == "way" then
    if (g.ahead or 0) > 0 and g.ahead <= 3 then return "Same stops, shorter order: " .. pn .. " right after" .. sv, "The same stops in a shorter order: " .. nameOf(p) .. " comes right after.", both end
    if (g.ahead or 0) > 0 then return "Your plan has it " .. g.ahead .. " stops on: on your way now" .. sv, "Your plan has this " .. g.ahead .. " stops on; from here it's on your way.", both end
    return "On your way to " .. pn .. sv, "On your way to " .. nameOf(p) .. ".", both
  end
end

-- the card's one grounded line for step i (plain text, Explain.LINE_MAX at most), or nil
function Explain.Ground(i)
  if not i or ns.Engine.view then return nil end
  local okD, d = pcall(devGround, i)
  if okD and d then return fit(d) end
  if ns.Engine.planned and i ~= ns.Engine.planned then return nil end -- (a pick with no reason: not the plan's line either)
  local okP, p = pcall(planGround, i)
  if okP and p then return fit(p) end
  return fit(Explain.CardLine(i))
end
-- the "?": -> why, fact (nil when step i has no grounded line)
function Explain.GroundLong(i)
  local okD, _, why, fact = pcall(devGround, i)
  if okD and why then return why, fact end
  if ns.Engine.planned and i ~= ns.Engine.planned then return nil end
  local okP, _, w2, f2 = pcall(planGround, i)
  if okP and w2 then return w2, f2 end
end

-- the newest decision log entry of a kind (ns.Why), at most `within` seconds old
local function recentWhy(kind, within, pattern)
  local w = BeelineDB and BeelineDB.why
  if type(w) ~= "table" then return nil end
  local now = time and time() or 0
  for k = #w, math.max(1, #w - 40), -1 do
    local e = w[k]
    if e and now - (e.t or 0) > within then return nil end
    if e and e.k == kind and (not pattern or (e.x or ""):find(pattern)) then return e end
  end
end

-- -> { { text, color }, ... }: the why first, the fact backing it, then (a trip of several legs) the way, leg by leg
Explain.LEGS = 6
function Explain.Lines(i)
  local out = {}
  local function add(t, c) if t and t ~= "" then out[#out + 1] = { t, c } end end
  local list = steps()
  local s = i and list[i]
  if not s then add("Nothing to do here: your route is done."); return out end
  local planned = ns.Engine.planned
  local trip, legs = tripOf(s)
  local here = Explain.HereZone()
  local why, fact
  -- 1. the solver took this stop out of your plan's order
  if planned and i ~= planned and list[planned] then
    -- (grounded: what it connects to and the numbers both ways - Explain.GroundLong; the tag's words when it has none)
    local gw, gf = Explain.GroundLong(i)
    why = gw or pickWhy(i)
    if why then fact = gf or ("Your plan's next step after it: " .. ns.Card.Plain((ns.Card.Describe(list[planned]))) .. ".") end
  end
  -- 1b. your plan's own step that looks odd (its g): what it connects to later
  if not why then why, fact = Explain.GroundLong(i) end
  -- 2. a trip out of the zone you picked that the planner kept because it pays: reassurance and the reason first
  local d = not why and leaves(i) and detourOf(i)
  if d then why, fact = Explain.Detour(d) end
  -- 3. a trip out of the zone you're in
  if not why and trip and leaves(i) then
    local st = Explain.Stretch(i)
    local secs
    local pm, px, py = ns.State.Position()
    if pm and px and ns.Travel and ns.Travel.Plan then
      local to = s.k == "fly" and s.to and { m = s.to, x = 0.5, y = 0.5, name = s.dest or s.text } or (s.m and s.x and { m = s.m, x = s.x, y = s.y, name = s.zone, stop = s.npc })
      local fs = st and st.first and list[st.first]
      if s.k == "fly" and fs and fs.m and fs.x then to = { m = fs.m, x = fs.x, y = fs.y, name = s.dest or s.text, stop = fs.npc } end
      if to then local ok, _, t = pcall(ns.Travel.Plan, { m = pm, x = px, y = py }, to); if ok then secs = tonumber(t) end end
    end
    local zone = (st and st.zone) or (s.k == "fly" and (s.dest or s.text)) or s.zone or "the next zone"
    local n = st and (st.n or st.quests) or 0
    local back = st and here and st.after == here
    local round = secs and st and st.secs and (2 * secs + st.secs) or nil
    if back and round and round <= 15 * 60 and n > 0 then
      local what = (st.hand == n) and plural(n, "hand-in") or plural(n, "quest")
      why = string.format("Short hop worth it: %s in %s%s, back in about %d min.", what, ns.Style.ShortZone(zone), (st.xp or 0) > 0 and (" for ~" .. Explain.Xp(st.xp) .. " XP") or "", minutes(round))
    else
      why = (n > 0 and st.xp and st.xp > 0)
        and string.format("Your plan moves on to %s: %s there for ~%s XP. The fastest route the planner found.", ns.Style.ShortZone(zone), plural(n, "quest") .. " at your level", Explain.Xp(st.xp))
        or string.format("Your plan moves on to %s: the fastest route the planner found.", ns.Style.ShortZone(zone))
      local bits = {}
      if st and st.name then bits[#bits + 1] = "First up there: " .. st.name end
      if secs then bits[#bits + 1] = "about " .. minutes(secs) .. " min to get there" end
      if back then bits[#bits + 1] = "then back here" elseif st and st.after then bits[#bits + 1] = "then " .. ns.Style.ShortZone(st.after) end
      fact = #bits > 0 and (cap(table.concat(bits, ", ")) .. ".") or nil
    end
  end
  -- 3. a flight inside your zone that beats the walk (Travel.Shortcut)
  if not why and trip and trip.shortcut and legs[1] and legs[1].gain then
    why = "Quicker than walking: " .. legs[1].gain .. "."
  end
  -- 4. your plan's own next step
  if not why then
    local kept = recentWhy("next", 180, "^kept the plan's step")
    if ns.Next and ns.Next.rejoin and planned and i >= (ns.Next.rejoin.at or math.huge) then
      why = ns.Next.rejoin.trip and "Quickest from here: your plan quests here right after a short trip, so these come first and the trip waits."
        or "Quickest from here: these quests of your plan are right around you, so they come first."
    elseif kept and kept.x:find("another continent", 1, true) then
      why = "Next on your plan. The quickest other stop is on another continent, so this comes first."
    elseif kept then
      why = "Next on your plan: nothing close by is worth doing before it."
    else
      why = "Next on your plan: the fastest route the planner found."
    end
    local z = ns.Engine.ZonesAhead and ns.Engine.ZonesAhead(i, 2)
    local a, b = z and z[1], z and z[2]
    if a and a.zone == s.zone and a.quests > 0 then
      fact = plural(a.quests, "quest") .. " left in " .. ns.Style.ShortZone(a.zone) .. (b and (", then " .. ns.Style.ShortZone(b.zone)) or "") .. "."
    end
  end
  add(why, { 1, 1, 1 })
  -- a stop left out of this trip a moment ago (Engine/Inserts.lua's "merge" log): said, so it isn't a mystery
  local merge = recentWhy("merge", 600, "^left ")
  if merge and not fact then
    local what = merge.x:match("^left %S+ (.-) %(") or merge.x:match("^left (.-) for later")
    if what and what ~= "" then fact = "Left for later: " .. what .. " (too far off this trip)." end
  end
  add(fact, { 0.75, 0.8, 0.88 })
  -- the way, leg by leg (the card shows only the leg you're on)
  if trip and legs and #legs > 1 then
    add("The way:", { 0.55, 0.6, 0.68 })
    for n, l in ipairs(legs) do
      if n > Explain.LEGS then add(string.format("+%d more", #legs - Explain.LEGS), { 0.55, 0.6, 0.68 }); break end
      add(n .. ". " .. (l.text or ""), n == 1 and { 1, 0.82, 0.36 } or { 0.6, 0.65, 0.72 })
    end
  elseif trip and legs and legs[1] and legs[1].fp and (legs[1].text or "") ~= "" then
    add(legs[1].text, { 0.6, 0.65, 0.72 })
  end
  return out
end

-- the "?" clicked: the lines in a tooltip on the button (until the mouse leaves it)
function Explain.Show(owner, i)
  if not (owner and GameTooltip) then return end
  local ok, lines = pcall(Explain.Lines, i)
  if not ok then lines = { { "The fastest route the planner found." } } end
  GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMLEFT")
  GameTooltip:SetText("Why this step?", 1, 0.82, 0.36)
  for _, l in ipairs(lines) do local c = l[2] or { 1, 1, 1 }; GameTooltip:AddLine(l[1], c[1], c[2], c[3], true) end
  GameTooltip:Show()
end
