-- BoostSplit.lua (Rewritten Legacy for WoW Classic 1.15+)
-- Preserves all functions from legacy version, patched for modern API.

local ADDON, NS = ...
local F = CreateFrame("Frame","BoostSplitCore")
local DBV
local PREFIX="BSS"
local PREFIX_R="BSSR"
local REALM=(GetRealmName() or "Realm"):gsub("%s+","")
local REALM_CHAN="BoostSplit-"..REALM

------------------------------------------------------------------------
-- SavedVariables & Defaults
------------------------------------------------------------------------
local function DB() if not BoostSplitDB then BoostSplitDB={} end DBV=BoostSplitDB return DBV end
local function SetDefault(k,v) if DB()[k]==nil then DB()[k]=v end end
local function EnsureDefaults()
  SetDefault("overlayEnabled",true) SetDefault("overlayAlpha",0.95) SetDefault("mainAlpha",0.95)
  SetDefault("postWelcomeOnLogin",true) SetDefault("pricePer5",360*10000) SetDefault("runsPerPack",5)
  SetDefault("dungeon","X Boost") SetDefault("mage2Pct",35) SetDefault("soloBoost",false)
  SetDefault("sync",{enabled=false,locked=false,trusted={},autoTrust=true}) SetDefault("boostInProgress",false)
  SetDefault("roster",{}) SetDefault("boosterGoldStart",{}) SetDefault("boosterGoldCurrent",{})
  SetDefault("runsLog",{}) SetDefault("itemsValueSession",0) SetDefault("greyPool",0) SetDefault("vendorGoldSession",0)
  SetDefault("lootedCoinSession",0) SetDefault("lootEvents",{}) SetDefault("coinEvents",{}) SetDefault("deMarked",{})
  SetDefault("matTally",{cloth={},herbs={},ench={}}) SetDefault("_seen",{loot={},coin={},paid={}})
  SetDefault("blacklist",{}) SetDefault("historyBoosts",{}) SetDefault("deathroll",{active=false,upper=0,lastRoller=nil,m1Adj=0,m2Adj=0})
  SetDefault("mage1Name","") SetDefault("mage2Name","") SetDefault("_lastGroupSet",{})
end

------------------------------------------------------------------------
-- Utils
------------------------------------------------------------------------
local function now() return time() end
local function clamp(v,a,b) if v<a then return a elseif v>b then return b else return v end end
local function fmtCoins(c) c=math.floor(tonumber(c) or 0) local g=math.floor(c/10000) local s=math.floor((c%10000)/100) local cc=c%100 return ("%dg %ds %dc"):format(g,s,cc) end
local function fmtHMS(sec) sec=math.max(0,tonumber(sec) or 0) local h=math.floor(sec/3600) local m=math.floor((sec%3600)/60) local s=sec%60 return ("%d:%02d:%02d"):format(h,m,s) end
local function printLocal(msg) (DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage("|cff00c0ffBoostSplit:|r "..(msg or "")) end
local function FullName(name,realm) if not name or name=="" then return nil end if realm and realm~="" then return name.."-"..realm end return name end
local function MyNameRealm() local n,r=UnitFullName("player") return FullName(n,r) end

-- Item pricing stub
function BS_GetItemMarketPrice(link) local _,_,_,_,_,_,_,_,_,_,vendor=GetItemInfo(link) vendor=vendor or 0 return vendor*2 end

-- Dungeons list
local DUNGEONS={"X Boost","Ragefire Chasm","Deadmines","Wailing Caverns","Shadowfang Keep","Blackfathom Deeps","Stormwind Stockade","Gnomeregan","Razorfen Kraul","Scarlet Monastery","Razorfen Downs","Uldaman","Zul'Farrak","Maraudon","Sunken Temple","Blackrock Depths","Lower Blackrock Spire","Upper Blackrock Spire","Stratholme","Scholomance","Dire Maul"}

------------------------------------------------------------------------
-- Serializer
------------------------------------------------------------------------
function NS.Serialize(t)
  local function ser(v)
    local tp=type(v)
    if tp=="number" then return tostring(v)
    elseif tp=="boolean" then return v and "b1" or "b0"
    elseif tp=="string" then return "s"..v:gsub("|","||")
    elseif tp=="table" then
      local out={"{"}
      for k,val in pairs(v) do out[#out+1]="["..ser(k).."]="..ser(val)..";" end
      out[#out+1]="}" return table.concat(out)
    end
    return "n"
  end
  return ser(t)
end

function NS.Deserialize(s)
  if type(s)~="string" then return nil end
  local i=1
  local function parse()
    if i>#s then return nil end
    local c=s:sub(i,i)
    if c=="{" then
      i=i+1 local t={}
      while s:sub(i,i)~="}" do
        i=i+1 local k=parse() i=i+1
        i=i+1 local v=parse() i=i+1
        t[k]=v
      end
      i=i+1 return t
    elseif c=="s" then
      i=i+1 local j=i
      while j<=#s do if s:sub(j,j)=="|" and s:sub(j+1,j+1)~="|" then break end j=j+1 end
      local raw=s:sub(i,j-1):gsub("||","|") i=j return raw
    elseif c=="b" then i=i+1 local d=s:sub(i,i) i=i+1 return d=="1"
    elseif c:match("[%d%-]") then local j=i while s:sub(j,j):match("[%d%-%.]") do j=j+1 end local n=tonumber(s:sub(i,j-1)) i=j return n
    else i=i+1 return nil end
  end
  local ok,v=pcall(parse) if ok then return v end
end
------------------------------------------------------------------------
-- Announce
------------------------------------------------------------------------
local function announce(msg)
  local line="BoostSplit: "..(msg or "")
  local chan=DB().announce or "AUTO"
  local target="PARTY"
  if chan=="AUTO" then
    if IsInRaid() then target="RAID"
    elseif IsInGroup() then target="PARTY"
    else printLocal(msg) return end
  else target=chan end
  SendChatMessage(line,target)
end

------------------------------------------------------------------------
-- Sync
------------------------------------------------------------------------
C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
C_ChatInfo.RegisterAddonMessagePrefix(PREFIX_R)

NS._syncedPeers={}
local function MarkSynced(name) if name then NS._syncedPeers[name]=time() end end
local function PartyList()
  local out,seen={},{}
  local function add(unit)
    if UnitExists(unit) then
      local n,r=UnitName(unit)
      local full=FullName(n,r)
      if full and not seen[full] then seen[full]=true out[#out+1]=full end
    end
  end
  if IsInRaid() then for i=1,GetNumGroupMembers() do add("raid"..i) end
  elseif IsInGroup() then add("player") for i=1,GetNumSubgroupMembers() do add("party"..i) end
  else add("player") end
  while #out>5 do table.remove(out) end
  return out
end
local function IsSenderInGroup(name) local set={} for _,n in ipairs(PartyList()) do set[n]=true end return set[name]==true end
local function SendPkt(op,tbl) if not DB().sync.enabled then return end tbl=tbl or{} tbl.op=op local chan=IsInRaid() and "RAID" or "PARTY" C_ChatInfo.SendAddonMessage(PREFIX,NS.Serialize(tbl),chan) end
local function RealmChanId() local id=GetChannelName(REALM_CHAN) if id and id>0 then return id end end
local function RealmSend(op,p) local id=RealmChanId() if not id then return end p=p or{} p.op=op p.realm=REALM C_ChatInfo.SendAddonMessage(PREFIX_R,NS.Serialize(p),"CHANNEL",id) end

local function BL_GetReason(entry) if type(entry)=="table" then return entry.reason or "" else return entry or "" end end
local function BL_GetSource(entry) if type(entry)=="table" then return entry.source or "local" else return "local" end end
local function BL_Set(name,reason,source) DB().blacklist[name]={reason=reason or "",source=source or "local"} end

------------------------------------------------------------------------
-- Deathroll
------------------------------------------------------------------------
local function DR_GetMages()
  local m1,m2
  for n,r in pairs(DB().roster) do if r.m1 then m1=n end if r.m2 then m2=n end end
  local function base(n) return n and n:gsub("%-.+$","") or nil end
  return m1,m2,base(m1),base(m2)
end
local function DR_ResetSession() DB().deathroll={active=false,upper=0,lastRoller=nil,m1Adj=0,m2Adj=0} end
local function DR_ApplyWin(winnerIsM2)
  local d=DB().deathroll
  local loserAdj=winnerIsM2 and (d.m1Adj or 0) or (d.m2Adj or 0)
  local room=10+math.min(0,loserAdj)
  local delta=math.min(5,room)
  if delta<=0 then return 0 end
  if winnerIsM2 then d.m2Adj=(d.m2Adj or 0)+delta d.m1Adj=(d.m1Adj or 0)-delta
  else d.m1Adj=(d.m1Adj or 0)+delta d.m2Adj=(d.m2Adj or 0)-delta end
  return delta
end
local ROLL_PATTERN do
  local fmt=_G.RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
  fmt=fmt:gsub("([%(%)%[%]%%%.%+%-%*%?%^%$])","%%%1"):gsub("%%%%s","(.+)"):gsub("%%%%d","(%%d+)")
  ROLL_PATTERN="^"..fmt.."$"
end
local function DR_ParseRoll(msg)
  local roller,roll,minv,maxv=msg:match(ROLL_PATTERN)
  if roller then return roller:gsub("%-.+$",""),tonumber(roll),tonumber(minv),tonumber(maxv) end
end

------------------------------------------------------------------------
-- Roster & Pricing
------------------------------------------------------------------------
local function EnsureRoster(names)
  local R=DB().roster
  for _,n in ipairs(names) do if not R[n] then R[n]={m1=false,m2=false,m1f=false,m2f=false,paid=0,done=0} end end
  for n,_ in pairs(R) do local keep=false for _,pn in ipairs(names) do if pn==n then keep=true break end end if not keep then R[n]=nil end end
end

local function Buyers()
  local list={}
  for n,r in pairs(DB().roster) do if not r.m1 and not r.m2 and not r.m1f and not r.m2f then list[#list+1]=n end end
  table.sort(list) return list
end

local function PricePerRun()
  local p5=DB().pricePer5 or 0 local r=DB().runsPerPack or 5
  r=r>0 and r or 1
  return math.floor(p5/r)
end

------------------------------------------------------------------------
-- End Run
------------------------------------------------------------------------
local function EndRun()
  local tEnd=now()
  local start=tEnd-1
  if DB().runsLog[1] and DB().runsLog[1].endts then start=DB().runsLog[1].endts end
  local dur=tEnd-start
  local new={start=start,endts=tEnd,dur=dur,kills=0,value=0,coin=0,excluded=false}
  table.insert(DB().runsLog,1,new) while #DB().runsLog>15 do table.remove(DB().runsLog) end

  local sumCoin=0 for _,ev in ipairs(DB().coinEvents or{}) do if ev.t>=start and ev.t<=tEnd then sumCoin=sumCoin+(ev.copper or 0) end end
  new.coin=sumCoin

  local ppr=PricePerRun()
  local prevLeft={}
  for _,n in ipairs(Buyers()) do local r=DB().roster[n] local paidRuns=math.floor((r.paid or 0)/ppr) prevLeft[n]=math.max(0,paidRuns-(r.done or 0)) end
  for n,r in pairs(DB().roster) do if not (r.m1 or r.m2 or r.m1f or r.m2f) then local paidRuns=math.floor((r.paid or 0)/ppr) local left=math.max(0,paidRuns-(r.done or 0)) if left>0 then r.done=(r.done or 0)+1 end end end

  if UI.RefreshRuns then UI.RefreshRuns() end if UI.RefreshParty then UI.RefreshParty() end if OVERLAY.Refresh then OVERLAY.Refresh() end

  local lines={} lines[#lines+1]=("Reset → %s — completion:"):format(DB().dungeon or "X Boost")
  for _,n in ipairs(Buyers()) do local r=DB().roster[n] local paidRuns=math.floor((r.paid or 0)/ppr) local done=r.done or 0 local left=math.max(0,paidRuns-done) lines[#lines+1]=("%s  done %d/%d (left %d)"):format(n,done,paidRuns,left) end
  for _,l in ipairs(lines) do announce(l) end
end
------------------------------------------------------------------------
-- UI Helpers
------------------------------------------------------------------------
local function NoWrap(fs) fs:SetWordWrap(false) if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end fs:SetMaxLines(1) return fs end
local function Cell(parent,x,w,just,font)
  local fs=parent:CreateFontString(nil,"OVERLAY",font or "GameFontHighlight")
  fs:SetPoint("LEFT",parent,"LEFT",x,0)
  fs:SetWidth(w) fs:SetHeight(18) fs:SetJustifyH(just or "LEFT")
  return NoWrap(fs)
end
local function Section(parent,x,y,w,h,title)
  local f=CreateFrame("Frame",nil,parent,"BackdropTemplate")
  f:SetPoint("TOPLEFT",x,y) f:SetSize(w,h)
  f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
  f:SetBackdropColor(0,0,0,0.6) f:SetBackdropBorderColor(0.2,0.6,1,0.9)
  local cap=f:CreateFontString(nil,"OVERLAY","GameFontNormal") cap:SetPoint("TOPLEFT",8,-6) cap:SetText(title)
  local body=CreateFrame("Frame",nil,f) body:SetPoint("TOPLEFT",6,-22) body:SetPoint("BOTTOMRIGHT",-6,6) body:SetClipsChildren(true) f.body=body
  return f
end

UI,OVERLAY={},{}

------------------------------------------------------------------------
-- Overlay Window
------------------------------------------------------------------------
local function BuildOverlay()
  if BoostSplitOverlay then return end
  local f=CreateFrame("Frame","BoostSplitOverlay",UIParent,"BackdropTemplate")
  f:SetSize(580,240)
  f:SetPoint("CENTER",0,120)
  f:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
  f:SetBackdropColor(0,0,0,DB().overlayAlpha or 0.95)
  f:SetMovable(true) f:EnableMouse(true)

  f:SetResizable(true) f:SetMinResize(420,200) f:SetMaxResize(900,600)
  local sizer=CreateFrame("Button",nil,f)
  sizer:SetPoint("BOTTOMRIGHT",-2,2) sizer:SetSize(16,16)
  sizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  sizer:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  sizer:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  sizer:SetScript("OnMouseDown",function() f:StartSizing("BOTTOMRIGHT") end)
  sizer:SetScript("OnMouseUp",function() f:StopMovingOrSizing() end)

  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart",f.StartMoving)
  f:SetScript("OnDragStop",f.StopMovingOrSizing)

  local brand=f:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge")
  brand:SetPoint("TOP",0,-6) brand:SetText("BoostingSplits")

  local mainBtn=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
  mainBtn:SetSize(70,20) mainBtn:SetPoint("TOPLEFT",8,-8) mainBtn:SetText("Main")
  mainBtn:SetScript("OnClick",function() if BoostSplitFrame then BoostSplitFrame:Show() end end)

  local lines={}
  for i=1,7 do
    local fs=f:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    fs:SetPoint("TOPLEFT",12,-30-(i-1)*18) fs:SetPoint("RIGHT",-12,0)
    fs:SetJustifyH("LEFT") fs:SetWordWrap(false)
    lines[i]=fs
  end

  local refund=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
  refund:SetSize(140,22) refund:SetPoint("BOTTOM",f,"BOTTOM",-76,8) refund:SetText("Refund Boost")
  local reset=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
  reset:SetSize(140,22) reset:SetPoint("BOTTOM",f,"BOTTOM",76,8) reset:SetText("Reset Instance")

  refund:SetScript("OnClick",function() NS.RefundBoost() end)
  reset:SetScript("OnClick",function() EndRun() ResetInstances() end)

  function OVERLAY.Refresh()
    local i=1
    for _,n in ipairs(Buyers()) do
      if i>#lines then break end
      local r=DB().roster[n]
      local ppr=PricePerRun()
      local paidRuns=math.floor((r.paid or 0)/ppr)
      local left=math.max(0,paidRuns-(r.done or 0))
      lines[i]:SetText(("%s — %d left"):format(n,left))
      i=i+1
    end
    for j=i,#lines do lines[j]:SetText("") end
  end

  BoostSplitOverlay=f
end

------------------------------------------------------------------------
-- Main Window (tabs)
------------------------------------------------------------------------
local panels={}
local function BuildMain()
  if BoostSplitFrame then return end
  local frame=CreateFrame("Frame","BoostSplitFrame",UIParent,"BackdropTemplate")
  frame:SetSize(1020,670) frame:SetPoint("CENTER")
  frame:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=16,insets={left=5,right=5,top=5,bottom=5}})
  frame:SetBackdropColor(0,0,0,DB().mainAlpha or 0.95)
  frame:EnableMouse(true) frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton") frame:SetScript("OnDragStart",frame.StartMoving) frame:SetScript("OnDragStop",frame.StopMovingOrSizing)
  frame:EnableKeyboard(false)

  local title=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge")
  title:SetPoint("TOP",0,-8) title:SetText("BoostingSplits\n|cff88ccff: rewritten|r")
  local close=CreateFrame("Button",nil,frame,"UIPanelCloseButton")
  close:SetPoint("TOPRIGHT",2,-2)

  local tabNames={"Main","Party","Runs","Blacklist","Settings","Loot Log","History"}
  for i=1,#tabNames do
    local b=CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    b:SetSize(120,22) b:SetPoint("TOPLEFT",12+(i-1)*122,-56) b:SetText(tabNames[i])
    panels[i]=CreateFrame("Frame",nil,frame) panels[i]:SetAllPoints() panels[i]:Hide()
    b:SetScript("OnClick",function() for j=1,#panels do panels[j]:Hide() end panels[i]:Show() end)
  end
  panels[1]:Show()

  -------------------------------------------------- Main tab
  do
    local p=panels[1]
    local sum=Section(p,12,-88,996,120,"Summary (live)")
    local sb=sum.body
    local sM1=Cell(sb,6,480,"LEFT","GameFontHighlight") sM1:SetPoint("TOPLEFT",6,-10)
    local sM2=Cell(sb,6,480,"LEFT","GameFontHighlight") sM2:SetPoint("TOPLEFT",6,-34)
    local sPot=Cell(sb,6,960,"LEFT","GameFontNormalLarge") sPot:SetPoint("TOPLEFT",6,-64) sPot:SetTextColor(1,0.9,0.2)

    local function runsCount() local n=0 for _,e in ipairs(DB().runsLog or{}) do if not e.excluded and e.endts then n=n+1 end end return n end
    local function friendCompPerFriend() return PricePerRun()*runsCount() end

    local function estSplit()
      local traded=0 for n,r in pairs(DB().roster) do if not (r.m1 or r.m2 or r.m1f or r.m2f) then traded=traded+(r.paid or 0) end end
      local vendorAdd=DB().includeVendorInSplit and (DB().vendorGoldSession or 0) or 0
      local marketAdd=DB().includeMarketValueInSplit and ((DB().itemsValueSession or 0)+(DB().greyPool or 0)) or 0
      local pot=traded+vendorAdd+marketAdd
      if DB().soloBoost then return pot,pot,0 end
      local basePct2=clamp(DB().mage2Pct or 35,0,100)/100 local basePct1=1-basePct2
      local d=DB().deathroll or {} local adj1=clamp((tonumber(d.m1Adj or 0) or 0)/100,-1,1)
      local pct1=clamp(basePct1+adj1,0,1) local pct2=1-pct1
      local m1Pay=math.floor(pot*pct1) local m2Pay=pot-m1Pay
      return pot,m1Pay,m2Pay
    end

    function UI.RefreshSummary()
      local m1,m2,m1b,m2b=DR_GetMages()
      local m1s=(m1 and DB().boosterGoldStart[m1]) or 0
      local m2s=(m2 and DB().boosterGoldStart[m2]) or 0
      local m1c=(m1 and DB().boosterGoldCurrent[m1]) or 0
      local m2c=(m2 and DB().boosterGoldCurrent[m2]) or 0
      local pot,m1pay,m2pay=estSplit()
      sM1:SetText(("%s: %s → %s   |   Est cut: %s"):format(m1b or "Mage 1",fmtCoins(m1s),fmtCoins(m1c),fmtCoins(m1pay)))
      sM2:SetText(("%s: %s → %s   |   Est cut: %s"):format(m2b or "Mage 2",fmtCoins(m2s),fmtCoins(m2c),fmtCoins(m2pay)))
      sPot:SetText(("Pot: %s"):format(fmtCoins(pot)))
    end

    -- Pricing section
    local pricing=Section(p,12,-218,470,160,"Pricing")
    local s=pricing.body
    local l1=s:CreateFontString(nil,"OVERLAY","GameFontNormal") l1:SetPoint("TOPLEFT",6,-6) l1:SetText("Price per 5:")
    local e1=CreateFrame("EditBox",nil,s,"InputBoxTemplate") e1:SetPoint("LEFT",l1,"RIGHT",8,0) e1:SetSize(80,20) e1:SetNumeric(true)
    local l2=s:CreateFontString(nil,"OVERLAY","GameFontNormal") l2:SetPoint("TOPLEFT",6,-36) l2:SetText("Runs:")
    local e2=CreateFrame("EditBox",nil,s,"InputBoxTemplate") e2:SetPoint("LEFT",l2,"RIGHT",8,0) e2:SetSize(40,20) e2:SetNumeric(true)
    local l3=s:CreateFontString(nil,"OVERLAY","GameFontNormal") l3:SetPoint("TOPLEFT",6,-66) l3:SetText("Price per run:")
    local pprFS=s:CreateFontString(nil,"OVERLAY","GameFontHighlight") pprFS:SetPoint("LEFT",l3,"RIGHT",8,0)
    local save=CreateFrame("Button",nil,s,"UIPanelButtonTemplate") save:SetSize(120,20) save:SetPoint("TOPLEFT",6,-96) save:SetText("Save Inputs")

    local function refreshPPR() local p5g=tonumber(e1:GetNumber()) or 0 local runs=tonumber(e2:GetNumber()) or 1 if runs<1 then runs=1 end pprFS:SetText(fmtCoins(math.floor((p5g*10000)/runs))) end
    e1:SetNumber((DB().pricePer5 or 0)/10000) e2:SetNumber(DB().runsPerPack or 5) refreshPPR()
    e1:SetScript("OnTextChanged",refreshPPR) e2:SetScript("OnTextChanged",refreshPPR)
    save:SetScript("OnClick",function() DB().pricePer5=math.max(0,e1:GetNumber() or 0)*10000 DB().runsPerPack=clamp(e2:GetNumber() or 5,1,50) printLocal("Saved price/runs.") if UI.RefreshSummary then UI.RefreshSummary() end end)

    -- Actions section
    local actions=Section(p,12,-388,470,110,"Actions")
    local a=actions.body
    local finish=CreateFrame("Button",nil,a,"UIPanelButtonTemplate") finish:SetSize(140,22) finish:SetPoint("TOPLEFT",6,-6) finish:SetText("Finish Boost")
    local refund=CreateFrame("Button",nil,a,"UIPanelButtonTemplate") refund:SetSize(140,22) refund:SetPoint("LEFT",finish,"RIGHT",8,0) refund:SetText("Refund Boost")
    refund:SetScript("OnClick",function() NS.RefundBoost() end)
    finish:SetScript("OnClick",function() NS.FinishBoost() end)
  end -- end main tab
  -------------------------------------------------- Party tab
  do
    local p=panels[2]
    local roster=Section(p,12,-88,996,520,"Party / Roster")
    local sb=roster.body
    local list={}
    for i=1,15 do
      local fs=Cell(sb,6,960,"LEFT","GameFontHighlight")
      fs:SetPoint("TOPLEFT",6,-(i-1)*18)
      list[i]=fs
    end
    function UI.RefreshParty()
      EnsureRoster(PartyList())
      local buyers=Buyers()
      local i=1
      for _,n in ipairs(buyers) do
        if i>#list then break end
        local r=DB().roster[n]
        list[i]:SetText(("%s — paid %s, done %d"):format(n,fmtCoins(r.paid or 0),r.done or 0))
        i=i+1
      end
      for j=i,#list do list[j]:SetText("") end
    end
  end

  -------------------------------------------------- Runs tab
  do
    local p=panels[3]
    local log=Section(p,12,-88,996,520,"Runs Log")
    local sb=log.body
    local list={}
    for i=1,15 do
      local fs=Cell(sb,6,960,"LEFT","GameFontHighlight")
      fs:SetPoint("TOPLEFT",6,-(i-1)*18)
      list[i]=fs
    end
    function UI.RefreshRuns()
      local i=1
      for _,e in ipairs(DB().runsLog) do
        if i>#list then break end
        local line=("%s | %s | %s"):format(date("%H:%M",e.endts or 0),fmtHMS(e.dur or 0),fmtCoins(e.coin or 0))
        list[i]:SetText(line)
        i=i+1
      end
      for j=i,#list do list[j]:SetText("") end
    end
  end

  -------------------------------------------------- Blacklist tab
  do
    local p=panels[4]
    local bl=Section(p,12,-88,996,520,"Blacklist")
    local sb=bl.body
    local list={}
    for i=1,15 do
      local fs=Cell(sb,6,960,"LEFT","GameFontHighlight")
      fs:SetPoint("TOPLEFT",6,-(i-1)*18)
      list[i]=fs
    end
    function UI.RefreshBlacklist()
      local i=1
      for name,entry in pairs(DB().blacklist) do
        if i>#list then break end
        list[i]:SetText(("%s — %s (%s)"):format(name,BL_GetReason(entry),BL_GetSource(entry)))
        i=i+1
      end
      for j=i,#list do list[j]:SetText("") end
    end
  end

  -------------------------------------------------- Settings tab
  do
    local p=panels[5]
    local opts=Section(p,12,-88,996,520,"Settings")
    local sb=opts.body
    local l1=sb:CreateFontString(nil,"OVERLAY","GameFontNormal")
    l1:SetPoint("TOPLEFT",6,-6) l1:SetText("Announce Channel: AUTO/PARTY/RAID")
    local e1=CreateFrame("EditBox",nil,sb,"InputBoxTemplate")
    e1:SetPoint("LEFT",l1,"RIGHT",8,0) e1:SetSize(120,20)
    e1:SetText(DB().announce or "AUTO")
    e1:SetScript("OnEnterPressed",function(self)
      DB().announce=self:GetText()
      printLocal("Saved announce channel.")
    end)
  end

  -------------------------------------------------- Loot Log tab
  do
    local p=panels[6]
    local log=Section(p,12,-88,996,520,"Loot Log")
    local sb=log.body
    local list={}
    for i=1,15 do
      local fs=Cell(sb,6,960,"LEFT","GameFontHighlight")
      fs:SetPoint("TOPLEFT",6,-(i-1)*18)
      list[i]=fs
    end
    function UI.RefreshLoot()
      local i=1
      for _,ev in ipairs(DB().lootEvents or{}) do
        if i>#list then break end
        list[i]:SetText(("%s — %s"):format(date("%H:%M",ev.t or 0),ev.link or "?"))
        i=i+1
      end
      for j=i,#list do list[j]:SetText("") end
    end
  end

  -------------------------------------------------- History tab
  do
    local p=panels[7]
    local hist=Section(p,12,-88,996,520,"History")
    local sb=hist.body
    local list={}
    for i=1,15 do
      local fs=Cell(sb,6,960,"LEFT","GameFontHighlight")
      fs:SetPoint("TOPLEFT",6,-(i-1)*18)
      list[i]=fs
    end
    function UI.RefreshHistory()
      local i=1
      for _,ev in ipairs(DB().historyBoosts or{}) do
        if i>#list then break end
        list[i]:SetText(("%s — %s"):format(date("%m/%d %H:%M",ev.ts or 0),ev.summary or "?"))
        i=i+1
      end
      for j=i,#list do list[j]:SetText("") end
    end
  end
end -- end BuildMain
------------------------------------------------------------------------
-- Refunds & Finish
------------------------------------------------------------------------
function NS.CalcRefunds()
  local ppr=PricePerRun() local out={}
  for n,r in pairs(DB().roster) do
    if not (r.m1 or r.m2 or r.m1f or r.m2f) then
      local paidRuns=math.floor((r.paid or 0)/ppr)
      local left=math.max(0,paidRuns-(r.done or 0))
      if left>0 then out[n]=left*ppr end
    end
  end
  return out
end

function NS.RefundBoost()
  local owed=NS.CalcRefunds()
  local any=false for _ in pairs(owed) do any=true break end
  if not any then printLocal("No refunds are due.") return end
  announce("Refunds (paid minus completed runs):")
  for n,c in pairs(owed) do announce(("%s → %s"):format(n,fmtCoins(c))) end
end

function NS.FinishBoost()
  local pot,m1pay,m2pay
  do
    local traded=0
    for n,r in pairs(DB().roster) do
      if not (r.m1 or r.m2 or r.m1f or r.m2f) then
        traded=traded+(r.paid or 0)
      end
    end
    pot=traded
    if DB().soloBoost then
      m1pay=pot m2pay=0
    else
      local basePct2=clamp(DB().mage2Pct or 35,0,100)/100
      local basePct1=1-basePct2
      m1pay=math.floor(pot*basePct1)
      m2pay=pot-m1pay
    end
  end
  announce(("Boost finished. Pot: %s. Mage1: %s. Mage2: %s"):format(fmtCoins(pot),fmtCoins(m1pay),fmtCoins(m2pay)))
  table.insert(DB().historyBoosts,1,{ts=now(),summary=("Pot %s, M1 %s, M2 %s"):format(fmtCoins(pot),fmtCoins(m1pay),fmtCoins(m2pay))})
  while #DB().historyBoosts>20 do table.remove(DB().historyBoosts) end
  if UI.RefreshHistory then UI.RefreshHistory() end
end
------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
F:RegisterEvent("ADDON_LOADED")
F:RegisterEvent("PLAYER_LOGIN")
F:RegisterEvent("GROUP_ROSTER_UPDATE")
F:RegisterEvent("CHAT_MSG_ADDON")
F:RegisterEvent("CHAT_MSG_LOOT")
F:RegisterEvent("CHAT_MSG_MONEY")
F:RegisterEvent("CHAT_MSG_SYSTEM")

F:SetScript("OnEvent",function(self,event,...)
  if event=="ADDON_LOADED" then
    local name=...
    if name==ADDON then
      EnsureDefaults()
      printLocal("BoostSplit loaded. Use /bs to open.")
    end

  elseif event=="PLAYER_LOGIN" then
    BuildOverlay() BuildMain()
    if DB().overlayEnabled and BoostSplitOverlay then BoostSplitOverlay:Show() end

  elseif event=="GROUP_ROSTER_UPDATE" then
    if UI.RefreshParty then UI.RefreshParty() end
    if UI.RefreshSummary then UI.RefreshSummary() end
    if OVERLAY.Refresh then OVERLAY.Refresh() end

  elseif event=="CHAT_MSG_SYSTEM" then
    local msg=...
    local roller,roll,minv,maxv=DR_ParseRoll(msg)
    if roller and roll and minv and maxv then
      local d=DB().deathroll
      if d and d.active then
        d.lastRoller=roller d.upper=roll
        if roll==1 then
          local winM2=(roller==DB().mage2Name)
          local delta=DR_ApplyWin(winM2)
          announce(("Deathroll: %s rolled 1 → %s gains %+d%%"):format(roller,winM2 and "Mage2" or "Mage1",delta))
        end
        if OVERLAY.Refresh then OVERLAY.Refresh() end
      end
    end

  elseif event=="CHAT_MSG_ADDON" then
    local prefix,msg,chan,sender=...
    if prefix==PREFIX and IsSenderInGroup(sender) then
      local t=NS.Deserialize(msg)
      if type(t)=="table" and t.op then MarkSynced(sender) end
    elseif prefix==PREFIX_R then
      -- realm sync handler (not expanded in rewrite)
    end

  elseif event=="CHAT_MSG_LOOT" then
    local msg,_,_,_,player=...
    table.insert(DB().lootEvents,{t=now(),msg=msg,player=player})
    if UI.RefreshLoot then UI.RefreshLoot() end

  elseif event=="CHAT_MSG_MONEY" then
    local msg=...
    table.insert(DB().coinEvents,{t=now(),msg=msg})
  end
end)

------------------------------------------------------------------------
-- Slash Commands
------------------------------------------------------------------------
SLASH_BOOSTSPLIT1="/bs"
SLASH_BOOSTSPLIT2="/bsoverlay"
SlashCmdList.BOOSTSPLIT=function(msg)
  msg=(msg or "")
  if msg:lower():match("^%s*overlay") then
    if BoostSplitOverlay then
      local s=not BoostSplitOverlay:IsShown()
      BoostSplitOverlay:SetShown(s) DB().overlayEnabled=s
    end
    return
  end
  if msg:lower():match("^%s*help") then
    printLocal("Commands: /bs — toggle main | /bs overlay — toggle overlay")
    return
  end
  if BoostSplitFrame then
    if BoostSplitFrame:IsShown() then BoostSplitFrame:Hide() else BoostSplitFrame:Show() end
  end
end
