-- Minimap button: left click opens the options, right click shows or hides
-- the meter, drag to move it around the minimap edge.

local _, ns = ...

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local ICON = "Interface\\AddOns\\CZMeter\\Media\\icon"
local RADIUS_PAD = 10

local button

local function Place()
  local angle = math.rad(CZMeterDB.opt.minimapAngle)
  local radius = Minimap:GetWidth() / 2 + RADIUS_PAD
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function FollowCursor()
  local mx, my = Minimap:GetCenter()
  local scale = Minimap:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  cx, cy = cx / scale, cy / scale
  CZMeterDB.opt.minimapAngle = math.floor(math.deg(math.atan2(cy - my, cx - mx)) + 0.5) % 360
  Place()
end

local function Build()
  button = CreateFrame("Button", "CZMeterMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local background = button:CreateTexture(nil, "BACKGROUND")
  background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  background:SetSize(20, 20)
  background:SetPoint("CENTER")

  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ICON)
  icon:SetSize(18, 18)
  icon:SetPoint("CENTER")
  -- Round the square icon off to sit inside the border ring.
  local mask = button:CreateMaskTexture()
  mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  mask:SetAllPoints(icon)
  icon:AddMaskTexture(mask)

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")

  button:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then
      ns.Window.Toggle()
    else
      ns.Options.Toggle()
    end
  end)
  button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", FollowCursor)
  end)
  button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("CZ Meter", 0.96, 0.62, 0.23)
    GameTooltip:AddLine("Left click: options", 1, 1, 1)
    GameTooltip:AddLine("Right click: show or hide the meter", 1, 1, 1)
    GameTooltip:AddLine("Drag: move this button", 0.55, 0.58, 0.64)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Builds the button on first use and shows or hides it to match the setting.
function MinimapButton.Update()
  if not CZMeterDB.opt.minimapButton then
    if button then button:Hide() end
    return
  end
  if not button then Build() end
  Place()
  button:Show()
end
