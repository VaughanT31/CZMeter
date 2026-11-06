-- Player detail panel: click a row in any window to open it. Shows that player's
-- totals for the window's metric and view, with Spells, Targets and Defense tabs.
-- In combat most values are secret, so rows are drawn as Blizzard gives them and
-- anything worked out (shares, ranks, merging) waits until combat ends.

local _, ns = ...

local Detail = {}
ns.Detail = Detail

local Data, Skins = ns.Data, ns.Skins
local issecret = ns.issecret
local Plain = Data.Plain

local MEDIA = "Interface\\AddOns\\CZMeter\\Media\\"
local WIDTH, HEIGHT = 480, 470
local ROW_HEIGHT, ROW_GAP = 20, 1
local LIST_ROWS = 14
local DEFAULT_COLOR = { 0.45, 0.48, 0.55 }

-- The other meters shown on the Defense tab, with their label.
local DEFENSE = {
  { "DamageTaken", "Damage taken" }, { "AvoidableDamageTaken", "Avoidable damage" },
  { "Absorbs", "Absorbs" }, { "HealingDone", "Healing done" },
  { "Interrupts", "Interrupts" }, { "Dispels", "Dispels" }, { "Deaths", "Deaths" },
}

local panel
local state = { tab = "spells", offset = 0 }

---------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------
local function Round(parent, file, layer, r, g, b, a)
  local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
  tex:SetTexture(MEDIA .. file)
  tex:SetTextureSliceMargins(8, 8, 8, 8)
  tex:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
  tex:SetVertexColor(r, g, b, a)
  tex:SetAllPoints()
  return tex
end

local function Label(parent, size, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont("Fonts\\FRIZQT__.TTF", size, "")
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  return fs
end

local function Color(fs, c)
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

local function ClassColor(classFile)
  if classFile == nil or issecret(classFile) or classFile == "" then return DEFAULT_COLOR end
  local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
  return color and { color.r, color.g, color.b } or DEFAULT_COLOR
end

local function Tab(parent, text, key)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(80, 20)
  b.fill = Round(b, "Round", "BACKGROUND", 0.20, 0.22, 0.27, 0.9)
  b.line = Round(b, "RoundLine", "BORDER", 0.30, 0.32, 0.38, 0.9)
  b.label = Label(b, 10, "CENTER")
  b.label:SetPoint("CENTER")
  b.label:SetText(text)
  b.key = key
  b:SetScript("OnClick", function()
    state.tab = key
    state.offset = 0
    Detail.Refresh(true)
  end)
  return b
end

local function StatBox(parent)
  local box = CreateFrame("Frame", nil, parent)
  box:SetSize(104, 40)
  Round(box, "Round", "BACKGROUND", 0.12, 0.13, 0.16, 0.95)
  box.label = Label(box, 9)
  box.label:SetPoint("TOPLEFT", 8, -6)
  box.value = Label(box, 14)
  box.value:SetPoint("BOTTOMLEFT", 8, 6)
  box.value:SetWidth(90)
  return box
end

---------------------------------------------------------------------------
-- List rows
---------------------------------------------------------------------------
local function CreateRow(index)
  local row = CreateFrame("Frame", nil, panel.list)
  row:SetHeight(ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, -(index - 1) * (ROW_HEIGHT + ROW_GAP))
  row:SetPoint("TOPRIGHT", 0, -(index - 1) * (ROW_HEIGHT + ROW_GAP))
  row:EnableMouse(true)

  row.back = row:CreateTexture(nil, "BACKGROUND")
  row.back:SetAllPoints()
  row.back:SetColorTexture(0, 0, 0, 0.28)

  row.bar = CreateFrame("StatusBar", nil, row)
  row.bar:SetAllPoints()
  row.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
  row.bar:SetMinMaxValues(0, 1)

  row.layer = CreateFrame("Frame", nil, row)
  row.layer:SetAllPoints()
  row.layer:SetFrameLevel(row.bar:GetFrameLevel() + 2)

  row.icon = row.layer:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(16, 16)
  row.icon:SetPoint("LEFT", 3, 0)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  row.share = Label(row.layer, 11, "RIGHT")
  row.share:SetPoint("RIGHT", -6, 0)
  row.share:SetWidth(48)
  row.dps = Label(row.layer, 11, "RIGHT")
  row.dps:SetPoint("RIGHT", row.share, "LEFT", -4, 0)
  row.dps:SetWidth(64)
  row.value = Label(row.layer, 12, "RIGHT")
  row.value:SetPoint("RIGHT", row.dps, "LEFT", -4, 0)
  row.value:SetWidth(60)
  row.name = Label(row.layer, 12)
  row.name:SetPoint("LEFT", 24, 0)
  row.name:SetPoint("RIGHT", row.value, "LEFT", -4, 0)

  row:SetScript("OnEnter", function(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    for i, line in ipairs(self.tip) do
      if i == 1 then GameTooltip:SetText(line, 1, 1, 1) else GameTooltip:AddLine(line, 0.8, 0.82, 0.86, true) end
    end
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row:EnableMouseWheel(true)
  row:SetScript("OnMouseWheel", function(_, delta) Detail.Scroll(delta) end)
  return row
end

-- entry: { name, icon, total, perSecond, share, max, color, header, tip, rankText }
local function DrawRow(row, entry, accent)
  row:Show()
  row.tip = entry.tip
  if entry.header then
    row.bar:SetValue(0)
    row.back:SetColorTexture(0, 0, 0, 0)
    row.icon:Hide()
    row.name:SetText(entry.name)
    Color(row.name, accent)
    row.value:SetText("")
    row.dps:SetText("")
    row.share:SetText("")
    return
  end
  row.back:SetColorTexture(0, 0, 0, 0.28)
  Color(row.name, { 0.91, 0.92, 0.95 })
  local color = entry.color or DEFAULT_COLOR
  row.bar:SetStatusBarColor(color[1] * 0.62, color[2] * 0.62, color[3] * 0.62, 0.85)
  local total = entry.total
  if total == nil then total = 0 end
  local max = entry.max
  if max == nil then max = 1 end
  row.bar:SetMinMaxValues(0, max)
  if entry.noBar then row.bar:SetValue(0) else row.bar:SetValue(total) end
  if entry.icon ~= nil and pcall(row.icon.SetTexture, row.icon, entry.icon) then
    row.icon:Show()
  else
    row.icon:Hide()
  end
  row.name:SetText(entry.name)
  row.value:SetText(ns.Num(total))
  if entry.perSecond ~= nil then
    row.dps:SetFormattedText("%s/s", AbbreviateNumbers(entry.perSecond))
  else
    row.dps:SetText(entry.rankText or "")
  end
  if Plain(entry.share) then
    row.share:SetFormattedText("%.1f%%", entry.share)
  else
    row.share:SetText("")
  end
end

---------------------------------------------------------------------------
-- Building each tab's rows
---------------------------------------------------------------------------
local function SpellTip(sp)
  local tip = { sp.name }
  if Plain(sp.overkill) and sp.overkill > 0 then tip[#tip + 1] = "Overkill: " .. ns.Num(sp.overkill) end
  if sp.avoidable then tip[#tip + 1] = "Avoidable" end
  if sp.deadly then tip[#tip + 1] = "Deadly" end
  local targets = {}
  for unit, amount in pairs(sp.targets or {}) do targets[#targets + 1] = { unit, amount } end
  table.sort(targets, function(a, b) return a[2] > b[2] end)
  for i, t in ipairs(targets) do
    if i > 6 then break end
    tip[#tip + 1] = t[1] .. ": " .. ns.Num(t[2])
  end
  if sp.ids and #sp.ids > 1 then tip[#tip + 1] = "Merged from " .. #sp.ids .. " spell IDs" end
  return #tip > 1 and tip or nil
end

local function SpellEntries(spells, max, color, perSecond)
  local out = {}
  for _, sp in ipairs(spells) do
    out[#out + 1] = {
      name = sp.name, icon = sp.icon, total = sp.total, share = sp.share, max = max, color = color,
      perSecond = perSecond and sp.perSecond or nil, tip = SpellTip(sp),
    }
  end
  return out
end

local function MaxOf(rows, fallback)
  local max = 0
  for _, r in ipairs(rows) do
    if not Plain(r.total) then return fallback end
    if r.total > max then max = r.total end
  end
  return max > 0 and max or 1
end

-- Rank of guid in a meter's rows, readable values only.
local function RankIn(rows, guid)
  for i, src in ipairs(rows) do
    if src.sourceGUID ~= nil and not issecret(src.sourceGUID) and src.sourceGUID == guid then
      return i, src
    end
  end
end

local function Build(info)
  local win, src, metric = info.win, info.src, info.metric
  local color = ClassColor(src.classFilename)
  local entries, note = {}, nil

  local spells, readable
  if ns.testMode then
    spells, readable = Data.TestSource(src), true
  else
    spells, readable = Data.Spells(Data.ReadSource(win, metric.key, info.guid))
  end

  if state.tab == "spells" then
    if #spells == 0 then
      note = "No spell breakdown for this player and metric."
    else
      entries = SpellEntries(spells, readable and MaxOf(spells, 1) or src.totalAmount, color, metric.perSecond)
      if not readable then note = "Spell names, shares and order settle once combat ends." end
    end

  elseif state.tab == "targets" then
    if not readable then
      note = "Targets show once combat ends."
    else
      local targets = Data.Targets(spells)
      if #targets == 0 then
        note = "The game doesn't split this metric by target. Try the Enemies tab in the window for damage into each enemy type."
      else
        local max = MaxOf(targets, 1)
        for _, t in ipairs(targets) do
          entries[#entries + 1] = { name = t.name, total = t.total, share = t.share, max = max, color = color }
        end
      end
    end

  else -- defense
    if InCombatLockdown() and not ns.testMode then
      note = "Defense totals show once combat ends."
    else
      for _, def in ipairs(DEFENSE) do
        local rows, total, rank, count
        if ns.testMode then
          total, rank, count = math.floor((src.totalAmount or 0) * 0.08), 4, 25
          if def[1] == "Deaths" or def[1] == "Interrupts" or def[1] == "Dispels" then total = 1 end
        else
          rows = Data.ReadMeter(win, def[1])
          local found
          rank, found = RankIn(rows, info.guid)
          total, count = found and found.totalAmount or 0, #rows
        end
        entries[#entries + 1] = {
          name = def[2], total = total, color = color, max = 1, noBar = true,
          rankText = rank and string.format("#%d of %d", rank, count) or "",
        }
      end
      local taken = ns.testMode and Data.TestSource({ totalAmount = (src.totalAmount or 0) * 0.08 })
        or Data.Spells(Data.ReadSource(win, "DamageTaken", info.guid))
      if #taken > 0 then
        entries[#entries + 1] = { header = true, name = "Damage taken by spell" }
        local max = MaxOf(taken, 1)
        for i, sp in ipairs(taken) do
          if i > 10 then break end
          entries[#entries + 1] = {
            name = sp.name, icon = sp.icon, total = sp.total, share = sp.share, max = max,
            color = sp.avoidable and { 0.85, 0.35, 0.30 } or { 0.55, 0.58, 0.64 }, tip = SpellTip(sp),
          }
        end
      end
    end
  end
  return entries, note
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local function BuildPanel()
  panel = CreateFrame("Frame", "CZMeterDetail", UIParent)
  panel:SetSize(WIDTH, HEIGHT)
  panel:SetPoint("CENTER", -200, 40)
  panel:SetFrameStrata("HIGH")
  panel:SetClampedToScreen(true)
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:EnableMouseWheel(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  panel:SetScript("OnMouseWheel", function(_, delta) Detail.Scroll(delta) end)
  tinsert(UISpecialFrames, "CZMeterDetail")
  panel.bg = Round(panel, "Round", "BACKGROUND", 0.07, 0.08, 0.10, 0.95)
  panel.border = Round(panel, "RoundLine", "BORDER", 0.25, 0.27, 0.32, 0.9)

  panel.spec = panel:CreateTexture(nil, "ARTWORK")
  panel.spec:SetSize(28, 28)
  panel.spec:SetPoint("TOPLEFT", 14, -12)
  panel.spec:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  panel.name = Label(panel, 16)
  panel.name:SetPoint("TOPLEFT", 50, -12)
  panel.name:SetWidth(WIDTH - 110)
  panel.sub = Label(panel, 10)
  panel.sub:SetPoint("TOPLEFT", 50, -32)
  panel.sub:SetWidth(WIDTH - 110)

  local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)

  panel.stats = {}
  for i = 1, 4 do
    local box = StatBox(panel)
    box:SetPoint("TOPLEFT", 14 + (i - 1) * 114, -54)
    panel.stats[i] = box
  end

  panel.tabs = {}
  for i, def in ipairs({ { "Spells", "spells" }, { "Targets", "targets" }, { "Defense", "defense" } }) do
    local b = Tab(panel, def[1], def[2])
    b:SetPoint("TOPLEFT", 14 + (i - 1) * 84, -104)
    panel.tabs[i] = b
  end

  panel.list = CreateFrame("Frame", nil, panel)
  panel.list:SetPoint("TOPLEFT", 14, -132)
  panel.list:SetPoint("TOPRIGHT", -14, -132)
  panel.list:SetHeight(LIST_ROWS * (ROW_HEIGHT + ROW_GAP))
  panel.rows = {}

  panel.note = Label(panel, 10)
  panel.note:SetPoint("BOTTOMLEFT", 14, 12)
  panel.note:SetWidth(WIDTH - 28)
  panel.note:SetWordWrap(true)
  panel.note:SetJustifyV("BOTTOM")
end

function Detail.Scroll(delta)
  state.offset = state.offset - delta * CZMeterDB.opt.wheel
  Detail.Refresh(true)
end

local REDRAW_GAP = 1 -- spell lookups and sorting are the heaviest work here
local lastDraw = 0

-- force: redraw now (clicks, tabs, scrolling). Otherwise at most once a second.
function Detail.Refresh(force)
  if not panel or not panel:IsShown() or not state.info then return end
  local now = GetTime()
  if not force and now - lastDraw < REDRAW_GAP then return end
  lastDraw = now
  local info = state.info
  local skin = info.win.skin or Skins.Get("Default")
  local accent, dim = skin.accent, skin.dim
  local src, metric = info.src, info.metric

  for _, b in ipairs(panel.tabs) do
    local on = b.key == state.tab
    if on then
      b.fill:SetVertexColor(accent[1] * 0.45, accent[2] * 0.45, accent[3] * 0.45, 0.95)
      b.line:SetVertexColor(accent[1], accent[2], accent[3], 0.5)
      Color(b.label, accent)
    else
      b.fill:SetVertexColor(0.20, 0.22, 0.27, 0.9)
      b.line:SetVertexColor(0.30, 0.32, 0.38, 0.9)
      Color(b.label, { 0.91, 0.92, 0.95 })
    end
  end

  -- Header from the window's latest copy of this row: found again by GUID when
  -- readable, or by name for test bars (they're rebuilt on every read).
  local list = Data.Read(info.win.db)
  local rank, found
  if ns.testMode then
    for i, row in ipairs(list) do
      if row.name == src.name then rank, found = i, row break end
    end
  elseif info.guid then
    rank, found = RankIn(list, info.guid)
  end
  if found then src, info.src, info.rank = found, found, rank end

  local name = src.name
  if name ~= nil and not issecret(name) and Ambiguate then name = Ambiguate(name, "short") end
  panel.name:SetText(name)
  Color(panel.name, ClassColor(src.classFilename))
  local icon = src.specIconID
  if icon ~= nil and not issecret(icon) and icon ~= 0 then
    panel.spec:SetTexture(icon)
    panel.spec:Show()
  else
    panel.spec:Hide()
  end
  local view = info.win.db.view
  local viewText = ns.testMode and "test bars" or view == "overall" and "overall" or type(view) == "number" and "earlier pull" or "current fight"
  panel.sub:SetText(metric.label .. ", " .. viewText)
  Color(panel.sub, dim)

  local shares = Data.Shares(list)
  local share
  if shares then
    for i, row in ipairs(list) do
      if row == src then share = shares[i] end
    end
  end
  local stats = {
    { metric.column, ns.Num(src.totalAmount) },
    { metric.perSecond and "PER SECOND" or "", metric.perSecond and src.amountPerSecond ~= nil and AbbreviateNumbers(src.amountPerSecond) or "" },
    { "SHARE", share and string.format("%.1f%%", share) or "" },
    { "RANK", info.rank and string.format("#%d of %d", info.rank, #list) or "" },
  }
  for i, box in ipairs(panel.stats) do
    box.label:SetText(stats[i][1])
    Color(box.label, dim)
    box.value:SetText(stats[i][2])
    Color(box.value, { 0.91, 0.92, 0.95 })
  end

  local entries, note = Build(info)
  state.offset = math.max(0, math.min(state.offset, #entries - LIST_ROWS))
  for i = 1, LIST_ROWS do
    local entry = entries[i + state.offset]
    local row = panel.rows[i]
    if entry then
      row = row or CreateRow(i)
      panel.rows[i] = row
      DrawRow(row, entry, accent)
    elseif row then
      row:Hide()
    end
  end
  panel.note:SetText(note or (#entries > LIST_ROWS and "Scroll for more." or ""))
  Color(panel.note, dim)
end

-- Opens the panel for a row of a window. rank is the row's place in the list.
function Detail.Open(w, src, rank)
  if w.db.tab == "enemies" and not ns.testMode then
    print("|cfff59e3bCZ Meter|r: enemy rows don't have a breakdown. Click a player.")
    return
  end
  if w.db.showBest and not ns.testMode then
    print("|cfff59e3bCZ Meter|r: best try only keeps totals. Switch to Current or History for details.")
    return
  end
  local guid = src.sourceGUID
  if guid ~= nil and issecret(guid) then
    guid = src.isLocalPlayer == true and UnitGUID("player") or nil
  end
  if guid == nil and not ns.testMode then
    print("|cfff59e3bCZ Meter|r: other players' details open once combat ends.")
    return
  end
  if not panel then BuildPanel() end
  if not state.info or state.info.guid ~= guid then state.offset = 0 end
  state.info = { win = w, src = src, guid = guid, rank = rank, metric = Data.Metric(w.db) }
  panel:Show()
  Detail.Refresh(true)
end

function Detail.Hide()
  if panel then panel:Hide() end
end
