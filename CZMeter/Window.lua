-- Meter windows. Each window has its own metric, view and skin. Rows draw
-- Blizzard's values directly and rely on Blizzard's order. Columns are a fixed
-- width because text holding a secret can't be measured.
--
-- Windows dragged near each other snap together into a group. A group moves as
-- one (dragging any window moves the first one, the others are anchored to it)
-- and locks as one.

local _, ns = ...

local Window = {}
ns.Window = Window

local Data, Skins = ns.Data, ns.Skins
local issecret = ns.issecret

local MEDIA = "Interface\\AddOns\\CZMeter\\Media\\"
local FLAT = "Interface\\Buttons\\WHITE8x8"
local ENEMY_COLOR = { 0.72, 0.30, 0.28 }
local DEFAULT_COLOR = { 0.45, 0.48, 0.55 }

local MIN_WIDTH, MAX_WIDTH = 240, 900
local MIN_HEIGHT, MAX_HEIGHT = 60, 1000
local FULL_WIDTH = 430 -- "Auto" toolbars go compact below this width
local TOOLBAR_HEIGHT, HEADINGS_HEIGHT = 30, 24
local MAX_ROWS = 40
local MAX_WINDOWS = 6
local SNAP, GAP = 14, 2
local TOP_CHOICES = { 5, 10, 20, 40 }
Window.MIN_WIDTH, Window.MAX_WIDTH = MIN_WIDTH, MAX_WIDTH
Window.MIN_HEIGHT, Window.MAX_HEIGHT = MIN_HEIGHT, MAX_HEIGHT
Window.MAX_WINDOWS, Window.TOP_CHOICES = MAX_WINDOWS, TOP_CHOICES

Window.DEFAULTS = {
  metric = 1, tab = "players", view = "current", top = 40, myOnly = false, showBest = false, alwaysMe = true,
  width = 430, height = 200, autoHeight = false, scale = 1, shown = true, locked = false,
  skin = "Default",
}

local windows = {} -- id -> window
local retired = {} -- frames of deleted windows, reused by id

---------------------------------------------------------------------------
-- Lookups and groups
---------------------------------------------------------------------------
function Window.Get(id)
  return windows[id]
end

function Window.List()
  local ids = {}
  for id in pairs(windows) do ids[#ids + 1] = id end
  table.sort(ids)
  local out = {}
  for i, id in ipairs(ids) do out[i] = windows[id] end
  return out
end

local function Count()
  local n = 0
  for _ in pairs(windows) do n = n + 1 end
  return n
end

-- The window a group hangs from. Stops on a broken or looping chain.
local function Root(w)
  local seen = {}
  while w.db.attach and not seen[w] do
    seen[w] = true
    local parent = windows[w.db.attach.to]
    if not parent then break end
    w = parent
  end
  return w
end
Window.Root = Root

function Window.GroupOf(w)
  local root = Root(w)
  local out = {}
  for _, other in ipairs(Window.List()) do
    if Root(other) == root then out[#out + 1] = other end
  end
  return out
end

function Window.InGroup(w)
  return #Window.GroupOf(w) > 1
end

-- Pure edge test, in screen units. a is the window being dropped, b a window
-- already placed. Returns the side of b that a should stick to, and the gap.
function Window.SnapSide(a, b, snap)
  local best, bestGap
  local function Try(side, gap)
    gap = math.abs(gap)
    if gap <= snap and (not bestGap or gap < bestGap) then best, bestGap = side, gap end
  end
  if a.l < b.r and a.r > b.l then
    Try("bottom", a.t - b.b)
    Try("top", a.b - b.t)
  end
  if a.b < b.t and a.t > b.b then
    Try("right", a.l - b.r)
    Try("left", a.r - b.l)
  end
  return best, bestGap
end

---------------------------------------------------------------------------
-- Small building blocks
---------------------------------------------------------------------------
local function Round(parent, file, layer)
  local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
  tex:SetTexture(MEDIA .. file)
  tex:SetTextureSliceMargins(8, 8, 8, 8)
  tex:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
  tex:SetAllPoints()
  return tex
end

local function Paint(tex, color, alpha)
  tex:SetVertexColor(color[1], color[2], color[3], alpha or color[4] or 1)
end

local function Label(parent)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(Skins.Font(Skins.Get("Default")), 12, "")
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(false)
  return fs
end

local function Style(fs, skin, size, color, justify)
  fs:SetFont(Skins.Font(skin), size, Skins.Outline(skin))
  fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
  if justify then fs:SetJustifyH(justify) end
end

-- A rounded button. Active pills take the skin's accent colour.
local function Pill(w, parent, width, text, onClick, height)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, height or 20)
  b.fill = Round(b, "Round", "BACKGROUND")
  b.line = Round(b, "RoundLine", "BORDER")
  b.label = Label(b)
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
    local skin = w.skin
    Style(self.label, skin, 10, on and skin.accent or skin.text, "CENTER")
    if on then
      local a = skin.accent
      self.fill:SetVertexColor(a[1] * 0.45, a[2] * 0.45, a[3] * 0.45, 0.95)
      self.line:SetVertexColor(a[1], a[2], a[3], 0.5)
    else
      self.fill:SetVertexColor(0.20, 0.22, 0.27, 0.9)
      self.line:SetVertexColor(0.30, 0.32, 0.38, 0.9)
    end
  end
  return b
end

local function IconPill(w, parent, file, tip, onClick)
  local b = Pill(w, parent, 20, "", onClick)
  b.tip = tip
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(file)
  icon:SetSize(13, 13)
  icon:SetPoint("CENTER")
  return b
end

local function TextButton(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, 20)
  b.label = Label(b)
  b.label:SetPoint("CENTER")
  b.label:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

---------------------------------------------------------------------------
-- Columns: widths follow the font size; hidden columns take no space
---------------------------------------------------------------------------
local function Columns(skin)
  local scale = skin.fontSize / 12
  return {
    share = skin.showShare and math.floor(42 * scale + 0.5) or 0,
    dps = skin.showPerSecond and math.floor(58 * scale + 0.5) or 0,
    value = math.floor(52 * scale + 0.5),
    badge = skin.showBadge and math.floor(36 * scale + 0.5) or 0,
  }
end

-- Lines up share, per second, value and badge from the right edge.
-- Returns the frame and point the name column should stop at.
local function ChainRight(parent, items)
  local anchor, point, x = parent, "RIGHT", -6
  for _, item in ipairs(items) do
    local el, width = item[1], item[2]
    el:ClearAllPoints()
    if width > 0 then
      el:SetWidth(width)
      el:SetPoint("RIGHT", anchor, point, x, 0)
      el:Show()
      anchor, point, x = el, "LEFT", -4
    else
      el:Hide()
    end
  end
  return anchor, point, x
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function CreateRow(w)
  local row = CreateFrame("Frame", nil, w.body)
  row.back = row:CreateTexture(nil, "BACKGROUND")
  row.back:SetAllPoints()

  row.bar = CreateFrame("StatusBar", nil, row)
  row.bar:SetAllPoints()
  row.bar:SetMinMaxValues(0, 1)
  row.bar:SetValue(0)

  row.accent = row:CreateTexture(nil, "ARTWORK")
  row.accent:SetPoint("TOPLEFT")
  row.accent:SetPoint("BOTTOMLEFT")

  row.layer = CreateFrame("Frame", nil, row)
  row.layer:SetAllPoints()
  row.layer:SetFrameLevel(row.bar:GetFrameLevel() + 2)

  row.rank = Label(row.layer)
  row.icon = row.layer:CreateTexture(nil, "ARTWORK")
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.name = Label(row.layer)

  row.badge = CreateFrame("Frame", nil, row.layer)
  row.badge:SetHeight(16)
  local badgeBack = Round(row.badge, "Round", "BACKGROUND")
  badgeBack:SetVertexColor(0.05, 0.22, 0.26, 0.95)
  row.badgeText = Label(row.badge)
  row.badgeText:SetPoint("CENTER")

  row.share = Label(row.layer)
  row.dps = Label(row.layer)
  row.value = Label(row.layer)

  row.me = Round(row.layer, "RoundLine", "OVERLAY")
  row.me:Hide()

  -- A click (no movement) opens the detail panel. Rows take the mouse, so drags
  -- and the wheel are passed on to the window.
  local f = w.frame
  row:EnableMouse(true)
  row:EnableMouseWheel(true)
  row:RegisterForDrag("LeftButton")
  row:SetScript("OnDragStart", function() f:GetScript("OnDragStart")(f) end)
  row:SetScript("OnDragStop", function() f:GetScript("OnDragStop")(f) end)
  row:SetScript("OnMouseWheel", function(_, delta) f:GetScript("OnMouseWheel")(f, delta) end)
  row:SetScript("OnMouseDown", function(self)
    self.downX, self.downY = GetCursorPosition()
  end)
  row:SetScript("OnMouseUp", function(self, button)
    if button ~= "LeftButton" or not self.src or not self.downX then return end
    local x, y = GetCursorPosition()
    local moved = math.abs(x - self.downX) + math.abs(y - self.downY)
    self.downX = nil
    if moved < 6 then ns.Detail.Open(w, self.src, self.rankNumber) end
  end)
  row:Hide()
  return row
end

local function StyleRow(w, row, index)
  local skin = w.skin
  local step = skin.rowHeight + skin.rowGap
  row:ClearAllPoints()
  row:SetHeight(skin.rowHeight)
  row:SetPoint("TOPLEFT", w.body, "TOPLEFT", 0, -(index - 1) * step)
  row:SetPoint("TOPRIGHT", w.body, "TOPRIGHT", 0, -(index - 1) * step)

  row.back:SetColorTexture(0, 0, 0, skin.rowBack)
  row.bar:SetStatusBarTexture(Skins.Texture(skin))
  row.bar:SetReverseFill(skin.reverse)
  row.accent:SetWidth(math.max(skin.stripe, 1))
  row.accent:SetShown(skin.stripe > 0)

  local size = skin.fontSize
  local scale = size / 12
  Style(row.rank, skin, size - 1, skin.dim, "CENTER")
  Style(row.name, skin, size, skin.text, "LEFT")
  Style(row.value, skin, size, skin.text, "RIGHT")
  Style(row.dps, skin, size - 1, skin.text, "RIGHT")
  Style(row.share, skin, size - 1, skin.text, "RIGHT")
  Style(row.badgeText, skin, math.max(size - 2, 8), { 0.78, 0.92, 0.95, 1 }, "CENTER")
  Paint(row.me, skin.accent, 0.9)

  local x = 4 + skin.stripe
  row.rank:ClearAllPoints()
  if skin.showRank then
    row.rank:SetPoint("LEFT", x, 0)
    row.rank:SetWidth(math.floor(14 * scale + 0.5))
    x = x + math.floor(16 * scale + 0.5)
  end
  row.rank:SetShown(skin.showRank)

  local iconSize = math.min(16, skin.rowHeight - 4)
  row.icon:ClearAllPoints()
  row.icon:SetSize(iconSize, iconSize)
  if skin.showIcon then
    row.icon:SetPoint("LEFT", x, 0)
    x = x + iconSize + 4
  end
  row.showIcon = skin.showIcon

  local cols = Columns(skin)
  local anchor, point, gap = ChainRight(row.layer, {
    { row.share, cols.share }, { row.dps, cols.dps }, { row.value, cols.value }, { row.badge, cols.badge },
  })
  row.name:ClearAllPoints()
  row.name:SetPoint("LEFT", x, 0)
  row.name:SetPoint("RIGHT", anchor, point, gap, 0)
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

local function DrawRow(w, row, src, rank, maxAmount, share, metric, isEnemyTab)
  local skin = w.skin
  row:Show()
  row.src, row.rankNumber = src, rank
  row.rank:SetText(rank)

  local classColor = isEnemyTab and ENEMY_COLOR or ClassColor(src.classFilename)
  local color = classColor
  if not isEnemyTab then
    if skin.meCustom and src.isLocalPlayer == true then
      color = skin.meColor
    elseif not skin.classBars then
      color = skin.barColor
    end
  end
  local k = skin.barBrightness
  row.bar:SetStatusBarColor(color[1] * k, color[2] * k, color[3] * k, skin.barAlpha)
  row.accent:SetColorTexture(classColor[1], classColor[2], classColor[3], 1)
  local total = src.totalAmount
  if total == nil then total = 0 end
  if maxAmount == nil then maxAmount = 1 end
  row.bar:SetMinMaxValues(0, maxAmount)
  row.bar:SetValue(total)

  local icon = src.specIconID
  if row.showIcon and icon ~= nil and not issecret(icon) and icon ~= 0 and not isEnemyTab then
    row.icon:SetTexture(icon)
    row.icon:Show()
  else
    row.icon:Hide()
  end

  DrawName(row.name, src.name)
  row.value:SetText(ns.Num(total))

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

  local level = skin.showBadge and not isEnemyTab and Data.ItemLevel(src.sourceGUID)
  if level then
    row.badgeText:SetText(level)
    row.badge:SetAlpha(1)
  else
    row.badge:SetAlpha(0)
  end

  row.me:SetShown(skin.meOutline and src.isLocalPlayer == true)
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
local function ChooseRows(db, list)
  local isEnemyTab = db.tab == "enemies"
  if db.myOnly and not isEnemyTab then
    for i, src in ipairs(list) do
      if src.isLocalPlayer == true then return { { src = src, rank = i } } end
    end
    return {}
  end
  local out = {}
  local limit = math.min(db.top, MAX_ROWS)
  for i, src in ipairs(list) do
    if i <= limit then
      out[#out + 1] = { src = src, rank = i }
    elseif db.alwaysMe and src.isLocalPlayer == true and #out > 0 then
      -- Below the cut, so the last row shows you at your real rank.
      out[#out] = { src = src, rank = i }
      break
    end
  end
  return out
end

local function Step(w)
  return w.skin.rowHeight + w.skin.rowGap
end

function Window.Refresh(w)
  if not w or not w.frame:IsShown() then return end
  local db, skin = w.db, w.skin
  local list, maxAmount, duration, metric, best = Data.Read(db)
  local isEnemyTab = db.tab == "enemies" and not db.showBest and not ns.testMode
  local chosen = ChooseRows(db, list)
  local shares = Data.Shares(list)
  local shareOf = {}
  if shares then
    for i, src in ipairs(list) do shareOf[src] = shares[i] end
  end

  local step = Step(w)
  local visible
  if db.autoHeight and not w.sizing then
    visible = math.min(#chosen, MAX_ROWS)
    w.frame:SetHeight(w.top + math.max(visible, 1) * step + 8)
  else
    visible = math.floor((w.frame:GetHeight() - w.top - 8 + skin.rowGap) / step)
    visible = math.max(1, math.min(visible, MAX_ROWS))
  end
  w.offset = math.max(0, math.min(w.offset, #chosen - visible))
  w.chosenCount, w.visible = #chosen, visible

  -- "Always show me": when your row is out of sight (the window is too
  -- short, or scrolled), it takes the bottom row, at your real rank.
  local pinned
  if db.alwaysMe and not db.myOnly and not isEnemyTab and #chosen > visible then
    for i, entry in ipairs(chosen) do
      if entry.src.isLocalPlayer == true then
        if i <= w.offset or i > w.offset + visible then pinned = entry end
        break
      end
    end
  end

  for i = 1, MAX_ROWS do
    local entry = i <= visible and chosen[i + w.offset]
    if pinned and i == visible then entry = pinned end
    local row = w.rows[i]
    if entry then
      if not row then
        row = CreateRow(w)
        w.rows[i] = row
        StyleRow(w, row, i)
      end
      DrawRow(w, row, entry.src, entry.rank, maxAmount, shareOf[entry.src], metric, isEnemyTab)
    elseif row then
      row:Hide()
    end
  end

  w.empty:SetShown(#chosen == 0)
  if db.showBest and not best and not ns.testMode then
    w.empty:SetText("No best try for this boss yet.")
  else
    w.empty:SetText("Nothing to show yet.")
  end

  local c = w.controls
  c.metric.label:SetText(isEnemyTab and "Enemy damage" or metric.label)
  w.valueHeader:SetText(isEnemyTab and "DAMAGE" or metric.column)
  w.dpsHeader:SetText((metric.perSecond and not isEnemyTab) and (metric.key == "DamageDone" and "DPS" or "PER SEC") or "")

  if ns.testMode then
    w.timer:SetText(ns.Clock(duration))
  elseif db.view == "current" and not db.showBest and ns.combatStart then
    w.timer:SetText(ns.Clock(GetTime() - ns.combatStart))
  elseif duration ~= nil and not issecret(duration) then
    w.timer:SetText(ns.Clock(duration))
  else
    w.timer:SetText("")
  end
end

function Window.RefreshAll()
  for _, w in pairs(windows) do Window.Refresh(w) end
  if ns.Detail then ns.Detail.Refresh() end
end

local function RefreshControls(w)
  local db, c = w.db, w.controls
  c.myDps:SetActive(db.myOnly)
  c.best:SetActive(db.showBest)
  c.players:SetActive(db.tab ~= "enemies")
  c.enemies:SetActive(db.tab == "enemies")
  c.top.label:SetText("Top " .. db.top)
  local view = db.view
  if ns.testMode then
    c.history.label:SetText("Test")
  elseif view == "overall" then
    c.history.label:SetText("Overall")
  elseif type(view) == "number" then
    c.history.label:SetText("History")
  else
    c.history.label:SetText("Current")
  end
  c.history:SetActive(ns.testMode)
  c.cog:SetActive(false)
  c.top:SetActive(false)
  c.copy:SetActive(false)
  Window.Refresh(w)
end

---------------------------------------------------------------------------
-- Layout: toolbar mode, headings line, body
---------------------------------------------------------------------------
local function Layout(w)
  local skin, c = w.skin, w.controls
  local compact = skin.toolbar == "compact" or (skin.toolbar == "auto" and w.frame:GetWidth() < FULL_WIDTH)
  w.compact = compact

  for _, key in ipairs({ "prev", "next", "top", "copy", "best", "myDps" }) do
    c[key]:SetShown(not compact)
  end
  c.metric:ClearAllPoints()
  if compact then
    c.metric:SetPoint("TOPLEFT", 8, -6)
  else
    c.metric:SetPoint("LEFT", c.prev, "RIGHT", 2, 0)
  end
  c.history:ClearAllPoints()
  c.history:SetPoint("RIGHT", compact and c.cog or c.copy, "LEFT", -3, 0)

  local headShown = (not compact) or skin.showHeadings
  w.head:SetShown(headShown)
  c.players:SetShown(not compact)
  c.enemies:SetShown(not compact)

  w.top = TOOLBAR_HEIGHT + (headShown and HEADINGS_HEIGHT or 0)
  w.body:ClearAllPoints()
  w.body:SetPoint("TOPLEFT", 8, -w.top)
  w.body:SetPoint("TOPRIGHT", -8, -w.top)
end

local function ApplySkin(w)
  local skin = Skins.Get(w.db.skin)
  w.skin = skin
  local f = w.frame

  if skin.rounded then
    f:SetBackdrop(nil)
    Paint(w.bgRound, skin.bg)
    Paint(w.lineRound, skin.border)
    w.bgRound:Show()
    w.lineRound:Show()
  else
    w.bgRound:Hide()
    w.lineRound:Hide()
    f:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    f:SetBackdropColor(skin.bg[1], skin.bg[2], skin.bg[3], skin.bg[4])
    f:SetBackdropBorderColor(skin.border[1], skin.border[2], skin.border[3], skin.border[4])
  end

  local c = w.controls
  Style(c.metric.label, skin, 12, skin.accent)
  c.metric.arrow:SetVertexColor(skin.accent[1], skin.accent[2], skin.accent[3])
  Style(c.prev.label, skin, 14, skin.text, "CENTER")
  Style(c.next.label, skin, 14, skin.text, "CENTER")
  Style(w.timer, skin, 11, skin.dim)
  Style(w.empty, skin, 12, skin.dim, "CENTER")

  local cols = Columns(skin)
  for _, fs in ipairs({ w.shareHeader, w.dpsHeader, w.valueHeader }) do Style(fs, skin, 9, skin.dim, "RIGHT") end
  -- Headings sit over the same columns as the rows: rows have no badge spacer here.
  ChainRight(w.headCols, { { w.shareHeader, cols.share }, { w.dpsHeader, cols.dps }, { w.valueHeader, cols.value } })
  for _, fs in ipairs({ w.shareHeader, w.dpsHeader, w.valueHeader }) do fs:SetShown(skin.showHeadings and fs:IsShown()) end

  for i, row in pairs(w.rows) do StyleRow(w, row, i) end
  Layout(w)
  RefreshControls(w)
end

---------------------------------------------------------------------------
-- Placement
---------------------------------------------------------------------------
local ANCHORS = {
  bottom = { "TOPLEFT", "BOTTOMLEFT", 0, -GAP },
  top = { "BOTTOMLEFT", "TOPLEFT", 0, GAP },
  right = { "TOPLEFT", "TOPRIGHT", GAP, 0 },
  left = { "TOPRIGHT", "TOPLEFT", -GAP, 0 },
}

-- True if following attachments up from a window leads to target.
local function Reaches(from, target)
  local seen = {}
  while from and not seen[from] do
    if from == target then return true end
    seen[from] = true
    from = from.db.attach and windows[from.db.attach.to]
  end
  return false
end

local function Place(w)
  local f, db = w.frame, w.db
  f:ClearAllPoints()
  local parent = db.attach and windows[db.attach.to]
  local anchor = db.attach and ANCHORS[db.attach.side]
  if parent and anchor and not Reaches(parent, w) then
    f:SetPoint(anchor[1], parent.frame, anchor[2], anchor[3], anchor[4])
    return
  end
  db.attach = nil
  local pos = db.pos
  if pos then
    f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 300 - (w.id - 1) * 40, -(w.id - 1) * 40)
  end
end

local function SavePosition(w)
  if w.db.attach then return end
  local point, _, relativePoint, x, y = w.frame:GetPoint(1)
  if point then w.db.pos = { point, relativePoint, x, y } end
end

-- Cuts a window loose where it stands now.
local function FreeAt(w, left, top)
  w.db.attach = nil
  w.frame:ClearAllPoints()
  w.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
  w.db.pos = { "TOPLEFT", "BOTTOMLEFT", left, top }
end

local function Rect(w, scale)
  local f = w.frame
  local k = f:GetEffectiveScale() / scale
  return { l = f:GetLeft() * k, r = f:GetRight() * k, t = f:GetTop() * k, b = f:GetBottom() * k }
end

-- After a drop: stick to the nearest free edge of a window in another group.
local function TrySnap(root)
  local scale = root.frame:GetEffectiveScale()
  local mine = Rect(root, scale)
  local taken = {}
  for _, other in pairs(windows) do
    if other.db.attach then taken[other.db.attach.to .. ":" .. other.db.attach.side] = true end
  end
  local bestWindow, bestSide, bestGap
  for _, other in pairs(windows) do
    if other.frame:IsShown() and Root(other) ~= root and other.frame:GetLeft() then
      local side, gap = Window.SnapSide(mine, Rect(other, scale), SNAP)
      if side and not taken[other.id .. ":" .. side] and (not bestGap or gap < bestGap) then
        bestWindow, bestSide, bestGap = other, side, gap
      end
    end
  end
  if bestWindow then
    root.db.attach = { to = bestWindow.id, side = bestSide }
    root.db.pos = nil
    Place(root)
  else
    SavePosition(root)
  end
end

function Window.Ungroup(w)
  local spots = {}
  for _, member in ipairs(Window.GroupOf(w)) do
    if member.db.attach then
      spots[#spots + 1] = { member, member.frame:GetLeft(), member.frame:GetTop() }
    end
  end
  for _, spot in ipairs(spots) do FreeAt(spot[1], spot[2], spot[3]) end
end

local function UpdateGrip(w)
  w.grip:SetShown(not w.db.locked)
end

function Window.SetLocked(w, on)
  for _, member in ipairs(Window.GroupOf(w)) do
    member.db.locked = on
    UpdateGrip(member)
  end
end

local function ApplyGeometry(w)
  local db, f = w.db, w.frame
  f:SetScale(db.scale)
  f:SetWidth(math.max(MIN_WIDTH, math.min(db.width, MAX_WIDTH)))
  if not db.autoHeight then f:SetHeight(math.max(MIN_HEIGHT, math.min(db.height, MAX_HEIGHT))) end
  UpdateGrip(w)
end

---------------------------------------------------------------------------
-- Menus and actions
---------------------------------------------------------------------------
local function StepMetric(w, step)
  local count = #Data.METRICS
  w.db.metric = (w.db.metric - 1 + step) % count + 1
  w.db.tab = "players"
  RefreshControls(w)
end

local function OpenMetricMenu(w, owner)
  MenuUtil.CreateContextMenu(owner, function(_, root)
    for i, metric in ipairs(Data.METRICS) do
      root:CreateRadio(metric.label, function() return w.db.tab ~= "enemies" and w.db.metric == i end, function()
        w.db.metric = i
        w.db.tab = "players"
        RefreshControls(w)
      end)
    end
    root:CreateDivider()
    root:CreateRadio("Enemy damage", function() return w.db.tab == "enemies" end, function()
      w.db.tab = "enemies"
      w.db.showBest = false
      RefreshControls(w)
    end)
  end)
end

local function OpenHistoryMenu(w, owner)
  MenuUtil.CreateContextMenu(owner, function(_, root)
    if ns.testMode then
      root:CreateButton("Turn off test bars", function() ns.SetTestMode(false) end)
      return
    end
    local function Add(label, value)
      root:CreateRadio(label, function() return w.db.view == value end, function()
        w.db.view = value
        w.db.showBest = false
        RefreshControls(w)
      end)
    end
    Add("Current", "current")
    Add("Overall", "overall")
    for _, entry in ipairs(Data.History()) do Add(entry.label, entry.id) end
  end)
end

local function CycleTop(w)
  local nextChoice = TOP_CHOICES[1]
  for i, choice in ipairs(TOP_CHOICES) do
    if choice == w.db.top then nextChoice = TOP_CHOICES[i % #TOP_CHOICES + 1] end
  end
  w.db.top = nextChoice
  RefreshControls(w)
end

local copyFrame
local function ShowCopy(w)
  if InCombatLockdown() and not ns.testMode then
    print("|cfff59e3bCZ Meter|r: the numbers can be copied once combat ends.")
    return
  end
  local list, _, duration, metric = Data.Read(w.db)
  local title = metric.label
  if duration ~= nil and not issecret(duration) then title = title .. " (" .. ns.Clock(duration) .. ")" end
  local lines = { title }
  local shares = Data.Shares(list)
  for i, src in ipairs(list) do
    if issecret(src.totalAmount) then break end
    if src.totalAmount == nil or issecret(src.name) then break end
    lines[#lines + 1] = string.format("%d. %s  %s%s", i, Ambiguate(src.name, "short"),
      ns.Num(src.totalAmount), shares and string.format("  %.1f%%", shares[i]) or "")
  end
  ns.ShowText("Ctrl+C to copy, Esc to close", table.concat(lines, "\n"))
end

-- A shared text box: copy out, or paste in when onAccept is given.
function ns.ShowText(title, text, onAccept, acceptLabel)
  if not copyFrame then
    copyFrame = CreateFrame("Frame", "CZMeterTextBox", UIParent)
    copyFrame:SetSize(400, 260)
    copyFrame:SetPoint("CENTER")
    copyFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    copyFrame:EnableMouse(true)
    local back = Round(copyFrame, "Round", "BACKGROUND")
    back:SetVertexColor(0.09, 0.10, 0.13, 0.97)
    local line = Round(copyFrame, "RoundLine", "BORDER")
    line:SetVertexColor(0.30, 0.32, 0.38, 0.9)
    copyFrame.title = Label(copyFrame)
    copyFrame.title:SetTextColor(0.96, 0.62, 0.23)
    copyFrame.title:SetPoint("TOPLEFT", 12, -10)
    local scroll = CreateFrame("ScrollFrame", nil, copyFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -30)
    scroll:SetPoint("BOTTOMRIGHT", -30, 40)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetFontObject(ChatFontNormal)
    box:SetWidth(350)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
    scroll:SetScrollChild(box)
    copyFrame.box = box
    copyFrame.accept = CreateFrame("Button", nil, copyFrame, "UIPanelButtonTemplate")
    copyFrame.accept:SetSize(110, 22)
    copyFrame.accept:SetPoint("BOTTOMRIGHT", -126, 10)
    copyFrame.close = CreateFrame("Button", nil, copyFrame, "UIPanelButtonTemplate")
    copyFrame.close:SetSize(110, 22)
    copyFrame.close:SetPoint("BOTTOMRIGHT", -10, 10)
    copyFrame.close:SetText(CLOSE)
    copyFrame.close:SetScript("OnClick", function() copyFrame:Hide() end)
  end
  copyFrame.title:SetText(title)
  copyFrame.box:SetText(text or "")
  copyFrame.accept:SetShown(onAccept ~= nil)
  copyFrame.accept:SetText(acceptLabel or "Import")
  copyFrame.accept:SetScript("OnClick", function()
    if onAccept and onAccept(copyFrame.box:GetText()) ~= false then copyFrame:Hide() end
  end)
  copyFrame:Show()
  copyFrame.box:SetFocus()
  if not onAccept then copyFrame.box:HighlightText() end
end

StaticPopupDialogs["CZMETER_RESET"] = {
  text = "Clear all of this character's meter history? This also clears Blizzard's meter.",
  button1 = YES,
  button2 = NO,
  OnAccept = function() ns.ResetMeter() end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

-- Changes one look setting on a window's skin. Built-in skins are read only:
-- the first change makes "<name> custom" and moves the window (and any of
-- targets wearing the same skin) onto it.
function Window.SetSkinValue(w, key, value, targets)
  local name = w.db.skin
  if Skins.IsBuiltIn(name) or not Skins.Exists(name) then
    local copy = Skins.Copy(name, name .. " custom")
    for _, t in ipairs(targets or { w }) do
      if t.db.skin == name then t.db.skin = copy end
    end
    w.db.skin = copy
    name = copy
  end
  Skins.Get(name)[key] = value
  Window.ApplyAll()
  if ns.Options then ns.Options.Refresh() end
end

local COLUMNS = {
  { "showRank", "Rank" }, { "showIcon", "Spec icon" }, { "showBadge", "Item level" },
  { "showPerSecond", "Per second" }, { "showShare", "Share" },
}

local function OpenWindowMenu(w, owner)
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle("Window " .. w.id)
    local columns = root:CreateButton("Columns")
    for _, col in ipairs(COLUMNS) do
      local key = col[1]
      columns:CreateCheckbox(col[2], function() return w.skin[key] end, function()
        Window.SetSkinValue(w, key, not w.skin[key], Window.GroupOf(w))
      end)
    end
    root:CreateCheckbox("Always show me", function() return w.db.alwaysMe end, function()
      w.db.alwaysMe = not w.db.alwaysMe
      Window.Refresh(w)
    end)
    if w.compact then
      root:CreateCheckbox("My DPS only", function() return w.db.myOnly end, function()
        w.db.myOnly = not w.db.myOnly
        RefreshControls(w)
      end)
      root:CreateCheckbox("Best try", function() return w.db.showBest end, function()
        w.db.showBest = not w.db.showBest
        RefreshControls(w)
      end)
      local top = root:CreateButton("Show top")
      for _, choice in ipairs(TOP_CHOICES) do
        top:CreateRadio(tostring(choice), function() return w.db.top == choice end, function()
          w.db.top = choice
          RefreshControls(w)
        end)
      end
      root:CreateButton("Copy these numbers", function() ShowCopy(w) end)
    end
    root:CreateButton("Clear meter history", function()
      if not InCombatLockdown() then StaticPopup_Show("CZMETER_RESET") end
    end)
    root:CreateDivider()
    local new = root:CreateButton("New window", function() Window.Create() end)
    new:SetEnabled(Count() < MAX_WINDOWS)
    root:CreateCheckbox("Lock", function() return w.db.locked end, function()
      Window.SetLocked(w, not w.db.locked)
    end)
    if Window.InGroup(w) then
      root:CreateButton("Ungroup", function() Window.Ungroup(w) end)
    end
    root:CreateButton("Close window", function() Window.Close(w) end)
    root:CreateButton("Options", function() ns.Options.Open(w.id) end)
  end)
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
local function Build(w)
  local f = CreateFrame("Frame", "CZMeterWindow" .. w.id, UIParent, "BackdropTemplate")
  w.frame = f
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:SetResizable(true)
  f:SetDontSavePosition(true)
  f:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
  f:EnableMouse(true)
  f:EnableMouseWheel(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function()
    if w.db.locked then return end
    w.dragging = Root(w)
    w.dragging.frame:StartMoving()
  end)
  f:SetScript("OnDragStop", function()
    local root = w.dragging
    w.dragging = nil
    if not root then return end
    root.frame:StopMovingOrSizing()
    TrySnap(root)
  end)
  f:SetScript("OnMouseWheel", function(_, delta)
    w.offset = w.offset - delta * CZMeterDB.opt.wheel
    Window.Refresh(w)
  end)
  f:SetScript("OnSizeChanged", function()
    if not w.skin then return end
    local compact = w.skin.toolbar == "compact" or (w.skin.toolbar == "auto" and f:GetWidth() < FULL_WIDTH)
    if compact ~= w.compact then Layout(w) end
  end)

  w.bgRound = Round(f, "Round", "BACKGROUND")
  w.lineRound = Round(f, "RoundLine", "BORDER")

  local c = w.controls
  -- Toolbar: metric and timer on the left, buttons on the right
  c.prev = TextButton(f, "<", 16, function() StepMetric(w, -1) end)
  c.prev:SetPoint("TOPLEFT", 8, -6)

  c.metric = CreateFrame("Button", nil, f)
  c.metric:SetSize(112, 20)
  c.metric.label = Label(c.metric)
  c.metric.label:SetPoint("LEFT", 2, 0)
  c.metric.label:SetWidth(98)
  c.metric.arrow = c.metric:CreateTexture(nil, "ARTWORK")
  c.metric.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
  c.metric.arrow:SetSize(11, 11)
  c.metric.arrow:SetPoint("RIGHT", 0, -2)
  c.metric:SetScript("OnClick", function(self) OpenMetricMenu(w, self) end)

  c.next = TextButton(f, ">", 16, function() StepMetric(w, 1) end)
  c.next:SetPoint("LEFT", c.metric, "RIGHT", 2, 0)

  w.timer = Label(f)
  w.timer:SetPoint("LEFT", c.metric, "RIGHT", 21, 0)
  w.timer:SetWidth(32)

  c.cog = IconPill(w, f, "Interface\\Buttons\\UI-OptionsButton", "Window menu", function(self)
    OpenWindowMenu(w, self)
  end)
  c.cog:SetPoint("TOPRIGHT", -8, -6)

  c.top = Pill(w, f, 36, "Top 5", function() CycleTop(w) end)
  c.top:SetPoint("RIGHT", c.cog, "LEFT", -3, 0)

  c.copy = IconPill(w, f, "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", "Copy these numbers", function()
    ShowCopy(w)
  end)
  c.copy:SetPoint("RIGHT", c.top, "LEFT", -3, 0)

  c.history = Pill(w, f, 50, "Current", function(self) OpenHistoryMenu(w, self) end)

  c.best = Pill(w, f, 44, "Best try", function()
    w.db.showBest = not w.db.showBest
    RefreshControls(w)
  end)
  c.best:SetPoint("RIGHT", c.history, "LEFT", -3, 0)
  c.best.tip = "The group's best pull on the last boss you fought, saved after combat."

  c.myDps = Pill(w, f, 44, "My DPS", function()
    w.db.myOnly = not w.db.myOnly
    RefreshControls(w)
  end)
  c.myDps:SetPoint("RIGHT", c.best, "LEFT", -3, 0)
  c.myDps.tip = "Show only your own row."

  -- Second line: tabs on the left, column headings lined up with the rows
  w.head = CreateFrame("Frame", nil, f)
  w.head:SetPoint("TOPLEFT", 8, -TOOLBAR_HEIGHT)
  w.head:SetPoint("TOPRIGHT", -8, -TOOLBAR_HEIGHT)
  w.head:SetHeight(20)

  c.players = Pill(w, w.head, 46, "Players", function()
    w.db.tab = "players"
    RefreshControls(w)
  end, 18)
  c.players:SetPoint("LEFT")

  c.enemies = Pill(w, w.head, 48, "Enemies", function()
    w.db.tab = "enemies"
    w.db.showBest = false
    RefreshControls(w)
  end, 18)
  c.enemies:SetPoint("LEFT", c.players, "RIGHT", 3, 0)
  c.enemies.tip = "Group damage into each enemy type. Identical adds share one row."

  w.headCols = CreateFrame("Frame", nil, w.head)
  w.headCols:SetAllPoints()
  w.shareHeader = Label(w.headCols)
  w.shareHeader:SetText("SHARE")
  w.dpsHeader = Label(w.headCols)
  w.valueHeader = Label(w.headCols)

  w.body = CreateFrame("Frame", nil, f)
  w.body:SetHeight(10)
  w.empty = Label(w.body)
  w.empty:SetPoint("TOP", 0, -6)

  -- Size grip: width only while the window grows with its rows
  w.grip = CreateFrame("Button", nil, f)
  w.grip:SetSize(16, 16)
  w.grip:SetPoint("BOTTOMRIGHT", -2, 2)
  w.grip:SetFrameLevel(f:GetFrameLevel() + 10)
  w.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  w.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  w.grip:SetScript("OnMouseDown", function()
    w.sizing = f:GetHeight()
    f:StartSizing("BOTTOMRIGHT")
  end)
  w.grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    local before = w.sizing
    w.sizing = nil
    w.db.width = math.floor(f:GetWidth() + 0.5)
    -- Dragging the height on a growing window means the player wants a fixed one.
    if w.db.autoHeight and before and math.abs(f:GetHeight() - before) > 2 then w.db.autoHeight = false end
    if not w.db.autoHeight then w.db.height = math.floor(f:GetHeight() + 0.5) end
    -- Sizing can re-anchor the frame to the screen; put it back where it belongs.
    if w.db.attach then Place(w) else SavePosition(w) end
    Layout(w)
    Window.Refresh(w)
    if ns.Options then ns.Options.Refresh() end
  end)
end

local function Setup(id, db)
  local w = retired[id]
  retired[id] = nil
  if w then
    w.db = db
  else
    w = { id = id, db = db, rows = {}, controls = {}, offset = 0 }
    Build(w)
  end
  windows[id] = w
  return w
end

local function Visible(w)
  return w.db.shown and not CZMeterDB.hidden
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------
-- Builds every saved window. Called once at login.
function Window.Init()
  local ids = {}
  for id in pairs(CZMeterDB.windows) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do Setup(id, CZMeterDB.windows[id]) end
  Window.ApplyAll()
end

-- Re-reads every window's settings and skin. Used after any options change.
function Window.ApplyAll()
  local list = Window.List()
  for _, w in ipairs(list) do ApplyGeometry(w) end
  for _, w in ipairs(list) do Place(w) end
  for _, w in ipairs(list) do
    w.frame:SetShown(Visible(w))
    ApplySkin(w)
  end
end

function Window.Create()
  if Count() >= MAX_WINDOWS then
    print("|cfff59e3bCZ Meter|r: " .. MAX_WINDOWS .. " windows is the most you can have.")
    return
  end
  local id = 1
  while windows[id] do id = id + 1 end
  local db = {}
  for key, value in pairs(Window.DEFAULTS) do db[key] = value end
  local first = Window.List()[1]
  if first then
    db.skin = first.db.skin
    db.metric = first.db.metric % #Data.METRICS + 1
  end
  CZMeterDB.windows[id] = db
  CZMeterDB.hidden = false
  local w = Setup(id, db)
  Window.ApplyAll()
  return w
end

function Window.Delete(w)
  if Count() <= 1 then return false end
  for _, other in pairs(windows) do
    if other.db.attach and other.db.attach.to == w.id then
      FreeAt(other, other.frame:GetLeft(), other.frame:GetTop())
    end
  end
  w.frame:Hide()
  windows[w.id] = nil
  CZMeterDB.windows[w.id] = nil
  retired[w.id] = w
  return true
end

function Window.Close(w)
  w.db.shown = false
  w.frame:Hide()
end

function Window.Show(w)
  w.db.shown = true
  CZMeterDB.hidden = false
  w.frame:Show()
  RefreshControls(w)
end

-- /cz: hides everything, or brings it back. Closed windows return if none would show.
function Window.Toggle()
  if not CZMeterDB.hidden then
    local any = false
    for _, w in pairs(windows) do any = any or w.frame:IsShown() end
    if any then
      CZMeterDB.hidden = true
      for _, w in pairs(windows) do w.frame:Hide() end
      return
    end
  end
  CZMeterDB.hidden = false
  local any = false
  for _, w in pairs(windows) do any = any or w.db.shown end
  for _, w in pairs(windows) do
    if not any then w.db.shown = true end
    w.frame:SetShown(w.db.shown)
    if w.db.shown then RefreshControls(w) end
  end
end

function Window.RefreshControlsAll()
  for _, w in pairs(windows) do RefreshControls(w) end
end

-- One timer draws everything. In combat: a few redraws a second (the clock ticks
-- and secret values can't be compared to spot changes). Out of combat: only after
-- something flagged a change, with a slow safety redraw in case an update was missed.
local IDLE_CHECK, IDLE_SAFETY = 0.5, 5
local dirty = true
local waited, idle = 0, 0

function Window.MarkDirty()
  dirty = true
end

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, elapsed)
  if not (CZMeterDB and CZMeterDB.opt) then return end
  waited = waited + elapsed
  if InCombatLockdown() or ns.testMode then
    if waited < CZMeterDB.opt.combatUpdate then return end
  else
    if waited < IDLE_CHECK then return end
    idle = idle + waited
    if not dirty and idle < IDLE_SAFETY then
      waited = 0
      return
    end
  end
  waited, idle, dirty = 0, 0, false
  Window.RefreshAll()
end)
