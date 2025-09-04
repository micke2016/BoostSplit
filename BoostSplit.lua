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
  SetDefault("pricePer5", 500 * 10000)
  SetDefault("runsPerPack", 5)
  SetDefault("cutPercent", 50)
  DB.roster = DB.roster or {}
  DB.whitelist = DB.whitelist or {}
end
-- === Overlay ===
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
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("TRADE_ACCEPT_UPDATE")

f:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4, arg5)
  if event == "ADDON_LOADED" and arg1 == addonName then
    EnsureDefaults()
    C_ChatInfo.RegisterAddonMessagePrefix("BoostSplit")
    printLocal("BoostSplit loaded. Use /bs.")
  elseif event == "PLAYER_LOGIN" then
    BuildMainUI()
    BuildOverlay()
    if DB.overlayEnabled and BoostSplitOverlay then
      BoostSplitOverlay:Show()
    end
  elseif event == "GROUP_ROSTER_UPDATE" then
    for i = 1, GetNumGroupMembers() do
      local name = GetRaidRosterInfo(i)
      if name and DB.whitelist[name] then
        local data = {
          roster = DB.roster,
          mage1 = DB.mage1,
          mage2 = DB.mage2,
          timestamp = time()
        }
        local msg = LibSerialize:Serialize(data)
        C_ChatInfo.SendAddonMessage("BoostSplit", msg, "PARTY")
      end
    end
  elseif event == "CHAT_MSG_ADDON" then
    if arg1 == "BoostSplit" then
      local sender = arg4
      if not DB.whitelist[sender] then return end
      local success, data = LibSerialize:Deserialize(arg2)
      if success and type(data) == "table" then
        for k, v in pairs(data.roster or {}) do
          if not DB.roster[k] or (v.gold or 0) > (DB.roster[k].gold or 0) then
            DB.roster[k] = v
          end
        end
        printLocal("Synced with " .. sender)
      end
    end
  elseif event == "TRADE_ACCEPT_UPDATE" then
    local copper = GetTargetTradeMoney()
    local target = UnitExists("NPC") and GetUnitName("NPC", true)
    if target and copper and copper > 0 then
      DB.roster[target] = DB.roster[target] or { gold = 0, runs = 0 }
      DB.roster[target].gold = (DB.roster[target].gold or 0) + copper
      local runValue = (DB.pricePer5 or 0) / (DB.runsPerPack or 5)
      DB.roster[target].runs = math.floor(DB.roster[target].gold / runValue)
      printLocal(target .. " paid " .. fmtCoins(copper) .. " — covers " .. DB.roster[target].runs .. " runs.")
    end
  end
end)
-- === UI ===
function BuildMainUI()
  if BoostSplitFrame then return end

  local f = CreateFrame("Frame", "BoostSplitFrame", UIParent, "BackdropTemplate")
  f:SetSize(500, 360)
  f:SetPoint("CENTER")
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
  })
  f:SetBackdropColor(0, 0, 0, 0.85)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  title:SetPoint("TOP", 0, -10)
  title:SetText("BoostSplit")

  local function CreateTab(name, index)
    local tab = CreateFrame("Button", nil, f, "OptionsFrameTabButtonTemplate")
    tab:SetID(index)
    tab:SetText(name)
    PanelTemplates_TabResize(tab, 0)
    tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 10 + (index - 1) * 100, 2)
    PanelTemplates_Tab_OnClick(tab)
    return tab
  end

  -- Create Tabs
  f.tabs = {
    settings = CreateFrame("Frame", nil, f),
    roster = CreateFrame("Frame", nil, f),
    export = CreateFrame("Frame", nil, f),
  }

  local function ShowTab(tabName)
    for name, panel in pairs(f.tabs) do
      panel:Hide()
    end
    f.tabs[tabName]:SetAllPoints(f)
    f.tabs[tabName]:Show()
  end

  local t1 = CreateTab("Settings", 1)
  t1:SetScript("OnClick", function() PanelTemplates_SetTab(f, 1); ShowTab("settings") end)
  local t2 = CreateTab("Roster", 2)
  t2:SetScript("OnClick", function() PanelTemplates_SetTab(f, 2); ShowTab("roster") end)
  local t3 = CreateTab("Export", 3)
  t3:SetScript("OnClick", function() PanelTemplates_SetTab(f, 3); ShowTab("export") end)

  PanelTemplates_SetNumTabs(f, 3)
  PanelTemplates_SetTab(f, 1)
  ShowTab("settings")

  BoostSplitFrame = f
end
-- === SETTINGS TAB ===
do
  local p = BoostSplitFrame.tabs.settings

  -- Price per 5 input
  local p5Label = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  p5Label:SetPoint("TOPLEFT", 20, -20)
  p5Label:SetText("Price per 5 runs (gold):")

  local p5Input = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
  p5Input:SetSize(80, 20)
  p5Input:SetPoint("LEFT", p5Label, "RIGHT", 10, 0)
  p5Input:SetAutoFocus(false)
  p5Input:SetNumeric(true)
  p5Input:SetNumber((DB.pricePer5 or 0) / 10000)

  -- Runs per pack input
  local rLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  rLabel:SetPoint("TOPLEFT", p5Label, "BOTTOMLEFT", 0, -20)
  rLabel:SetText("Runs per pack:")

  local rInput = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
  rInput:SetSize(50, 20)
  rInput:SetPoint("LEFT", rLabel, "RIGHT", 10, 0)
  rInput:SetAutoFocus(false)
  rInput:SetNumeric(true)
  rInput:SetNumber(DB.runsPerPack or 5)

  -- Cut %
  local cutLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  cutLabel:SetPoint("TOPLEFT", rLabel, "BOTTOMLEFT", 0, -20)
  cutLabel:SetText("Mage 2 cut %:")

  local cutSlider = CreateFrame("Slider", nil, p, "OptionsSliderTemplate")
  cutSlider:SetPoint("TOPLEFT", cutLabel, "BOTTOMLEFT", 0, -10)
  cutSlider:SetWidth(200)
  cutSlider:SetMinMaxValues(0, 100)
  cutSlider:SetValueStep(1)
  cutSlider:SetObeyStepOnDrag(true)
  cutSlider:SetValue(DB.cutPercent or 50)
  cutSlider:SetScript("OnValueChanged", function(self, val)
    DB.cutPercent = math.floor(val)
    self.Text:SetText(DB.cutPercent .. "%")
  end)
  cutSlider.Text:SetText(DB.cutPercent .. "%")

  -- Save settings
  local saveBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  saveBtn:SetSize(100, 22)
  saveBtn:SetPoint("TOPLEFT", cutSlider, "BOTTOMLEFT", 0, -20)
  saveBtn:SetText("Save")
  saveBtn:SetScript("OnClick", function()
    DB.pricePer5 = (tonumber(p5Input:GetText()) or 0) * 10000
    DB.runsPerPack = tonumber(rInput:GetText()) or 5
    printLocal("Settings saved.")
  end)
end

-- === EXPORT TAB ===
do
  local p = BoostSplitFrame.tabs.export

  local text = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  text:SetPoint("TOPLEFT", 20, -20)
  text:SetText("Session Summary:")

  local box = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
  box:SetMultiLine(true)
  box:SetSize(440, 240)
  box:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -10)
  box:SetAutoFocus(false)
  box:SetFontObject(GameFontHighlightSmall)
  box:SetScript("OnEscapePressed", function() box:ClearFocus() end)

  local function BuildExport()
    local total = 0
    for _, v in pairs(DB.roster) do
      total = total + (v.gold or 0)
    end

    local str = "Total Gold: " .. fmtCoins(total) .. "\n\n"
    for name, v in pairs(DB.roster) do
      str = str .. name .. ": " .. fmtCoins(v.gold or 0) .. " (" .. (v.runs or 0) .. " runs)"
      if v.isFriend then str = str .. " [FRIEND]" end
      str = str .. "\n"
    end

    local cut2 = math.floor(total * (DB.cutPercent or 50) / 100)
    local cut1 = total - cut2
    str = str .. "\nMage 1: " .. fmtCoins(cut1) .. "\nMage 2: " .. fmtCoins(cut2)

    box:SetText(str)
    box:HighlightText()
  end

  local exportBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  exportBtn:SetSize(120, 22)
  exportBtn:SetPoint("BOTTOMLEFT", 20, 20)
  exportBtn:SetText("Export Summary")
  exportBtn:SetScript("OnClick", BuildExport)

  local resetBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  resetBtn:SetSize(80, 22)
  resetBtn:SetPoint("LEFT", exportBtn, "RIGHT", 10, 0)
  resetBtn:SetText("Reset")
  resetBtn:SetScript("OnClick", function()
    DB.roster = {}
    printLocal("Session reset.")
    box:SetText("")
  end)
end
-- === ROSTER TAB ===
do
  local p = BoostSplitFrame.tabs.roster

  local scroll = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
  scroll:SetSize(440, 240)
  scroll:SetPoint("TOPLEFT", 20, -20)

  local content = CreateFrame("Frame")
  scroll:SetScrollChild(content)
  content:SetSize(440, 240)

  local function RefreshRoster()
    for _, child in pairs({content:GetChildren()}) do
      child:Hide()
    end

    local i = 0
    for name, data in pairs(DB.roster) do
      i = i + 1
      local row = CreateFrame("Frame", nil, content)
      row:SetSize(400, 24)
      row:SetPoint("TOPLEFT", 0, -((i - 1) * 26))

      local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      text:SetPoint("LEFT")
      text:SetText(name .. ": " .. fmtCoins(data.gold or 0) .. " (" .. (data.runs or 0) .. " runs)")

      local friendBox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
      friendBox:SetSize(20, 20)
      friendBox:SetPoint("LEFT", text, "RIGHT", 10, 0)
      friendBox:SetChecked(data.isFriend)
      friendBox:SetScript("OnClick", function(self)
        DB.roster[name].isFriend = self:GetChecked()
      end)

      local remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
      remove:SetSize(50, 20)
      remove:SetPoint("LEFT", friendBox, "RIGHT", 10, 0)
      remove:SetText("X")
      remove:SetScript("OnClick", function()
        DB.roster[name] = nil
        RefreshRoster()
      end)
    end
  end

  local refreshBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  refreshBtn:SetSize(100, 22)
  refreshBtn:SetPoint("BOTTOMLEFT", 20, 20)
  refreshBtn:SetText("Refresh")
  refreshBtn:SetScript("OnClick", RefreshRoster)

  -- Auto-refresh when opening tab
  p:SetScript("OnShow", RefreshRoster)
end

