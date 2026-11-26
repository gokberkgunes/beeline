-- "Side trips": a group's going - pick its dungeon and get a route that picks up every quest for it (and does the whole
-- chain that unlocks them), takes you there, then hands everything in. Every party dungeon with a quest for your race
-- and class is here (tools/dungeon-routes.js), the ones for your level first; what you've done drops out. Special
-- rewards (class quests, one-off items) after them. Your leveling path is kept as it was; the card shows "Back to plan"
-- while you're on one. The Home base window's third tab (UI/Paths.lua): Dungeons.Draw draws into the frame it hands
-- over. Opened from the tab, the route list or /bee dungeons (FR_TOGGLE_DUNGEONS).
local _, ns = ...
local Style = ns.Style
local C = Style.C
local Dungeons = {}
ns.Dungeons = Dungeons

-- quest progress for a route, from the quest log; kept until a quest is picked up, handed in or dropped (a kill or a
-- loot redraws the window and changes none of it; asking the game each time is most of a redraw)
local progCache = {}
function Dungeons.Forget() progCache = {} end
for _, e in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED" }) do ns.On(e, function() progCache = {} end) end
local function progressOf(r)
  local c = progCache[r]
  if c then return c[1], c[2], c[3] end
  local total, done, inLog = 0, 0, 0
  for q in pairs(ns.QuestIds(r)) do
    if q > 0 then
      total = total + 1
      if ns.State.IsCompleted(q) then done = done + 1 elseif ns.State.OnQuest(q) then inLog = inLog + 1 end
    end
  end
  progCache[r] = { done, total, inLog }
  return done, total, inLog
end

local host, W -- the frame the Home base window hands over, and its width
local cards = {}

local function card(k)
  if cards[k] then return cards[k] end
  local c = CreateFrame("Frame", nil, host)
  c:SetWidth(W)
  c.bg = Style.RowBg(c, 10, 0.035)
  c.edge = Style.RowEdge(c, 3, 1, 8)
  c.name = Style.Text(c, 13, C.text, "OUTLINE"); c.name:SetPoint("TOPLEFT", 14, -10); c.name:SetWordWrap(false)
  c.cur = Style.Pill(c, "FOLLOWING", C.gold)
  c.quick = Style.Pill(c, "QUICK", C.good)
  c.special = Style.Pill(c, "SPECIAL REWARD", C.gold) -- (its text: the trip's group, Dungeons.GROUPS)
  c.time = Style.Text(c, 12, C.gold); c.time:SetPoint("TOPRIGHT", -14, -11); c.time:SetJustifyH("RIGHT")
  c.lvl = Style.Text(c, 10, C.sub); c.lvl:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -5); c.lvl:SetWordWrap(true); c.lvl:SetWidth(W - 150) -- clear of the button
  c.quests = Style.Text(c, 10, C.dim); c.quests:SetPoint("TOPLEFT", c.lvl, "BOTTOMLEFT", 0, -4); c.quests:SetWidth(W - 160)
  c.go = Style.Button(c, "Route me", 110, 22, function(self) local r = self:GetParent().route; if r then ns.EnterDungeonRoute(r.id); Dungeons.Redraw() end end)
  c.go:SetPoint("RIGHT", c, "RIGHT", -12, -6)
  cards[k] = c
  return c
end

-- the dungeons for your level are listed; the rest behind a button (each one listed is a card to draw and its quests to
-- ask the game about: all of them at once is several times dearer)
Dungeons.all = false
function Dungeons.Reset() Dungeons.all = false end
-- the window it is drawn in redraws (the list's height changes the window's scroll)
function Dungeons.Redraw() if ns.Paths and ns.Paths.Draw then ns.Paths.Draw() end end

-- the frame to draw in (w wide), handed over once when the Home base window is built
function Dungeons.Attach(into, w)
  host, W = into, w
  host.back = Style.Button(host, "Back to plan", 130, 20, function() ns.LeaveDungeonRoute(); Dungeons.Redraw() end)
  host.empty = Style.Text(host, 11, C.dim)
  host.heads = {}
end
-- draws the list into the frame from its top; returns its height
function Dungeons.Draw()
  local f = host
  if not f then return 0 end
  local list, finished, more, prog = Dungeons.List(nil, Dungeons.all)
  local yc = 0
  local onDungeon = BeelineData and BeelineData.dungeon
  f.back:ClearAllPoints(); f.back:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0); f.back:SetShown(onDungeon and true or false)
  if onDungeon then yc = yc + 28 end
  for k, c in ipairs(cards) do if k > #list then c:Hide() end end
  f.empty:SetShown(#list == 0)
  if #list == 0 then f.empty:ClearAllPoints(); f.empty:SetPoint("TOPLEFT", 0, -yc); f.empty:SetText(finished > 0 and "You've done every dungeon's quests and side trip in this plan." or "No dungeons or side trips in this plan."); yc = yc + 24 end
  local myLevel = UnitLevel("player") or 1
  for _, h in pairs(f.heads) do h:Hide() end
  local function head(key, text)
    local h = f.heads[key] or Style.Text(f, 12, C.gold, "OUTLINE"); f.heads[key] = h
    h:ClearAllPoints(); h:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -yc); h:SetText(text); h:Show()
    yc = yc + 20
  end
  local lastKind
  for k, r in ipairs(list) do
    local g = r.special and Dungeons.Group(r) or nil
    local kind = g and g.key or "dungeon"
    if kind ~= lastKind then head(kind, g and g.head or "Dungeons"); lastKind = kind end
    local c = card(k)
    if g then c.special:Set(g.pill) end
    c.route = r
    local isCur = (BeelineData == r)
    local zc = Style.ZoneColor(r.dungeonName or r.title)
    c.name:SetText(r.dungeonName or r.title); c.name:SetTextColor(zc[1], zc[2], zc[3])
    c.quick:ClearAllPoints(); c.quick:SetPoint("LEFT", c.name, "RIGHT", 8, 0); c.quick:SetShown(r.variant == "quick")
    c.special:ClearAllPoints(); c.special:SetPoint("LEFT", c.name, "RIGHT", 8, 0); c.special:SetShown(r.special and true or false)
    local tag = (r.variant == "quick" and c.quick) or (r.special and c.special) or nil
    c.cur:ClearAllPoints(); c.cur:SetPoint("LEFT", tag or c.name, "RIGHT", tag and 4 or 8, 0); c.cur:SetShown(isCur)
    local pr = prog[r] or { 0, 0, 0 }
    local done, total, inLog = pr[1], pr[2], pr[3]
    local mins = r.meta and r.meta.hours and math.floor(tonumber(r.meta.hours) * 60 + 0.5)
    -- (planned with nothing done: with some done it's quicker, so "up to")
    c.time:SetText(mins and ((done > 0 and "up to " or "~") .. mins .. " min") or "")
    local need = tonumber(r.needsLevel) or 0
    local lvlText = string.format("Quests around level %s", r.questLevel or "?")
    if need > myLevel then lvlText = lvlText .. "  ·  |cffff8c4dsome need level " .. need .. "|r" end
    c.lvl:SetText(lvlText .. string.format("  ·  %d of %d quest%s left", total - done, total, total == 1 and "" or "s") .. (inLog > 0 and string.format(", %d in your log", inLog) or "") .. ((tonumber(r.xp) or 0) > 0 and string.format("  ·  |cffffd25a%.1fk XP|r", r.xp / 1000) or ""))
    if r.special then
      c.lvl:SetText(string.format("Can start at level %s  ·  %d quest%s", r.needsLevel or "?", total, total == 1 and "" or "s") .. (done > 0 and string.format(" (%d done)", done) or "") .. (inLog > 0 and string.format(", %d in your log", inLog) or ""))
      c.quests:SetText((r.why or "") .. "\n|cff8a93a6" .. ((r.meta and r.meta.legs) or "") .. "|r")
    else
    c.quests:SetText("For the dungeon: " .. (r.quests or "") .. ((r.chainCount or 0) > 0 and string.format("  |cff8a93a6+ %d chain quest%s that unlock them|r", r.chainCount, r.chainCount == 1 and "" or "s") or "")
      .. (r.cut and ("\n|cffffb36bSkips: " .. r.cut .. "|r") or ""))
    end
    c.go.label:SetText(isCur and "Following" or "Route me"); c.go:SetEnabled(not isCur)
    local col = isCur and C.gold or zc
    c.edge:SetVertexColor(col[1], col[2], col[3], isCur and 0.95 or 0.5)
    c.quests:ClearAllPoints(); c.quests:SetPoint("TOPLEFT", c.lvl, "BOTTOMLEFT", 0, -4)
    local h = 10 + 16 + 5 + c.lvl:GetStringHeight() + 4 + c.quests:GetStringHeight() + 12
    c:SetHeight(math.max(64, h))
    c:ClearAllPoints(); c:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -yc); c:Show()
    yc = yc + c:GetHeight() + 8
  end
  if finished > 0 and #list > 0 then head("finished", string.format("|cff8a93a6%d more with nothing left for you|r", finished)) end
  -- the other dungeons: a group going to one not at your level
  f.more = f.more or Style.Button(f, "", 200, 22, function() Dungeons.all = not Dungeons.all; Dungeons.Redraw() end)
  f.more:SetShown(Dungeons.all or more > 0)
  if Dungeons.all or more > 0 then
    f.more.label:SetText(Dungeons.all and "Only the ones for my level" or string.format("All dungeons (%d more)", more))
    f.more:ClearAllPoints(); f.more:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -yc); yc = yc + 30
  end
  return yc
end

-- what the window lists, in order: the dungeons, those for your level first (quests around your level, then the ones
-- above it, then the ones below), then the special rewards; a route with nothing left for you (every quest done) is
-- left out and counted. Without all: only the dungeons around your level (at most 6; the 3 nearest when none is).
-- Returns the list, how many were left out as done, how many dungeons more "all" would list, and each listed route's
-- progress ({ done, total, in your log }).
local SHOWN = 6
-- the side trips that aren't dungeons, by what they get you (the plan's group = ..., tools/reviewed-<faction>.json), in
-- the window's order: a heading and a tag each
Dungeons.GROUPS = {
  { key = "class", head = "Class quests", pill = "CLASS QUEST" },
  { key = "attune", head = "Attunements", pill = "ATTUNEMENT" },
  { key = "key", head = "Dungeon keys", pill = "DUNGEON KEY" },
  { key = "reward", head = "Special rewards", pill = "SPECIAL REWARD" },
}
local groupBy = {}; for i, g in ipairs(Dungeons.GROUPS) do g.order = i; groupBy[g.key] = g end
-- (a plan from before trips had a group: special rewards, as they all were)
function Dungeons.Group(r) return groupBy[r.group] or groupBy.reward end
function Dungeons.List(level, all)
  level = level or (UnitLevel and UnitLevel("player")) or 1
  -- 0: around your level (from 4 below to 4 above), 1: above it, 2: below it (gray to you: little XP)
  local function band(r) local q = tonumber(r.questLevel) or 0; return (q > level + 4 and 1) or (q < level - 4 and 2) or 0 end
  local function dist(r) return math.abs((tonumber(r.questLevel) or 0) - level) end
  local dung, spec, finished, prog = {}, {}, 0, {}
  local function keep(r, into)
    local done, total, inLog = progressOf(r)
    if total > 0 and done >= total then finished = finished + 1; return end
    prog[r] = { done, total, inLog }; into[#into + 1] = r
  end
  local cand = {}
  for _, r in ipairs(ns.DungeonRoutes()) do if r.special then keep(r, spec) else cand[#cand + 1] = r end end
  local more = 0
  if all then for _, r in ipairs(cand) do keep(r, dung) end
  else
    -- the nearest first (no game calls for the ones left out)
    table.sort(cand, function(a, b) local da, db = dist(a), dist(b); if da ~= db then return da < db end return (a.dungeonName or "") < (b.dungeonName or "") end)
    local inBand = 0; for _, r in ipairs(cand) do if band(r) == 0 then inBand = inBand + 1 end end
    local take = inBand > 0 and math.min(SHOWN, inBand) or math.min(3, #cand)
    for i, r in ipairs(cand) do if i <= take then keep(r, dung) else more = more + 1 end end
  end
  table.sort(dung, function(a, b)
    local ba, bb = band(a), band(b)
    if ba ~= bb then return ba < bb end
    local qa, qb = tonumber(a.questLevel) or 0, tonumber(b.questLevel) or 0
    if qa ~= qb then if ba == 2 then return qa > qb end return qa < qb end
    return (a.dungeonName or a.title or "") < (b.dungeonName or b.title or "")
  end)
  -- (by group, each in the plan's own order)
  local at = {}; for i, r in ipairs(spec) do at[r] = i end
  table.sort(spec, function(a, b) local ga, gb = Dungeons.Group(a).order, Dungeons.Group(b).order; if ga ~= gb then return ga < gb end return at[a] < at[b] end)
  for _, r in ipairs(spec) do dung[#dung + 1] = r end
  return dung, finished, more, prog
end

-- the Home base window on this tab, or closed when it is on it already
function Dungeons.Toggle()
  local P = ns.Paths
  if not (P and P.Show) then return end
  if P.IsShown("trips") then P.Hide(); return end
  Dungeons.Reset() -- (opened again: the ones for your level)
  P.Show("trips")
end

ns.On("FR_TOGGLE_DUNGEONS", function() Dungeons.Toggle() end)
-- (open, it follows your log: once for a burst of log updates - a kill or a loot sends two or three - not for each)
local redrawDue = false
ns.On("QUEST_LOG_UPDATE", function()
  if redrawDue or not (ns.Paths and ns.Paths.IsShown and ns.Paths.IsShown("trips")) then return end
  redrawDue = true
  C_Timer.After(0.2, function() redrawDue = false; Dungeons.Redraw() end)
end)
