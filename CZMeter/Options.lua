-- Options panel. Pick a window at the top, then change it page by page.
-- With "Editing group" ticked, window changes go to every window stuck to it.
-- Look settings live in the window's skin; changing a built-in skin makes a
-- custom copy first, so Default, Minimal and Classic always stay as shipped.

local _, ns = ...

local Options = {}
ns.Options = Options

local Skins, Window, Data = ns.Skins, ns.Window, ns.Data

local MEDIA = "Interface\\AddOns\\CZMeter\\Media\\"
local FONT = "Fonts\\FRIZQT__.TTF"
local ORANGE = { 0.96, 0.62, 0.23 }
local TEXT = { 0.91, 0.92, 0.95 }
local DIM = { 0.55, 0.58, 0.64 }

local WIDTH, HEIGHT = 800, 540
local NAV_WIDTH = 140
local COLUMN_WIDTH = 300

local panel
local editing = 1
local editGroup = true
local pages, nav = {}, {}
local widgets = {}

---------------------------------------------------------------------------
-- What is being edited
---------------------------------------------------------------------------
local function Win()
  local w = Window.Get(editing)
  if not w then
    w = Window.List()[1]
    editing = w and w.id or 1
  end
  return w
end

local function Targets()
  local w = Win()
  if not w then return {} end
  return editGroup and Window.GroupOf(w) or { w }
end

local function GetWin(key)
  local w = Win()
  return w and w.db[key]
end

local function SetWin(key, value)
  for _, w in ipairs(Targets()) do w.db[key] = value end
  Window.ApplyAll()
end

local function Skin()
  local w = Win()
  return Skins.Get(w and w.db.skin or "Default")
end

local function GetSkin(key)
  return Skin()[key]
end

local function SetSkin(key, value)
  local w = Win()
  if w then Window.SetSkinValue(w, key, value, Targets()) end
end

local function GetOpt(key) return CZMeterDB.opt[key] end
local function SetOpt(key, value) CZMeterDB.opt[key] = value end

function Options.Refresh()
  if not panel or not panel:IsShown() then return end
  for _, widget in ipairs(widgets) do
    if widget.Refresh then widget:Refresh() end
  end
end

local function Changed()
  Options.Refresh()
end

---------------------------------------------------------------------------
-- Widgets
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
  return fs
end

local function Tip(frame, text)
  if not text then return end
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Register(widget)
  widgets[#widgets + 1] = widget
  return widget
end

local function PillButton(parent, width, text, onClick, height)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, height or 20)
  b.fill = Round(b, "Round", "BACKGROUND", 0.20, 0.22, 0.27, 0.9)
  b.line = Round(b, "RoundLine", "BORDER", 0.30, 0.32, 0.38, 0.9)
  b.label = Label(b, 10, TEXT, "CENTER")
  b.label:SetPoint("LEFT", 6, 0)
  b.label:SetPoint("RIGHT", -6, 0)
  b.label:SetWordWrap(false)
  b.label:SetText(text or "")
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(self)
    self.fill:SetVertexColor(0.27, 0.29, 0.35, 0.95)
    if self.tip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
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
      self.label:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3])
    else
      self.fill:SetVertexColor(0.20, 0.22, 0.27, 0.9)
      self.line:SetVertexColor(0.30, 0.32, 0.38, 0.9)
      self.label:SetTextColor(TEXT[1], TEXT[2], TEXT[3])
    end
  end
  function b:SetEnabledLook(on)
    self:SetEnabled(on)
    self:SetAlpha(on and 1 or 0.4)
  end
  return b
end

-- A column lays widgets out top to bottom.
local function Column(page, x)
  local col = { page = page, x = x, y = -6 }

  function col:Place(frame, height, indent)
    frame:SetPoint("TOPLEFT", self.page, "TOPLEFT", self.x + (indent or 0), self.y)
    self.y = self.y - height
    return frame
  end

  function col:Space(height)
    self.y = self.y - (height or 8)
  end

  function col:Header(text)
    if self.y < -6 then self:Space(10) end
    local fs = Label(self.page, 12, ORANGE)
    fs:SetPoint("TOPLEFT", self.page, "TOPLEFT", self.x, self.y)
    fs:SetText(text)
    self.y = self.y - 22
    return fs
  end

  function col:Note(text)
    local fs = Label(self.page, 10, DIM)
    fs:SetWidth(COLUMN_WIDTH - 10)
    fs:SetWordWrap(true)
    fs:SetText(text)
    fs:SetPoint("TOPLEFT", self.page, "TOPLEFT", self.x, self.y)
    self.y = self.y - math.ceil(fs:GetStringHeight()) - 8
    return fs
  end

  function col:Check(text, get, set, tip)
    local holder = CreateFrame("Frame", nil, self.page)
    holder:SetSize(COLUMN_WIDTH, 22)
    local box = CreateFrame("CheckButton", nil, holder, "UICheckButtonTemplate")
    box:SetSize(22, 22)
    box:SetPoint("LEFT")
    local label = Label(holder, 11, TEXT)
    label:SetPoint("LEFT", box, "RIGHT", 4, 0)
    label:SetPoint("RIGHT")
    label:SetWordWrap(false)
    label:SetText(text)
    box:SetScript("OnClick", function(self)
      set(self:GetChecked() and true or false)
      Changed()
    end)
    Tip(box, tip)
    function holder:Refresh()
      box:SetChecked(get() and true or false)
    end
    self:Place(holder, 24)
    return Register(holder)
  end

  function col:Slider(text, low, high, step, get, set, format)
    local holder = CreateFrame("Frame", nil, self.page)
    holder:SetSize(COLUMN_WIDTH, 24)
    local label = Label(holder, 11, TEXT)
    label:SetPoint("LEFT")
    label:SetWidth(130)
    label:SetWordWrap(false)
    label:SetText(text)

    local slider = CreateFrame("Slider", nil, holder)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(110, 14)
    slider:SetPoint("LEFT", 134, 0)
    slider:SetMinMaxValues(low, high)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:EnableMouseWheel(true)
    Round(slider, "Round", "BACKGROUND", 0.15, 0.16, 0.20, 0.95)
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local value = Label(holder, 10, DIM, "RIGHT")
    value:SetPoint("LEFT", slider, "RIGHT", 4, 0)
    value:SetWidth(50)

    local function Show(v)
      value:SetText(format and string.format(format, v) or tostring(v))
    end
    local function Snap(v)
      v = math.floor(v / step + 0.5) * step
      return math.max(low, math.min(high, v))
    end
    slider:SetScript("OnValueChanged", function(_, v, userInput)
      v = Snap(v)
      Show(v)
      if userInput then set(v) end
    end)
    slider:SetScript("OnMouseUp", Changed)
    slider:SetScript("OnMouseWheel", function(self, delta)
      local v = Snap(self:GetValue() + delta * step)
      self:SetValue(v)
      set(v)
      Changed()
    end)
    function holder:Refresh()
      local v = get() or low
      slider:SetValue(v)
      Show(Snap(v))
    end
    self:Place(holder, 26)
    return Register(holder)
  end

  -- choices: a list of { value, label }, or a function returning one
  function col:Choice(text, choices, get, set, tip)
    local holder = CreateFrame("Frame", nil, self.page)
    holder:SetSize(COLUMN_WIDTH, 24)
    local label = Label(holder, 11, TEXT)
    label:SetPoint("LEFT")
    label:SetWidth(130)
    label:SetWordWrap(false)
    label:SetText(text)
    local function List()
      return type(choices) == "function" and choices() or choices
    end
    local button = PillButton(holder, 150, "", function(self)
      MenuUtil.CreateContextMenu(self, function(_, root)
        for _, entry in ipairs(List()) do
          root:CreateRadio(entry.label, function() return get() == entry.value end, function()
            set(entry.value)
            Changed()
          end)
        end
      end)
    end)
    button:SetPoint("LEFT", 134, 0)
    button.tip = tip
    function holder:Refresh()
      local current = get()
      local shown = tostring(current or "")
      for _, entry in ipairs(List()) do
        if entry.value == current then shown = entry.label end
      end
      button.label:SetText(shown)
    end
    self:Place(holder, 26)
    return Register(holder)
  end

  function col:Color(text, get, set, hasAlpha)
    local holder = CreateFrame("Frame", nil, self.page)
    holder:SetSize(COLUMN_WIDTH, 24)
    local label = Label(holder, 11, TEXT)
    label:SetPoint("LEFT")
    label:SetWidth(130)
    label:SetText(text)
    local swatch = CreateFrame("Button", nil, holder)
    swatch:SetSize(40, 16)
    swatch:SetPoint("LEFT", 134, 0)
    local edge = swatch:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(0.4, 0.42, 0.48, 1)
    local checker = swatch:CreateTexture(nil, "BORDER")
    checker:SetPoint("TOPLEFT", 1, -1)
    checker:SetPoint("BOTTOMRIGHT", -1, 1)
    checker:SetColorTexture(0.12, 0.12, 0.12, 1)
    local fill = swatch:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)

    swatch:SetScript("OnClick", function()
      local c = get()
      local before = { c[1], c[2], c[3], c[4] or 1 }
      local function Read()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        local a = hasAlpha and ColorPickerFrame:GetColorAlpha() or 1
        return { r, g, b, a }
      end
      ColorPickerFrame:SetupColorPickerAndShow({
        r = before[1], g = before[2], b = before[3],
        opacity = before[4], hasOpacity = hasAlpha,
        swatchFunc = function() set(Read()); Changed() end,
        opacityFunc = function() set(Read()); Changed() end,
        cancelFunc = function() set(before); Changed() end,
      })
    end)
    function holder:Refresh()
      local c = get()
      fill:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    end
    self:Place(holder, 26)
    return Register(holder)
  end

  function col:Button(text, onClick, width, tip)
    local b = PillButton(self.page, width or 150, text, function(selfButton)
      onClick(selfButton)
      Changed()
    end, 22)
    b.tip = tip
    self:Place(b, 26)
    return b
  end

  function col:Edit(text, width)
    local holder = CreateFrame("Frame", nil, self.page)
    holder:SetSize(COLUMN_WIDTH, 24)
    local label = Label(holder, 11, TEXT)
    label:SetPoint("LEFT")
    label:SetWidth(130)
    label:SetText(text)
    local box = CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
    box:SetSize(width or 140, 20)
    box:SetPoint("LEFT", 140, 0)
    box:SetAutoFocus(false)
    box:SetMaxLetters(32)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    holder.box = box
    self:Place(holder, 26)
    return holder
  end

  return col
end

---------------------------------------------------------------------------
-- Choice lists
---------------------------------------------------------------------------
local function ValueList(list)
  local out = {}
  for i, entry in ipairs(list) do out[i] = { value = entry.value, label = entry.label } end
  return out
end

local function SkinChoices()
  local out = {}
  for _, name in ipairs(Skins.Names()) do
    out[#out + 1] = { value = name, label = Skins.IsBuiltIn(name) and (name .. " (built in)") or name }
  end
  return out
end

local function WindowLabel(w)
  local metric = Data.METRICS[w.db.metric] or Data.METRICS[1]
  local text = string.format("#%d %s", w.id, w.db.tab == "enemies" and "Enemy damage" or metric.label)
  if not w.db.shown then text = text .. " (closed)" end
  return text
end

local function WindowChoices()
  local out = {}
  for _, w in ipairs(Window.List()) do out[#out + 1] = { value = w.id, label = WindowLabel(w) } end
  return out
end

local TOP_LIST = {}
for i, n in ipairs(Window.TOP_CHOICES) do TOP_LIST[i] = { value = n, label = tostring(n) } end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
local PAGES = {}

PAGES[#PAGES + 1] = { key = "display", label = "Display", build = function(page)
  local left = Column(page, 0)
  left:Header("General")
  left:Slider("Update speed in combat", 0.1, 1, 0.05,
    function() return GetOpt("combatUpdate") end, function(v) SetOpt("combatUpdate", v) end, "%.2fs")
  left:Slider("Mouse wheel speed", 1, 5, 1,
    function() return GetOpt("wheel") end, function(v) SetOpt("wheel", v) end, "%d rows")
  left:Choice("Number format", {
    { value = "short", label = "Short (1.2M)" }, { value = "full", label = "Full (1,234,567)" },
  }, function() return GetOpt("numbers") end, function(v)
    SetOpt("numbers", v)
    Window.RefreshAll()
  end, "In combat the game only allows the short form, so full numbers show once combat ends.")
  left:Check("Show minimap button", function() return GetOpt("minimapButton") end, function(v)
    SetOpt("minimapButton", v)
    ns.MinimapButton.Update()
  end, "Left click opens these options, right click shows or hides the meter.")
  left:Check("Show details when hovering a row", function() return GetOpt("hoverCard") end,
    function(v) SetOpt("hoverCard", v) end,
    "A short breakdown above the window. Clicking a row still opens the full one.")

  left:Header("Overall data")
  left:Check("Clear the meter when a Mythic+ key starts",
    function() return GetOpt("clearOnKey") end, function(v) SetOpt("clearOnKey", v) end,
    "Clears the meter history, including Blizzard's own meter.")
  left:Check("Clear the meter on entering a dungeon or raid",
    function() return GetOpt("clearOnInstance") end, function(v) SetOpt("clearOnInstance", v) end,
    "Only when it's a different instance from the last one, so a wipe and run back keeps your pulls.")

  left:Header("Your self")
  left:Check("Outline my row", function() return GetSkin("meOutline") end, function(v) SetSkin("meOutline", v) end)
  left:Check("Use a different colour for me", function() return GetSkin("meCustom") end,
    function(v) SetSkin("meCustom", v) end)
  left:Color("My bar colour", function() return GetSkin("meColor") end, function(v) SetSkin("meColor", v) end)

  local right = Column(page, COLUMN_WIDTH + 20)
  right:Header("Window control")
  local lock
  right:Button("Create window", function() local w = Window.Create(); if w then editing = w.id end end, 150,
    "Each window keeps its own metric, so one can show damage and another healing.")
  lock = right:Button("Lock", function()
    local w = Win()
    if w then Window.SetLocked(w, not w.db.locked) end
  end, 150, "Locks the window and every window stuck to it.")
  local ungroup = right:Button("Ungroup", function()
    local w = Win()
    if w then Window.Ungroup(w) end
  end, 150, "Unsticks every window in this group. Drag a window near another to stick them together.")
  local close = right:Button("Close", function()
    local w = Win()
    if not w then return end
    if w.db.shown then Window.Close(w) else Window.Show(w) end
  end, 150)
  local delete = right:Button("Delete window", function()
    local w = Win()
    if w and Window.Delete(w) then editing = Window.List()[1].id end
  end, 150, "Removes this window and its settings. The last window can't be deleted.")
  right:Note("Drag a window close to another one and it sticks to that edge. Stuck windows move and lock together.")
  Register({ Refresh = function()
    local w = Win()
    if not w then return end
    lock.label:SetText(w.db.locked and "Unlock" or "Lock")
    lock:SetActive(w.db.locked)
    ungroup:SetEnabledLook(Window.InGroup(w))
    close.label:SetText(w.db.shown and "Close" or "Show")
    delete:SetEnabledLook(#Window.List() > 1)
  end })
end }

PAGES[#PAGES + 1] = { key = "window", label = "Window", build = function(page)
  local left = Column(page, 0)
  left:Header("Window")
  left:Choice("Skin", SkinChoices, function() return GetWin("skin") end, function(v) SetWin("skin", v) end)
  left:Slider("Width", Window.MIN_WIDTH, Window.MAX_WIDTH, 5,
    function() return GetWin("width") end, function(v) SetWin("width", v) end, "%d")
  left:Slider("Height", Window.MIN_HEIGHT, Window.MAX_HEIGHT, 5,
    function() return GetWin("height") end, function(v) SetWin("height", v) end, "%d")
  left:Check("Grow with the number of rows", function() return GetWin("autoHeight") end,
    function(v) SetWin("autoHeight", v) end, "Off: a fixed height, scroll with the mouse wheel to see more rows.")
  left:Slider("Scale", 0.6, 1.6, 0.05, function() return GetWin("scale") end, function(v) SetWin("scale", v) end, "%.2f")
  left:Choice("Show top", TOP_LIST, function() return GetWin("top") end, function(v) SetWin("top", v) end)
  left:Choice("Toolbar", ValueList(Skins.TOOLBARS), function() return GetSkin("toolbar") end,
    function(v) SetSkin("toolbar", v) end, "Compact keeps the metric, history and menu buttons. The rest move into the menu.")
  left:Check("Column headings", function() return GetSkin("showHeadings") end, function(v) SetSkin("showHeadings", v) end)

  local right = Column(page, COLUMN_WIDTH + 20)
  right:Header("Look")
  right:Color("Background", function() return GetSkin("bg") end, function(v) SetSkin("bg", v) end, true)
  right:Color("Border", function() return GetSkin("border") end, function(v) SetSkin("border", v) end, true)
  right:Check("Rounded corners", function() return GetSkin("rounded") end, function(v) SetSkin("rounded", v) end)
  right:Color("Accent", function() return GetSkin("accent") end, function(v) SetSkin("accent", v) end)
  right:Note("Look settings belong to the skin, so every window wearing it changes too. Changing a built-in skin saves a custom copy.")
end }

PAGES[#PAGES + 1] = { key = "bars", label = "Bars", build = function(page)
  local left = Column(page, 0)
  left:Header("Rows")
  left:Slider("Row height", 14, 40, 1, function() return GetSkin("rowHeight") end, function(v) SetSkin("rowHeight", v) end, "%d")
  left:Slider("Row gap", 0, 6, 1, function() return GetSkin("rowGap") end, function(v) SetSkin("rowGap", v) end, "%d")
  left:Choice("Texture", ValueList(Skins.TEXTURES), function() return GetSkin("texture") end,
    function(v) SetSkin("texture", v) end)
  left:Choice("Bar orientation", {
    { value = false, label = "Left to right" }, { value = true, label = "Right to left" },
  }, function() return GetSkin("reverse") end, function(v) SetSkin("reverse", v) end)
  left:Slider("Row background", 0, 1, 0.05, function() return GetSkin("rowBack") end, function(v) SetSkin("rowBack", v) end, "%.2f")

  local right = Column(page, COLUMN_WIDTH + 20)
  right:Header("Colour")
  right:Check("Class colours", function() return GetSkin("classBars") end, function(v) SetSkin("classBars", v) end)
  right:Color("Bar colour", function() return GetSkin("barColor") end, function(v) SetSkin("barColor", v) end)
  right:Slider("Brightness", 0.2, 1, 0.05, function() return GetSkin("barBrightness") end,
    function(v) SetSkin("barBrightness", v) end, "%.2f")
  right:Slider("Opacity", 0, 1, 0.05, function() return GetSkin("barAlpha") end, function(v) SetSkin("barAlpha", v) end, "%.2f")
  right:Slider("Class stripe", 0, 6, 1, function() return GetSkin("stripe") end, function(v) SetSkin("stripe", v) end, "%d px")
  right:Note("Bar colour is used when class colours are off. Enemy rows keep their own red.")
end }

PAGES[#PAGES + 1] = { key = "text", label = "Text", build = function(page)
  local left = Column(page, 0)
  left:Header("Font")
  left:Choice("Font", ValueList(Skins.FONTS), function() return GetSkin("font") end, function(v) SetSkin("font", v) end)
  left:Slider("Size", 8, 18, 1, function() return GetSkin("fontSize") end, function(v) SetSkin("fontSize", v) end, "%d")
  left:Choice("Outline", ValueList(Skins.OUTLINES), function() return GetSkin("outline") end,
    function(v) SetSkin("outline", v) end)
  left:Color("Text", function() return GetSkin("text") end, function(v) SetSkin("text", v) end)
  left:Color("Secondary text", function() return GetSkin("dim") end, function(v) SetSkin("dim", v) end)

  local right = Column(page, COLUMN_WIDTH + 20)
  right:Header("Columns")
  right:Check("Rank", function() return GetSkin("showRank") end, function(v) SetSkin("showRank", v) end)
  right:Check("Spec icon", function() return GetSkin("showIcon") end, function(v) SetSkin("showIcon", v) end)
  right:Check("Item level", function() return GetSkin("showBadge") end, function(v) SetSkin("showBadge", v) end)
  right:Check("Per second", function() return GetSkin("showPerSecond") end, function(v) SetSkin("showPerSecond", v) end)
  right:Check("Share", function() return GetSkin("showShare") end, function(v) SetSkin("showShare", v) end)
  right:Note("Fewer columns leave more room for names. These are also under Columns in each window's menu button.")
end }

PAGES[#PAGES + 1] = { key = "skins", label = "Skins", build = function(page)
  local left = Column(page, 0)
  left:Header("Skins")
  left:Choice("This window", SkinChoices, function() return GetWin("skin") end, function(v) SetWin("skin", v) end)
  local nameBox = left:Edit("New skin name")
  left:Button("Save as a new skin", function()
    local w = Win()
    if not w then return end
    local name = Skins.Copy(w.db.skin, nameBox.box:GetText() ~= "" and nameBox.box:GetText() or (w.db.skin .. " custom"))
    nameBox.box:SetText("")
    SetWin("skin", name)
  end, 150, "Copies this window's skin under a new name.")
  local delete = left:Button("Delete this skin", function()
    local w = Win()
    if w and Skins.Delete(w.db.skin) then Window.ApplyAll() end
  end, 150, "Windows wearing it go back to Default. Built-in skins can't be deleted.")
  left:Note("Default, Minimal and Classic come with the addon. Change any setting and a custom copy is saved for you.")

  local right = Column(page, COLUMN_WIDTH + 20)
  right:Header("Share with friends")
  right:Button("Export this skin", function()
    local w = Win()
    if not w then return end
    ns.ShowText("Copy this string (Ctrl+C) and send it to a friend", Skins.Export(w.db.skin))
  end, 150)
  right:Button("Import a skin", function()
    ns.ShowText("Paste a CZ Meter skin string (Ctrl+V)", "", function(text)
      local name, err = Skins.Import(text)
      if not name then
        print("|cfff59e3bCZ Meter|r: " .. err)
        return false
      end
      SetWin("skin", name)
      print("|cfff59e3bCZ Meter|r: skin \"" .. name .. "\" added.")
      Options.Refresh()
    end)
  end, 150)
  right:Note("Skins travel as text, like WeakAuras strings. A skin only holds looks: no names, no numbers, nothing from your meter.")
  Register({ Refresh = function()
    local w = Win()
    delete:SetEnabledLook(w ~= nil and not Skins.IsBuiltIn(w.db.skin))
  end })
end }

PAGES[#PAGES + 1] = { key = "log", label = "Combat log", build = function(page)
  local left = Column(page, 0)
  left:Header("WoWCombatLog.txt")
  left:Choice("Start it automatically", {
    { value = "off", label = "Off" },
    { value = "keys", label = "Raids and Mythic+" },
    { value = "all", label = "All dungeons and raids" },
  }, function() return GetOpt("autoLog") end, function(v)
    SetOpt("autoLog", v)
    ns.CheckCombatLog()
  end, "Turns combat logging on as you zone in and off when you leave, if CZ Meter turned it on.")
  left:Check("Warn when Advanced Combat Logging is off", function() return GetOpt("logWarn") end,
    function(v) SetOpt("logWarn", v) end)
  local status = left:Note(" \n ")
  left:Note("The combat log is what the CZ Meter log tool on ctrlshiftzed.com reads for crit %, hits, casts and uptime. The file stays on your PC.")

  local right = Column(page, COLUMN_WIDTH + 20)
  right:Header("Disk space")
  right:Note("Log files can reach several GB after a few raid nights. Addons can't see or delete files, so CZ Meter only turns logging off when you leave and reminds you to clear old logs from World of Warcraft\\_retail_\\Logs.")
  right:Slider("Remind me after", 0, 40, 1, function() return GetOpt("logRemindHours") end,
    function(v) SetOpt("logRemindHours", v) end, "%d hours")
  -- Two lines held for the count, which wraps, so the button below doesn't sit on it.
  local logged = right:Note(" \n ")
  right:Button("I've cleared my logs", function() ns.ClearLoggedTime() end, 150,
    "Starts the count again.")
  right:Note("Set the reminder to 0 to turn it off.")
  Register({ Refresh = function()
    local on = LoggingCombat and LoggingCombat()
    local advanced = C_CVar and C_CVar.GetCVarBool("advancedCombatLogging")
    status:SetText(string.format("Combat log is %s now. Advanced Combat Logging is %s.",
      on and "|cff5fd35fon|r" or "off", advanced and "|cff5fd35fon|r" or "|cffe05050off|r"))
    logged:SetText(string.format("Logged by CZ Meter since the last reminder: %.1f hours.", ns.LoggedHours()))
  end })
end }

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local function ShowPage(key)
  for k, page in pairs(pages) do page:SetShown(k == key) end
  for k, button in pairs(nav) do button:SetActive(k == key) end
  CZMeterDB.opt.page = key
  Options.Refresh()
end

local function Build()
  panel = CreateFrame("Frame", "CZMeterOptions", UIParent)
  panel:SetSize(WIDTH, HEIGHT)
  panel:SetPoint("CENTER")
  panel:SetFrameStrata("DIALOG")
  panel:SetClampedToScreen(true)
  panel:EnableMouse(true)
  panel:SetMovable(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  panel:SetScript("OnShow", Options.Refresh)
  tinsert(UISpecialFrames, "CZMeterOptions")
  Round(panel, "Round", "BACKGROUND", 0.07, 0.08, 0.10, 0.97)
  Round(panel, "RoundLine", "BORDER", 0.25, 0.27, 0.32, 0.9)

  local title = Label(panel, 14, ORANGE)
  title:SetPoint("TOP", 0, -12)
  title:SetText("CZ Meter Options")

  local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)

  local test = PillButton(panel, 120, "Test bars", function(self)
    ns.SetTestMode(not ns.testMode)
    self:SetActive(ns.testMode)
  end, 22)
  test:SetPoint("TOPLEFT", 16, -40)
  test.tip = "Fills every window with made-up rows, so you can try skins and a full raid list anywhere."
  Register({ Refresh = function() test:SetActive(ns.testMode) end })

  -- Editing window / group, top right
  local holder = CreateFrame("Frame", nil, panel)
  holder:SetSize(400, 50)
  holder:SetPoint("TOPRIGHT", -16, -34)
  local col = Column(holder, 70)
  col:Choice("Editing window", WindowChoices, function() return Win() and Win().id end, function(v) editing = v end)
  col:Check("Editing group", function() return editGroup end, function(v) editGroup = v end,
    "Window settings change every window stuck to this one.")

  local navFrame = CreateFrame("Frame", nil, panel)
  navFrame:SetPoint("TOPLEFT", 16, -90)
  navFrame:SetSize(NAV_WIDTH, HEIGHT - 120)
  for i, def in ipairs(PAGES) do
    local b = PillButton(navFrame, NAV_WIDTH - 10, def.label, function() ShowPage(def.key) end, 22)
    b:SetPoint("TOPLEFT", 0, -(i - 1) * 26)
    nav[def.key] = b

    local page = CreateFrame("Frame", nil, panel)
    page:SetPoint("TOPLEFT", NAV_WIDTH + 30, -92)
    page:SetPoint("BOTTOMRIGHT", -16, 40)
    page:Hide()
    def.build(page)
    pages[def.key] = page
  end

  local foot = Label(panel, 10, DIM)
  foot:SetPoint("BOTTOMLEFT", 16, 14)
  foot:SetText("CZ Meter by CtrlShift_Zed  ||  ctrlshiftzed.com  ||  /cz options")
end

function Options.Open(windowID)
  if not panel then Build() end
  if windowID then editing = windowID end
  panel:Show()
  ShowPage(pages[CZMeterDB.opt.page] and CZMeterDB.opt.page or "display")
end

function Options.Toggle()
  if panel and panel:IsShown() then panel:Hide() else Options.Open() end
end

-- A small page in the game's own AddOns settings that opens the full panel.
function Options.Register()
  if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
  local canvas = CreateFrame("Frame")
  local heading = Label(canvas, 16, ORANGE)
  heading:SetPoint("TOPLEFT", 16, -16)
  heading:SetText("CZ Meter")
  local button = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
  button:SetSize(180, 26)
  button:SetPoint("TOPLEFT", 16, -48)
  button:SetText("Open CZ Meter options")
  button:SetScript("OnClick", function()
    if SettingsPanel then HideUIPanel(SettingsPanel) end
    Options.Open()
  end)
  local category = Settings.RegisterCanvasLayoutCategory(canvas, "CZ Meter")
  Settings.RegisterAddOnCategory(category)
end
