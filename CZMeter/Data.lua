-- Reads Blizzard's meter. In combat most values are secret: they can be drawn,
-- but never compared, added or formatted by us. Anything calculated checks first.

local _, ns = ...

local Data = {}
ns.Data = Data

local issecret = issecretvalue or function() return false end
ns.issecret = issecret

local METRICS = {
  { key = "DamageDone", label = "Damage dealt", column = "DAMAGE", perSecond = true },
  { key = "HealingDone", label = "Healing done", column = "HEALING", perSecond = true },
  { key = "Absorbs", label = "Absorbs", column = "ABSORBED", perSecond = true },
  { key = "DamageTaken", label = "Damage taken", column = "TAKEN", perSecond = true },
  { key = "AvoidableDamageTaken", label = "Avoidable damage", column = "TAKEN", perSecond = true },
  { key = "Interrupts", label = "Interrupts", column = "COUNT", perSecond = false },
  { key = "Dispels", label = "Dispels", column = "COUNT", perSecond = false },
  { key = "Deaths", label = "Deaths", column = "COUNT", perSecond = false },
}
Data.METRICS = METRICS

function Data.Metric()
  return METRICS[CZMeterDB.metric] or METRICS[1]
end

-- The session this view is showing, or nil.
local function ReadSession(meterType)
  local view = CZMeterDB.view
  local ok, session
  if view == "overall" then
    ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, Enum.DamageMeterSessionType.Overall, meterType)
  elseif type(view) == "number" then
    ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, view, meterType)
  else
    ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, Enum.DamageMeterSessionType.Current, meterType)
  end
  if ok then return session end
end

-- Returns rows, the bar scale, the duration if readable, and the column info.
function Data.Read()
  local metric = Data.Metric()

  if CZMeterDB.showBest then
    local best = Data.BestTry()
    if best then
      return best.rows, best.maxAmount, best.duration, metric, best
    end
    return {}, 1, nil, metric, nil
  end

  local meterType
  if CZMeterDB.tab == "enemies" then
    meterType = Enum.DamageMeterType.EnemyDamageTaken
  else
    meterType = Enum.DamageMeterType[metric.key]
  end
  local session = meterType and ReadSession(meterType)
  if type(session) ~= "table" then return {}, 1, nil, metric end
  return session.combatSources or {}, session.maxAmount, session.durationSeconds, metric
end

-- Share of the total, only once the numbers can be read. Nil in combat.
function Data.Shares(rows)
  local sum = 0
  for _, row in ipairs(rows) do
    if issecret(row.totalAmount) or type(row.totalAmount) ~= "number" then return nil end
    sum = sum + row.totalAmount
  end
  if sum <= 0 then return nil end
  local shares = {}
  for i, row in ipairs(rows) do shares[i] = row.totalAmount / sum * 100 end
  return shares
end

---------------------------------------------------------------------------
-- History
---------------------------------------------------------------------------
function Data.History()
  local out = {}
  local ok, list = pcall(C_DamageMeter.GetAvailableCombatSessions)
  if not ok or type(list) ~= "table" then return out end
  for i, entry in ipairs(list) do
    if not issecret(entry.sessionID) then
      local name = entry.name
      if name == nil or issecret(name) or name == "" then name = "Pull " .. i end
      local seconds = entry.durationSeconds
      if seconds ~= nil and not issecret(seconds) then
        name = string.format("%s (%s)", name, ns.Clock(seconds))
      end
      out[#out + 1] = { id = entry.sessionID, label = name }
    end
  end
  return out
end

function ns.Clock(seconds)
  seconds = math.max(0, math.floor(seconds))
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

---------------------------------------------------------------------------
-- Best try: the group's best DPS per boss and difficulty, saved after combat
---------------------------------------------------------------------------
local pendingKey, lastKey

function Data.EncounterEnded(encounterID, name, difficultyID)
  pendingKey = encounterID .. ":" .. difficultyID
  lastKey = pendingKey
  Data.pendingName = name
end

function Data.BestTry()
  return lastKey and CZMeterDB.best[lastKey] or nil
end

-- Called once out of combat, when the totals can be read again.
function Data.SaveBestTry()
  if not pendingKey then return end
  local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType,
    Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.DamageDone)
  local key = pendingKey
  pendingKey = nil
  if not ok or type(session) ~= "table" then return end
  local duration = session.durationSeconds
  local total = session.totalAmount
  if duration == nil or total == nil or issecret(duration) or issecret(total) or duration <= 0 then return end

  local rows = {}
  for i, src in ipairs(session.combatSources or {}) do
    if issecret(src.totalAmount) then return end
    rows[i] = {
      name = src.name, classFilename = src.classFilename, specIconID = src.specIconID,
      totalAmount = src.totalAmount, amountPerSecond = src.amountPerSecond,
      isLocalPlayer = src.isLocalPlayer, sourceGUID = src.sourceGUID,
    }
  end

  local groupDps = total / duration
  local old = CZMeterDB.best[key]
  if not old or groupDps > old.groupDps then
    CZMeterDB.best[key] = {
      name = Data.pendingName, groupDps = groupDps, duration = duration,
      maxAmount = session.maxAmount, rows = rows, when = time(),
    }
  end
end

---------------------------------------------------------------------------
-- Item levels: inspected out of combat, shown when the row can be identified
---------------------------------------------------------------------------
local itemLevels = {}
local queue = {}
local inspecting
local INSPECT_GAP = 2
local lastInspect = 0

function Data.ItemLevel(guid)
  if guid == nil or issecret(guid) then return nil end
  return itemLevels[guid]
end

function Data.ReadOwnItemLevel()
  local _, equipped = GetAverageItemLevel()
  local guid = UnitGUID("player")
  if equipped ~= nil and not issecret(equipped) and guid then itemLevels[guid] = math.floor(equipped) end
end

function Data.QueueGroup()
  wipe(queue)
  local prefix, count = "party", GetNumSubgroupMembers()
  if IsInRaid() then prefix, count = "raid", GetNumGroupMembers() end
  for i = 1, count do
    local unit = prefix .. i
    local guid = UnitGUID(unit)
    if guid and not issecret(guid) and not itemLevels[guid] and not UnitIsUnit(unit, "player") then
      queue[#queue + 1] = unit
    end
  end
end

function Data.InspectNext()
  if InCombatLockdown() or inspecting or #queue == 0 then return end
  if GetTime() - lastInspect < INSPECT_GAP then return end
  if InspectFrame and InspectFrame:IsShown() then return end
  local unit = table.remove(queue, 1)
  if UnitExists(unit) and CanInspect(unit) then
    inspecting = UnitGUID(unit)
    lastInspect = GetTime()
    NotifyInspect(unit)
  end
end

function Data.InspectReady(guid)
  if guid ~= inspecting then return end
  inspecting = nil
  local prefix, count = "party", GetNumSubgroupMembers()
  if IsInRaid() then prefix, count = "raid", GetNumGroupMembers() end
  for i = 1, count do
    local unit = prefix .. i
    if UnitGUID(unit) == guid then
      local level = C_PaperDollInfo.GetInspectItemLevel(unit)
      if level ~= nil and not issecret(level) and level > 0 then itemLevels[guid] = math.floor(level) end
      break
    end
  end
  ClearInspectPlayer()
end
