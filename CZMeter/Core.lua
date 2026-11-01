local ADDON, ns = ...

local Data, Window = ns.Data, ns.Window

local DEFAULTS = {
  metric = 1, tab = "players", view = "current", top = 5, width = 500,
  myOnly = false, showBest = false, shown = true, best = {},
}

local events = CreateFrame("Frame")

local function OnLeaveCombat()
  ns.combatStart = nil
  C_Timer.After(1, function()
    if InCombatLockdown() then return end
    Data.SaveBestTry()
    Data.ReadOwnItemLevel()
    Data.QueueGroup()
    Window.Refresh()
  end)
end

events:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    CZMeterDB = CZMeterDB or {}
    for key, value in pairs(DEFAULTS) do
      if CZMeterDB[key] == nil then CZMeterDB[key] = value end
    end
    -- Session IDs don't survive a reload.
    CZMeterDB.view = "current"
  elseif event == "PLAYER_LOGIN" then
    Data.ReadOwnItemLevel()
    Data.QueueGroup()
    if CZMeterDB.shown then Window.Open() end
    C_Timer.NewTicker(1, Data.InspectNext)
  elseif event == "PLAYER_REGEN_DISABLED" then
    ns.combatStart = GetTime()
  elseif event == "PLAYER_REGEN_ENABLED" then
    OnLeaveCombat()
  elseif event == "DAMAGE_METER_CURRENT_SESSION_UPDATED" then
    -- A boss can begin mid-combat, which swaps the session under us: start the clock again.
    if InCombatLockdown() then ns.combatStart = GetTime() end
    Window.Refresh()
  elseif event == "ENCOUNTER_END" then
    local encounterID, name, difficultyID = ...
    Data.EncounterEnded(encounterID, name, difficultyID)
    if not InCombatLockdown() then OnLeaveCombat() end
  elseif event == "GROUP_ROSTER_UPDATE" then
    if not InCombatLockdown() then Data.QueueGroup() end
  elseif event == "INSPECT_READY" then
    Data.InspectReady(...)
  end
end)

for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
                         "DAMAGE_METER_CURRENT_SESSION_UPDATED", "ENCOUNTER_END", "GROUP_ROSTER_UPDATE",
                         "INSPECT_READY" }) do
  events:RegisterEvent(event)
end

SLASH_CZMETER1 = "/cz"
SlashCmdList.CZMETER = function()
  Window.Toggle()
end
