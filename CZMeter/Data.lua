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

-- Each window passes its own settings (metric, tab, view, best try).
function Data.Metric(win)
  return METRICS[win.metric] or METRICS[1]
end

-- Numbers in our chosen style. Secret values can only take Blizzard's short form.
function ns.Num(value)
  if value == nil then return "" end
  if issecret(value) then return AbbreviateNumbers(value) end
  if type(value) ~= "number" then return "" end
  if CZMeterDB.opt.numbers == "full" then return BreakUpLargeNumbers(math.floor(value + 0.5)) end
  return AbbreviateNumbers(value)
end

---------------------------------------------------------------------------
-- Test bars: made-up rows so skins and big raid windows can be tried anywhere
---------------------------------------------------------------------------
local TEST_CLASSES = {
  { "WARRIOR", "Warrior" }, { "PALADIN", "Paladin" }, { "HUNTER", "Hunter" }, { "ROGUE", "Rogue" },
  { "PRIEST", "Priest" }, { "DEATHKNIGHT", "DeathKnight" }, { "SHAMAN", "Shaman" }, { "MAGE", "Mage" },
  { "WARLOCK", "Warlock" }, { "MONK", "Monk" }, { "DRUID", "Druid" }, { "DEMONHUNTER", "DemonHunter" },
  { "EVOKER", "Evoker" },
}
local TEST_NAMES = {
  "Brannick", "Lysa", "Torvald", "Quill", "Seraphine", "Mordrak", "Tavi", "Elandor", "Vex", "Hollin",
  "Kestra", "Ozric", "Pell", "Ysolde", "Grimm", "Nalia", "Corvin", "Sabre", "Dunmore", "Ilsa",
  "Fenwick", "Rhea", "Bastian", "Juno", "Wick",
}
local TEST_SCALE = {
  DamageDone = 1, HealingDone = 0.6, Absorbs = 0.2, DamageTaken = 0.3, AvoidableDamageTaken = 0.05,
  Interrupts = 0, Dispels = 0, Deaths = 0,
}
local TEST_SECONDS = 180

function Data.TestRows(metric)
  local rows = {}
  local scale = TEST_SCALE[metric.key] or 1
  for i, name in ipairs(TEST_NAMES) do
    local class = TEST_CLASSES[(i - 1) % #TEST_CLASSES + 1]
    local total
    if scale == 0 then
      total = math.max(0, 9 - i)
    else
      total = math.floor(18000000 * scale * 0.93 ^ (i - 1))
    end
    rows[i] = {
      name = name, classFilename = class[1], specIconID = "Interface\\Icons\\ClassIcon_" .. class[2],
      totalAmount = total, amountPerSecond = total / TEST_SECONDS, isLocalPlayer = i == 7,
    }
  end
  return rows, rows[1].totalAmount, TEST_SECONDS
end

-- The session this view is showing, or nil.
local function ReadSession(win, meterType)
  local view = win.view
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
function Data.Read(win)
  local metric = Data.Metric(win)

  if ns.testMode then
    local rows, maxAmount, duration = Data.TestRows(metric)
    return rows, maxAmount, duration, metric
  end

  if win.showBest then
    local best = Data.BestTry()
    if best then
      return best.rows, best.maxAmount, best.duration, metric, best
    end
    return {}, 1, nil, metric, nil
  end

  local meterType
  if win.tab == "enemies" then
    meterType = Enum.DamageMeterType.EnemyDamageTaken
  else
    meterType = Enum.DamageMeterType[metric.key]
  end
  local session = meterType and ReadSession(win, meterType)
  if type(session) ~= "table" then return {}, 1, nil, metric end
  return session.combatSources or {}, session.maxAmount, session.durationSeconds, metric
end

---------------------------------------------------------------------------
-- One player's breakdown for the detail panel
---------------------------------------------------------------------------
-- The same session the window shows, for one source and one meter.
function Data.ReadSource(win, meterKey, guid)
  local meterType = Enum.DamageMeterType[meterKey]
  if not meterType or guid == nil then return nil end
  local view = win.view
  local ok, src
  if type(view) == "number" then
    ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromID, view, meterType, guid)
  else
    local kind = view == "overall" and Enum.DamageMeterSessionType.Overall or Enum.DamageMeterSessionType.Current
    ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromType, kind, meterType, guid)
  end
  if ok and type(src) == "table" then return src end
end

-- The whole group's rows for one meter, in the window's view.
function Data.ReadMeter(win, meterKey)
  local meterType = Enum.DamageMeterType[meterKey]
  local session = meterType and ReadSession(win, meterType)
  if type(session) == "table" then return session.combatSources or {}, session end
  return {}
end

local function Plain(value)
  return value ~= nil and not issecret(value) and type(value) == "number"
end
Data.Plain = Plain

-- In combat the spell ID is secret. The game still takes it and gives back a
-- secret name and icon, which can be drawn but not read, so pass it through.
local function SecretSpellInfo(spellID)
  if not C_Spell then return nil, nil end
  local okName, name = pcall(C_Spell.GetSpellName, spellID)
  local okIcon, icon = pcall(C_Spell.GetSpellTexture, spellID)
  return okName and name or nil, okIcon and icon or nil
end

local function SpellInfo(spellID)
  if spellID ~= nil and issecret(spellID) then return SecretSpellInfo(spellID) end
  if not Plain(spellID) then return nil, nil end
  local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
  local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
  return name, icon
end

-- A source's spells as rows. Out of combat they're merged by name (one ability
-- can log under several IDs), sorted, and given a share of the player's total.
-- In combat the values are secret, so they're passed through in Blizzard's order.
function Data.Spells(src)
  local out = {}
  local spells = type(src) == "table" and src.combatSpells
  if type(spells) ~= "table" then return out, false end
  local readable = true
  for _, sp in ipairs(spells) do
    if not Plain(sp.totalAmount) then readable = false break end
  end
  if not readable then
    for i, sp in ipairs(spells) do
      local name, icon = SpellInfo(sp.spellID)
      -- name may be secret: compare with nil only, never test it as true/false.
      if name == nil then name = "Spell" end
      out[i] = { name = name, icon = icon, total = sp.totalAmount, perSecond = sp.amountPerSecond }
    end
    return out, false
  end

  local byName, sum = {}, 0
  for _, sp in ipairs(spells) do
    local name, icon = SpellInfo(sp.spellID)
    name = name or ("Spell " .. tostring(sp.spellID))
    local row = byName[name]
    if not row then
      row = { name = name, icon = icon, total = 0, perSecond = 0, overkill = 0, ids = {}, targets = {} }
      byName[name] = row
      out[#out + 1] = row
    end
    row.total = row.total + sp.totalAmount
    if Plain(sp.amountPerSecond) then row.perSecond = row.perSecond + sp.amountPerSecond end
    if Plain(sp.overkillAmount) then row.overkill = row.overkill + sp.overkillAmount end
    if sp.isAvoidable == true then row.avoidable = true end
    if sp.isDeadly == true then row.deadly = true end
    row.ids[#row.ids + 1] = sp.spellID
    local details = sp.combatSpellDetails
    if type(details) == "table" then
      if details.unitName ~= nil then details = { details } end
      for _, t in ipairs(details) do
        local unit = t.unitName
        if unit ~= nil and not issecret(unit) and unit ~= "" and Plain(t.amount) and t.amount > 0 then
          row.targets[unit] = (row.targets[unit] or 0) + t.amount
        end
      end
    end
    sum = sum + sp.totalAmount
  end
  table.sort(out, function(a, b) return a.total > b.total end)
  for _, row in ipairs(out) do row.share = sum > 0 and row.total / sum * 100 or 0 end
  return out, true
end

-- Damage per target, added up over every spell. Empty when the game gives no split.
function Data.Targets(spellRows)
  local byName, out, sum = {}, {}, 0
  for _, sp in ipairs(spellRows) do
    for unit, amount in pairs(sp.targets or {}) do
      local row = byName[unit]
      if not row then
        row = { name = unit, total = 0 }
        byName[unit] = row
        out[#out + 1] = row
      end
      row.total = row.total + amount
      sum = sum + amount
    end
  end
  table.sort(out, function(a, b) return a.total > b.total end)
  for _, row in ipairs(out) do row.share = sum > 0 and row.total / sum * 100 or 0 end
  return out
end

-- Test bars: a made-up spell list for the detail panel.
local TEST_SPELLS = {
  { "Shadow Strike", "Interface\\Icons\\Ability_Rogue_ShadowStrikes", 0.31 },
  { "Eviscerate", "Interface\\Icons\\Ability_Rogue_Eviscerate", 0.22 },
  { "Rupture", "Interface\\Icons\\Ability_Rogue_Rupture", 0.14 },
  { "Melee", "Interface\\Icons\\INV_Sword_04", 0.11 },
  { "Shuriken Storm", "Interface\\Icons\\Ability_Rogue_ShurikenStorm", 0.09 },
  { "Secret Technique", "Interface\\Icons\\Ability_Rogue_SecretTechnique", 0.07 },
  { "Deadly Poison", "Interface\\Icons\\Ability_Rogue_DualWeild", 0.04 },
  { "Black Powder", "Interface\\Icons\\Ability_Rogue_BlackPowder", 0.02 },
}

function Data.TestSource(src)
  local spells = {}
  for i, def in ipairs(TEST_SPELLS) do
    local total = math.floor(src.totalAmount * def[3])
    spells[i] = {
      name = def[1], icon = def[2], total = total, perSecond = total / TEST_SECONDS,
      overkill = math.floor(total * 0.03), share = def[3] * 100,
      targets = { ["Training Boss"] = math.floor(total * 0.8), ["Shadow Add"] = total - math.floor(total * 0.8) },
    }
  end
  return spells
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
