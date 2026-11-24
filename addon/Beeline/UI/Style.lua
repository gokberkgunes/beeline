-- Shared look: the active skin's tokens and builders, the scale, and helpers every skin shares.
-- A skin (UI/Skins/*.lua) holds colours (C), metrics (M) and builders (Panel, Button, Text, ...). Style.UseSkin copies
-- them onto Style once, at ADDON_LOADED, before any frame is built: callers keep calling Style.X, at no extra cost.
-- Style.C and Style.M are filled in place, so a file's `local C = Style.C` (taken at load) sees the active skin's.
local _, ns = ...
local Style = {}
ns.Style = Style

local MEDIA = "Interface\\AddOns\\Beeline\\Media\\"
Style.MEDIA = MEDIA
Style.WHITE = MEDIA .. "white"

Style.C = {} -- colours (UseSkin)
Style.M = {} -- metrics (UseSkin)
-- per step kind: icon + accent colour + verb (the same in every skin: they are what a step is; the map pins use them)
Style.KIND = {
  accept = { icon = "icon-accept", color = { 1.0, 0.82, 0.36 }, verb = "Accept" },
  turnin = { icon = "icon-turnin", color = { 0.45, 0.78, 1.0 }, verb = "Turn in" },
  obj = { icon = "icon-kill", color = { 1.0, 0.47, 0.42 }, verb = "" },
  loot = { icon = "icon-loot", color = { 0.82, 0.64, 1.0 }, verb = "" },
  ["goto"] = { icon = "icon-goto", color = { 0.9, 0.92, 0.96 }, verb = "Go to" },
  fly = { icon = "icon-fly", color = { 0.5, 0.9, 1.0 }, verb = "Fly to" },
  -- a boat crossing is a travel step too (k = "fly" with boat set), but it must never read "Fly to" or show wings
  boat = { icon = "icon-goto", color = { 0.45, 0.78, 1.0 }, verb = "Boat to" },
  -- a travel step's live trip (from the flight paths you know) can be a ride, or several kinds of leg
  ride = { icon = "icon-goto", color = { 0.5, 0.9, 1.0 }, verb = "Ride to" },
  travel = { icon = "icon-goto", color = { 0.5, 0.9, 1.0 }, verb = "Travel to" },
  fp = { icon = "icon-fly", color = { 0.5, 0.9, 1.0 }, verb = "Get the flight path" },
  hearth = { icon = "icon-hearth", color = { 1.0, 0.62, 0.3 }, verb = "Hearth to" },
  bind = { icon = "icon-hearth", color = { 1.0, 0.62, 0.3 }, verb = "Set your hearthstone" },
  train = { icon = "icon-train", color = { 0.58, 1.0, 0.62 }, verb = "Train" },
  grind = { icon = "icon-grind", color = { 1.0, 0.47, 0.42 }, verb = "Grind" },
  note = { icon = "icon-note", color = { 0.8, 0.84, 0.92 }, verb = "" },
  bonus = { icon = "icon-loot", color = { 0.98, 0.62, 0.95 }, verb = "Bonus:" },
}
for k, m in pairs(Style.KIND) do m.key = k end
function Style.Kind(step)
  local k = step.k
  if k == "obj" and step.loot then k = "loot" end
  if k == "fly" and step.boat then k = "boat" end
  return Style.KIND[k] or Style.KIND.note
end

-- no text of ours under MIN_FONT.
-- tiny = true skips the floor: the numbers inside the small map pins
Style.MIN_FONT = 10

-- ---------------------------------------------------------------- skins

-- Style.Skins[name] = skin. A skin other than "beeline" inherits what it leaves out from it (UI/Skins/Blizzard.lua).
Style.Skins = {}
Style.SKIN_DEFAULT = "beeline"
local function copyInto(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      local t = dst[k]
      if type(t) ~= "table" then t = {}; dst[k] = t end
      for i = 1, 4 do t[i] = v[i] end
    else dst[k] = v end
  end
end
-- the skin named (unknown or nil: the default) becomes the active one; returns its name
function Style.UseSkin(name)
  local bee = Style.Skins[Style.SKIN_DEFAULT]
  local s = Style.Skins[name] or bee
  if s.Prepare then s.Prepare() end
  copyInto(Style.C, bee.C); copyInto(Style.M, bee.M)
  if s ~= bee then copyInto(Style.C, s.C); copyInto(Style.M, s.M) end
  for k, v in pairs(bee) do if type(v) == "function" and k ~= "Prepare" then Style[k] = s[k] end end
  for k, m in pairs(Style.KIND) do m.mark = s.MARK and s.MARK[k] or nil end
  Style.skin, Style.skinName = s, s.name
  return s.name
end
function Style.SkinNames() local t = {}; for k in pairs(Style.Skins) do t[#t + 1] = k end; table.sort(t); return t end

-- ---------------------------------------------------------------- scale

-- One scale for everything of ours ("Beeline scale", ns.db.uiScale; nil = never chosen = 1). Our frames are
-- children of UIParent, so they follow the game's UI scale (and ElvUI's, which sets UIParent's); this multiplies on
-- top of it, for the card, the arrow, the route list and every window alike. The card and the arrow keep their own
-- sliders as a fine adjustment (their scale = this x theirs).
Style.SCALE_MIN, Style.SCALE_MAX = 0.6, 2.5
Style.SMALL_PX, Style.GOAL_PX = 1.2, 1.4 -- screen pixels per UI unit: under SMALL we offer to grow to GOAL
local scaled = {}
function Style.UIScale() return math.max(Style.SCALE_MIN, math.min(Style.SCALE_MAX, tonumber(ns.db and ns.db.uiScale) or 1)) end
-- screen pixels per UI unit for a frame (UIParent when none): 1.875 at 2560x1440 and 1.41 at 1920x1080 with the
-- default UI scale, 1.0 with a "pixel perfect" UI scale (768 / screen height) - text of size 10 is then 10 px tall
function Style.PxPerUnit(frame)
  local _, h = GetPhysicalScreenSize()
  if not h or h <= 0 then h = 768 end
  return (frame or UIParent):GetEffectiveScale() * h / 768
end
-- the scale that brings our text back to a readable size on this screen, or nil when it already is
function Style.SuggestScale()
  local px = Style.PxPerUnit()
  if px <= 0 or px >= Style.SMALL_PX then return nil end
  local s = math.floor(Style.GOAL_PX / px / 0.05 + 0.5) * 0.05
  return math.max(1.05, math.min(Style.SCALE_MAX, s))
end
local function applyScale(frame, o)
  local s = Style.UIScale() * (o.key and tonumber(ns.db[o.key]) or 1)
  -- a window never grows past the screen (a big scale on a small screen)
  if o.fit then
    local pw, ph, w, h = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0, frame:GetWidth() or 0, frame:GetHeight() or 0
    if h > 0 and ph > 0 then s = math.min(s, ph * 0.96 / h) end
    if w > 0 and pw > 0 then s = math.min(s, pw * 0.96 / w) end
  end
  s = math.max(0.3, s)
  if math.abs((frame:GetScale() or 1) - s) > 0.0005 then frame:SetScale(s) end
end
-- Style.Scaled(frame, key, fit): frame follows the Beeline scale. key = a setting that multiplies it (the
-- card's and the arrow's own sliders); fit = keep it inside the screen (windows; checked again each time it opens)
function Style.Scaled(frame, key, fit)
  local o = { key = key, fit = fit }
  scaled[frame] = o
  applyScale(frame, o)
  if fit then frame:HookScript("OnShow", function(self) applyScale(self, o) end) end
  return frame
end
function Style.ApplyScale() for frame, o in pairs(scaled) do applyScale(frame, o) end end
-- A dragged frame's place, kept as ns.db[key] = { "ABS", x, y }: its point ("TOPLEFT" or "CENTER") in UIParent units,
-- never in its own scaled ones (the game multiplies offsets by the frame's scale, so those move with the scale)
function Style.SavePos(frame, key, point)
  local x, y
  if point == "CENTER" then x, y = frame:GetCenter() else x, y = frame:GetLeft(), frame:GetTop() end
  if not (x and y) then return false end
  local s = frame:GetScale() or 1
  ns.db[key] = { "ABS", x * s, y * s }
  return true
end
-- sets the frame at its kept place for its current scale; false when none is kept
function Style.PlaceSaved(frame, key, point)
  local p = ns.db[key]
  if not (type(p) == "table" and p[1] == "ABS" and tonumber(p[2]) and tonumber(p[3])) then return false end
  local s = frame:GetScale() or 1
  frame:SetPoint(point, UIParent, "BOTTOMLEFT", p[2] / s, p[3] / s)
  return true
end
-- "/bee scale": what the screen and our scale come to; "/bee scale 1.3" sets it, "/bee scale auto" takes the suggestion
function Style.ScaleInfo()
  local pw, ph = GetPhysicalScreenSize()
  local card = BeelineCard
  local sug = Style.SuggestScale()
  return string.format("screen %sx%s px, %d units tall; game UI scale %.3f (%.2f px per unit); Beeline scale %.2f%s, card x%.2f: card %.2f px per unit, size-11 text about %d px tall%s",
    tostring(pw), tostring(ph), GetScreenHeight() or 0, UIParent:GetEffectiveScale(), Style.PxPerUnit(), Style.UIScale(), ns.db.uiScale and "" or " (never changed)",
    tonumber(ns.db.scale) or 1, Style.PxPerUnit(card), math.floor(11 * Style.PxPerUnit(card) + 0.5), sug and string.format("; suggested for this screen: %.2f", sug) or "")
end
function Style.SetUIScale(v)
  ns.db.uiScale = math.max(Style.SCALE_MIN, math.min(Style.SCALE_MAX, v))
  ns.Fire("FR_SETTINGS", "uiScale")
end
function Style.SlashScale(arg)
  arg = (arg or ""):gsub("^%s+", "")
  if arg == "auto" then Style.SetUIScale(Style.SuggestScale() or 1)
  elseif arg == "reset" then ns.db.uiScale = nil; ns.Fire("FR_SETTINGS", "uiScale")
  elseif tonumber(arg) then Style.SetUIScale(tonumber(arg))
  elseif arg ~= "" then ns.Print("/bee scale  (shows it)  -  /bee scale 1.3  -  /bee scale auto  -  /bee scale reset"); return end
  ns.Print(Style.ScaleInfo())
end
-- FR_SETTINGS(key): the setting that changed (nil: any or several). Each listener redoes only what that key touches;
-- the scale is applied here, once, before the card's and the arrow's listeners run
ns.On("FR_SETTINGS", function() Style.ApplyScale() end)
ns.On("UI_SCALE_CHANGED", function() Style.ApplyScale() end)
ns.On("DISPLAY_SIZE_CHANGED", function() Style.ApplyScale() end)

-- ---------------------------------------------------------------- behaviour every skin shares

-- A scrollbar you can use: a strip over the (thin, drawn) track that takes the mouse - drag the thumb, or click
-- anywhere on the strip to jump there. The track and thumb stay plain textures the list draws; setFraction(0..1)
-- scrolls the list. Returns the strip.
Style.GRIP_W = 14
function Style.ScrollGrip(parent, track, thumb, setFraction)
  local grip = CreateFrame("Button", nil, parent)
  grip:SetWidth(Style.GRIP_W)
  grip:SetPoint("TOP", track, "TOP"); grip:SetPoint("BOTTOM", track, "BOTTOM")
  grip:SetFrameLevel(parent:GetFrameLevel() + 10)
  grip:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
  local function cursorY() local _, y = GetCursorPosition(); return y / grip:GetEffectiveScale() end
  -- the thumb's top, as a fraction of the room it moves in, for a cursor at y (grab: where on the thumb you took it)
  local function fractionAt(y, grab)
    local top, th, h = track:GetTop(), track:GetHeight(), thumb:GetHeight()
    if not (top and th) or th - h <= 0 then return 0 end
    return math.max(0, math.min(1, (top - y - grab) / (th - h)))
  end
  grip.FractionAt, grip.SetFraction = fractionAt, setFraction
  grip:SetScript("OnMouseDown", function(self)
    local y, tTop = cursorY(), thumb:GetTop()
    local onThumb = thumb:IsShown() and tTop and y <= tTop and y >= tTop - thumb:GetHeight()
    self.grab = onThumb and (tTop - y) or thumb:GetHeight() / 2 -- off the thumb: centre it where you clicked
    setFraction(fractionAt(y, self.grab))
    self.dragging = true
  end)
  grip:SetScript("OnMouseUp", function(self) self.dragging = false end)
  grip:SetScript("OnUpdate", function(self) if self.dragging then if not IsMouseButtonDown("LeftButton") then self.dragging = false else setFraction(fractionAt(cursorY(), self.grab)) end end end)
  grip:SetScript("OnEnter", function() thumb:SetAlpha(1) end)
  grip:SetScript("OnLeave", function() thumb:SetAlpha(0.8) end)
  return grip
end

-- the slim bars under the card (Style.CardBar, a skin's): they stack under the card in order (1 first), the shown ones only
Style.cardBars = {}
function Style.StackCardBars()
  local above = BeelineCard
  for k = 1, 3 do
    local b = Style.cardBars[k]
    if b and b:IsShown() then
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -4); b:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, -4)
      above = b
    end
  end
end

-- quest difficulty colour (like the quest log)
function Style.QuestColor(level)
  if not level then return Style.C.text end
  local d = level - UnitLevel("player")
  if d >= 5 then return { 1, 0.25, 0.2 } elseif d >= 3 then return { 1, 0.5, 0.25 } elseif d >= -2 then return { 1, 0.85, 0.2 }
  elseif d >= -(GetQuestGreenRange and GetQuestGreenRange() or 8) then return { 0.3, 0.85, 0.35 } else return { 0.6, 0.6, 0.6 } end
end
function Style.Hex(c) return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end

function Style.Distance(yards)
  if not yards then return "" end
  if yards < 1000 then return string.format("%d yd", yards) end
  return string.format("%.1fk yd", yards / 1000)
end
function Style.Duration(sec)
  if not sec then return "" end
  if sec < 60 then return string.format("%ds", sec) end
  return string.format("%dm %02ds", sec / 60, sec % 60)
end

-- short zone names for tight spots
local SHORT = { ["Redridge Mountains"] = "Redridge", ["Stonetalon Mountains"] = "Stonetalon", ["Hillsbrad Foothills"] = "Hillsbrad", ["Stranglethorn Vale"] = "Stranglethorn",
  ["Thousand Needles"] = "Thousand Needles", ["Arathi Highlands"] = "Arathi", ["Swamp of Sorrows"] = "Swamp of Sorrows", ["Alterac Mountains"] = "Alterac", ["Dustwallow Marsh"] = "Dustwallow",
  -- the map data's name for a capital the planner's steps call Stormwind: one zone, one name ("Stormwind > Hillsbrad >
  -- Stormwind City" in the route list)
  ["Stormwind City"] = "Stormwind" }
function Style.ShortZone(z) return SHORT[z] or z end
-- a steady colour per zone, so the same zone looks the same everywhere
local ZONE_COLORS = {
  { 0.45, 0.78, 1.0 }, { 0.58, 1.0, 0.62 }, { 1.0, 0.70, 0.40 }, { 0.82, 0.64, 1.0 }, { 1.0, 0.55, 0.62 },
  { 0.45, 0.92, 0.85 }, { 1.0, 0.86, 0.45 }, { 0.70, 0.80, 1.0 }, { 0.95, 0.62, 0.95 }, { 0.75, 0.92, 0.50 },
}
function Style.ZoneColor(z)
  local h = 0
  for i = 1, #(z or "") do h = (h * 31 + z:byte(i)) % 9973 end
  return ZONE_COLORS[h % #ZONE_COLORS + 1]
end
