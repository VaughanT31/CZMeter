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

---------------------------------------------------------------------------
-- Compare with the previous pull (0.5.0)
---------------------------------------------------------------------------
-- The fight a window shows and the newest earlier one with the same name
-- (the same boss), as session IDs: current, previous, name. Nil for the
-- overall view, test bars, best try, or a fight with no earlier try.
local function Pulls(win)
  if ns.testMode or win.showBest or win.view == "overall" then return nil end
  local ok, list = pcall(C_DamageMeter.GetAvailableCombatSessions)
  if not ok or type(list) ~= "table" then return nil end
  local byID, newest = {}, nil
  for _, entry in ipairs(list) do
    local id, name = entry.sessionID, entry.name
    if id ~= nil and not issecret(id) and name ~= nil and not issecret(name) and name ~= "" then
      byID[id] = name
      if not newest or id > newest then newest = id end
    end
  end
  local current = type(win.view) == "number" and win.view or newest
  local name = current and byID[current]
  if not name then return nil end
  local previous
  for id, other in pairs(byID) do
    if other == name and id < current and (not previous or id > previous) then previous = id end
  end
  if not previous then return nil end
  return current, previous, name
end

local function SourceAt(sessionID, meterKey, guid)
  local meterType = Enum.DamageMeterType[meterKey]
  if not meterType then return nil end
  local ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromID, sessionID, meterType, guid)
  if ok and type(src) == "table" then return src end
end

-- How a player did against their previous pull on the same boss, out of
-- combat only: { pct, name, up = { name, delta }, down = { name, delta } }.
-- pct compares per second when the metric has it, else the total.
function Data.Compare(win, guid)
  if guid == nil or issecret(guid) or InCombatLockdown() then return nil end
  local current, previous, name = Pulls(win)
  if not current then return nil end
  local metric = Data.Metric(win)
  if win.tab == "enemies" then return nil end
  local now, before = SourceAt(current, metric.key, guid), SourceAt(previous, metric.key, guid)
  if not now or not before then return nil end
  local field = metric.perSecond and "amountPerSecond" or "totalAmount"
  local a, b = now[field], before[field]
  if not Plain(a) or not Plain(b) or b <= 0 then return nil end
  local result = { pct = (a - b) / b * 100, name = name }

  -- The spells that changed most, by total.
  local spellsNow, readNow = Data.Spells(now)
  local spellsBefore, readBefore = Data.Spells(before)
  if readNow and readBefore then
    local delta = {}
    for _, sp in ipairs(spellsNow) do delta[sp.name] = (delta[sp.name] or 0) + sp.total end
    for _, sp in ipairs(spellsBefore) do delta[sp.name] = (delta[sp.name] or 0) - sp.total end
    for spell, d in pairs(delta) do
      if d > 0 and (not result.up or d > result.up.delta) then result.up = { name = spell, delta = d } end
      if d < 0 and (not result.down or d < result.down.delta) then result.down = { name = spell, delta = d } end
    end
  end
  return result
end

-- "+4.2% vs last pull" in green, or red when lower.
function Data.CompareText(cmp)
  if not cmp then return nil end
  local color = cmp.pct >= 0 and "|cff66dd77" or "|cffff6655"
  return string.format("%s%+.1f%%|r vs last pull", color, cmp.pct)
end

-- "Eviscerate +1.2M, Rupture -300K"
function Data.CompareSpellsText(cmp)
  if not cmp then return nil end
  local parts = {}
  if cmp.up then parts[#parts + 1] = cmp.up.name .. " |cff66dd77+" .. AbbreviateNumbers(cmp.up.delta) .. "|r" end
  if cmp.down then parts[#parts + 1] = cmp.down.name .. " |cffff6655-" .. AbbreviateNumbers(-cmp.down.delta) .. "|r" end
  return #parts > 0 and table.concat(parts, ", ") or nil
end

function ns.Clock(seconds)
  seconds = math.max(0, math.floor(seconds))
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

---------------------------------------------------------------------------
-- Best try: the group's best DPS per boss and difficulty, saved after combat
---------------------------------------------------------------------------
local pendingKey, lastKey
local pendingKill, pendingWipe, pendingDifficulty

function Data.EncounterEnded(encounterID, name, difficultyID, success)
  pendingKey = encounterID .. ":" .. difficultyID
  lastKey = pendingKey
  Data.pendingName = name
  pendingKill = success == 1
  pendingWipe = success == 0
  pendingDifficulty = difficultyID
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

  local kill, wipe = pendingKill, pendingWipe
  pendingKill, pendingWipe = nil, nil
  if kill then Data.SavePersonalBest(key, session, duration) end
  if wipe then Data.WipeSummary() end
end

---------------------------------------------------------------------------
-- Personal bests (0.6.0): your own DPS and HPS per boss, difficulty and
-- spec, saved after each kill. Dungeon bosses count one by one, which
-- Raider.IO and Warcraft Logs only show as the whole run.
--   CZMeterDB.pb["encounterID:difficultyID:specID"] = { name, dps, hps,
--     duration, when, level (Mythic+ key level), spec }
---------------------------------------------------------------------------
local PREFIX = "|cfff59e3bCZ Meter|r: "

local function SpecNow()
  local ok, index = pcall(GetSpecialization)
  if ok and index then
    local ok2, id, specName = pcall(GetSpecializationInfo, index)
    if ok2 and id then return id, specName end
  end
  local _, class = UnitClass("player")
  return class or "?", UnitClass("player")
end

local function IsHealer()
  local ok, index = pcall(GetSpecialization)
  if not ok or not index then return false end
  local ok2, role = pcall(GetSpecializationRole, index)
  return ok2 and role == "HEALER"
end

local function KeyLevel()
  if not C_ChallengeMode or not C_ChallengeMode.GetActiveKeystoneInfo then return nil end
  local ok, level = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
  if ok and type(level) == "number" and level > 0 then return level end
end

-- Your per-second amount in a meter's current session, or nil.
local function MinePerSecond(meterType, duration)
  local ok, s = pcall(C_DamageMeter.GetCombatSessionFromType, Enum.DamageMeterSessionType.Current, meterType)
  if not ok or type(s) ~= "table" then return nil end
  for _, src in ipairs(s.combatSources or {}) do
    if src.isLocalPlayer == true then
      local total = src.totalAmount
      if total == nil or issecret(total) then return nil end
      return total / duration
    end
  end
  return 0
end

local function DifficultyName(id)
  local ok, name = pcall(GetDifficultyInfo, id)
  return ok and name or nil
end

function Data.PersonalBestKey(encounterKey)
  return encounterKey .. ":" .. tostring((SpecNow()))
end

function Data.SavePersonalBest(encounterKey, session, duration)
  if not CZMeterDB.pb then CZMeterDB.pb = {} end
  local dps = MinePerSecond(Enum.DamageMeterType.DamageDone, duration)
  local hps = MinePerSecond(Enum.DamageMeterType.HealingDone, duration)
  if not dps then return end
  local healer = IsHealer()
  local mine = healer and hps or dps
  if not mine or mine <= 0 then return end
  local specID, specName = SpecNow()
  local key = encounterKey .. ":" .. tostring(specID)
  local old = CZMeterDB.pb[key]
  local oldMine = old and (healer and old.hps or old.dps)
  local metric = healer and "HPS" or "DPS"
  local where = Data.pendingName .. (DifficultyName(pendingDifficulty) and (" (" .. DifficultyName(pendingDifficulty) .. ")") or "")
  if not oldMine or mine > oldMine then
    CZMeterDB.pb[key] = {
      name = Data.pendingName, dps = dps, hps = hps, duration = duration,
      when = time(), level = KeyLevel(), spec = specName,
    }
    if CZMeterDB.opt.pbChat then
      if oldMine and oldMine > 0 then
        print(PREFIX .. string.format("new personal best on %s: %s %s, up %.1f%% from %s.",
          where, AbbreviateNumbers(mine), metric, (mine - oldMine) / oldMine * 100, AbbreviateNumbers(oldMine)))
      else
        print(PREFIX .. string.format("first kill saved for %s: %s %s.", where, AbbreviateNumbers(mine), metric))
      end
    end
  elseif CZMeterDB.opt.pbChat then
    print(PREFIX .. string.format("%s: %s %s, %.1f%% under your best (%s).",
      where, AbbreviateNumbers(mine), metric, (oldMine - mine) / oldMine * 100, AbbreviateNumbers(oldMine)))
  end
end

-- "Your best here: 1.2M DPS" for your own row, on the boss last fought.
function Data.PersonalBestText(src)
  if not src or src.isLocalPlayer ~= true or not lastKey or not CZMeterDB.pb then return nil end
  local pb = CZMeterDB.pb[Data.PersonalBestKey(lastKey)]
  if not pb then return nil end
  local healer = IsHealer()
  local value = healer and pb.hps or pb.dps
  if not value or value <= 0 then return nil end
  return string.format("Your best on %s: %s %s%s", pb.name or "this boss", AbbreviateNumbers(value),
    healer and "HPS" or "DPS", pb.level and (" (+" .. pb.level .. ")") or "")
end

-- Your personal bests for the spec you're in, newest first, as lines.
function Data.PersonalBestLines()
  local specID = tostring((SpecNow()))
  local list = {}
  for key, pb in pairs(CZMeterDB.pb or {}) do
    local encounter, difficulty, spec = key:match("^(%d+):(%d+):(.+)$")
    if spec == specID then
      list[#list + 1] = { pb = pb, difficulty = tonumber(difficulty) }
    end
  end
  table.sort(list, function(a, b) return (a.pb.when or 0) > (b.pb.when or 0) end)
  local lines = {}
  for _, e in ipairs(list) do
    local pb = e.pb
    local diff = DifficultyName(e.difficulty)
    lines[#lines + 1] = string.format("%s%s: %s DPS%s%s", pb.name or "?", diff and (" (" .. diff .. ")") or "",
      AbbreviateNumbers(pb.dps or 0), (pb.hps or 0) > 0 and (", " .. AbbreviateNumbers(pb.hps) .. " HPS") or "",
      pb.level and (", +" .. pb.level) or "")
  end
  return lines
end

---------------------------------------------------------------------------
-- Death recap (0.6.0): the last hits before a death, from Blizzard's own
-- death recap (each death on the meter has one).
---------------------------------------------------------------------------
-- Newest first: { { name, icon, amount, overkill, caster, hp, ago, killing } }, or nil.
function Data.DeathRecap(recapID)
  if not recapID or recapID == 0 or issecret(recapID) or not C_DeathRecap then return nil end
  local ok, events = pcall(C_DeathRecap.GetRecapEvents, recapID)
  if not ok or type(events) ~= "table" or #events == 0 then return nil end
  local okMax, maxHealth = pcall(C_DeathRecap.GetRecapMaxHealth, recapID)
  if not okMax or not Plain(maxHealth) or maxHealth <= 0 then maxHealth = nil end
  local last = 0
  for _, e in ipairs(events) do
    if Plain(e.timestamp) and e.timestamp > last then last = e.timestamp end
  end
  local list = {}
  for i, e in ipairs(events) do
    local name, icon = e.spellName, nil
    if e.event == "SWING_DAMAGE" then
      name = ACTION_SWING or "Melee"
      icon = 132223
    elseif e.event == "ENVIRONMENTAL_DAMAGE" and e.environmentalType then
      name = _G["ACTION_ENVIRONMENTAL_DAMAGE_" .. string.upper(e.environmentalType)] or e.environmentalType
    end
    if not icon and e.spellId and C_Spell and C_Spell.GetSpellTexture then
      local okIcon, tex = pcall(C_Spell.GetSpellTexture, e.spellId)
      if okIcon then icon = tex end
    end
    list[#list + 1] = {
      name = name or "?", icon = icon,
      amount = Plain(e.amount) and e.amount or nil,
      overkill = Plain(e.overkill) and e.overkill > 0 and e.overkill or nil,
      caster = e.sourceName,
      hp = maxHealth and Plain(e.currentHP) and math.floor(e.currentHP / maxHealth * 100) or nil,
      ago = Plain(e.timestamp) and last - e.timestamp or nil,
      killing = i == 1,
    }
  end
  return list
end

-- After a wipe, one chat line per death in order: who, what killed them,
-- and when in the fight.
function Data.WipeSummary()
  if not CZMeterDB.opt.deathSummary then return end
  local ok, s = pcall(C_DamageMeter.GetCombatSessionFromType, Enum.DamageMeterSessionType.Current, Enum.DamageMeterType.Deaths)
  if not ok or type(s) ~= "table" then return end
  local deaths = {}
  for _, src in ipairs(s.combatSources or {}) do
    local at, id = src.deathTimeSeconds, src.deathRecapID
    if id and id ~= 0 and Plain(at) and src.name and not issecret(src.name) then
      deaths[#deaths + 1] = { name = src.name, at = at, id = id }
    end
  end
  if #deaths == 0 then return end
  table.sort(deaths, function(a, b) return a.at < b.at end)
  print(PREFIX .. "deaths on " .. (Data.pendingName or "that pull") .. ":")
  for i, d in ipairs(deaths) do
    if i > 8 then
      print(PREFIX .. string.format("  and %d more. Open the Deaths meter for all of them.", #deaths - 8))
      break
    end
    local recap = Data.DeathRecap(d.id)
    local blow = recap and recap[1]
    local what = blow and (blow.name .. (blow.caster and (" (" .. blow.caster .. ")") or "")) or "unknown"
    local name = Ambiguate and Ambiguate(d.name, "short") or d.name
    print(PREFIX .. string.format("  %s %s - %s", ns.Clock(d.at), name, what))
  end
end

---------------------------------------------------------------------------
-- Item levels: inspected out of combat, shown when the row can be identified
---------------------------------------------------------------------------
-- Saved between sessions (CZMeterDB.itemLevels[guid] = { l = level, t = when,
-- s = stale }). Read once per player and kept for the whole key or raid:
-- inside an instance nobody known is inspected again. Leaving the instance
-- marks them stale, so they're read again (the old number shows until then).
local itemLevels = {}
local queue = {}
local KEEP_DAYS = 7

function Data.UseSavedItemLevels(saved)
  itemLevels = saved
  local cutoff = time() - KEEP_DAYS * 86400
  for guid, entry in pairs(itemLevels) do
    if type(entry) ~= "table" or (entry.t or 0) < cutoff then
      itemLevels[guid] = nil
    elseif time() - (entry.t or 0) > 86400 then
      entry.s = true
    end
  end
end

function Data.MarkItemLevelsStale()
  for _, entry in pairs(itemLevels) do entry.s = true end
end

local function InInstance()
  local inInstance, kind = IsInInstance()
  return inInstance and (kind == "party" or kind == "raid")
end
local inspecting
local INSPECT_GAP = 2
local lastInspect = 0

function Data.ItemLevel(guid)
  if guid == nil or issecret(guid) then return nil end
  local entry = itemLevels[guid]
  return entry and entry.l
end

function Data.ReadOwnItemLevel()
  local _, equipped = GetAverageItemLevel()
  local guid = UnitGUID("player")
  if equipped ~= nil and not issecret(equipped) and guid then itemLevels[guid] = { l = math.floor(equipped), t = time() } end
end

function Data.QueueGroup()
  wipe(queue)
  local prefix, count = "party", GetNumSubgroupMembers()
  if IsInRaid() then prefix, count = "raid", GetNumGroupMembers() end
  for i = 1, count do
    local unit = prefix .. i
    local guid = UnitGUID(unit)
    local known = guid and itemLevels[guid]
    -- Unknown, or stale while out of an instance.
    local want = not known or (known.s and not InInstance())
    if guid and not issecret(guid) and want and not UnitIsUnit(unit, "player") then
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
      if level ~= nil and not issecret(level) and level > 0 then itemLevels[guid] = { l = math.floor(level), t = time() } end
      break
    end
  end
  ClearInspectPlayer()
end
