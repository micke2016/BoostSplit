local addonName = ...
BoostSplitDB = BoostSplitDB or {}
local DB = BoostSplitDB

-- === Helpers ===
local function printLocal(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff00c0ffBoostSplit:|r " .. (msg or ""))
end

local function clamp(v, min, max)
  return math.max(min, math.min(max, v))
end

local function fmtCoins(c)
  c = math.floor(c)
  local g = math.floor(c / 10000)
  local s = math.floor((c % 10000) / 100)
  local c = c % 100
  return string.format("%dg %ds %dc", g, s, c)
end

local function SetDefault(k, v)
  if DB[k] == nil then DB[k] = v end
end

local function EnsureDefaults()
  SetDefault("overlayEnabled", true)
  SetDefault("pricePer5", 360 * 10000)
  SetDefault("runsPerPack", 5)
end

-- === Build Main UI ===
local function BuildMain()
  if BoostSplitFrame then return end

  local f = CreateFrame("Frame", "BoostSplitFrame", UIParent, "BackdropTemplate")
  f:SetSize(400, 220)
  f:SetPoint("CENTER")
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
  })
  f:SetBackdropColor(0, 0, 0, 0.8)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  title:SetPoint("TOP", 0, -10)
  title:SetText("BoostSplit Settings")

  -- Price per 5 input
  local p5Label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  p5Label:SetPoint("TOPLEFT", 20, -40)
  p5Label:SetText("Price per 5 runs (gold):")

  local p5Input = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  p5Input:SetSize(100, 20)
  p5Input:SetPoint("LEFT", p5Label, "RIGHT", 10, 0)
  p5Input:SetAutoFocus(false)
  p5Input:SetNumeric(true)
  p5Input:SetNumber((DB.pricePer5 or 0) / 10000)

  -- Runs per pack input
  local runsLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  runsLabel:SetPoint("TOPLEFT", p5Label, "BOTTOMLEFT", 0, -20)
  runsLabel:SetText("Runs per pack:")

  local runsInput = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  runsInput:SetSize(50, 20)
  runsInput:SetPoint("LEFT", runsLabel, "RIGHT", 10, 0)
  runsInput:SetAutoFocus(false)
  runsInput:SetNumeric(true)
  runsInput:SetNumber(DB.runsPerPack or 5)

  -- Price per run display
  local pprLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  pprLabel:SetPoint("TOPLEFT", runsLabel, "BOTTOMLEFT", 0, -20)
  pprLabel:SetText("Price per run:")

  local pprValue = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  pprValue:SetPoint("LEFT", pprLabel, "RIGHT", 10, 0)

  local function update()
    local gold = tonumber(p5Input:GetText()) or 0
    local runs = tonumber(runsInput:GetText()) or 1
    runs = math.max(1, runs)
    DB.pricePer5 = gold * 10000
    DB.runsPerPack = clamp(runs, 1, 50)
    local copper = math.floor(DB.pricePer5 / DB.runsPerPack)
    pprValue:SetText(fmtCoins(copper))
    printLocal("Settings saved.")
  end

  local function preview()
    local gold = tonumber(p5Input:GetText()) or 0
    local runs = tonumber(runsInput:GetText()) or 1
    runs = math.max(1, runs)
    local copper = math.floor((gold * 10000) / runs)
    pprValue:SetText(fmtCoins(copper))
  end

  p5Input:SetScript("OnEnterPressed", update)
  p5Input:SetScript("OnEditFocusLost", update)
  p5Input:SetScript("OnTextChanged", preview)

  runsInput:SetScript("OnEnterPressed", update)
  runsInput:SetScript("OnEditFocusLost", update)
  runsInput:SetScript("OnTextChanged", preview)

  local copper = math.floor((DB.pricePer5 or 0) / (DB.runsPerPack or 1))
  pprValue:SetText(fmtCoins(copper))

  f:Hide()
end

-- === Build Overlay ===
local function BuildOverlay()
  if BoostSplitOverlay then return end

  local f = CreateFrame("Frame", "BoostSplitOverlay", UIParent, "BackdropTemplate")
  f:SetSize(300, 100)
  f:SetPoint("CENTER", 0, 200)
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
  })
  f:SetBackdropColor(0, 0, 0, 0.8)

  local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("CENTER")
  label:SetText("BoostSplit Overlay")

  f:Hide()
end

-- === Slash Commands ===
SLASH_BOOSTSPLIT1 = "/bs"
SLASH_BOOSTSPLIT2 = "/bsoverlay"

SlashCmdList["BOOSTSPLIT"] = function(msg)
  msg = msg and msg:lower() or ""
  if msg == "overlay" then
    if BoostSplitOverlay then
      local s = not BoostSplitOverlay:IsShown()
      BoostSplitOverlay:SetShown(s)
      DB.overlayEnabled = s
    end
  else
    if BoostSplitFrame then
      BoostSplitFrame:SetShown(not BoostSplitFrame:IsShown())
    end
  end
end

-- === Load Event ===
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")

f:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" and arg1 == addonName then
    EnsureDefaults()
    printLocal("BoostSplit loaded. Use /bs.")
  elseif event == "PLAYER_LOGIN" then
    BuildMain()
    BuildOverlay()
    if DB.overlayEnabled and BoostSplitOverlay then
      BoostSplitOverlay:Show()
    end
  end
end)
