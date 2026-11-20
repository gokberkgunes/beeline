-- Beeline was called ForeverRoute until 2.0 (another addon has that name). The game keeps an addon's saves in a file
-- named after its folder, so the old ones sit in ForeverRoute.lua, where Beeline can't see them. The release ships an
-- empty addon by that name (addon/ForeverRoute: the two old saved tables, and a note to restart the game when Beeline
-- was installed while it ran) so each character's first login under Beeline can read them once and copy what Beeline
-- doesn't have yet. It loads before Beeline (## OptionalDeps), so its saves are already there at ADDON_LOADED. Only our own empty
-- one is loaded (## X-Beeline-Stub): a folder by that name from someone else is left alone.
-- A whole 1.x ForeverRoute still installed by hand would run beside Beeline (two cards): it is turned off for the next
-- /reload, and you're asked to reload.
local _, ns = ...
local Migrate = {}
ns.Migrate = Migrate
Migrate.OLD = "ForeverRoute"

-- the game's addon calls, looked up when used (C_AddOns, or the older globals)
local function api(n) return (C_AddOns and C_AddOns[n]) or _G[n] end
local function meta(name, field)
  local f = api("GetAddOnMetadata")
  if not f then return nil end
  local ok, v = pcall(f, name, field)
  return ok and v or nil
end
local function isLoaded(name)
  local f = api("IsAddOnLoaded")
  return f and f(name) and true or false
end

local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end
-- what Beeline already has stays; the rest comes over from the old save. Returns how many keys came over.
local function fill(new, old)
  local n = 0
  for k, v in pairs(old) do
    if new[k] == nil then new[k] = copy(v); n = n + 1 end
  end
  return n
end

-- ours: the empty one Beeline ships (copy), or a whole 1.x ForeverRoute (turn off). Anyone else's: "theirs". None: nil.
function Migrate.OldKind()
  local author = meta(Migrate.OLD, "Author")
  if author == nil then return nil end
  if author ~= "noopz" then return "theirs" end
  return meta(Migrate.OLD, "X-Beeline-Stub") == "1" and "stub" or "old"
end

-- the old saves are ours: every 1.x keeps mapBounds in its account save and charKey in a character's. (Another addon
-- by that name, whose folder ours replaced, could have left a save under the same names: not copied.)
local function oursDB(t) return type(t) == "table" and type(t.mapBounds) == "table" end
local function oursChar(t, accountOurs) return type(t) == "table" and (accountOurs or type(t.charKey) == "string") end

local function askReload()
  if not StaticPopupDialogs then return end
  StaticPopupDialogs.BEELINE_OLD_ADDON = StaticPopupDialogs.BEELINE_OLD_ADDON or {
    text = "ForeverRoute is now Beeline.\n\nThe old ForeverRoute was still installed, so both were running. It's turned off now: reload to finish. You can delete its folder (Interface\\AddOns\\ForeverRoute) any time.",
    button1 = "Reload", button2 = "Later", OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
  }
  if StaticPopup_Show then StaticPopup_Show("BEELINE_OLD_ADDON") end
end

-- Your key bindings were kept under the old names (FOREVERROUTE_SKIP, CLICK ForeverRouteTargetButton:LeftButton...):
-- the same keys go on the new ones. At login, once per character (bindings can't change in combat). Returns how many.
local BINDS = { "SKIP", "BACK", "UNDO", "TOGGLE", "LIST" }
function Migrate.Bindings()
  if not (GetBindingKey and SetBinding and GetBindingAction) then return 0 end
  if InCombatLockdown and InCombatLockdown() then return nil end
  local list = { { "CLICK ForeverRouteTargetButton:LeftButton", "CLICK BeelineTargetButton:LeftButton" } }
  for _, b in ipairs(BINDS) do list[#list + 1] = { "FOREVERROUTE_" .. b, "BEELINE_" .. b } end
  local n = 0
  for _, p in ipairs(list) do
    for _, key in ipairs({ GetBindingKey(p[1]) }) do
      if key and GetBindingAction(key) == p[1] then SetBinding(key, p[2]); n = n + 1 end
    end
  end
  if n > 0 and SaveBindings and GetCurrentBindingSet then SaveBindings(GetCurrentBindingSet()) end
  return n
end
-- (no "done" flag: a character's bindings may not be there yet at login, and moving finds nothing the second time)
local function moveBindings()
  if BeelineChar and BeelineChar.migratedFrom == Migrate.OLD then Migrate.Bindings() end
end
ns.On("PLAYER_LOGIN", moveBindings)
ns.On("UPDATE_BINDINGS", moveBindings)

-- a whole 1.x ForeverRoute running beside Beeline: turned off for this character (not all of them: each alt still has
-- to bring its own saves over), once the character's name is known
function Migrate.TurnOffOld()
  if not Migrate.oldRunning then return false end
  local off = api("DisableAddOn")
  local ok, me = pcall(UnitName, "player")
  if off then pcall(off, Migrate.OLD, ok and me or nil) end
  C_Timer.After(2, askReload)
  return true
end
ns.On("PLAYER_LOGIN", Migrate.TurnOffOld)

-- at ADDON_LOADED, before the saves are used. Returns what it did ("copied", "none", "skip", "old"), for the tests.
function Migrate.Run()
  BeelineDB = type(BeelineDB) == "table" and BeelineDB or {}
  BeelineChar = type(BeelineChar) == "table" and BeelineChar or {}
  local kind = Migrate.OldKind()
  if kind == "old" and isLoaded(Migrate.OLD) then
    -- its saves are loaded with it: copy them now, then turn it off for the next reload
    local d, c = 0, 0
    if not BeelineDB.migratedFrom and type(ForeverRouteDB) == "table" then d = fill(BeelineDB, ForeverRouteDB); BeelineDB.migratedFrom = Migrate.OLD end
    if not BeelineChar.migratedFrom and type(ForeverRouteChar) == "table" then c = fill(BeelineChar, ForeverRouteChar); BeelineChar.migratedFrom = Migrate.OLD end
    Migrate.oldRunning = true -- (turned off at PLAYER_LOGIN)
    return "old", d, c
  end
  if BeelineDB.migratedFrom and BeelineChar.migratedFrom then return "none" end
  -- a whole 1.x ForeverRoute installed but turned off: its saves can't be loaded (it isn't load-on-demand). Not marked
  -- done: the release's empty one, once in its place, still brings them over
  if kind == "old" then return "skip" end
  -- someone else's ForeverRoute in that folder: not read, and not marked done (ours may take its place later)
  if kind == "theirs" then return "skip" end
  if kind ~= "stub" then
    -- no ForeverRoute at all (a new player): never look again
    BeelineDB.migratedFrom = BeelineDB.migratedFrom or "none"; BeelineChar.migratedFrom = BeelineChar.migratedFrom or "none"
    return "skip"
  end
  -- it loads before Beeline (## OptionalDeps); turned off in the addon list, it's turned on for this one load
  if not isLoaded(Migrate.OLD) then
    local on, load = api("EnableAddOn"), api("LoadAddOn")
    local ok, me = pcall(UnitName, "player")
    if on then pcall(on, Migrate.OLD, ok and me or nil) end
    if load then pcall(load, Migrate.OLD) end
    -- still not loaded (out of date, damaged): nothing read, nothing marked - next login tries again
    if not isLoaded(Migrate.OLD) then return "skip" end
  end
  local d, c = 0, 0
  local dbOurs = oursDB(ForeverRouteDB)
  if not BeelineDB.migratedFrom then
    if dbOurs then d = fill(BeelineDB, ForeverRouteDB) end
    BeelineDB.migratedFrom = Migrate.OLD
  end
  if not BeelineChar.migratedFrom then
    if oursChar(ForeverRouteChar, dbOurs) then c = fill(BeelineChar, ForeverRouteChar) end
    BeelineChar.migratedFrom = Migrate.OLD
  end
  return "copied", d, c
end
