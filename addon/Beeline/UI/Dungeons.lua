-- "Dungeons": a group's going - pick its dungeon and get a route that picks up every quest for it (and does the whole
-- chain that unlocks them), takes you there, then hands everything in. Every party dungeon with a quest for your race
-- and class is here (tools/dungeon-routes.js), the ones for your level first; what you've done drops out. Special
-- rewards (class quests, one-off items) after them. Your leveling path is kept as it was; the card shows "Back to plan"
-- while you're on one. Opened from the card (sword button), the route list or /bee dungeons.
local _, ns = ...
local Style = ns.Style
local C = Style.C
local Dungeons = {}
ns.Dungeons = Dungeons

local f
local W, PAD = 470, 14
local cards = {}

-- quest progress for a route, from the quest log; kept until a quest is picked up, handed in or dropped (a kill or a
-- loot redraws the window and changes none of it: asking the game about every listed dungeon's quests each time was
-- most of a redraw)
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

local function card(k)
  if cards[k] then return cards[k] end
  local c = CreateFrame("Frame", nil, f.content)
  c:SetWidth(W - 2 * PAD)
  c.bg = Style.Nine(c, "panel", "BACKGROUND", 0, 10, 0, 1, 1, 1, 0.035)
  c.edge = c:CreateTexture(nil, "ARTWORK"); c.edge:SetTexture(Style.WHITE); c.edge:SetWidth(3); c.edge:SetPoint("TOPLEFT", 1, -8); c.edge:SetPoint("BOTTOMLEFT", 1, 8)
  c.name = Style.Text(c, 13, C.text, "OUTLINE"); c.name:SetPoint("TOPLEFT", 14, -10); c.name:SetWordWrap(false)
  c.cur = Style.Pill(c, "FOLLOWING", C.gold)
  c.quick = Style.Pill(c, "QUICK", C.good)
  c.special = Style.Pill(c, "SPECIAL REWARD", C.gold)
  c.time = Style.Text(c, 12, C.gold); c.time:SetPoint("TOPRIGHT", -14, -11); c.time:SetJustifyH("RIGHT")
  c.lvl = Style.Text(c, 10, C.sub); c.lvl:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -5); c.lvl:SetWordWrap(true); c.lvl:SetWidth(W - 2 * PAD - 150) -- clear of the button
  c.quests = Style.Text(c, 10, C.dim); c.quests:SetPoint("TOPLEFT", c.lvl, "BOTTOMLEFT", 0, -4); c.quests:SetWidth(W - 2 * PAD - 160)
  c.go = Style.Button(c, "Route me", 110, 22, function(self) local r = self:GetParent().route; if r then ns.EnterDungeonRoute(r.id); Dungeons.Draw() end end)
  c.go:SetPoint("RIGHT", c, "RIGHT", -12, -6)
  cards[k] = c
  return c
end

local function build()
  f = CreateFrame("Frame", "BeelineDungeons", UIParent)
  f:SetSize(W, 200); f:SetPoint("CENTER", 0, 40)
  Style.Window(f, "BeelineDungeons")
  f.title = Style.Text(f, 15, C.gold, "OUTLINE"); f.title:SetPoint("TOPLEFT", PAD, -12); f.title:SetText("Dungeons & side trips")
  local close = Style.CloseButton(f)
  f.intro = Style.Text(f, 11, C.sub); f.intro:SetPoint("TOPLEFT", PAD, -34); f.intro:SetWidth(W - 2 * PAD)
  f.intro:SetText("A group's going? Pick its dungeon: the card gets you every quest for it first - and the quests that unlock them - then the run, then the hand-ins. Your plan waits: \"Back to plan\" on the card returns you to it.")
  f.back = Style.Button(f, "Back to plan", 130, 20, function() ns.LeaveDungeonRoute(); Dungeons.Draw() end)
  f.empty = Style.Text(f, 11, C.dim)
  f.heads = {}
  -- the dungeons for your level are listed; the rest behind this (each one listed is a card to draw and its quests to ask
  -- the game about: all 20-odd at once took the window from about 1 ms to 6 a redraw, and 760 ms the first time)
  f.all = false
  -- the list scrolls (mouse wheel) once it is taller than most of the screen
  f.scroll = CreateFrame("ScrollFrame", nil, f)
  f.content = CreateFrame("Frame", nil, f.scroll); f.content:SetSize(W, 10)
  f.scroll:SetScrollChild(f.content)
  f.scroll:EnableMouseWheel(true)
  f.bar = f:CreateTexture(nil, "OVERLAY"); f.bar:SetTexture(Style.WHITE); f.bar:SetWidth(3); f.bar:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 0.6)
  local function scrollTo(v)
    local max = math.max(0, f.content:GetHeight() - f.scroll:GetHeight())
    v = math.max(0, math.min(max, v)); f.scroll:SetVerticalScroll(v)
    local vh, ch = f.scroll:GetHeight(), f.content:GetHeight()
    f.bar:SetShown(max > 0)
    if max > 0 then
      local bh = math.max(24, vh * vh / ch)
      f.bar:ClearAllPoints(); f.bar:SetPoint("TOPRIGHT", f.scroll, "TOPRIGHT", -4, -((vh - bh) * v / max)); f.bar:SetHeight(bh)
    end
  end
  f.scrollTo = scrollTo
  f.scroll:SetScript("OnMouseWheel", function(_, delta) scrollTo(f.scroll:GetVerticalScroll() - delta * 80) end)
  f:Hide()
end

function Dungeons.Draw()
  if not f or not f:IsShown() then return end
  local list, finished, more, prog = Dungeons.List(nil, f.all)
  local y = 34 + f.intro:GetStringHeight() + 12
  local y0
  local onDungeon = BeelineData and BeelineData.dungeon
  f.back:ClearAllPoints(); f.back:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -y); f.back:SetShown(onDungeon and true or false)
  if onDungeon then y = y + 28 end
  for k, c in ipairs(cards) do if k > #list then c:Hide() end end
  f.empty:SetShown(#list == 0)
  if #list == 0 then f.empty:ClearAllPoints(); f.empty:SetPoint("TOPLEFT", PAD, -y); f.empty:SetText(finished > 0 and "You've done every dungeon's quests and side trip in this plan." or "No dungeons or side trips in this plan."); y = y + 24 end
  y0 = y
  local yc = 0
  local myLevel = UnitLevel("player") or 1
  for _, h in pairs(f.heads) do h:Hide() end
  local function head(key, text)
    local h = f.heads[key] or Style.Text(f.content, 12, C.gold, "OUTLINE"); f.heads[key] = h
    h:ClearAllPoints(); h:SetPoint("TOPLEFT", f.content, "TOPLEFT", PAD, -yc); h:SetText(text); h:Show()
    yc = yc + 20
  end
  local lastKind
  for k, r in ipairs(list) do
    local kind = r.special and "special" or "dungeon"
    if kind ~= lastKind then head(kind, kind == "dungeon" and "Dungeons" or "Special rewards"); lastKind = kind end
    local c = card(k)
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
    c:ClearAllPoints(); c:SetPoint("TOPLEFT", f.content, "TOPLEFT", PAD, -yc); c:Show()
    yc = yc + c:GetHeight() + 8
  end
  if finished > 0 and #list > 0 then head("finished", string.format("|cff8a93a6%d more with nothing left for you|r", finished)) end
  -- the other dungeons: a group going to one not at your level
  f.more = f.more or Style.Button(f.content, "", 200, 22, function() f.all = not f.all; Dungeons.Draw() end)
  f.more:SetShown(f.all or more > 0)
  if f.all or more > 0 then
    f.more.label:SetText(f.all and "Only the ones for my level" or string.format("All dungeons (%d more)", more))
    f.more:ClearAllPoints(); f.more:SetPoint("TOPLEFT", f.content, "TOPLEFT", PAD, -yc); yc = yc + 30
  end
  -- at most 85% of the screen tall; the rest scrolls
  local maxH = (UIParent:GetHeight() or 800) / f:GetScale() * 0.85
  local view = math.max(60, math.min(yc, maxH - y0 - 6))
  f.content:SetHeight(math.max(1, yc))
  f.scroll:ClearAllPoints(); f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y0); f.scroll:SetSize(W, view)
  f:SetHeight(y0 + view + 6)
  f.scrollTo(f.scroll:GetVerticalScroll())
end

-- what the window lists, in order: the dungeons, those for your level first (quests around your level, then the ones
-- above it, then the ones below), then the special rewards; a route with nothing left for you (every quest done) is
-- left out and counted. Without all: only the dungeons around your level (at most 6; the 3 nearest when none is).
-- Returns the list, how many were left out as done, how many dungeons more "all" would list, and each listed route's
-- progress ({ done, total, in your log }).
local SHOWN = 6
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
  for _, r in ipairs(spec) do dung[#dung + 1] = r end
  return dung, finished, more, prog
end

function Dungeons.Toggle()
  if f:IsShown() then f:Hide(); return end
  f.all = false -- (opened again: the ones for your level)
  f:Show(); Dungeons.Draw()
end

ns.On("FR_LOADED", build)
ns.On("FR_TOGGLE_DUNGEONS", function() Dungeons.Toggle() end)
ns.On("FR_ROUTE_CHANGED", function() Dungeons.Draw() end)
-- (open, it follows your log: once for a burst of log updates - a kill or a loot sends two or three - not for each)
local redrawDue = false
ns.On("QUEST_LOG_UPDATE", function()
  if redrawDue or not (f and f:IsShown()) then return end
  redrawDue = true
  C_Timer.After(0.2, function() redrawDue = false; Dungeons.Draw() end)
end)
