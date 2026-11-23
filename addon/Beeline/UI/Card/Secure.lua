-- The card's secure buttons (Target, the other mobs' Targets, use-item): built, filled and placed here, with the combat
-- queue - a secure button can't be changed or moved in combat.
local _, ns = ...
local Style = ns.Style
local C = Style.C
local Card = ns.Card
local f

local pendingSecure
local function setSecure(fn) if InCombatLockdown() then pendingSecure = fn; return end fn() end
-- a secure Target button (a macro /tm, set by Card.SetButtons): a 140x20 panel, a sword icon, the mob's name;
-- tip() adds its tooltip's lines
local function targetButton(name, strata, tip)
  local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate"); b:SetFrameStrata(strata)
  b:SetSize(140, 20); b:RegisterForClicks("AnyUp", "AnyDown"); b:SetAttribute("type", "macro")
  Style.Nine(b, "panel", "BACKGROUND", 0, 8, 0, 1, 0.47, 0.42, 0.2)
  local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetTexture(Style.WHITE); hl:SetPoint("TOPLEFT", 3, -3); hl:SetPoint("BOTTOMRIGHT", -3, 3); hl:SetVertexColor(1, 1, 1, 0.07)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetTexture(Style.MEDIA .. "icon-grind"); b.icon:SetSize(12, 12); b.icon:SetPoint("LEFT", 7, 0); b.icon:SetVertexColor(1, 0.55, 0.5)
  b.label = Style.Text(b, 10, C.text); b.label:SetPoint("LEFT", b.icon, "RIGHT", 5, 0); b.label:SetPoint("RIGHT", -6, 0); b.label:SetWordWrap(false); b.label:SetJustifyV("MIDDLE")
  b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Click to target " .. (self.who or ""), 1, 1, 1); tip(); GameTooltip:Show() end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

-- the buttons, made with the card (build, UI/Card.lua)
function Card.BuildSecure(frame, cur)
  f = frame
  -- target / use-item: secure buttons on UIParent, floating just above the card's top edge (Card.PlaceSecure, out of
  -- combat). Not in a slot on the card: a secure button can't move in combat, the card's rows can.
  -- on the card's own layer, a level above it (Card.PlaceSecure sets the level): what covers the card - the
  -- character sheet, the map - covers these too (not "HIGH": that floats over every window)
  cur.target = targetButton("BeelineTargetButton", f:GetFrameStrata(), function()
    GameTooltip:AddLine("Works when they're close enough to see, in combat too.", 0.75, 0.8, 0.88, true)
    GameTooltip:AddLine("Want a key for it? Options > Keybindings, under AddOns: Beeline Targeting.", 0.5, 0.55, 0.62, true)
    GameTooltip:AddLine("Ctrl+drag to move it (/bee target reset puts it back above the card).", 0.5, 0.55, 0.62, true)
  end)
  -- its name before 2.0, for a key or a /click macro still using it (unless something else took the name)
  if _G.ForeverRouteTargetButton == nil then _G.ForeverRouteTargetButton = cur.target end
  -- Ctrl+drag puts it wherever you like (ns.db.targetPos; /bee target reset brings it back); a Ctrl-click runs an empty
  -- macro, so grabbing it never targets
  cur.target:SetAttribute("ctrl-type1", "macro"); cur.target:SetAttribute("ctrl-macrotext1", "")
  cur.target:SetMovable(true); cur.target:RegisterForDrag("LeftButton"); cur.target:SetClampedToScreen(true)
  cur.target:SetScript("OnDragStart", function(self) if IsControlKeyDown() and not InCombatLockdown() then self.dragging = true; self:StartMoving() end end)
  cur.target:SetScript("OnDragStop", function(self)
    -- (only a drag we started: a drag in combat, never started, would call a protected function - ADDON_ACTION_BLOCKED)
    if not self.dragging or InCombatLockdown() then return end
    self.dragging = nil
    self:StopMovingOrSizing(); self:SetUserPlaced(false) -- (ours to keep, not the game's layout cache)
    local l, t, s = self:GetLeft(), self:GetTop(), self:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if l and t then ns.db.targetPos = { l * s, t * s } end
    Card.PlaceSecure()
  end)
  cur.item = CreateFrame("Button", "BeelineItemButton", UIParent, "SecureActionButtonTemplate"); cur.item:SetFrameStrata(f:GetFrameStrata())
  cur.item:SetSize(26, 26); cur.item:RegisterForClicks("AnyUp", "AnyDown"); cur.item:SetAttribute("type", "item")
  local ibg = cur.item:CreateTexture(nil, "BACKGROUND"); ibg:SetTexture(Style.WHITE); ibg:SetAllPoints(); ibg:SetVertexColor(0, 0, 0, 0.8)
  cur.item.icon = cur.item:CreateTexture(nil, "ARTWORK"); cur.item.icon:SetPoint("TOPLEFT", 1, -1); cur.item.icon:SetPoint("BOTTOMRIGHT", -1, 1); cur.item.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local ihl = cur.item:CreateTexture(nil, "HIGHLIGHT"); ihl:SetTexture(Style.WHITE); ihl:SetAllPoints(); ihl:SetVertexColor(1, 1, 1, 0.15)
  cur.item:SetScript("OnEnter", function(self) if self.itemID then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetItemByID(self.itemID); GameTooltip:Show() end end)
  cur.item:SetScript("OnLeave", GameTooltip_Hide)
  -- one more Target button for each other mob of the step (its quest item drops from several, or the objectives
  -- grouped with it name others): stacked under the first and moved with it
  cur.targets = {}
  local function extraTip() GameTooltip:AddLine("Also drops what this step needs. Ctrl+drag the top button to move them all.", 0.6, 0.65, 0.72, true) end
  for n = 1, Card.EXTRA_TARGETS do
    local b = targetButton("BeelineTargetButton" .. (n + 1), f:GetFrameStrata(), extraTip)
    b:Hide()
    cur.targets[n] = b
  end
  cur.target:Hide(); cur.item:Hide()
end

-- The Target button's macro (also its key, Options > Keybindings > AddOns): target the NPC by name, then put a star on
-- it with the game's own /tm - marking from addon code (/run ... SetRaidTarget) is a protected action on Forever
-- (ADDON_ACTION_FORBIDDEN, no star). "/tm 0" then "/tm 1": /tm 1 alone toggles a star that's already there off, and
-- the button fires on key down and up. Only on a target ([exists]): /tm with no target puts "You can't do that right
-- now" on screen; /tm takes macro conditions, and one that fails does nothing.
Card.MARK = 1 -- the star
function Card.TargetMacro(who)
  local m = "/cleartarget\n/target " .. who .. "\n/targetexact " .. who
  if ns.db and ns.db.markTarget ~= false then m = m .. "\n/tm [exists] 0\n/tm [exists] " .. Card.MARK end
  return m
end

-- the other mobs of step s worth a Target button of their own: the ones its text names ("Collect 10 Turtle Meat
-- (Snapjaw, Cranky Benj)") and the targets of the objectives done at the same spot, without the first (who)
Card.EXTRA_TARGETS = 3
function Card.OtherTargets(s, who)
  local out, seen = {}, { [who or ""] = true }
  local function add(n) n = n and n:gsub("^%s+", ""):gsub("%s+$", ""); if n and n ~= "" and not seen[n] and #out < Card.EXTRA_TARGETS then seen[n] = true; out[#out + 1] = n end end
  if not (s and s.k == "obj" and who) then return out end
  local inner = (s.text or ""):match("%(([^()]+)%)%s*$")
  if inner then for n in inner:gmatch("[^,]+") do add(n) end end
  local i = ns.Engine.Shown and ns.Engine.Shown()
  if i and BeelineData and BeelineData.steps[i] == s and ns.Engine.Group then
    for _, j in ipairs(ns.Engine.Group(i)) do add(BeelineData.steps[j].target) end
  end
  return out
end

function Card.SetButtons(s)
  local cur = f.cur
  local who = s and (s.target or ((s.k == "accept" or s.k == "turnin" or s.k == "bind" or s.k == "fp" or s.k == "train") and s.npc))
  local item = s and s.k ~= "bonus" and s.item -- books are looted, not used
  -- no item of the step's own: the button starts the quest an item in your bags offers (ns.ItemQuests)
  local offer = not item and not ns.Engine.view and ns.db.cardItemQuests ~= false and ns.ItemQuests and ns.ItemQuests.Current()
  if offer then item = offer.item end
  cur.offerItem = offer and true or false
  cur.wantTarget, cur.wantItem = who, item
  setSecure(function()
    if who then cur.target:SetAttribute("macrotext", Card.TargetMacro(who)); cur.target.who = who; cur.target.label:SetText(who)
    else cur.target:SetAttribute("macrotext", ""); cur.target.who = nil end -- the key does nothing on a step with no one to target
    local others = Card.OtherTargets(s, who)
    cur.wantOthers = #others
    for n, b in ipairs(cur.targets) do
      local o = others[n]
      b.who = o; b:SetAttribute("macrotext", o and Card.TargetMacro(o) or ""); b.label:SetText(o or "")
    end
    if item then
      cur.item:SetAttribute("item", "item:" .. item); cur.item.itemID = item
      cur.item.icon:SetTexture((ns.GetItemIcon and ns.GetItemIcon(item)) or 134400)
    else
      cur.item:SetAttribute("item", nil); cur.item.itemID = nil -- (a /click on it uses nothing, not the last step's item)
    end
  end)
end

-- Where the Target button goes when you haven't put it somewhere yourself: just above the card's top edge, its left
-- side on the card's (the use-item button next to it). It is beside the card, never on it, so no row of the card can
-- run under it, and it does not depend on how tall the card is. No room above (the card at the top of the screen):
-- left of the card's top corner, or right of it.
-- -> x, y of the Target button's bottom-left corner in UIParent units, and "above" / "left" / "right"
Card.SECURE_GAP, Card.TARGET_W, Card.TARGET_H, Card.ITEM_SIZE = 4, 140, 20, 26
function Card.SecureSpot(withItem)
  if not f then return nil end
  local l, t, r = f:GetLeft(), f:GetTop(), f:GetRight()
  if not (l and t and r) then return nil end
  -- the card's units -> the screen's (UIParent's): the buttons are UIParent's children, at the card's scale
  local S = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
  local gap = Card.SECURE_GAP * S
  local w = (Card.TARGET_W + (withItem and Card.SECURE_GAP + Card.ITEM_SIZE or 0)) * S
  local h = (withItem and Card.ITEM_SIZE or Card.TARGET_H) * S
  local W, H = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
  l, t, r = l * S, t * S, r * S
  if H <= 0 or t + gap + h <= H then return l, t + gap, "above" end
  if l - gap - w >= 0 then return l - gap - w, t - h, "left" end
  if W <= 0 or r + gap + w <= W then return r + gap, t - h, "right" end
  return l, t + gap, "above" -- (nowhere beside it either: the screen clamp keeps it in sight)
end
function Card.PlaceSecure()
  if not f then return end
  local cur = f.cur
  if InCombatLockdown() then Card.needPlace = true; return end
  Card.needPlace = false
  local x, y, where = Card.SecureSpot(cur.wantItem and true or false)
  if not (f:IsShown() and not ns.db.collapsed and (cur.wantTarget or cur.wantItem) and x and not ns.Engine.view) then cur.target:Hide(); cur.item:Hide(); for _, b in ipairs(cur.targets) do b:Hide() end cur.secureAt = nil; return end
  -- on the card's layer, a level above it and everything on it
  local lvl = f:GetFrameLevel() + 20
  for _, b in ipairs({ cur.item, cur.target, unpack(cur.targets) }) do b:SetScale(f:GetScale()); b:SetFrameStrata(f:GetFrameStrata()); b:SetFrameLevel(lvl) end
  -- places are worked out in UIParent units; the game multiplies a frame's offsets by its scale, so they are set
  -- divided by the buttons' own
  local S = cur.target:GetEffectiveScale() / UIParent:GetEffectiveScale()
  -- where you dragged it (Ctrl+drag: its top-left corner), else above the card
  local tp = ns.db.targetPos
  if type(tp) == "table" and tonumber(tp[1]) and tonumber(tp[2]) then x, y, where = tp[1], tp[2] - Card.TARGET_H * S, "dragged" end
  cur.secureAt = where
  cur.target:ClearAllPoints(); cur.target:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / S, y / S)
  cur.target:SetShown(cur.wantTarget and true or false)
  -- the other mobs' buttons: a column under the first (above the card they'd cover it: they go up instead)
  local up = where ~= "dragged"
  for n, b in ipairs(cur.targets) do
    b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / S, (y + (up and n or -n) * (Card.TARGET_H + 2) * S) / S)
    b:SetShown((cur.wantTarget and (cur.wantOthers or 0) >= n) and true or false)
  end
  -- the use-item button: next to the Target button, or in its place on a step with no one to target
  local ix = cur.wantTarget and x + (Card.TARGET_W + Card.SECURE_GAP) * S or x
  cur.item:ClearAllPoints(); cur.item:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", ix / S, y / S)
  cur.item:SetShown(cur.wantItem and true or false)
end
-- /bee target reset: forget where you dragged the Target button; it goes back above the card. In combat it can't be
-- moved (the game forbids it): it goes back when the fight ends, and says so.
function Card.ResetTarget()
  ns.db.targetPos = nil
  if not f then return end
  if InCombatLockdown() then Card.needPlace = true; ns.Print("Target button: it can't move during a fight. It goes back above the card when the fight ends."); return end
  Card.PlaceSecure()
  local cur = f.cur
  if cur.target:IsShown() or cur.item:IsShown() then ns.Print("Target button back above the card.")
  else ns.Print("Target button: it will be above the card the next time a step has someone to target.") end
end
ns.On("PLAYER_REGEN_ENABLED", function()
  if pendingSecure then local fn = pendingSecure; pendingSecure = nil; fn() end
  if f and Card.needPlace then Card.PlaceSecure() end
end)
