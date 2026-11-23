-- Hints: a slim bar under the card for something only you can fix, shown until it's fixed or you dismiss it.
-- Flight paths: Forever's client won't tell addons which ones you know (its world map marks every flight point as
-- discovered - State.ScanTaxi), only a flight master's map does. A character of level 10 or more that the addon knows
-- at most one flight path for gets "open any flight master's map once"; it goes by itself once you have.
local _, ns = ...
local Hints = {}
ns.Hints = Hints
local Style = ns.Style
local C = Style.C

Hints.FP_LEVEL = 10

function Hints.TaxiDue()
  if ns.db.hintTaxiOff then return false end
  if (UnitLevel("player") or 1) < Hints.FP_LEVEL then return false end
  local n = 0
  for _ in pairs((ns.State and ns.State.knownTaxi) or {}) do n = n + 1 end
  return n <= 1
end

-- Small text: the game's UI scale is the player's choice and we follow it, but on a tall screen with a small UI
-- scale (ElvUI's pixel-perfect 768 / screen height: one pixel per unit) our size-10 and 11 text is 10-11 px tall.
-- Under Style.SMALL_PX pixels per unit, and only while the Beeline scale was never chosen, a bar offers the
-- scale that brings it back to what a 1080p screen shows. One click, or dismissed for good; never by itself.
function Hints.ScaleDue()
  if ns.db.hintScaleOff or ns.db.uiScale then return nil end
  local card = BeelineCard
  if card and Style.PxPerUnit(card) >= Style.SMALL_PX then return nil end -- (the card's own scale already makes up for it)
  return Style.SuggestScale()
end
local sbar
local function buildScale()
  sbar = Style.CardBar("BeelineScaleBar", 3, C.warn, function() ns.db.hintScaleOff = true; sbar:Hide() end, "Leave it as it is (Beeline scale, in /bee options, changes it any time)")
  if not sbar then return nil end
  sbar.go = Style.CardBarButton(sbar, "Bigger", 96, function()
    local s = sbar.suggest or Style.SuggestScale(); if not s then sbar:Hide(); return end
    Style.SetUIScale(s); sbar:Hide()
    ns.Print(string.format("Beeline scale set to %.2f. Change it under /bee options, or /bee scale 1 to go back.", s))
  end, "Makes the card, the arrow, the route list and every Beeline window bigger. Nothing else in your UI changes.")
  return sbar
end
function Hints.CheckScale()
  local s = Hints.ScaleDue()
  if not s then if sbar then sbar:Hide() end; return false end
  if not (sbar or buildScale()) then return false end
  sbar.suggest = s
  sbar.text:SetText("Small text on this screen?"); sbar.go.label:SetText(string.format("Make it %d%%", math.floor(s * 100 + 0.5)))
  sbar:Show()
  Style.StackCardBars()
  return true
end

local bar
local function build()
  bar = Style.CardBar("BeelineHintBar", 2, C.warn, function() ns.db.hintTaxiOff = true; bar:Hide() end, "Don't show this again")
  return bar
end

function Hints.Check()
  local due = Hints.TaxiDue()
  if not due then if bar then bar:Hide() end; return false end
  if not (bar or build()) then return false end
  bar.text:SetText("Open any flight master's map once so I know your flight paths.")
  bar:Show()
  Style.StackCardBars()
  return true
end

ns.On("FR_LOADED", function() C_Timer.After(6, ns.Guard("hints", Hints.Check)) end)
ns.On("FR_TAXI_OPENED", function() Hints.Check() end)
ns.On("FR_LOADED", function() C_Timer.After(7, ns.Guard("hints", Hints.CheckScale)) end)
ns.On("FR_SETTINGS", function() if sbar and sbar:IsShown() then Hints.CheckScale() end end)
ns.On("UI_SCALE_CHANGED", function() C_Timer.After(1, ns.Guard("hints", Hints.CheckScale)) end)
ns.On("PLAYER_LEVEL_UP", function() C_Timer.After(1, ns.Guard("hints", Hints.Check)) end)
