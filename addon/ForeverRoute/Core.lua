-- ForeverRoute is now Beeline. This folder keeps the old saves for Beeline (it reads them once per character), and
-- says one thing: the game only finds a new addon folder when it starts, not on /reload. Updated while playing, Beeline
-- isn't there until a restart - say so, instead of a card that's simply gone.
-- Only when the game doesn't know Beeline at all: turned off on purpose, or loaded, it stays quiet. At most 3 times
-- (ForeverRouteStubNotes): someone who removed Beeline and kept this folder isn't told forever.
-- It also keeps ForeverRoute's key actions (Bindings.xml) doing what Beeline's do, until Beeline moves your keys.

local function api(n) return (C_AddOns and C_AddOns[n]) or _G[n] end

-- true when Beeline's folder isn't known to the game yet (installed after the game started, or not installed)
function ForeverRouteStub_NeedsRestart()
  local loaded = api("IsAddOnLoaded")
  if loaded and loaded("Beeline") then return false end
  local exists = api("DoesAddOnExist")
  if exists then return not exists("Beeline") end
  local info = api("GetAddOnInfo")
  if not info then return false end
  local ok, name, _, _, _, reason = pcall(info, "Beeline")
  if not ok then return true end -- (older clients: an unknown name is an error)
  return name == nil or reason == "MISSING"
end

BINDING_HEADER_FOREVERROUTE = "ForeverRoute (old keys - now Beeline)"
BINDING_NAME_FOREVERROUTE_SKIP = "Skip current step"
BINDING_NAME_FOREVERROUTE_BACK = "Look at previous step"
BINDING_NAME_FOREVERROUTE_UNDO = "Undo last skip / done"
BINDING_NAME_FOREVERROUTE_TOGGLE = "Show / hide the card"
BINDING_NAME_FOREVERROUTE_LIST = "Show the whole route"
_G["BINDING_NAME_CLICK ForeverRouteTargetButton:LeftButton"] = "Targeting"

local TEXT = "ForeverRoute is now Beeline. Restart the game (exit and start it again - a /reload isn't enough) to finish the update."

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
  if not ForeverRouteStub_NeedsRestart() then return end
  ForeverRouteStubNotes = type(ForeverRouteStubNotes) == "table" and ForeverRouteStubNotes or {}
  local n = tonumber(ForeverRouteStubNotes.restart) or 0
  if n >= 3 then return end
  ForeverRouteStubNotes.restart = n + 1
  local function say()
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffffd200" .. TEXT .. "|r") end
    if StaticPopupDialogs and StaticPopup_Show then
      StaticPopupDialogs.FOREVERROUTE_RESTART = StaticPopupDialogs.FOREVERROUTE_RESTART or {
        text = TEXT, button1 = OKAY or "Okay", timeout = 0, whileDead = true, hideOnEscape = true,
      }
      StaticPopup_Show("FOREVERROUTE_RESTART")
    end
  end
  if C_Timer and C_Timer.After then C_Timer.After(3, say) else say() end
end)
