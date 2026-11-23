-- Shared look: palette, fonts, panel/backdrop builder, small widgets.
local _, ns = ...
local Style = {}
ns.Style = Style

local MEDIA = "Interface\\AddOns\\Beeline\\Media\\"
Style.MEDIA = MEDIA
Style.WHITE = MEDIA .. "white"

Style.C = {
  bg = { 0.025, 0.028, 0.036, 0.94 },
  bg2 = { 0.035, 0.038, 0.05, 0.96 },
  edge = { 1, 1, 1, 0.07 },
  gold = { 1.0, 0.82, 0.36 },
  text = { 0.95, 0.95, 0.97 },
  -- secondary text. On the panel fill (bg) sub is about 10:1 and dim about 7:1 (small text needs at least 4.5:1)
  sub = { 0.72, 0.76, 0.84 },
  dim = { 0.56, 0.60, 0.68 },
  good = { 0.36, 0.86, 0.48 },
  warn = { 1.0, 0.55, 0.30 },
  bad = { 1.0, 0.36, 0.36 },
}
-- per step kind: icon + accent colour + verb
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
function Style.Kind(step)
  local k = step.k
  if k == "obj" and step.loot then k = "loot" end
  if k == "fly" and step.boat then k = "boat" end
  return Style.KIND[k] or Style.KIND.note
end

local fontPath = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local fonts = {}
-- no text of ours under MIN_FONT.
-- tiny = true skips the floor: the numbers inside the small map pins
Style.MIN_FONT = 10
function Style.Font(size, flags, tiny)
  if not tiny and size < Style.MIN_FONT then size = Style.MIN_FONT end
  local key = size .. (flags or "")
  if not fonts[key] then
    local f = CreateFont("BeelineFont" .. key:gsub("%W", ""))
    f:SetFont(fontPath, size, flags or "")
    f:SetShadowOffset(1, -1); f:SetShadowColor(0, 0, 0, 0.8)
    fonts[key] = f
  end
  return fonts[key]
end
function Style.Text(parent, size, color, flags, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  fs:SetFontObject(Style.Font(size, flags))
  local c = color or Style.C.text
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
  fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
  fs:SetWordWrap(true)
  return fs
end

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

-- 9-slice from a 64px rounded-rect texture: corners keep their curve at any size
function Style.Nine(frame, tex, layer, sub, corner, inset, r, g, b, a)
  local parts = {}
  local c, t = corner or 12, 0.25
  local spec = {
    { "TOPLEFT", 0, t, 0, t }, { "TOP", t, 1 - t, 0, t }, { "TOPRIGHT", 1 - t, 1, 0, t },
    { "LEFT", 0, t, t, 1 - t }, { "CENTER", t, 1 - t, t, 1 - t }, { "RIGHT", 1 - t, 1, t, 1 - t },
    { "BOTTOMLEFT", 0, t, 1 - t, 1 }, { "BOTTOM", t, 1 - t, 1 - t, 1 }, { "BOTTOMRIGHT", 1 - t, 1, 1 - t, 1 },
  }
  local i = inset or 0
  for k, sp in ipairs(spec) do
    local x = frame:CreateTexture(nil, layer, nil, sub)
    x:SetTexture(Style.MEDIA .. tex); x:SetTexCoord(sp[2], sp[3], sp[4], sp[5]); x:SetVertexColor(r, g, b, a)
    parts[k] = x
  end
  local TL, T, TR, L, C, R, BL, B, BR = unpack(parts)
  TL:SetSize(c, c); TL:SetPoint("TOPLEFT", -i, i)
  TR:SetSize(c, c); TR:SetPoint("TOPRIGHT", i, i)
  BL:SetSize(c, c); BL:SetPoint("BOTTOMLEFT", -i, -i)
  BR:SetSize(c, c); BR:SetPoint("BOTTOMRIGHT", i, -i)
  T:SetPoint("TOPLEFT", TL, "TOPRIGHT"); T:SetPoint("BOTTOMRIGHT", TR, "BOTTOMLEFT")
  B:SetPoint("TOPLEFT", BL, "TOPRIGHT"); B:SetPoint("BOTTOMRIGHT", BR, "BOTTOMLEFT")
  L:SetPoint("TOPLEFT", TL, "BOTTOMLEFT"); L:SetPoint("BOTTOMRIGHT", BL, "TOPRIGHT")
  R:SetPoint("TOPLEFT", TR, "BOTTOMLEFT"); R:SetPoint("BOTTOMRIGHT", BR, "TOPRIGHT")
  C:SetPoint("TOPLEFT", TL, "BOTTOMRIGHT"); C:SetPoint("BOTTOMRIGHT", BR, "TOPLEFT")
  return parts
end

-- rounded panel: soft shadow, fill, hairline edge, faint top sheen
function Style.Panel(frame, fill)
  local c = fill or Style.C.bg
  Style.Nine(frame, "shadow", "BACKGROUND", -8, 22, 12, 0, 0, 0, 0.6)
  frame.fill = Style.Nine(frame, "panel", "BACKGROUND", -7, 12, 0, c[1], c[2], c[3], c[4])
  Style.Nine(frame, "panel-edge", "BORDER", 0, 12, 0, 1, 1, 1, 0.09)
  -- header band: a slightly lighter strip behind the title row
  local band = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
  band:SetTexture(Style.WHITE); band:SetPoint("TOPLEFT", 4, -4); band:SetPoint("TOPRIGHT", -4, -4); band:SetHeight(26)
  band:SetVertexColor(1, 1, 1, 0.025)
end

-- square icon button (tinted glyph, hover glow, tooltip)
-- tip: one line, or { title, line, line... }: a white title with what the button does under it
-- color: the glyph's colour at rest (default: the secondary text colour) - a red X reads as "no" before any tooltip
function Style.IconButton(parent, glyph, size, onClick, tip, color)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetTexture(Style.MEDIA .. "disc"); b.bg:SetAllPoints(); b.bg:SetVertexColor(1, 1, 1, 0.06)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetTexture(Style.MEDIA .. glyph); b.icon:SetPoint("CENTER"); b.icon:SetSize(size * 0.55, size * 0.55)
  local rest = color or Style.C.sub
  b.icon:SetVertexColor(rest[1], rest[2], rest[3])
  b.tip = tip
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(self)
    self.bg:SetVertexColor(1, 0.82, 0.36, 0.22); self.icon:SetVertexColor(1, 0.9, 0.6)
    local t = self.tip
    if type(t) == "table" then
      GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(t[1], 1, 1, 1, 1, true)
      for k = 2, #t do GameTooltip:AddLine(t[k], 0.75, 0.8, 0.88, true) end
      GameTooltip:Show()
    elseif t then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(t, 1, 1, 1, 1, true); GameTooltip:Show() end
    if parent.OnChildEnter then parent:OnChildEnter() end
  end)
  b:SetScript("OnLeave", function(self) self.bg:SetVertexColor(1, 1, 1, 0.06); self.icon:SetVertexColor(rest[1], rest[2], rest[3]); GameTooltip:Hide() end)
  return b
end

-- small flat button with hover highlight; rest: the label's colour off hover (default sub), size: its font size
function Style.Button(parent, label, w, h, onClick, tip, rest, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetTexture(Style.WHITE); bg:SetAllPoints(); bg:SetVertexColor(1, 1, 1, 0.05)
  local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetTexture(Style.WHITE); hl:SetAllPoints(); hl:SetVertexColor(1, 0.82, 0.36, 0.14)
  b.label = Style.Text(b, 11, Style.C.sub); b.label:SetPoint("CENTER"); b.label:SetJustifyH("CENTER"); b.label:SetText(label)
  if size then b.label:SetFontObject(Style.Font(size)) end
  b.rest = rest or Style.C.sub
  if rest then b.label:SetTextColor(rest[1], rest[2], rest[3]) end
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 0.86, 0.5); if tip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(tip, 1, 1, 1, 1, true); GameTooltip:Show() end end)
  b:SetScript("OnLeave", function(self) local c = self.rest; self.label:SetTextColor(c[1], c[2], c[3]); GameTooltip:Hide() end)
  return b
end

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

-- the slim bars under the card (what's new, a hint, a scale offer): a line of text and "x"; Style.CardBarButton adds
-- a button left of the "x". They stack under the card in order (1 first), the shown ones only: Style.StackCardBars
local cardBars = {}
function Style.CardBar(name, order, color, onX, xTip)
  local card = BeelineCard
  if not card then return nil end
  local b = CreateFrame("Frame", name, card)
  b:SetHeight(22)
  Style.Panel(b, Style.C.bg2)
  b.text = Style.Text(b, 11, color); b.text:SetPoint("LEFT", 10, 0); b.text:SetWordWrap(false)
  b.x = Style.Button(b, "x", 18, 18, onX, xTip); b.x:SetPoint("RIGHT", -3, 0)
  b.text:SetPoint("RIGHT", b.x, "LEFT", -6, 0)
  cardBars[order] = b
  return b
end
function Style.CardBarButton(b, label, w, onClick, tip)
  local go = Style.Button(b, label, w, 18, onClick, tip)
  go:SetPoint("RIGHT", b.x, "LEFT", -4, 0)
  b.text:SetPoint("RIGHT", go, "LEFT", -6, 0)
  return go
end
function Style.StackCardBars()
  local above = BeelineCard
  for k = 1, 3 do
    local b = cardBars[k]
    if b and b:IsShown() then
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -4); b:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, -4)
      above = b
    end
  end
end

-- a window's tab rail: a tab button (t = { label, icon, color, tip? }), w wide, at y under the rail's top; b.on marks
-- the open one (then Style.PaintTab(b))
function Style.PaintTab(b)
  local t = b.t
  local lit = b.on or b.hover
  local col = lit and t.color or Style.C.sub
  b.icon:SetVertexColor(col[1], col[2], col[3]); b.icon:SetAlpha(lit and 1 or 0.65)
  b.label:SetTextColor(col[1], col[2], col[3])
  b.wash:SetVertexColor(t.color[1], t.color[2], t.color[3], 0.12); b.wash:SetShown(b.on)
  b.bar:SetVertexColor(t.color[1], t.color[2], t.color[3]); b.bar:SetShown(b.on)
end
function Style.RailTab(rail, t, y, onClick, w)
  local b = CreateFrame("Button", nil, rail)
  b:SetSize(w, 48); b:SetPoint("TOP", rail, "TOP", 0, -y); b.t = t
  b.wash = b:CreateTexture(nil, "BACKGROUND"); b.wash:SetTexture(Style.WHITE); b.wash:SetAllPoints()
  b.bar = b:CreateTexture(nil, "ARTWORK"); b.bar:SetTexture(Style.WHITE); b.bar:SetWidth(3); b.bar:SetPoint("TOPLEFT", 0, -6); b.bar:SetPoint("BOTTOMLEFT", 0, 6)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetTexture(MEDIA .. t.icon); b.icon:SetSize(18, 18); b.icon:SetPoint("TOP", 0, -8)
  b.label = Style.Text(b, 10, Style.C.sub); b.label:SetPoint("TOP", b.icon, "BOTTOM", 0, -4); b.label:SetJustifyH("CENTER"); b.label:SetText(t.label)
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(self)
    self.hover = true; Style.PaintTab(self)
    if t.tip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(t.tip, 1, 1, 1, 1, true); GameTooltip:Show() end
  end)
  b:SetScript("OnLeave", function(self) self.hover = false; Style.PaintTab(self); if t.tip then GameTooltip:Hide() end end)
  return b
end

-- A window's scrolling list: f.scroll (place it), f.content (contentW wide; set its height), a track and thumb (place
-- f.track beside the list) with a grip to drag, the mouse wheel (step: px a notch). Returns f.setScroll(v), which
-- clamps v and redraws the thumb; call it after a layout.
function Style.ScrollList(f, contentW, step)
  local gold = Style.C.gold
  f.scroll = CreateFrame("ScrollFrame", nil, f); f.scroll:EnableMouseWheel(true)
  f.content = CreateFrame("Frame", nil, f.scroll); f.content:SetSize(contentW, 10); f.scroll:SetScrollChild(f.content)
  f.track = f:CreateTexture(nil, "ARTWORK"); f.track:SetTexture(Style.WHITE); f.track:SetVertexColor(1, 1, 1, 0.05); f.track:SetWidth(4)
  f.thumb = f:CreateTexture(nil, "OVERLAY"); f.thumb:SetTexture(Style.WHITE); f.thumb:SetVertexColor(gold[1], gold[2], gold[3], 0.6); f.thumb:SetWidth(4)
  local function setScroll(v)
    local max = math.max(0, f.content:GetHeight() - f.scroll:GetHeight())
    v = math.max(0, math.min(max, v)); f.scroll:SetVerticalScroll(v)
    local th = f.track:GetHeight() or 0
    f.thumb:SetShown(max > 0); f.track:SetShown(max > 0); f.grip:SetShown(max > 0)
    if max > 0 and th > 0 then
      local h = math.max(20, th * f.scroll:GetHeight() / f.content:GetHeight())
      f.thumb:SetHeight(h); f.thumb:ClearAllPoints(); f.thumb:SetPoint("TOP", f.track, "TOP", 0, -(th - h) * v / max)
    end
  end
  f.setScroll = setScroll
  f.scroll:SetScript("OnMouseWheel", function(self, d) setScroll(self:GetVerticalScroll() - d * (step or 60)) end)
  f.grip = Style.ScrollGrip(f, f.track, f.thumb, function(fr) setScroll(fr * math.max(0, f.content:GetHeight() - f.scroll:GetHeight())) end)
  return setScroll
end

-- progress bar with label
function Style.Bar(parent, h)
  local f = CreateFrame("Frame", nil, parent); f:SetHeight(18)
  f.label = Style.Text(f, 10, Style.C.text); f.label:SetPoint("TOPLEFT"); f.label:SetWordWrap(false); f.label:SetPoint("RIGHT", -48, 0)
  f.value = Style.Text(f, 10, Style.C.sub); f.value:SetPoint("TOPRIGHT"); f.value:SetJustifyH("RIGHT")
  local track = CreateFrame("Frame", nil, f); track:SetPoint("BOTTOMLEFT"); track:SetPoint("BOTTOMRIGHT"); track:SetHeight(4)
  local bg = track:CreateTexture(nil, "BACKGROUND"); bg:SetTexture(Style.WHITE); bg:SetAllPoints(); bg:SetVertexColor(1, 1, 1, 0.07)
  local fill = track:CreateTexture(nil, "ARTWORK"); fill:SetTexture(Style.WHITE); fill:SetPoint("TOPLEFT"); fill:SetPoint("BOTTOMLEFT")
  fill:SetWidth(0.001); fill:Hide() -- empty until there is progress (a texture with no width would draw a default sliver)
  f.fill, f.track = fill, track
  function f:Set(p, color, label, value)
    p = math.max(0, math.min(1, p or 0))
    self.target = p
    if p <= 0 and (self.cur or 0) <= 0.004 then self.fill:Hide() end
    local done = p >= 1
    local c = done and Style.C.good or color
    self.fill:SetVertexColor(c[1], c[2], c[3], 0.95)
    self.label:SetText(label or ""); self.value:SetText(done and "|cff5cdc7adone|r" or (value or ""))
    self.label:SetTextColor(done and 0.6 or 0.92, done and 0.65 or 0.93, done and 0.7 or 0.96)
    self:SetScript("OnUpdate", self.step) -- (it runs only while the fill moves toward its target)
  end
  function f.step(self, el)
    local w = self.track:GetWidth(); if w <= 0 then return end
    self.cur = self.cur or 0
    local t = self.target or 0
    if math.abs(t - self.cur) < 0.001 then self:SetScript("OnUpdate", nil); return end
    self.cur = self.cur + (t - self.cur) * math.min(1, el * 8)
    self.fill:SetWidth(math.max(0.001, w * self.cur))
    self.fill:SetShown(self.cur > 0.004)
  end
  return f
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
-- small rounded label ("FASTEST", "CURRENT")
function Style.Pill(parent, text, color)
  local p = CreateFrame("Frame", nil, parent)
  p.bg = Style.Nine(p, "panel", "BACKGROUND", 0, 6, 0, color[1], color[2], color[3], 0.18)
  p.text = Style.Text(p, 9, color, "OUTLINE"); p.text:SetPoint("CENTER", 0, 0); p.text:SetJustifyH("CENTER"); p.text:SetWordWrap(false)
  function p:Set(t, c)
    c = c or color
    self.text:SetText(t); self.text:SetTextColor(c[1], c[2], c[3])
    for _, part in ipairs(self.bg or {}) do part:SetVertexColor(c[1], c[2], c[3], 0.18) end
    self:SetSize(self.text:GetStringWidth() + 12, 15)
  end
  p:Set(text, color)
  return p
end
-- zone chips flowing left to right with ">" between, wrapping at width; returns the height used
-- max (optional): only the first max zones, then "+N more zones" - the next few give the sense of a path; the ones
-- beyond are hours away, and the plan is rebuilt long before you get there
function Style.Chips(holder, zones, width, max)
  holder.chips = holder.chips or {}
  for _, c in ipairs(holder.chips) do c:Hide(); c.sep:Hide() end
  if holder.more then holder.more:Hide() end
  local x, y, lineH, gap = 0, 0, 18, 4
  local more = (max and #zones > max) and (#zones - max) or 0
  for i, z in ipairs(zones) do
    if more > 0 and i > max then break end
    local c = holder.chips[i]
    if not c then
      c = CreateFrame("Frame", nil, holder)
      c.bg = Style.Nine(c, "panel", "BACKGROUND", 0, 6, 0, 1, 1, 1, 0.08)
      c.text = Style.Text(c, 10, Style.C.text); c.text:SetPoint("CENTER", 0, 0); c.text:SetWordWrap(false)
      c.sep = Style.Text(holder, 10, Style.C.dim); c.sep:SetText(">")
      holder.chips[i] = c
    end
    local col = Style.ZoneColor(z)
    c.text:SetText(Style.ShortZone(z)); c.text:SetTextColor(col[1], col[2], col[3])
    for _, part in ipairs(c.bg or {}) do part:SetVertexColor(col[1], col[2], col[3], 0.13) end
    local w = c.text:GetStringWidth() + 12
    c:SetSize(w, 16)
    local sepW = i > 1 and 12 or 0
    if x > 0 and x + sepW + w > width then x = 0; y = y + lineH + 2; sepW = 0 end
    if sepW > 0 then c.sep:ClearAllPoints(); c.sep:SetPoint("TOPLEFT", holder, "TOPLEFT", x + 2, -y - 2); c.sep:Show() end
    x = x + sepW
    c:ClearAllPoints(); c:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -y); c:Show()
    x = x + w + gap
  end
  if more > 0 then
    holder.more = holder.more or Style.Text(holder, 10, Style.C.dim)
    holder.more:SetText("> +" .. more .. " more zone" .. (more == 1 and "" or "s"))
    local w = holder.more:GetStringWidth() + 4
    if x > 0 and x + w > width then x = 0; y = y + lineH + 2 end
    holder.more:ClearAllPoints(); holder.more:SetPoint("TOPLEFT", holder, "TOPLEFT", x + 2, -y - 2); holder.more:Show()
  end
  return y + lineH
end
