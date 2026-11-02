-- Skins: named looks a window can wear. Built-in skins never change; editing one
-- makes a custom copy. Skins travel between players as short text strings, and
-- an imported string is checked field by field, so it can only hold known values.

local _, ns = ...

local Skins = {}
ns.Skins = Skins

local FONTS = {
  { value = "friz", label = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
  { value = "arialn", label = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
  { value = "skurri", label = "Skurri", path = "Fonts\\skurri.ttf" },
  { value = "morpheus", label = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
}
local TEXTURES = {
  { value = "flat", label = "Flat", path = "Interface\\Buttons\\WHITE8x8" },
  { value = "blizzard", label = "Blizzard", path = "Interface\\TargetingFrame\\UI-StatusBar" },
  { value = "raid", label = "Raid frame", path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
  { value = "skill", label = "Skill bar", path = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
}
local OUTLINES = {
  { value = "none", label = "None", flag = "" },
  { value = "outline", label = "Outline", flag = "OUTLINE" },
  { value = "thick", label = "Thick outline", flag = "THICKOUTLINE" },
}
local TOOLBARS = {
  { value = "auto", label = "Auto (by width)" },
  { value = "full", label = "Full" },
  { value = "compact", label = "Compact" },
}
Skins.FONTS, Skins.TEXTURES, Skins.OUTLINES, Skins.TOOLBARS = FONTS, TEXTURES, OUTLINES, TOOLBARS

-- Every field a skin can hold, in export order. Anything else is dropped on import.
local FIELDS = {
  { key = "bg", kind = "color" },
  { key = "border", kind = "color" },
  { key = "rounded", kind = "bool" },
  { key = "accent", kind = "color" },
  { key = "text", kind = "color" },
  { key = "dim", kind = "color" },
  { key = "font", kind = "choice", choices = FONTS },
  { key = "fontSize", kind = "number", min = 8, max = 18, step = 1 },
  { key = "outline", kind = "choice", choices = OUTLINES },
  { key = "rowHeight", kind = "number", min = 14, max = 40, step = 1 },
  { key = "rowGap", kind = "number", min = 0, max = 6, step = 1 },
  { key = "texture", kind = "choice", choices = TEXTURES },
  { key = "reverse", kind = "bool" },
  { key = "classBars", kind = "bool" },
  { key = "barColor", kind = "color" },
  { key = "barBrightness", kind = "number", min = 0.2, max = 1, step = 0.05 },
  { key = "barAlpha", kind = "number", min = 0, max = 1, step = 0.05 },
  { key = "rowBack", kind = "number", min = 0, max = 1, step = 0.05 },
  { key = "stripe", kind = "number", min = 0, max = 6, step = 1 },
  { key = "showRank", kind = "bool" },
  { key = "showIcon", kind = "bool" },
  { key = "showBadge", kind = "bool" },
  { key = "showPerSecond", kind = "bool" },
  { key = "showShare", kind = "bool" },
  { key = "toolbar", kind = "choice", choices = TOOLBARS },
  { key = "showHeadings", kind = "bool" },
  { key = "meOutline", kind = "bool" },
  { key = "meCustom", kind = "bool" },
  { key = "meColor", kind = "color" },
}
Skins.FIELDS = FIELDS

local DEFAULT = {
  bg = { 0.07, 0.08, 0.10, 0.88 }, border = { 0.25, 0.27, 0.32, 0.8 }, rounded = true,
  accent = { 0.96, 0.62, 0.23, 1 }, text = { 0.91, 0.92, 0.95, 1 }, dim = { 0.55, 0.58, 0.64, 1 },
  font = "friz", fontSize = 12, outline = "none",
  rowHeight = 22, rowGap = 1, texture = "flat", reverse = false,
  classBars = true, barColor = { 0.45, 0.48, 0.55, 1 }, barBrightness = 0.62, barAlpha = 0.85,
  rowBack = 0.28, stripe = 3,
  showRank = true, showIcon = true, showBadge = true, showPerSecond = true, showShare = false,
  toolbar = "auto", showHeadings = true,
  meOutline = true, meCustom = false, meColor = { 0.80, 0.30, 0.90, 1 },
}

local function Copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = Copy(v) end
  return out
end

local function Over(base, changes)
  local out = Copy(base)
  for k, v in pairs(changes) do out[k] = Copy(v) end
  return out
end

local BUILT_IN = {
  Default = DEFAULT,
  Minimal = Over(DEFAULT, {
    bg = { 0.05, 0.05, 0.06, 0.35 }, border = { 0, 0, 0, 0 }, rounded = false,
    fontSize = 11, outline = "outline", rowHeight = 18, rowGap = 0,
    barBrightness = 0.75, barAlpha = 0.7, rowBack = 0.12, stripe = 0,
    showRank = false, showBadge = false, toolbar = "compact", showHeadings = false,
  }),
  Classic = Over(DEFAULT, {
    bg = { 0, 0, 0, 0.6 }, border = { 0, 0, 0, 0 }, rounded = false,
    font = "arialn", fontSize = 13, outline = "outline", rowHeight = 18, rowGap = 1,
    texture = "blizzard", barBrightness = 1, barAlpha = 1, rowBack = 0.3, stripe = 0,
    showBadge = false, accent = { 1, 0.82, 0, 1 },
  }),
}
local BUILT_IN_ORDER = { "Default", "Minimal", "Classic" }
local MAX_NAME = 32

local function Lookup(list, value)
  for _, entry in ipairs(list) do
    if entry.value == value then return entry end
  end
  return list[1]
end

function Skins.Font(skin) return Lookup(FONTS, skin.font).path end
function Skins.Texture(skin) return Lookup(TEXTURES, skin.texture).path end
function Skins.Outline(skin) return Lookup(OUTLINES, skin.outline).flag end

function Skins.IsBuiltIn(name)
  return BUILT_IN[name] ~= nil
end

function Skins.Exists(name)
  return BUILT_IN[name] ~= nil or (CZMeterDB.skins[name] ~= nil)
end

function Skins.Get(name)
  return BUILT_IN[name] or CZMeterDB.skins[name] or DEFAULT
end

function Skins.Names()
  local out = {}
  for _, name in ipairs(BUILT_IN_ORDER) do out[#out + 1] = name end
  local custom = {}
  for name in pairs(CZMeterDB.skins) do custom[#custom + 1] = name end
  table.sort(custom)
  for _, name in ipairs(custom) do out[#out + 1] = name end
  return out
end

-- Names can't hold the separators or colour codes used by the string format.
function Skins.CleanName(name)
  name = tostring(name or ""):gsub("[;=|%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
  return name:sub(1, MAX_NAME)
end

function Skins.UniqueName(base)
  base = Skins.CleanName(base)
  if base == "" then base = "Custom" end
  if not Skins.Exists(base) then return base end
  for i = 2, 99 do
    local name = Skins.CleanName(base:sub(1, MAX_NAME - 3)) .. " " .. i
    if not Skins.Exists(name) then return name end
  end
  return base .. " " .. tostring(time and time() or 0)
end

-- Fills in fields an older custom skin doesn't have yet.
function Skins.Fill(skin)
  for _, field in ipairs(FIELDS) do
    if skin[field.key] == nil then skin[field.key] = Copy(DEFAULT[field.key]) end
  end
  return skin
end

function Skins.Copy(fromName, newName)
  local name = Skins.UniqueName(newName)
  CZMeterDB.skins[name] = Skins.Fill(Copy(Skins.Get(fromName)))
  return name
end

function Skins.Delete(name)
  if BUILT_IN[name] then return false end
  CZMeterDB.skins[name] = nil
  for _, win in pairs(CZMeterDB.windows) do
    if win.skin == name then win.skin = "Default" end
  end
  return true
end

---------------------------------------------------------------------------
-- Text format: v=1;name=...;bg=r,g,b,a;rounded=1;font=friz;...
---------------------------------------------------------------------------
local FORMAT_VERSION = 1

local function Number(value)
  local text = string.format("%.3f", value):gsub("0+$", ""):gsub("%.$", "")
  return text
end

function Skins.Serialize(skin, name)
  local parts = { "v=" .. FORMAT_VERSION, "name=" .. Skins.CleanName(name) }
  for _, field in ipairs(FIELDS) do
    local value = skin[field.key]
    if value == nil then value = DEFAULT[field.key] end
    local text
    if field.kind == "color" then
      text = table.concat({ Number(value[1]), Number(value[2]), Number(value[3]), Number(value[4] or 1) }, ",")
    elseif field.kind == "bool" then
      text = value and "1" or "0"
    elseif field.kind == "number" then
      text = Number(value)
    else
      text = tostring(value)
    end
    parts[#parts + 1] = field.key .. "=" .. text
  end
  return table.concat(parts, ";")
end

local function Clamp(value, low, high)
  if value < low then return low end
  if value > high then return high end
  return value
end

local function ReadField(field, text)
  if field.kind == "color" then
    local out = {}
    for piece in text:gmatch("[^,]+") do
      local n = tonumber(piece)
      if not n then return nil end
      out[#out + 1] = Clamp(n, 0, 1)
    end
    if #out == 3 then out[4] = 1 end
    if #out ~= 4 then return nil end
    return out
  elseif field.kind == "bool" then
    if text == "1" then return true elseif text == "0" then return false end
  elseif field.kind == "number" then
    local n = tonumber(text)
    if not n or n ~= n then return nil end
    n = Clamp(n, field.min, field.max)
    return math.floor(n / field.step + 0.5) * field.step
  elseif field.kind == "choice" then
    for _, entry in ipairs(field.choices) do
      if entry.value == text then return text end
    end
  end
end

-- Returns a full, checked skin and its name, or nil and a reason.
function Skins.Parse(text)
  if type(text) ~= "string" or text == "" then return nil, "The string is empty." end
  local values = {}
  for pair in text:gmatch("[^;]+") do
    local key, value = pair:match("^(%w+)=(.*)$")
    if key and values[key] == nil then values[key] = value end
  end
  local version = tonumber(values.v)
  if not version then return nil, "This isn't a CZ Meter skin." end
  if version > FORMAT_VERSION then return nil, "This skin comes from a newer CZ Meter. Update the addon first." end

  local skin = {}
  for _, field in ipairs(FIELDS) do
    local value = values[field.key] and ReadField(field, values[field.key])
    if value == nil then value = Copy(DEFAULT[field.key]) end
    skin[field.key] = value
  end
  local name = Skins.CleanName(values.name)
  if name == "" then name = "Imported" end
  return skin, name
end

---------------------------------------------------------------------------
-- Share strings. CZ1 is compressed with the game's own encoder; CZ0 is plain
-- text, used if that encoder is missing. Both import.
---------------------------------------------------------------------------
local function Encoder()
  local util = C_EncodingUtil
  if util and util.CompressString and util.DecompressString and util.EncodeBase64 and util.DecodeBase64
     and Enum and Enum.CompressionMethod then
    return util, Enum.CompressionMethod.Deflate
  end
end

function Skins.Export(name)
  local text = Skins.Serialize(Skins.Get(name), name)
  local util, method = Encoder()
  if util then
    local ok, packed = pcall(util.CompressString, text, method)
    if ok and packed then
      local ok2, encoded = pcall(util.EncodeBase64, packed)
      if ok2 and encoded then return "CZ1:" .. encoded end
    end
  end
  return "CZ0:" .. text
end

function Skins.Decode(str)
  str = tostring(str or ""):gsub("%s+", "")
  local tag, body = str:match("^(CZ%d):(.+)$")
  if tag == "CZ0" then return body end
  if tag == "CZ1" then
    local util, method = Encoder()
    if not util then return nil, "This game client can't read compressed skins." end
    local ok, packed = pcall(util.DecodeBase64, body)
    if not ok or not packed then return nil, "The string is damaged." end
    local ok2, text = pcall(util.DecompressString, packed, method)
    if not ok2 or not text then return nil, "The string is damaged." end
    return text
  end
  return nil, "This isn't a CZ Meter skin string."
end

-- Adds an imported skin to the list. Returns its name, or nil and a reason.
function Skins.Import(str)
  local text, err = Skins.Decode(str)
  if not text then return nil, err end
  local skin, name = Skins.Parse(text)
  if not skin then return nil, name end
  name = Skins.UniqueName(name)
  CZMeterDB.skins[name] = skin
  return name
end
