-- The meter window. Rows draw Blizzard's values directly and rely on Blizzard's
-- order. Columns are a fixed width because text holding a secret can't be measured.

local _, ns = ...

local Window = {}
ns.Window = Window

local Data = ns.Data
local issecret = ns.issecret

local MEDIA = "Interface\\AddOns\\CZMeter\\Media\\"
local FONT = "Fonts\\FRIZQT__.TTF"
local ORANGE = { 0.96, 0.62, 0.23 }
local TEXT = { 0.91, 0.92, 0.95 }
local DIM = { 0.55, 0.58, 0.64 }
local ENEMY_COLOR = { 0.72, 0.30, 0.28 }
local DEFAULT_COLOR = { 0.45, 0.48, 0.55 }

local MIN_WIDTH, MAX_WIDTH = 460, 800
local ROW_HEIGHT, ROW_GAP = 28, 2
local TOP_HEIGHT = 92
local MAX_ROWS = 40
local TOP_CHOICES = { 5, 10, 20, 40 }

local frame
local rows = {}
local controls = {}

---------------------------------------------------------------------------
-- Small building blocks
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

local function Label(parent, size, color, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(FONT, size, "")
  fs:SetTextColor(color[1], color[2], color[3])
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  return fs
end

local function SetColor(fs, color)
  fs:SetTextColor(color[1], color[2], color[3])
end

-- A rounded button. active = filled orange text, otherwise quiet.
local function Pill(parent, width, text, onClick, height)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, height or 24)
  b.fill = Round(b, "Round", "BACKGROUND", 0.20, 0.22, 0.27, 0.9)
  b.line = Round(b, "RoundLine", "BORDER", 0.30, 0.32, 0.38, 0.9)
  b.label = Label(b, 12, TEXT, "CENTER")
  b.label:SetPoint("CENTER")
  b.label:SetText(text or "")
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(self)
    self.fill:SetVertexColor(0.27, 0.29, 0.35, 0.95)
    if self.tip then
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
    self:SetActive(self.active)
  end)
  function b:SetActive(on)
    self.active = on
    if on then
      self.fill:SetVertexColor(0.42, 0.28, 0.12, 0.95)
      self.line:SetVertexColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.5)
      SetColor(self.label, ORANGE)
    else
      self.fill:SetVertexColor(0.20, 0.22, 0.27, 0.9)
      self.line:SetVertexColor(0.30, 0.32, 0.38, 0.9)
      SetColor(self.label, TEXT)
    end
  end
  return b
end

local function IconPill(parent, file, tip, onClick)
  local b = Pill(parent, 30, "", onClick)
  b.tip = tip
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(file)
  icon:SetSize(16, 16)
  icon:SetPoint("CENTER")
  return b
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function CreateRow(index)
  local row = CreateFrame("Frame", nil, frame.body)
  row:SetHeight(ROW_HEIGHT)
  row:SetPoint("TOPLEFT", frame.body, "TOPLEFT", 0, -(index - 1) * (ROW_HEIGHT + ROW_GAP))
  row:SetPoint("TOPRIGHT", frame.body, "TOPRIGHT", 0, -(index - 1) * (ROW_HEIGHT + ROW_GAP))

  local back = row:CreateTexture(nil, "BACKGROUND")
  back:SetAllPoints()
  back:SetColorTexture(0, 0, 0, 0.28)

  row.bar = CreateFrame("StatusBar", nil, row)
  row.bar:SetAllPoints()
  row.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
  row.bar:SetMinMaxValues(0, 1)
  row.bar:SetValue(0)

  row.accent = row:CreateTexture(nil, "ARTWORK")
  row.accent:SetPoint("TOPLEFT")
  row.accent:SetPoint("BOTTOMLEFT")
  row.accent:SetWidth(3)

  row.layer = CreateFrame("Frame", nil, row)
  row.layer:SetAllPoints()
  row.layer:SetFrameLevel(row.bar:GetFrameLevel() + 2)

  row.rank = Label(row.layer, 12, DIM, "CENTER")
  row.rank:SetPoint("LEFT", 6, 0)
  row.rank:SetWidth(18)

  row.icon = row.layer:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(20, 20)
  row.icon:SetPoint("LEFT", 26, 0)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  row.name = Label(row.layer, 13, TEXT)
  row.name:SetPoint("LEFT", 52, 0)
  row.name:SetWidth(112)

  row.badge = CreateFrame("Frame", nil, row.layer)
  row.badge:SetSize(50, 18)
  row.badge:SetPoint("LEFT", 168, 0)
  Round(row.badge, "Round", "BACKGROUND", 0.05, 0.22, 0.26, 0.95)
  row.badgeText = Label(row.badge, 11, { 0.78, 0.92, 0.95 }, "CENTER")
  row.badgeText:SetPoint("CENTER")

  row.share = Label(row.layer, 12, TEXT, "RIGHT")
  row.share:SetPoint("RIGHT", -8, 0)
  row.share:SetWidth(50)

  row.dps = Label(row.layer, 12, TEXT, "RIGHT")
  row.dps:SetPoint("RIGHT", row.share, "LEFT", -6, 0)
  row.dps:SetWidth(74)

  row.value = Label(row.layer, 13, TEXT, "RIGHT")
  row.value:SetPoint("RIGHT", row.dps, "LEFT", -6, 0)
  row.value:SetWidth(62)

  row.me = Round(row.layer, "RoundLine", "OVERLAY", ORANGE[1], ORANGE[2], ORANGE[3], 0.9)
  row.me:Hide()

  row:Hide()
  return row
end

local function ClassColor(classFile)
  if classFile == nil or issecret(classFile) or classFile == "" then return DEFAULT_COLOR end
  local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
  return color and { color.r, color.g, color.b } or DEFAULT_COLOR
end

local function DrawName(fs, name)
  if name ~= nil and not issecret(name) and Ambiguate then
    fs:SetText(Ambiguate(name, "short"))
  else
    fs:SetText(name)
  end
end

local function DrawRow(row, src, rank, maxAmount, share, metric, isEnemyTab)
  row:Show()
  row.rank:SetText(rank)

  local color = isEnemyTab and ENEMY_COLOR or ClassColor(src.classFilename)
  row.bar:SetStatusBarColor(color[1] * 0.62, color[2] * 0.62, color[3] * 0.62, 0.85)
  row.accent:SetColorTexture(color[1], color[2], color[3], 1)
  local total = src.totalAmount
  if total == nil then total = 0 end
  if maxAmount == nil then maxAmount = 1 end
  row.bar:SetMinMaxValues(0, maxAmount)
  row.bar:SetValue(total)

  local icon = src.specIconID
  if icon ~= nil and not issecret(icon) and icon ~= 0 and not isEnemyTab then
    row.icon:SetTexture(icon)
    row.icon:Show()
  else
    row.icon:Hide()
  end

  DrawName(row.name, src.name)
  row.value:SetText(AbbreviateNumbers(total))

  -- Enemy rows merge units of one type and their per-second figure doesn't match the total.
  if metric.perSecond and not isEnemyTab and src.amountPerSecond ~= nil then
    row.dps:SetFormattedText("%s/s", AbbreviateNumbers(src.amountPerSecond))
  else
    row.dps:SetText("")
  end

  if share then
    row.share:SetFormattedText("%.1f%%", share)
  else
    row.share:SetText("")
  end

  local level = Data.ItemLevel(src.sourceGUID)
  if level and not isEnemyTab then
    row.badgeText:SetText(level)
    row.badge:Show()
  else
    row.badge:Hide()
  end

  row.me:SetShown(src.isLocalPlayer == true)
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
local function ChooseRows(list)
  local isEnemyTab = CZMeterDB.tab == "enemies"
  if CZMeterDB.myOnly and not isEnemyTab then
    for i, src in ipairs(list) do
      if src.isLocalPlayer == true then return { { src = src, rank = i } } end
    end
    return {}
  end
  local out = {}
  local limit = math.min(CZMeterDB.top, MAX_ROWS)
  for i, src in ipairs(list) do
    if i <= limit then
      out[#out + 1] = { src = src, rank = i }
    elseif src.isLocalPlayer == true and #out > 0 then
      -- Below the cut, so the last row shows you at your real rank.
      out[#out] = { src = src, rank = i }
      break
    end
  end
  return out
end

function Window.Refresh()
  if not frame or not frame:IsShown() then return end
  local list, maxAmount, duration, metric, best = Data.Read()
  local isEnemyTab = CZMeterDB.tab == "enemies" and not CZMeterDB.showBest
  local chosen = ChooseRows(list)
  local shares = Data.Shares(list)
  local shareOf = {}
  if shares then
    for i, src in ipairs(list) do shareOf[src] = shares[i] end
  end

  for i = 1, MAX_ROWS do
    local entry = chosen[i]
    local row = rows[i]
    if entry then
      row = row or CreateRow(i)
      rows[i] = row
      DrawRow(row, entry.src, entry.rank, maxAmount, shareOf[entry.src], metric, isEnemyTab)
    elseif row then
      row:Hide()
    end
  end

  frame.empty:SetShown(#chosen == 0)
  if CZMeterDB.showBest and not best then
    frame.empty:SetText("No best try for this boss yet.")
  else
    frame.empty:SetText("Nothing to show yet.")
  end

  local shown = math.max(#chosen, 1)
  frame:SetHeight(TOP_HEIGHT + shown * (ROW_HEIGHT + ROW_GAP) + 10)

  controls.metric.label:SetText(isEnemyTab and "Damage to enemies" or metric.label)
  frame.valueHeader:SetText(isEnemyTab and "DAMAGE" or metric.column)
  frame.dpsHeader:SetText((metric.perSecond and not isEnemyTab) and (metric.key == "DamageDone" and "DPS" or "PER SEC") or "")
  frame.nameHeader:SetText(isEnemyTab and "ENEMY" or "PLAYER")

  if CZMeterDB.view == "current" and not CZMeterDB.showBest and ns.combatStart then
    frame.timer:SetText(ns.Clock(GetTime() - ns.combatStart))
  elseif duration ~= nil and not issecret(duration) then
    frame.timer:SetText(ns.Clock(duration))
  else
    frame.timer:SetText("")
  end
end

local function RefreshControls()
  controls.myDps:SetActive(CZMeterDB.myOnly)
  controls.best:SetActive(CZMeterDB.showBest)
  controls.players:SetActive(CZMeterDB.tab ~= "enemies")
  controls.enemies:SetActive(CZMeterDB.tab == "enemies")
  controls.top.label:SetText("Top " .. CZMeterDB.top)
  local view = CZMeterDB.view
  if view == "overall" then
    controls.history.label:SetText("Overall")
  elseif type(view) == "number" then
    controls.history.label:SetText("History")
  else
    controls.history.label:SetText("Current")
  end
  Window.Refresh()
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
local function StepMetric(step)
  local count = #Data.METRICS
  CZMeterDB.metric = (CZMeterDB.metric - 1 + step) % count + 1
  RefreshControls()
end

local function OpenMetricMenu(owner)
  MenuUtil.CreateContextMenu(owner, function(_, root)
    for i, metric in ipairs(Data.METRICS) do
      root:CreateRadio(metric.label, function() return CZMeterDB.metric == i end, function()
        CZMeterDB.metric = i
        CZMeterDB.tab = "players"
        RefreshControls()
      end)
    end
  end)
end

local function OpenHistoryMenu(owner)
  MenuUtil.CreateContextMenu(owner, function(_, root)
    local function Add(label, value)
      root:CreateRadio(label, function() return CZMeterDB.view == value end, function()
        CZMeterDB.view = value
        CZMeterDB.showBest = false
        RefreshControls()
      end)
    end
    Add("Current", "current")
    Add("Overall", "overall")
    for _, entry in ipairs(Data.History()) do Add(entry.label, entry.id) end
  end)
end

local function CycleTop()
  local nextChoice = TOP_CHOICES[1]
  for i, choice in ipairs(TOP_CHOICES) do
    if choice == CZMeterDB.top then nextChoice = TOP_CHOICES[i % #TOP_CHOICES + 1] end
  end
  CZMeterDB.top = nextChoice
  RefreshControls()
end

local copyFrame
local function ShowCopy()
  if InCombatLockdown() then
    print("|cfff59e3bCZ Meter|r: the numbers can be copied once combat ends.")
    return
  end
  local list, _, duration, metric = Data.Read()
  local title = metric.label
  if duration ~= nil and not issecret(duration) then title = title .. " (" .. ns.Clock(duration) .. ")" end
  local lines = { title }
  local shares = Data.Shares(list)
  for i, src in ipairs(list) do
    if issecret(src.totalAmount) then break end
    if src.totalAmount == nil or issecret(src.name) then break end
    lines[#lines + 1] = string.format("%d. %s  %s%s", i, Ambiguate(src.name, "short"),
      AbbreviateNumbers(src.totalAmount), shares and string.format("  %.1f%%", shares[i]) or "")
  end
  if not copyFrame then
    copyFrame = CreateFrame("Frame", nil, UIParent)
    copyFrame:SetSize(360, 240)
    copyFrame:SetPoint("CENTER")
    copyFrame:SetFrameStrata("DIALOG")
    Round(copyFrame, "Round", "BACKGROUND", 0.09, 0.10, 0.13, 0.97)
    local title = Label(copyFrame, 12, ORANGE)
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Ctrl+C to copy, Esc to close")
    local scroll = CreateFrame("ScrollFrame", nil, copyFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -30)
    scroll:SetPoint("BOTTOMRIGHT", -30, 12)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetFontObject(ChatFontNormal)
    box:SetWidth(310)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
    scroll:SetScrollChild(box)
    copyFrame.box = box
  end
  copyFrame.box:SetText(table.concat(lines, "\n"))
  copyFrame:Show()
  copyFrame.box:SetFocus()
  copyFrame.box:HighlightText()
end

StaticPopupDialogs["CZMETER_RESET"] = {
  text = "Clear all of this character's meter history? This also clears Blizzard's meter.",
  button1 = YES,
  button2 = NO,
  OnAccept = function()
    pcall(C_DamageMeter.ResetAllCombatSessions)
    CZMeterDB.view = "current"
    RefreshControls()
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
local function SavePosition()
  local point, _, relativePoint, x, y = frame:GetPoint()
  CZMeterDB.pos = { point, relativePoint, x, y }
end

local function Build()
  frame = CreateFrame("Frame", "CZMeterWindow", UIParent)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:SetResizable(true)
  frame:SetResizeBounds(MIN_WIDTH, 100, MAX_WIDTH, 2000)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
  end)
  frame:SetWidth(CZMeterDB.width)
  local pos = CZMeterDB.pos
  if pos then
    frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
  end

  Round(frame, "Round", "BACKGROUND", 0.07, 0.08, 0.10, 0.88)
  Round(frame, "RoundLine", "BORDER", 0.25, 0.27, 0.32, 0.8)

  -- First line: metric, My DPS, Best try, timer
  local prev = CreateFrame("Button", nil, frame)
  prev:SetSize(20, 24)
  prev:SetPoint("TOPLEFT", 10, -8)
  prev.text = Label(prev, 16, TEXT, "CENTER")
  prev.text:SetPoint("CENTER")
  prev.text:SetText("<")
  prev:SetScript("OnClick", function() StepMetric(-1) end)

  local metricButton = CreateFrame("Button", nil, frame)
  metricButton:SetSize(150, 24)
  metricButton:SetPoint("LEFT", prev, "RIGHT", 2, 0)
  metricButton.label = Label(metricButton, 15, ORANGE)
  metricButton.label:SetPoint("LEFT", 2, 0)
  metricButton.label:SetWidth(128)
  local arrow = metricButton:CreateTexture(nil, "ARTWORK")
  arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
  arrow:SetSize(14, 14)
  arrow:SetPoint("RIGHT", 0, -2)
  arrow:SetVertexColor(ORANGE[1], ORANGE[2], ORANGE[3])
  metricButton:SetScript("OnClick", OpenMetricMenu)
  controls.metric = metricButton

  local nextMetric = CreateFrame("Button", nil, frame)
  nextMetric:SetSize(20, 24)
  nextMetric:SetPoint("LEFT", metricButton, "RIGHT", 2, 0)
  nextMetric.text = Label(nextMetric, 16, TEXT, "CENTER")
  nextMetric.text:SetPoint("CENTER")
  nextMetric.text:SetText(">")
  nextMetric:SetScript("OnClick", function() StepMetric(1) end)

  frame.timer = Label(frame, 13, DIM, "RIGHT")
  frame.timer:SetPoint("TOPRIGHT", -12, -13)
  frame.timer:SetWidth(44)

  controls.best = Pill(frame, 66, "Best try", function()
    CZMeterDB.showBest = not CZMeterDB.showBest
    RefreshControls()
  end)
  controls.best:SetPoint("TOPRIGHT", -60, -8)
  controls.best.tip = "The group's best pull on the last boss you fought, saved after combat."

  controls.myDps = Pill(frame, 62, "My DPS", function()
    CZMeterDB.myOnly = not CZMeterDB.myOnly
    RefreshControls()
  end)
  controls.myDps:SetPoint("RIGHT", controls.best, "LEFT", -6, 0)
  controls.myDps.tip = "Show only your own row."

  -- Second line: tabs, history, copy, top, reset
  controls.players = Pill(frame, 62, "Players", function()
    CZMeterDB.tab = "players"
    RefreshControls()
  end)
  controls.players:SetPoint("TOPLEFT", 10, -38)

  controls.enemies = Pill(frame, 66, "Enemies", function()
    CZMeterDB.tab = "enemies"
    CZMeterDB.showBest = false
    RefreshControls()
  end)
  controls.enemies:SetPoint("LEFT", controls.players, "RIGHT", 4, 0)
  controls.enemies.tip = "Group damage into each enemy type. Identical adds share one row."

  controls.reset = IconPill(frame, "Interface\\Buttons\\UI-RefreshButton", "Clear meter history", function()
    if InCombatLockdown() then return end
    StaticPopup_Show("CZMETER_RESET")
  end)
  controls.reset:SetPoint("TOPRIGHT", -10, -38)

  controls.top = Pill(frame, 56, "Top 5", CycleTop)
  controls.top:SetPoint("RIGHT", controls.reset, "LEFT", -6, 0)

  controls.copy = IconPill(frame, "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", "Copy these numbers", ShowCopy)
  controls.copy:SetPoint("RIGHT", controls.top, "LEFT", -6, 0)

  controls.history = Pill(frame, 74, "Current", OpenHistoryMenu)
  controls.history:SetPoint("RIGHT", controls.copy, "LEFT", -6, 0)

  -- Column headings, lined up with the row columns
  local head = CreateFrame("Frame", nil, frame)
  head:SetPoint("TOPLEFT", 10, -68)
  head:SetPoint("TOPRIGHT", -10, -68)
  head:SetHeight(18)
  frame.nameHeader = Label(head, 10, DIM)
  frame.nameHeader:SetPoint("LEFT", 52, 0)
  local shareHeader = Label(head, 10, DIM, "RIGHT")
  shareHeader:SetPoint("RIGHT", -8, 0)
  shareHeader:SetWidth(50)
  shareHeader:SetText("SHARE")
  frame.dpsHeader = Label(head, 10, DIM, "RIGHT")
  frame.dpsHeader:SetPoint("RIGHT", shareHeader, "LEFT", -6, 0)
  frame.dpsHeader:SetWidth(74)
  frame.valueHeader = Label(head, 10, DIM, "RIGHT")
  frame.valueHeader:SetPoint("RIGHT", frame.dpsHeader, "LEFT", -6, 0)
  frame.valueHeader:SetWidth(62)

  frame.body = CreateFrame("Frame", nil, frame)
  frame.body:SetPoint("TOPLEFT", 10, -TOP_HEIGHT + 4)
  frame.body:SetPoint("TOPRIGHT", -10, -TOP_HEIGHT + 4)
  frame.body:SetHeight(10)

  frame.empty = Label(frame.body, 12, DIM, "CENTER")
  frame.empty:SetPoint("TOP", 0, -6)

  -- Width grip
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetScript("OnMouseDown", function() frame:StartSizing("RIGHT") end)
  grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    CZMeterDB.width = math.floor(frame:GetWidth())
    SavePosition()
  end)

  -- A few redraws a second in combat is plenty; Blizzard's update event fires far faster.
  local waited = 0
  frame:SetScript("OnUpdate", function(_, elapsed)
    waited = waited + elapsed
    local gap = InCombatLockdown() and 0.25 or 1
    if waited >= gap then
      waited = 0
      Window.Refresh()
    end
  end)
end

function Window.Toggle()
  if not frame then
    Build()
    RefreshControls()
    frame:Show()
    CZMeterDB.shown = true
    return
  end
  frame:SetShown(not frame:IsShown())
  CZMeterDB.shown = frame:IsShown()
  Window.Refresh()
end

function Window.Open()
  if not frame then Build() end
  frame:Show()
  RefreshControls()
end
