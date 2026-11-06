-- Hover card: a short version of the detail panel that shows above the window
-- while the mouse is over a row. Totals and the top spells only; a click still
-- opens the full panel. In combat other players' values are secret: they're
-- drawn as Blizzard gives them, and anything worked out waits for combat to end.

local _, ns = ...

local Hover = {}
ns.Hover = Hover

local Data, Skins = ns.Data, ns.Skins
local issecret = ns.issecret
local Plain = Data.Plain

local MEDIA = "Interface\\AddOns\\CZMeter\\Media\\"
local WIDTH = 290
local PAD = 10
local ROW_HEIGHT, ROW_GAP = 18, 2
local MAX_SPELLS = 8
local TOP_HEIGHT = 74 -- header and stats, above the spell rows
local REDRAW_GAP = 0.5
local DEFAULT_COLOR = { 0.45, 0.48, 0.55 }
local TEXT = { 0.91, 0.92, 0.95 }

local card
local hovered -- { win, row }
local sinceDraw = 0

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

local function CreateSpellRow(index)
  local row = CreateFrame("Frame", nil, card)
  row:SetHeight(ROW_HEIGHT)
  local y = -(TOP_HEIGHT + (index - 1) * (ROW_HEIGHT + ROW_GAP))
  row:SetPoint("TOPLEFT", PAD, y)
  row:SetPoint("TOPRIGHT", -PAD, y)

  local back = row:CreateTexture(nil, "BACKGROUND")
  back:SetAllPoints()
  back:SetColorTexture(0, 0, 0, 0.28)

  row.bar = CreateFrame("StatusBar", nil, row)
  row.bar:SetAllPoints()
  row.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
  row.bar:SetMinMaxValues(0, 1)

  local layer = CreateFrame("Frame", nil, row)
  layer:SetAllPoints()
  layer:SetFrameLevel(row.bar:GetFrameLevel() + 2)

  row.icon = layer:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ROW_HEIGHT - 2, ROW_HEIGHT - 2)
  row.icon:SetPoint("LEFT", 1, 0)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  row.share = Label(layer, 10, "RIGHT")
  row.share:SetPoint("RIGHT", -4, 0)
  row.share:SetWidth(42)
  row.value = Label(layer, 10, "RIGHT")
  row.value:SetPoint("RIGHT", row.share, "LEFT", -4, 0)
  row.value:SetWidth(56)
  row.name = Label(layer, 10)
  row.name:SetPoint("LEFT", ROW_HEIGHT + 3, 0)
  row.name:SetPoint("RIGHT", row.value, "LEFT", -4, 0)
  Color(row.name, TEXT)
  Color(row.value, TEXT)
  Color(row.share, TEXT)
  return row
end

local function Build()
  card = CreateFrame("Frame", "CZMeterHover", UIParent)
  card:SetWidth(WIDTH)
  card:SetFrameStrata("TOOLTIP")
  card:SetClampedToScreen(true)
  card:EnableMouse(false)
  card:Hide()
  Round(card, "Round", "BACKGROUND", 0.07, 0.08, 0.10, 0.96)
  card.border = Round(card, "RoundLine", "BORDER", 0.25, 0.27, 0.32, 0.9)

  card.spec = card:CreateTexture(nil, "ARTWORK")
  card.spec:SetSize(22, 22)
  card.spec:SetPoint("TOPLEFT", PAD, -PAD)
  card.spec:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  card.name = Label(card, 13)
  card.name:SetPoint("TOPLEFT", PAD + 28, -PAD)
  card.name:SetWidth(WIDTH - PAD * 2 - 28)
  card.sub = Label(card, 9)
  card.sub:SetPoint("TOPLEFT", PAD + 28, -PAD - 15)
  card.sub:SetWidth(WIDTH - PAD * 2 - 28)

  -- Four small stats in a line: total, per second, share, rank.
  card.stats = {}
  local statWidth = (WIDTH - PAD * 2) / 4
  for i = 1, 4 do
    local label = Label(card, 8)
    label:SetPoint("TOPLEFT", PAD + (i - 1) * statWidth, -42)
    label:SetWidth(statWidth - 4)
    local value = Label(card, 12)
    value:SetPoint("TOPLEFT", PAD + (i - 1) * statWidth, -53)
    value:SetWidth(statWidth - 4)
    Color(value, TEXT)
    card.stats[i] = { label = label, value = value }
  end

  card.rows = {}
  card.note = Label(card, 9)
  card.note:SetWidth(WIDTH - PAD * 2)
  card.note:SetWordWrap(true)

  card:SetScript("OnUpdate", function(_, elapsed)
    sinceDraw = sinceDraw + elapsed
    if sinceDraw >= REDRAW_GAP then Hover.Refresh() end
  end)
end

---------------------------------------------------------------------------
-- Reading one player
---------------------------------------------------------------------------
-- The player's spells for the window's metric: rows, readable, and a note when
-- there are none to show.
local function Spells(w, src, metric)
  if w.db.tab == "enemies" and not ns.testMode then
    return {}, false, "Enemy rows have no spell breakdown."
  end
  if w.db.showBest and not ns.testMode then
    return {}, false, "Best try only keeps totals."
  end
  if ns.testMode then return Data.TestSource(src), true end

  local guid = src.sourceGUID
  if guid ~= nil and issecret(guid) and src.isLocalPlayer == true then guid = UnitGUID("player") end
  if guid == nil then return {}, false, "Spells show once combat ends." end
  -- A secret GUID (another player in combat) is passed straight to the game.
  -- If it won't take it, the spells wait for combat to end.
  local spells, readable = Data.Spells(Data.ReadSource(w.db, Data.Metric(w.db).key, guid))
  if #spells == 0 then
    if issecret(guid) then return {}, false, "Other players' spells show once combat ends." end
    return {}, false, "No spell breakdown for this metric."
  end
  return spells, readable
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function Place(w)
  card:ClearAllPoints()
  local frame = w.frame
  local top = frame:GetTop()
  local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
  local room = UIParent:GetHeight() - (top or 0) * scale
  if top and room < card:GetHeight() + 8 then
    card:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -6)
  else
    card:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 6)
  end
end

function Hover.Refresh()
  sinceDraw = 0
  if not card or not card:IsShown() or not hovered then return end
  local w, row = hovered.win, hovered.row
  local src = row.src
  if not src or not row:IsVisible() then return Hover.Hide() end

  local skin = w.skin or Skins.Get("Default")
  local accent, dim = skin.accent, skin.dim
  card.border:SetVertexColor(accent[1], accent[2], accent[3], 0.55)

  local list, _, _, metric = Data.Read(w.db)
  local enemies = w.db.tab == "enemies" and not ns.testMode

  local name = src.name
  if name ~= nil and not issecret(name) and Ambiguate then name = Ambiguate(name, "short") end
  card.name:SetText(name)
  Color(card.name, enemies and TEXT or ClassColor(src.classFilename))
  local icon = src.specIconID
  if not enemies and icon ~= nil and not issecret(icon) and icon ~= 0 then
    card.spec:SetTexture(icon)
    card.spec:Show()
  else
    card.spec:Hide()
  end
  local view = w.db.view
  local viewText = ns.testMode and "test bars" or w.db.showBest and "best try"
    or view == "overall" and "overall" or type(view) == "number" and "earlier pull" or "current fight"
  card.sub:SetText(metric.label .. ", " .. viewText)
  Color(card.sub, dim)

  local share
  local shares = Data.Shares(list)
  if shares then
    for i, r in ipairs(list) do
      if r == src then share = shares[i] end
    end
  end
  local stats = {
    { metric.column, ns.Num(src.totalAmount) },
    { metric.perSecond and "PER SECOND" or "", metric.perSecond and src.amountPerSecond ~= nil and AbbreviateNumbers(src.amountPerSecond) or "" },
    { "SHARE", share and string.format("%.1f%%", share) or "" },
    { "RANK", row.rankNumber and string.format("#%d of %d", row.rankNumber, #list) or "" },
  }
  for i, stat in ipairs(card.stats) do
    stat.label:SetText(stats[i][1])
    Color(stat.label, dim)
    stat.value:SetText(stats[i][2])
  end

  local spells, readable, note = Spells(w, src, metric)
  local color = ClassColor(src.classFilename)
  local max = 1
  if readable then
    for _, sp in ipairs(spells) do
      if Plain(sp.total) and sp.total > max then max = sp.total end
    end
  elseif src.totalAmount ~= nil then
    max = src.totalAmount
  end
  local shown = math.min(#spells, MAX_SPELLS)
  for i = 1, MAX_SPELLS do
    local sp = spells[i]
    local r = card.rows[i]
    if sp then
      r = r or CreateSpellRow(i)
      card.rows[i] = r
      r:Show()
      r.bar:SetStatusBarColor(color[1] * 0.62, color[2] * 0.62, color[3] * 0.62, 0.85)
      r.bar:SetMinMaxValues(0, max)
      r.bar:SetValue(sp.total or 0)
      if sp.icon ~= nil and pcall(r.icon.SetTexture, r.icon, sp.icon) then
        r.icon:Show()
      else
        r.icon:Hide()
      end
      r.name:SetText(sp.name)
      r.value:SetText(ns.Num(sp.total))
      r.share:SetText(Plain(sp.share) and string.format("%.1f%%", sp.share) or "")
    elseif r then
      r:Hide()
    end
  end

  if not note then
    local more = #spells - shown
    note = more > 0 and string.format("%d more. Click for the full breakdown.", more) or "Click for the full breakdown."
    if not readable then note = "Order and shares settle once combat ends. " .. note end
  end
  local listBottom = TOP_HEIGHT + shown * (ROW_HEIGHT + ROW_GAP)
  card.note:ClearAllPoints()
  card.note:SetPoint("TOPLEFT", PAD, -(listBottom + 4))
  card.note:SetText(note)
  Color(card.note, dim)
  card:SetHeight(listBottom + 8 + card.note:GetStringHeight() + PAD)
  Place(w)
end

-- Called by a window row's OnEnter.
function Hover.Show(w, row)
  if not CZMeterDB.opt.hoverCard or not row.src then return end
  if not card then Build() end
  hovered = { win = w, row = row }
  card:Show()
  Hover.Refresh()
end

-- Called by OnLeave and clicks. With a row, only hides when that row is hovered.
function Hover.Hide(row)
  if row and hovered and hovered.row ~= row then return end
  hovered = nil
  if card then card:Hide() end
end
