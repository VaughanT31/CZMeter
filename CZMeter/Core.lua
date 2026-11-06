local ADDON, ns = ...

local Data, Window, Skins, Options = ns.Data, ns.Window, ns.Skins, ns.Options

local OPT_DEFAULTS = {
  combatUpdate = 0.25, wheel = 1, numbers = "short",
  autoLog = "off", logWarn = true, clearOnKey = false, clearOnInstance = false,
  minimapButton = true, minimapAngle = 200, hoverCard = true,
  logRemindHours = 10, logSeconds = 0,
}
local PREFIX = "|cfff59e3bCZ Meter|r: "

local events = CreateFrame("Frame")

local function Fill(target, defaults)
  for key, value in pairs(defaults) do
    if target[key] == nil then target[key] = value end
  end
end

-- 0.1.x kept one window's settings at the top level.
local function MoveOldSettings(db)
  if db.windows then return end
  local first = {
    metric = db.metric, tab = db.tab, top = db.top, myOnly = db.myOnly, showBest = db.showBest,
    width = db.windowWidth, pos = db.pos, shown = db.shown,
  }
  if db.metric ~= nil then first.autoHeight = true end
  db.windows = { first }
  for _, key in ipairs({ "metric", "tab", "view", "top", "myOnly", "showBest", "windowWidth", "pos", "shown" }) do
    db[key] = nil
  end
end

local function LoadSettings()
  CZMeterDB = CZMeterDB or {}
  local db = CZMeterDB
  MoveOldSettings(db)
  db.best = db.best or {}
  db.skins = db.skins or {}
  db.opt = db.opt or {}
  Fill(db.opt, OPT_DEFAULTS)
  if next(db.windows) == nil then db.windows[1] = {} end
  for _, win in pairs(db.windows) do
    Fill(win, Window.DEFAULTS)
    -- Session IDs don't survive a reload.
    win.view = "current"
  end
  for _, skin in pairs(db.skins) do Skins.Fill(skin) end
end

---------------------------------------------------------------------------
-- Shared actions
---------------------------------------------------------------------------
function ns.ResetMeter()
  pcall(C_DamageMeter.ResetAllCombatSessions)
  for _, w in ipairs(Window.List()) do w.db.view = "current" end
  Window.RefreshControlsAll()
end

function ns.SetTestMode(on)
  ns.testMode = on
  Window.RefreshControlsAll()
  Options.Refresh()
end

---------------------------------------------------------------------------
-- Combat log: on as you zone into the chosen content, off when you leave
-- (only if we turned it on)
---------------------------------------------------------------------------
local MYTHIC_PLUS = 8
local warnedAdvanced = false

local function WantsLog()
  local mode = CZMeterDB.opt.autoLog
  if mode == "off" then return false end
  local inInstance, kind = IsInInstance()
  if not inInstance then return false end
  if kind == "raid" then return true end
  if kind ~= "party" then return false end
  if mode == "all" then return true end
  local _, _, difficultyID = GetInstanceInfo()
  return difficultyID == MYTHIC_PLUS
end

-- Addons can't see or delete files, so the log can't be cleaned up from here.
-- Instead we count the time we've logged and remind the player to clear old logs.
local LOG_FOLDER = "World of Warcraft\\_retail_\\Logs"
local loggingSince

local function AddLoggedTime()
  if not loggingSince then return end
  CZMeterDB.opt.logSeconds = CZMeterDB.opt.logSeconds + math.max(0, time() - loggingSince)
  loggingSince = nil
end

function ns.LoggedHours()
  local seconds = CZMeterDB.opt.logSeconds
  if loggingSince then seconds = seconds + math.max(0, time() - loggingSince) end
  return seconds / 3600
end

function ns.ClearLoggedTime()
  CZMeterDB.opt.logSeconds = 0
  if loggingSince then loggingSince = time() end
end

local function RemindAboutLogs()
  local limit = CZMeterDB.opt.logRemindHours
  if limit <= 0 or CZMeterDB.opt.logSeconds < limit * 3600 then return end
  print(string.format("%sCZ Meter has turned on combat logging for about %d hours. Log files can grow to several GB, "
    .. "so delete the ones you've finished with from %s (or put them through the log tool first).",
    PREFIX, math.floor(CZMeterDB.opt.logSeconds / 3600), LOG_FOLDER))
  CZMeterDB.opt.logSeconds = 0
end

local function StopOurLog(quiet)
  if not (ns.startedLog and LoggingCombat and LoggingCombat()) then return end
  LoggingCombat(false)
  ns.startedLog = false
  AddLoggedTime()
  if not quiet then
    print(PREFIX .. "combat log stopped.")
    RemindAboutLogs()
  end
end

function ns.CheckCombatLog()
  if not LoggingCombat then return end
  if WantsLog() then
    if not LoggingCombat() then
      LoggingCombat(true)
      ns.startedLog = true
      loggingSince = time()
      print(PREFIX .. "combat log started.")
    end
    if CZMeterDB.opt.logWarn and not warnedAdvanced and C_CVar
       and not C_CVar.GetCVarBool("advancedCombatLogging") then
      warnedAdvanced = true
      print(PREFIX .. "Advanced Combat Logging is off. Turn it on under Options, Network, so the log tool gets full details.")
    end
  else
    StopOurLog()
  end
end

local lastInstance
local function OnEnterWorld()
  local inInstance, kind = IsInInstance()
  if inInstance and (kind == "party" or kind == "raid") then
    local instanceID = select(8, GetInstanceInfo())
    if CZMeterDB.opt.clearOnInstance and lastInstance and instanceID ~= lastInstance and not InCombatLockdown() then
      ns.ResetMeter()
    end
    lastInstance = instanceID
  end
  ns.CheckCombatLog()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function OnLeaveCombat()
  ns.combatStart = nil
  C_Timer.After(1, function()
    if InCombatLockdown() then return end
    Data.SaveBestTry()
    Data.ReadOwnItemLevel()
    Data.QueueGroup()
    Window.RefreshAll()
  end)
end

events:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    LoadSettings()
  elseif event == "PLAYER_LOGIN" then
    Data.ReadOwnItemLevel()
    Data.QueueGroup()
    Window.Init()
    Options.Register()
    ns.MinimapButton.Update()
    C_Timer.NewTicker(1, Data.InspectNext)
  elseif event == "PLAYER_ENTERING_WORLD" then
    OnEnterWorld()
  elseif event == "PLAYER_REGEN_DISABLED" then
    ns.combatStart = GetTime()
  elseif event == "PLAYER_REGEN_ENABLED" then
    OnLeaveCombat()
  elseif event == "DAMAGE_METER_CURRENT_SESSION_UPDATED" then
    -- This fires many times a second in a busy fight, so it only flags a redraw;
    -- the window timer does the drawing.
    Window.MarkDirty()
  elseif event == "ENCOUNTER_START" then
    -- A boss can begin mid-combat, which swaps the session under us: start the clock again.
    ns.combatStart = GetTime()
    Window.MarkDirty()
  elseif event == "ENCOUNTER_END" then
    local encounterID, name, difficultyID = ...
    Data.EncounterEnded(encounterID, name, difficultyID)
    if not InCombatLockdown() then OnLeaveCombat() end
  elseif event == "CHALLENGE_MODE_START" then
    if CZMeterDB.opt.clearOnKey then ns.ResetMeter() end
    ns.CheckCombatLog()
  elseif event == "ZONE_CHANGED_NEW_AREA" then
    ns.CheckCombatLog()
  elseif event == "PLAYER_LOGOUT" then
    StopOurLog(true)
  elseif event == "GROUP_ROSTER_UPDATE" then
    if not InCombatLockdown() then Data.QueueGroup() end
  elseif event == "INSPECT_READY" then
    Data.InspectReady(...)
    Window.MarkDirty()
  end
end)

for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED",
                         "PLAYER_REGEN_ENABLED", "DAMAGE_METER_CURRENT_SESSION_UPDATED", "ENCOUNTER_START", "ENCOUNTER_END",
                         "CHALLENGE_MODE_START", "ZONE_CHANGED_NEW_AREA", "PLAYER_LOGOUT", "GROUP_ROSTER_UPDATE",
                         "INSPECT_READY" }) do
  events:RegisterEvent(event)
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local HELP = {
  "/cz  show or hide the meter",
  "/cz options  open the options",
  "/cz new  open another window",
  "/cz lock  lock or unlock every window",
  "/cz test  fill the windows with test bars",
}

SLASH_CZMETER1 = "/cz"
SLASH_CZMETER2 = "/czmeter"
SlashCmdList.CZMETER = function(msg)
  local cmd = strtrim(msg or ""):lower()
  if cmd == "" then
    Window.Toggle()
  elseif cmd == "options" or cmd == "config" or cmd == "opt" then
    Options.Toggle()
  elseif cmd == "new" then
    Window.Create()
  elseif cmd == "lock" then
    local list = Window.List()
    local lock = not (list[1] and list[1].db.locked)
    for _, w in ipairs(list) do Window.SetLocked(w, lock) end
    print(PREFIX .. (lock and "windows locked." or "windows unlocked."))
  elseif cmd == "test" then
    ns.SetTestMode(not ns.testMode)
    print(PREFIX .. (ns.testMode and "test bars on." or "test bars off."))
  else
    for _, line in ipairs(HELP) do print(PREFIX .. line) end
  end
end
