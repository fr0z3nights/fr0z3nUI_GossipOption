local addonName, ns = ...
ns = ns or {}

local lastSelectAt = 0
local frame = CreateFrame("Frame")

local queueOverlayButton = nil
local queueOverlayHint = nil
local queueOverlayPendingHide = false
local queueOverlayWatchdogElapsed = 0
local queueOverlaySuppressUntil = 0
local queueOverlayProposalToken = 0
local queueOverlayDismissedToken = 0

local HideQueueOverlay

local function SuppressQueueOverlay(seconds)
    local now = (GetTime and GetTime()) or 0
    local untilTime = now + (seconds or 0)
    if untilTime > (queueOverlaySuppressUntil or 0) then
        queueOverlaySuppressUntil = untilTime
    end
    HideQueueOverlay()
end

local function DismissQueueOverlayForCurrentProposal()
    -- Dismiss until the current proposal ends (or a new one starts).
    if (queueOverlayProposalToken or 0) > 0 then
        queueOverlayDismissedToken = queueOverlayProposalToken
    end
    HideQueueOverlay()
end

local function Print(msg)
    print("|cff00ccff[FGO]|r " .. tostring(msg))
end

local function NormalizeID(value)
    if type(value) == "string" then
        local n = tonumber(value)
        if n then
            return n
        end
    end
    return value
end

local function MigrateDisabledFlatToNested(disabled)
    if type(disabled) ~= "table" then
        return {}
    end

    local sawLegacy = false
    for k, v in pairs(disabled) do
        if type(v) == "table" then
            -- Already nested.
            return disabled
        end
        if v and type(k) == "string" and k:find(":", 1, true) then
            sawLegacy = true
        end
    end
    if not sawLegacy then
        return disabled
    end

    local nested = {}
    for k, v in pairs(disabled) do
        if v and type(k) == "string" then
            local npc, opt = k:match("^(%d+):(%d+)$")
            if npc and opt then
                local npcID = tonumber(npc)
                local optID = tonumber(opt)
                if npcID and optID then
                    nested[npcID] = nested[npcID] or {}
                    nested[npcID][optID] = true
                end
            end
        end
    end
    return nested
end

local function InitSV()
    AutoGossip_Acc = AutoGossip_Acc or {}
    AutoGossip_Char = AutoGossip_Char or {}
    AutoGossip_Settings = AutoGossip_Settings or { disabled = {}, disabledDB = {}, tutorialOffAcc = false, hideTooltipBorderAcc = true }
    AutoGossip_CharSettings = AutoGossip_CharSettings or { disabled = {} }
    AutoGossip_UI = AutoGossip_UI or {}

    if type(AutoGossip_Settings.disabled) ~= "table" then
        AutoGossip_Settings.disabled = {}
    end
    if type(AutoGossip_Settings.disabledDB) ~= "table" then
        AutoGossip_Settings.disabledDB = {}
    end

    -- Tutorials: migrate from legacy tutorialOffAcc => tutorialEnabledAcc.
    if type(AutoGossip_Settings.tutorialEnabledAcc) ~= "boolean" then
        if type(AutoGossip_Settings.tutorialOffAcc) == "boolean" then
            AutoGossip_Settings.tutorialEnabledAcc = (not AutoGossip_Settings.tutorialOffAcc)
        else
            AutoGossip_Settings.tutorialEnabledAcc = true
        end
    end
    -- Keep legacy key in sync for any older modules.
    if type(AutoGossip_Settings.tutorialOffAcc) ~= "boolean" then
        AutoGossip_Settings.tutorialOffAcc = (not AutoGossip_Settings.tutorialEnabledAcc)
    end

    if type(AutoGossip_Settings.hideTooltipBorderAcc) ~= "boolean" then
        -- Hide tooltip borders ON (default).
        AutoGossip_Settings.hideTooltipBorderAcc = true
    end
    if type(AutoGossip_Settings.debugAcc) ~= "boolean" then
        AutoGossip_Settings.debugAcc = false
    end

    -- Queue accept overlay: 3-state UX via two SVs.
    -- - Acc On: queueAcceptAcc=true,  queueAcceptMode="acc"
    -- - On:     queueAcceptAcc=false, queueAcceptMode="on"
    -- - Off:    queueAcceptAcc=false, queueAcceptMode="acc" (inherit)
    if type(AutoGossip_Settings.queueAcceptAcc) ~= "boolean" then
        AutoGossip_Settings.queueAcceptAcc = true
    end
    if type(AutoGossip_CharSettings.queueAcceptMode) ~= "string" then
        AutoGossip_CharSettings.queueAcceptMode = "acc"
    end
    if AutoGossip_CharSettings.queueAcceptMode ~= "acc" and AutoGossip_CharSettings.queueAcceptMode ~= "on" then
        AutoGossip_CharSettings.queueAcceptMode = "acc"
    end
    if type(AutoGossip_CharSettings.disabled) ~= "table" then
        AutoGossip_CharSettings.disabled = {}
    end

    -- Migrate legacy flat keys ("npcID:optionID") => nested disabled[npcID][optionID].
    AutoGossip_Settings.disabled = MigrateDisabledFlatToNested(AutoGossip_Settings.disabled)
    AutoGossip_Settings.disabledDB = MigrateDisabledFlatToNested(AutoGossip_Settings.disabledDB)
    AutoGossip_CharSettings.disabled = MigrateDisabledFlatToNested(AutoGossip_CharSettings.disabled)
end

local function GetQueueAcceptState()
    InitSV()
    if AutoGossip_Settings and AutoGossip_Settings.queueAcceptAcc then
        return "acc"
    end
    if AutoGossip_CharSettings and AutoGossip_CharSettings.queueAcceptMode == "on" then
        return "char"
    end
    return "off"
end

local function SetQueueAcceptState(state)
    InitSV()
    if state == "acc" then
        AutoGossip_Settings.queueAcceptAcc = true
        AutoGossip_CharSettings.queueAcceptMode = "acc"
        return
    end
    if state == "char" then
        AutoGossip_Settings.queueAcceptAcc = false
        AutoGossip_CharSettings.queueAcceptMode = "on"
        return
    end
    AutoGossip_Settings.queueAcceptAcc = false
    AutoGossip_CharSettings.queueAcceptMode = "acc"
end

local function IsQueueAcceptEnabled()
    return GetQueueAcceptState() ~= "off"
end

local function HasActiveLfgProposal()
    if type(GetLFGProposal) == "function" then
        local proposalExists = GetLFGProposal()
        return proposalExists and true or false
    end

    local dialog = _G and _G["LFGDungeonReadyDialog"]
    if dialog and dialog.IsShown and dialog:IsShown() then
        return true
    end
    local popup = _G and _G["LFGDungeonReadyPopup"]
    if popup and popup.IsShown and popup:IsShown() then
        return true
    end
    return false
end

local function FindLfgAcceptButton()
    local candidates = {
        _G and _G["LFGDungeonReadyDialogEnterDungeonButton"],
        _G and _G["LFGDungeonReadyDialogAcceptButton"],
        _G and _G["LFGDungeonReadyPopupAcceptButton"],
        _G and _G["LFGDungeonReadyPopupEnterDungeonButton"],
    }

    for _, btn in ipairs(candidates) do
        if btn and btn.IsShown and btn:IsShown() and btn.IsEnabled and btn:IsEnabled() then
            return btn
        end
    end
    return nil
end

local function EnsureQueueOverlay()
    if queueOverlayButton then
        return queueOverlayButton
    end

    local b = CreateFrame("Button", "AutoGossipQueueAcceptOverlay", UIParent, "SecureActionButtonTemplate")
    queueOverlayButton = b

    b:SetAllPoints(UIParent)
    b:SetFrameStrata("BACKGROUND")
    b:SetFrameLevel(1)
    b:EnableMouse(true)
    b:RegisterForClicks("AnyUp")

    -- Configure secure attributes once to avoid tainting Blizzard action buttons.
    -- Using a macro here means we don't need to call :SetAttribute() again at runtime.
    b:SetAttribute("type1", "macro")
    b:SetAttribute("macrotext", table.concat({
        "/click LFGDungeonReadyDialogEnterDungeonButton",
        "/click LFGDungeonReadyDialogAcceptButton",
        "/click LFGDungeonReadyPopupAcceptButton",
        "/click LFGDungeonReadyPopupEnterDungeonButton",
    }, "\n"))

    -- PostClick runs after the secure macro has executed.
    -- - Left click: accept, then dismiss overlay for this proposal.
    -- - Right click: dismiss overlay for this proposal.
    b:SetScript("PostClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            DismissQueueOverlayForCurrentProposal()
            return
        end

        -- After accepting, keep hidden until this invite ends.
        DismissQueueOverlayForCurrentProposal()
    end)

    b:SetScript("OnUpdate", function(self, elapsed)
        if not (self and self.IsShown and self:IsShown()) then
            return
        end

        queueOverlayWatchdogElapsed = (queueOverlayWatchdogElapsed or 0) + (elapsed or 0)
        if queueOverlayWatchdogElapsed < 0.20 then
            return
        end
        queueOverlayWatchdogElapsed = 0

        if not IsQueueAcceptEnabled() then
            HideQueueOverlay()
            return
        end
        if not HasActiveLfgProposal() then
            HideQueueOverlay()
            return
        end

        local acceptButton = FindLfgAcceptButton()
        if not acceptButton then
            HideQueueOverlay()
            return
        end
    end)
    b:Hide()

    local hint = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    queueOverlayHint = hint
    hint:SetAllPoints(UIParent)
    hint:SetFrameStrata("FULLSCREEN_DIALOG")
    hint:EnableMouse(false)

    hint:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    hint:SetBackdropColor(0, 0, 0, 0.35)
    hint:SetBackdropBorderColor(1, 0.82, 0, 0.95)

    local fs = hint:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOP", UIParent, "TOP", 0, -140)
    fs:SetText("|cff00ccff[FGO]|r Queue ready — left click the world to accept (right click to dismiss)")
    hint.text = fs

    do
        local ag = hint:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")

        local a1 = ag:CreateAnimation("Alpha")
        a1:SetFromAlpha(0.15)
        a1:SetToAlpha(1.0)
        a1:SetDuration(0.35)
        a1:SetSmoothing("OUT")

        local a2 = ag:CreateAnimation("Alpha")
        a2:SetFromAlpha(1.0)
        a2:SetToAlpha(0.15)
        a2:SetDuration(0.35)
        a2:SetSmoothing("IN")
        a2:SetOrder(2)

        hint.flash = ag
    end

    hint:Hide()

    return b
end

HideQueueOverlay = function()
    if not (queueOverlayButton and queueOverlayButton.IsShown and queueOverlayButton:IsShown()) then
        queueOverlayPendingHide = false
        if queueOverlayHint and queueOverlayHint.Hide then
            queueOverlayHint:Hide()
        end
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        queueOverlayPendingHide = true
        return
    end

    queueOverlayButton:Hide()
    if queueOverlayHint and queueOverlayHint.flash and queueOverlayHint.flash.IsPlaying and queueOverlayHint.flash:IsPlaying() then
        queueOverlayHint.flash:Stop()
    end
    if queueOverlayHint and queueOverlayHint.Hide then
        queueOverlayHint:Hide()
    end
    queueOverlayPendingHide = false
end

local function ShowQueueOverlayIfNeeded()
    local now = (GetTime and GetTime()) or 0
    if (queueOverlaySuppressUntil or 0) > now then
        return
    end

    if (queueOverlayProposalToken or 0) > 0 and (queueOverlayDismissedToken or 0) == (queueOverlayProposalToken or 0) then
        return
    end

    if not IsQueueAcceptEnabled() then
        HideQueueOverlay()
        return
    end
    if not HasActiveLfgProposal() then
        HideQueueOverlay()
        queueOverlayProposalToken = 0
        queueOverlayDismissedToken = 0
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        return
    end

    local acceptButton = FindLfgAcceptButton()
    if not acceptButton then
        HideQueueOverlay()
        return
    end

    local overlay = EnsureQueueOverlay()
    overlay:Show()
    if queueOverlayHint and queueOverlayHint.Show then
        queueOverlayHint:Show()
        if queueOverlayHint.flash and queueOverlayHint.flash.Play then
            queueOverlayHint.flash:Play()
        end
    end
end

local function GetNpcIDFromGuid(guid)
    if type(guid) ~= "string" then
        return nil
    end
    local _, _, _, _, _, npcID = strsplit("-", guid)
    return tonumber(npcID)
end

local function GetCurrentNpcID()
    local guid = UnitGUID("npc") or UnitGUID("target")
    local npcID = GetNpcIDFromGuid(guid)
    if npcID then
        return npcID
    end

    -- Fallback: some gossip-like interactions (objects / journals) don't have an "npc" unit.
    if C_PlayerInteractionManager and C_PlayerInteractionManager.GetInteractionTarget then
        local targetGuid = C_PlayerInteractionManager.GetInteractionTarget()
        npcID = GetNpcIDFromGuid(targetGuid)
        if npcID then
            return npcID
        end
    end
    return nil
end

local function GetCurrentNpcName()
    return UnitName("npc") or UnitName("target")
end

local function GetCurrentZoneName()
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo then
        local mapID = C_Map.GetBestMapForUnit("player")
        if mapID then
            local info = C_Map.GetMapInfo(mapID)
            if info and type(info.name) == "string" and info.name ~= "" then
                return info.name
            end
        end
    end
    if GetRealZoneText then
        local z = GetRealZoneText()
        if type(z) == "string" and z ~= "" then
            return z
        end
    end
    return ""
end

local function MakeRuleKey(npcID, optionID)
    return tostring(npcID) .. ":" .. tostring(optionID)
end

local function IsDisabled(scope, npcID, optionID)
    npcID = NormalizeID(npcID)
    optionID = NormalizeID(optionID)

    if scope == "acc" then
        local t = AutoGossip_Settings.disabled
        local npcTable = t and t[npcID]
        if type(npcTable) == "table" and npcTable[optionID] then
            return true
        end
        -- Backward-compat read for older saves/versions.
        return (t and t[MakeRuleKey(npcID, optionID)]) and true or false
    end

    local t = AutoGossip_CharSettings.disabled
    local npcTable = t and t[npcID]
    if type(npcTable) == "table" and npcTable[optionID] then
        return true
    end
    return (t and t[MakeRuleKey(npcID, optionID)]) and true or false
end

local function SetDisabled(scope, npcID, optionID, disabled)
    npcID = NormalizeID(npcID)
    optionID = NormalizeID(optionID)

    local key = MakeRuleKey(npcID, optionID)
    if scope == "acc" then
        local t = AutoGossip_Settings.disabled
        t[key] = nil
        t[npcID] = t[npcID] or {}
        if disabled then
            t[npcID][optionID] = true
        else
            t[npcID][optionID] = nil
            if next(t[npcID]) == nil then
                t[npcID] = nil
            end
        end
    else
        local t = AutoGossip_CharSettings.disabled
        t[key] = nil
        t[npcID] = t[npcID] or {}
        if disabled then
            t[npcID][optionID] = true
        else
            t[npcID][optionID] = nil
            if next(t[npcID]) == nil then
                t[npcID] = nil
            end
        end
    end
end

local function IsDisabledDB(npcID, optionID)
    npcID = NormalizeID(npcID)
    optionID = NormalizeID(optionID)

    local t = AutoGossip_Settings.disabledDB
    local npcTable = t and t[npcID]
    if type(npcTable) == "table" and npcTable[optionID] then
        return true
    end
    return (t and t[MakeRuleKey(npcID, optionID)]) and true or false
end

local function SetDisabledDB(npcID, optionID, disabled)
    npcID = NormalizeID(npcID)
    optionID = NormalizeID(optionID)

    local key = MakeRuleKey(npcID, optionID)
    local t = AutoGossip_Settings.disabledDB
    t[key] = nil
    t[npcID] = t[npcID] or {}
    if disabled then
        t[npcID][optionID] = true
    else
        t[npcID][optionID] = nil
        if next(t[npcID]) == nil then
            t[npcID] = nil
        end
    end
end

local function GetDbNpcTable(npcID)
    local rules = ns and ns.db and ns.db.rules
    if type(rules) ~= "table" then
        return nil
    end
    local npcTable = rules[npcID]
    if type(npcTable) ~= "table" then
        return nil
    end
    return npcTable
end

local function HasDbRule(npcID, optionID)
    local npcTable = GetDbNpcTable(npcID)
    if not npcTable then
        return false
    end
    if npcTable[optionID] ~= nil then
        return true
    end
    if type(optionID) == "number" then
        return npcTable[tostring(optionID)] ~= nil
    end
    if type(optionID) == "string" then
        local n = tonumber(optionID)
        if n then
            return npcTable[n] ~= nil
        end
    end
    return false
end

local function HasRule(scope, npcID, optionID)
    local db = (scope == "acc") and AutoGossip_Acc or AutoGossip_Char
    local npcTable = db[npcID]
    if type(npcTable) ~= "table" then
        return false
    end
    if npcTable[optionID] ~= nil then
        return true
    end
    if type(optionID) == "number" then
        return npcTable[tostring(optionID)] ~= nil
    end
    if type(optionID) == "string" then
        local n = tonumber(optionID)
        if n then
            return npcTable[n] ~= nil
        end
    end
    return false
end

local function DeleteRule(scope, npcID, optionID)
    if not (npcID and optionID) then
        return
    end
    local db = (scope == "acc") and AutoGossip_Acc or AutoGossip_Char
    local npcTable = db[npcID]
    if type(npcTable) ~= "table" then
        return
    end
    npcTable[optionID] = nil
    if type(optionID) == "number" then
        npcTable[tostring(optionID)] = nil
    elseif type(optionID) == "string" then
        local n = tonumber(optionID)
        if n then
            npcTable[n] = nil
        end
    end
    if next(npcTable) == nil then
        db[npcID] = nil
    end
    SetDisabled(scope, npcID, optionID, false)
end

local function AddRule(scope, npcID, optionID, optionText, optionType)
    if not npcID or not optionID then
        return false, "Missing NPC or option ID"
    end

    local db = (scope == "acc") and AutoGossip_Acc or AutoGossip_Char
    db[npcID] = db[npcID] or {}

    if db[npcID][optionID] then
        return false, "Already exists"
    end

    db[npcID][optionID] = {
        text = optionText or "",
        type = optionType or "",
        addedAt = time(),
        zoneName = GetCurrentZoneName(),
        npcName = GetCurrentNpcName() or "",
    }

    SetDisabled(scope, npcID, optionID, false)
    return true
end

local function FindOptionInfoByID(optionID)
    if not (C_GossipInfo and C_GossipInfo.GetOptions) then
        return nil
    end
    for _, opt in ipairs(C_GossipInfo.GetOptions()) do
        if opt and opt.gossipOptionID == optionID then
            return opt
        end
    end
    return nil
end

local function TryAutoSelect()
    if IsShiftKeyDown() then
        return
    end
    if InCombatLockdown() then
        return
    end
    if not (C_GossipInfo and C_GossipInfo.GetOptions and C_GossipInfo.SelectOption) then
        return
    end

    local npcID = GetCurrentNpcID()
    if not npcID then
        return
    end

    local now = GetTime()
    if now - lastSelectAt < 0.25 then
        return
    end

    local options = C_GossipInfo.GetOptions() or {}

    -- Prefer character rules over account rules, then DB pack.
    for _, scope in ipairs({ "char", "acc" }) do
        local db = (scope == "acc") and AutoGossip_Acc or AutoGossip_Char
        local npcTable = db[npcID]
        if type(npcTable) == "table" then
            for _, opt in ipairs(options) do
                local optionID = opt and opt.gossipOptionID
                if optionID and npcTable[optionID] and (not IsDisabled(scope, npcID, optionID)) then
                    lastSelectAt = now
                    C_GossipInfo.SelectOption(optionID)
                    return
                end
            end
        end
    end

    local dbNpc = GetDbNpcTable(npcID)
    if dbNpc then
        for _, opt in ipairs(options) do
            local optionID = opt and opt.gossipOptionID
            if optionID and (dbNpc[optionID] or dbNpc[tostring(optionID)]) and (not IsDisabledDB(npcID, optionID)) then
                lastSelectAt = now
                C_GossipInfo.SelectOption(optionID)
                return
            end
        end
    end
end

-- UI (layout mirrored from AutoOpen's item entry panel)
local function CreateOptionsWindow()
    if AutoGossipOptions then
        return
    end
    InitSV()

    local f = CreateFrame("Frame", "AutoGossipOptions", UIParent, "BackdropTemplate")
    AutoGossipOptions = f

    do
        local special = _G and _G["UISpecialFrames"]
        if type(special) == "table" then
            local name = "AutoGossipOptions"
            local exists = false
            for i = 1, #special do
                if special[i] == name then
                    exists = true
                    break
                end
            end
            if not exists and table and table.insert then
                table.insert(special, name)
            end
        end
    end

    -- Wider (horizontal) layout
    local FRAME_W, FRAME_H = 760, 440
    f:SetSize(FRAME_W, FRAME_H)

    if AutoGossip_UI and AutoGossip_UI.point then
        f:SetPoint(AutoGossip_UI.point, UIParent, AutoGossip_UI.relPoint or AutoGossip_UI.point, AutoGossip_UI.x or 0, AutoGossip_UI.y or 0)
    else
        f:SetPoint("CENTER")
    end

    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        if self.StopMovingOrSizing then
            self:StopMovingOrSizing()
        end
        local point, _, relPoint, x, y = self:GetPoint(1)
        AutoGossip_UI.point, AutoGossip_UI.relPoint, AutoGossip_UI.x, AutoGossip_UI.y = point, relPoint, x, y
    end)

    f:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        tile = true,
        tileSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0, 0, 0, 0.7)

    local browserPanel = CreateFrame("Frame", nil, f)
    browserPanel:SetAllPoints()
    f.browserPanel = browserPanel

    local editPanel = CreateFrame("Frame", nil, f)
    editPanel:SetAllPoints()
    editPanel:Hide()
    f.editPanel = editPanel

    local togglesPanel = CreateFrame("Frame", nil, f)
    togglesPanel:SetAllPoints()
    togglesPanel:Hide()
    f.togglesPanel = togglesPanel

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetJustifyH("LEFT")
    title:SetText("|cff00ccff[FGO]|r GossipOption")

    local panelTemplatesSetNumTabs = _G and _G["PanelTemplates_SetNumTabs"]
    local panelTemplatesSetTab = _G and _G["PanelTemplates_SetTab"]

    local function SelectTab(self, tabID)
        f.activeTab = tabID
        if f.editPanel then f.editPanel:SetShown(tabID == 1) end
        if f.browserPanel then f.browserPanel:SetShown(tabID == 2) end
        if f.togglesPanel then f.togglesPanel:SetShown(tabID == 3) end
        if tabID == 3 and f.UpdateToggleButtons then
            f.UpdateToggleButtons()
        end
        if type(panelTemplatesSetTab) == "function" then
            panelTemplatesSetTab(f, tabID)
        end
    end
    f.SelectTab = SelectTab

    local function StyleTab(btn)
        if not btn then return end
        btn:SetHeight(22)
        local n = btn.GetNormalTexture and btn:GetNormalTexture() or nil
        if n and n.SetAlpha then n:SetAlpha(0.65) end
        local h = btn.GetHighlightTexture and btn:GetHighlightTexture() or nil
        if h and h.SetAlpha then h:SetAlpha(0.45) end
        local p = btn.GetPushedTexture and btn:GetPushedTexture() or nil
        if p and p.SetAlpha then p:SetAlpha(0.75) end
        local d = btn.GetDisabledTexture and btn:GetDisabledTexture() or nil
        if d and d.SetAlpha then d:SetAlpha(0.40) end
    end

    local tab1 = CreateFrame("Button", "$parentTab1", f, "PanelTabButtonTemplate")
    tab1:SetID(1)
    tab1:SetText("Edit/Add")
    tab1:SetPoint("LEFT", title, "RIGHT", 10, 0)
    tab1:SetScript("OnClick", function(self) f:SelectTab(self:GetID()) end)
    StyleTab(tab1)
    f.tab1 = tab1

    local tab2 = CreateFrame("Button", "$parentTab2", f, "PanelTabButtonTemplate")
    tab2:SetID(2)
    tab2:SetText("Rules")
    tab2:SetPoint("LEFT", tab1, "RIGHT", -16, 0)
    tab2:SetScript("OnClick", function(self) f:SelectTab(self:GetID()) end)
    StyleTab(tab2)
    f.tab2 = tab2

    local tab3 = CreateFrame("Button", "$parentTab3", f, "PanelTabButtonTemplate")
    tab3:SetID(3)
    tab3:SetText("Toggles")
    tab3:SetPoint("LEFT", tab2, "RIGHT", -16, 0)
    tab3:SetScript("OnClick", function(self) f:SelectTab(self:GetID()) end)
    StyleTab(tab3)
    f.tab3 = tab3

    if type(panelTemplatesSetNumTabs) == "function" then
        panelTemplatesSetNumTabs(f, 3)
    end
    if type(panelTemplatesSetTab) == "function" then
        panelTemplatesSetTab(f, 1)
    end

    -- Clear selection when the window closes so reopening starts fresh.
    f:SetScript("OnHide", function()
        f.selectedNpcID = nil
        f.selectedNpcName = nil
        if f.edit and f.edit.SetText then
            f.edit:SetText("")
        end
        if f._currentOptions then
            f._currentOptions = {}
        end
    end)

    local function BumpFont(fs, delta)
        if not (fs and fs.GetFont and fs.SetFont) then
            return
        end
        local fontPath, fontSize, fontFlags = fs:GetFont()
        if fontPath and fontSize then
            fs:SetFont(fontPath, fontSize + (delta or 0), fontFlags)
        end
    end

    local function CloseOptionsWindow()
        if f and f.Hide then
            f:Hide()
        end
    end

    local function CloseGossipWindow()
        if C_GossipInfo and C_GossipInfo.CloseGossip then
            C_GossipInfo.CloseGossip()
            return
        end
        if _G and type(_G["CloseGossip"]) == "function" then
            _G["CloseGossip"]()
            return
        end
        if GossipFrame and GossipFrame.IsShown and GossipFrame:IsShown() then
            if HideUIPanel then
                HideUIPanel(GossipFrame)
            elseif GossipFrame.Hide then
                GossipFrame:Hide()
            end
        end
    end

    -- Edit/Add layout: one full-width area containing 2 stacked boxes.
    local leftArea = CreateFrame("Frame", nil, editPanel)
    leftArea:SetPoint("TOPLEFT", editPanel, "TOPLEFT", 10, -54)
    leftArea:SetPoint("BOTTOMRIGHT", editPanel, "BOTTOMRIGHT", -10, 50)

    -- Legacy container (kept for minimal churn). Not used in the new layout.
    local rightArea = CreateFrame("Frame", nil, editPanel)
    rightArea:Hide()

    -- Rules browser (all rules)
    AutoGossip_UI.treeState = AutoGossip_UI.treeState or {}

    local function GetTreeExpanded(key, defaultValue)
        local v = AutoGossip_UI.treeState[key]
        if v == nil then
            return defaultValue and true or false
        end
        return v and true or false
    end

    local function SetTreeExpanded(key, expanded)
        AutoGossip_UI.treeState[key] = expanded and true or false
    end

    local browserArea = CreateFrame("Frame", nil, browserPanel, "BackdropTemplate")
    browserArea:SetPoint("TOPLEFT", browserPanel, "TOPLEFT", 10, -54)
    browserArea:SetPoint("BOTTOMRIGHT", browserPanel, "BOTTOMRIGHT", -10, 50)
    browserArea:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        tile = true,
        tileSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    browserArea:SetBackdropColor(0, 0, 0, 0.25)

    local browserHint = browserPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    browserHint:SetPoint("BOTTOMLEFT", browserPanel, "BOTTOMLEFT", 12, 28)
    browserHint:SetText("Click a rule to edit; use +/- to expand.")

    local browserEmpty = browserArea:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    browserEmpty:SetPoint("CENTER", browserArea, "CENTER", 0, 0)
    browserEmpty:SetText("No rules found")

    local browserScroll = CreateFrame("ScrollFrame", nil, browserArea, "FauxScrollFrameTemplate")
    browserScroll:SetPoint("TOPLEFT", browserArea, "TOPLEFT", 4, -4)
    browserScroll:SetPoint("BOTTOMRIGHT", browserArea, "BOTTOMRIGHT", -26, 4)
    f.browserScroll = browserScroll

    local BROW_ROW_H = 18
    local BROW_ROWS = 18
    local browRows = {}

    local function CollectAllRules()
        InitSV()
        local out = {}

        local function AddFrom(scope)
            local db = (scope == "acc") and AutoGossip_Acc or AutoGossip_Char
            if type(db) ~= "table" then
                return
            end
            for npcID, npcTable in pairs(db) do
                if type(npcTable) == "table" then
                    for optionID, data in pairs(npcTable) do
                        local numericID = tonumber(optionID) or optionID
                        local text = ""
                        local expansion = "User"
                        local zoneName = "Unknown"
                        local npcName = ""
                        if type(data) == "table" then
                            text = data.text or ""
                            expansion = data.expansion or expansion
                            zoneName = data.zoneName or data.zone or zoneName
                            npcName = data.npcName or npcName
                        end
                        table.insert(out, {
                            scope = scope,
                            npcID = tonumber(npcID) or npcID,
                            optionID = numericID,
                            text = text,
                            expansion = expansion,
                            zone = zoneName,
                            npcName = npcName,
                            isDisabled = IsDisabled(scope, npcID, numericID),
                        })
                    end
                end
            end
        end

        AddFrom("char")
        AddFrom("acc")

        local rules = ns and ns.db and ns.db.rules
        if type(rules) == "table" then
            for npcID, npcTable in pairs(rules) do
                if type(npcTable) == "table" then
                    for optionID, data in pairs(npcTable) do
                        local numericID = tonumber(optionID) or optionID
                        local text = ""
                        local expansion = "DB"
                        local zoneName = "Unknown"
                        local npcName = ""
                        if type(data) == "table" then
                            text = data.text or ""
                            expansion = data.expansion or expansion
                            zoneName = data.zoneName or data.zone or zoneName
                            npcName = data.npcName or npcName
                        end
                        table.insert(out, {
                            scope = "db",
                            npcID = tonumber(npcID) or npcID,
                            optionID = numericID,
                            text = text,
                            expansion = expansion,
                            zone = zoneName,
                            npcName = npcName,
                            isDisabled = IsDisabledDB(npcID, numericID),
                        })
                    end
                end
            end
        end

        return out
    end

    local function BuildVisibleTreeNodes(allRules)
        local expMap = {}
        for _, r in ipairs(allRules) do
            local exp = r.expansion or "Unknown"
            local zone = r.zone or "Unknown"
            expMap[exp] = expMap[exp] or {}
            expMap[exp][zone] = expMap[exp][zone] or {}
            local npcID = r.npcID
            expMap[exp][zone][npcID] = expMap[exp][zone][npcID] or { npcName = r.npcName or "", rules = {} }
            local npcBucket = expMap[exp][zone][npcID]
            if (npcBucket.npcName == "" or npcBucket.npcName == nil) and r.npcName and r.npcName ~= "" then
                npcBucket.npcName = r.npcName
            end
            table.insert(npcBucket.rules, r)
        end

        local exps = {}
        for exp in pairs(expMap) do
            table.insert(exps, exp)
        end
        table.sort(exps)

        local visible = {}
        for _, exp in ipairs(exps) do
            local expKey = "exp:" .. exp
            local expExpanded = GetTreeExpanded(expKey, true)
            table.insert(visible, { kind = "exp", key = expKey, label = exp, level = 0, expanded = expExpanded })

            if expExpanded then
                local zones = {}
                for zone in pairs(expMap[exp]) do
                    table.insert(zones, zone)
                end
                table.sort(zones)
                for _, zone in ipairs(zones) do
                    local zoneKey = "zone:" .. exp .. ":" .. zone
                    local zoneExpanded = GetTreeExpanded(zoneKey, false)
                    table.insert(visible, { kind = "zone", key = zoneKey, label = zone, level = 1, expanded = zoneExpanded, exp = exp })

                    if zoneExpanded then
                        local npcs = {}
                        for npcID in pairs(expMap[exp][zone]) do
                            table.insert(npcs, npcID)
                        end
                        table.sort(npcs, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
                        for _, npcID in ipairs(npcs) do
                            local npcBucket = expMap[exp][zone][npcID]
                            local npcName = npcBucket.npcName
                            local npcLabel = tostring(npcID)
                            if type(npcName) == "string" and npcName ~= "" then
                                npcLabel = npcLabel .. " - " .. npcName
                            end
                            local npcKey = "npc:" .. exp .. ":" .. zone .. ":" .. tostring(npcID)
                            local npcExpanded = GetTreeExpanded(npcKey, false)
                            table.insert(visible, { kind = "npc", key = npcKey, label = npcLabel, level = 2, expanded = npcExpanded, exp = exp, zone = zone, npcID = npcID })

                            if npcExpanded then
                                table.sort(npcBucket.rules, function(a, b)
                                    local sa = tostring(a.scope)
                                    local sb = tostring(b.scope)
                                    if sa ~= sb then
                                        local rank = { char = 1, acc = 2, db = 3 }
                                        return (rank[sa] or 9) < (rank[sb] or 9)
                                    end
                                    return (tonumber(a.optionID) or 0) < (tonumber(b.optionID) or 0)
                                end)
                                for _, rule in ipairs(npcBucket.rules) do
                                    local scopeLabel = (rule.scope == "char") and "C" or "A"
                                    if rule.scope == "db" then
                                        scopeLabel = "DB"
                                    end
                                    local text = rule.text or ""
                                    local line = string.format("[%s] %s: %s", scopeLabel, tostring(rule.optionID), text)
                                    table.insert(visible, {
                                        kind = "rule",
                                        level = 3,
                                        label = line,
                                        rule = rule,
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end

        return visible
    end

    for i = 1, BROW_ROWS do
        local row = CreateFrame("Frame", nil, browserArea)
        row:SetHeight(BROW_ROW_H)
        row:SetPoint("TOPLEFT", browserArea, "TOPLEFT", 8, -6 - (i - 1) * BROW_ROW_H)
        row:SetPoint("TOPRIGHT", browserArea, "TOPRIGHT", -8, -6 - (i - 1) * BROW_ROW_H)

        local expBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        expBtn:SetSize(18, BROW_ROW_H - 2)
        expBtn:SetPoint("LEFT", row, "LEFT", 0, 0)
        expBtn:SetText("+")
        row.btnExpand = expBtn

        local del = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        del:SetSize(34, BROW_ROW_H - 2)
        del:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        del:SetText("Del")
        row.btnDel = del

        local toggle = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        toggle:SetSize(60, BROW_ROW_H - 2)
        toggle:SetPoint("RIGHT", del, "LEFT", -4, 0)
        toggle:SetText("Disable")
        row.btnToggle = toggle

        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", expBtn, "RIGHT", 6, 0)
        fs:SetPoint("RIGHT", toggle, "LEFT", -6, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        row.text = fs

        local click = CreateFrame("Button", nil, row)
        click:SetAllPoints(row)
        click:RegisterForClicks("LeftButtonUp")
        row.btnClick = click

        row:Hide()
        browRows[i] = row
    end

    function f:RefreshBrowserList()
        InitSV()
        local allRules = CollectAllRules()
        local nodes = BuildVisibleTreeNodes(allRules)
        self._browserNodes = nodes

        browserEmpty:SetShown(#nodes == 0)

        if FauxScrollFrame_Update then
            FauxScrollFrame_Update(browserScroll, #nodes, BROW_ROWS, BROW_ROW_H)
        end

        local offset = 0
        if FauxScrollFrame_GetOffset then
            offset = FauxScrollFrame_GetOffset(browserScroll)
        end

        for i = 1, BROW_ROWS do
            local idx = offset + i
            local row = browRows[i]
            local node = nodes[idx]

            if not node then
                row:Hide()
            else
                row:Show()

                local indent = (node.level or 0) * 14
                row.btnExpand:ClearAllPoints()
                row.btnExpand:SetPoint("LEFT", row, "LEFT", indent, 0)

                if node.kind == "exp" or node.kind == "zone" or node.kind == "npc" then
                    row.btnExpand:Show()
                    row.btnExpand:SetText(node.expanded and "-" or "+")
                    row.btnToggle:Hide()
                    row.btnDel:Hide()

                    row.text:SetText(node.label)
                    if node.kind == "exp" then
                        row.text:SetTextColor(1, 0.82, 0, 1)
                    elseif node.kind == "zone" then
                        row.text:SetTextColor(0.8, 0.9, 1, 1)
                    else
                        row.text:SetTextColor(1, 1, 1, 1)
                    end

                    row.btnExpand:SetScript("OnClick", function()
                        SetTreeExpanded(node.key, not node.expanded)
                        f:RefreshBrowserList()
                    end)
                    row.btnClick:SetScript("OnClick", function()
                        SetTreeExpanded(node.key, not node.expanded)
                        f:RefreshBrowserList()
                    end)
                else
                    -- rule
                    row.btnExpand:Hide()
                    row.btnToggle:Show()
                    row.btnDel:Show()
                    row.text:SetText(node.label)

                    local rule = node.rule
                    local npcID = rule and rule.npcID
                    local optionID = rule and rule.optionID

                    local isDisabled = rule and rule.isDisabled
                    if isDisabled then
                        row.text:SetTextColor(0.67, 0.67, 0.67, 1)
                        row.btnToggle:SetText("Enable")
                    else
                        row.text:SetTextColor(1, 1, 1, 1)
                        row.btnToggle:SetText("Disable")
                    end

                    row.btnToggle:SetScript("OnClick", function()
                        InitSV()
                        if rule.scope == "db" then
                            SetDisabledDB(npcID, optionID, not IsDisabledDB(npcID, optionID))
                        else
                            SetDisabled(rule.scope, npcID, optionID, not IsDisabled(rule.scope, npcID, optionID))
                        end
                        f:RefreshBrowserList()
                        if f.RefreshRulesList then f:RefreshRulesList(f.currentNpcID) end
                    end)

                    if rule.scope == "db" then
                        row.btnDel:Disable()
                        row.btnDel:SetText("DB")
                        row.btnDel:SetScript("OnClick", nil)
                    else
                        row.btnDel:Enable()
                        row.btnDel:SetText("Del")
                        row.btnDel:SetScript("OnClick", function()
                            InitSV()
                            DeleteRule(rule.scope, npcID, optionID)
                            f:RefreshBrowserList()
                            if f.RefreshRulesList then f:RefreshRulesList(f.currentNpcID) end
                        end)
                    end

                    row.btnClick:SetScript("OnClick", function()
                        f.selectedNpcID = npcID
                        f.selectedNpcName = rule.npcName
                        if f.SelectTab then
                            f.SelectTab(2)
                        end
                        if f.edit and optionID then
                            f.edit:SetText(tostring(optionID))
                            f.edit:HighlightText()
                        end
                        if f.UpdateFromInput then
                            f:UpdateFromInput()
                        end
                    end)
                end
            end
        end
    end

    browserScroll:SetScript("OnVerticalScroll", function(self, offset)
        if FauxScrollFrame_OnVerticalScroll then
            FauxScrollFrame_OnVerticalScroll(self, offset, BROW_ROW_H, function()
                if f.RefreshBrowserList then
                    f:RefreshBrowserList()
                end
            end)
        end
    end)

    -- OptionID input (hidden by default; quick A/C buttons are the primary workflow)
    local info = editPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    info:SetPoint("TOPLEFT", leftArea, "TOPLEFT", 6, -2)
    info:SetText("")
    info:Hide()

    local edit = CreateFrame("EditBox", nil, editPanel, "InputBoxTemplate")
    edit:SetSize(1, 1)
    edit:SetPoint("TOPLEFT", leftArea, "TOPLEFT", 0, 0)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(10)
    edit:SetTextInsets(6, 6, 0, 0)
    edit:SetJustifyH("CENTER")
    if edit.SetJustifyV then
        edit:SetJustifyV("MIDDLE")
    end
    if edit.SetNumeric then
        edit:SetNumeric(true)
    end
    if edit.GetFont and edit.SetFont then
        local fontPath, _, fontFlags = edit:GetFont()
        if fontPath then
            edit:SetFont(fontPath, 16, fontFlags)
        end
    end
    f.edit = edit

    local function HideEditBoxFrame(box)
        if not box or not box.GetRegions then
            return
        end
        for i = 1, select("#", box:GetRegions()) do
            local region = select(i, box:GetRegions())
            if region and region.Hide and region.GetObjectType and region:GetObjectType() == "Texture" then
                region:Hide()
            end
        end
    end
    HideEditBoxFrame(edit)

    -- NPC header (top center)
    local nameLabel = editPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    nameLabel:SetPoint("TOP", leftArea, "TOP", 0, -2)
    nameLabel:SetPoint("LEFT", leftArea, "LEFT", 0, 0)
    nameLabel:SetPoint("RIGHT", leftArea, "RIGHT", 0, 0)
    nameLabel:SetJustifyH("CENTER")
    nameLabel:SetWordWrap(true)
    BumpFont(nameLabel, 4)
    f.nameLabel = nameLabel

    local reasonLabel = editPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    reasonLabel:SetPoint("TOP", nameLabel, "BOTTOM", 0, -2)
    reasonLabel:SetPoint("LEFT", leftArea, "LEFT", 0, 0)
    reasonLabel:SetPoint("RIGHT", leftArea, "RIGHT", 0, 0)
    reasonLabel:SetJustifyH("CENTER")
    reasonLabel:SetWordWrap(true)
    f.reasonLabel = reasonLabel

    -- Helpers
    local function IsFontStringTruncated(fs)
        if not fs then return false end
        if fs.IsTruncated then
            return fs:IsTruncated()
        end
        local w = fs.GetStringWidth and fs:GetStringWidth() or 0
        local maxW = fs.GetWidth and fs:GetWidth() or 0
        return w > (maxW + 1)
    end

    local function AttachTruncatedTooltip(owner, fs, getText)
        owner:SetScript("OnEnter", function()
            if not (GameTooltip and fs) then
                return
            end
            if IsFontStringTruncated(fs) then
                GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
                GameTooltip:SetText(getText())
                GameTooltip:Show()
            end
        end)
        owner:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
    end

    -- Two stacked boxes: top = current rules, bottom = current options
    local rulesArea = CreateFrame("Frame", nil, editPanel, "BackdropTemplate")
    rulesArea:SetPoint("TOPLEFT", reasonLabel, "BOTTOMLEFT", -2, -8)
    rulesArea:SetPoint("TOPRIGHT", reasonLabel, "BOTTOMRIGHT", 2, -8)
    rulesArea:SetHeight(170)
    rulesArea:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        tile = true,
        tileSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    rulesArea:SetBackdropColor(0, 0, 0, 0.25)

    local emptyLabel = rulesArea:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyLabel:SetPoint("CENTER", rulesArea, "CENTER", 0, 0)
    emptyLabel:SetText("No rules for this NPC")

    local scrollFrame = CreateFrame("ScrollFrame", nil, rulesArea, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", rulesArea, "TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", rulesArea, "BOTTOMRIGHT", -26, 4)
    f.scrollFrame = scrollFrame

    local RULE_ROW_H = 18
    local RULE_ROWS = 8
    local rows = {}

    local function SetRowVisible(row, visible)
        if visible then
            row:Show()
        else
            row:Hide()
        end
    end

    for i = 1, RULE_ROWS do
        local row = CreateFrame("Button", nil, rulesArea)
        row:SetHeight(RULE_ROW_H)
        row:SetPoint("TOPLEFT", rulesArea, "TOPLEFT", 8, -6 - (i - 1) * RULE_ROW_H)
        row:SetPoint("TOPRIGHT", rulesArea, "TOPRIGHT", -8, -6 - (i - 1) * RULE_ROW_H)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(row)
        bg:Hide()
        row.bg = bg

        local btnAccToggle = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btnAccToggle:SetSize(22, RULE_ROW_H - 2)
        btnAccToggle:SetPoint("LEFT", row, "LEFT", 0, 0)
        btnAccToggle:SetText("A")
        row.btnAccToggle = btnAccToggle

        local btnCharToggle = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btnCharToggle:SetSize(22, RULE_ROW_H - 2)
        btnCharToggle:SetPoint("LEFT", btnAccToggle, "RIGHT", 4, 0)
        btnCharToggle:SetText("C")
        row.btnCharToggle = btnCharToggle

        local btnDbToggle = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btnDbToggle:SetSize(26, RULE_ROW_H - 2)
        btnDbToggle:SetPoint("LEFT", btnCharToggle, "RIGHT", 4, 0)
        btnDbToggle:SetText("DB")
        row.btnDbToggle = btnDbToggle

        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", btnDbToggle, "RIGHT", 6, 0)
        fs:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        row.text = fs

        AttachTruncatedTooltip(row, fs, function()
            return fs:GetText() or ""
        end)

        SetRowVisible(row, false)
        rows[i] = row
    end

    local function CollectRulesForNpc(npcID)
        local entries = {}
        if not npcID then
            return entries
        end

        local byOption = {}
        local function Ensure(optionID)
            local key = tostring(optionID)
            local e = byOption[key]
            if not e then
                e = {
                    optionID = tonumber(optionID) or optionID,
                    text = "",
                    hasChar = false,
                    hasAcc = false,
                    hasDb = false,
                    disabledChar = false,
                    disabledAcc = false,
                    disabledDb = false,
                    expansion = "",
                }
                byOption[key] = e
                table.insert(entries, e)
            end
            return e
        end

        local function AddFrom(scope)
            local db = (scope == "acc") and AutoGossip_Acc or AutoGossip_Char
            local npcTable = db[npcID]
            if type(npcTable) ~= "table" then
                return
            end
            for optionID, data in pairs(npcTable) do
                local numericID = tonumber(optionID) or optionID
                local text = ""
                if type(data) == "table" then
                    text = data.text or ""
                end

                local e = Ensure(numericID)
                if e.text == "" and type(text) == "string" and text ~= "" then
                    e.text = text
                end

                if scope == "char" then
                    e.hasChar = true
                    e.disabledChar = IsDisabled("char", npcID, e.optionID)
                else
                    e.hasAcc = true
                    e.disabledAcc = IsDisabled("acc", npcID, e.optionID)
                end
            end
        end

        AddFrom("char")
        AddFrom("acc")

        local dbNpc = GetDbNpcTable(npcID)
        if dbNpc then
            for optionID, data in pairs(dbNpc) do
                local numericID = tonumber(optionID) or optionID
                local text = ""
                local expansion = ""
                if type(data) == "table" then
                    text = data.text or ""
                    expansion = data.expansion or ""
                end

                local e = Ensure(numericID)
                if e.text == "" and type(text) == "string" and text ~= "" then
                    e.text = text
                end
                e.hasDb = true
                e.disabledDb = IsDisabledDB(npcID, e.optionID)
                e.expansion = expansion or e.expansion
            end
        end

        table.sort(entries, function(a, b)
            return (tonumber(a.optionID) or 0) < (tonumber(b.optionID) or 0)
        end)

        return entries
    end

    function f:RefreshRulesList(npcID)
        InitSV()
        self.currentNpcID = npcID

        local entries = CollectRulesForNpc(npcID)
        self._rulesEntries = entries

        emptyLabel:SetShown(npcID and (#entries == 0) or false)

        local total = #entries
        if FauxScrollFrame_Update then
            FauxScrollFrame_Update(scrollFrame, total, RULE_ROWS, RULE_ROW_H)
        end

        local offset = 0
        if FauxScrollFrame_GetOffset then
            offset = FauxScrollFrame_GetOffset(scrollFrame)
        end

        for i = 1, RULE_ROWS do
            local idx = offset + i
            local row = rows[i]
            local entry = entries[idx]
            if entry then
                SetRowVisible(row, true)

                local zebra = (idx % 2) == 0
                row.bg:SetShown(zebra)
                row.bg:SetColorTexture(1, 1, 1, zebra and 0.05 or 0)

                local suffix = ""
                if entry.hasDb and entry.expansion and entry.expansion ~= "" then
                    suffix = " (" .. entry.expansion .. ")"
                end

                local text = entry.text
                if type(text) ~= "string" or text == "" then
                    text = "(no text)"
                end
                row.text:SetText(string.format("%s: %s%s", tostring(entry.optionID), text, suffix))

                local function ConfigureToggle(btn, label, exists, isDisabled, onClick, tooltipLabel)
                    if not exists then
                        btn:Disable()
                        btn:SetText("|cff666666" .. label .. "|r")
                        btn:SetScript("OnClick", nil)
                        btn:SetScript("OnEnter", nil)
                        btn:SetScript("OnLeave", nil)
                        return
                    end

                    btn:Enable()
                    if isDisabled then
                        btn:SetText("|cffffff00" .. label .. "|r")
                    else
                        btn:SetText("|cffff0000" .. label .. "|r")
                    end
                    btn:SetScript("OnClick", onClick)
                    btn:SetScript("OnEnter", function()
                        if GameTooltip then
                            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                            GameTooltip:SetText(tooltipLabel)
                            GameTooltip:AddLine(isDisabled and "Yellow = re-enable" or "Red = disable", 1, 1, 1, true)
                            GameTooltip:Show()
                        end
                    end)
                    btn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
                end

                ConfigureToggle(row.btnAccToggle, "A", entry.hasAcc, entry.disabledAcc, function()
                    InitSV()
                    SetDisabled("acc", npcID, entry.optionID, not IsDisabled("acc", npcID, entry.optionID))
                    f:RefreshRulesList(npcID)
                    if f.RefreshBrowserList then f:RefreshBrowserList() end
                    CloseOptionsWindow()
                    CloseGossipWindow()
                end, "Account")

                ConfigureToggle(row.btnCharToggle, "C", entry.hasChar, entry.disabledChar, function()
                    InitSV()
                    SetDisabled("char", npcID, entry.optionID, not IsDisabled("char", npcID, entry.optionID))
                    f:RefreshRulesList(npcID)
                    if f.RefreshBrowserList then f:RefreshBrowserList() end
                    CloseOptionsWindow()
                    CloseGossipWindow()
                end, "Character")

                ConfigureToggle(row.btnDbToggle, "DB", entry.hasDb, entry.disabledDb, function()
                    InitSV()
                    SetDisabledDB(npcID, entry.optionID, not IsDisabledDB(npcID, entry.optionID))
                    f:RefreshRulesList(npcID)
                    if f.RefreshBrowserList then f:RefreshBrowserList() end
                    CloseOptionsWindow()
                    CloseGossipWindow()
                end, "DB")
            else
                SetRowVisible(row, false)
            end
        end
    end

    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        if FauxScrollFrame_OnVerticalScroll then
            FauxScrollFrame_OnVerticalScroll(self, offset, RULE_ROW_H, function()
                if f.RefreshRulesList then
                    f:RefreshRulesList(f.currentNpcID)
                end
            end)
        end
    end)

    -- Bottom: current NPC options list
    local optionsArea = CreateFrame("Frame", nil, editPanel, "BackdropTemplate")
    optionsArea:SetPoint("TOPLEFT", rulesArea, "BOTTOMLEFT", 0, -10)
    optionsArea:SetPoint("TOPRIGHT", rulesArea, "BOTTOMRIGHT", 0, -10)
    optionsArea:SetPoint("BOTTOMLEFT", leftArea, "BOTTOMLEFT", 0, 0)
    optionsArea:SetPoint("BOTTOMRIGHT", leftArea, "BOTTOMRIGHT", 0, 0)
    optionsArea:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        tile = true,
        tileSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    optionsArea:SetBackdropColor(0, 0, 0, 0.25)

    local optEmpty = optionsArea:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    optEmpty:SetPoint("CENTER", optionsArea, "CENTER", 0, 0)
    optEmpty:SetText("Open a gossip window")

    local optScroll = CreateFrame("ScrollFrame", nil, optionsArea, "FauxScrollFrameTemplate")
    optScroll:SetPoint("TOPLEFT", optionsArea, "TOPLEFT", 4, -4)
    optScroll:SetPoint("BOTTOMRIGHT", optionsArea, "BOTTOMRIGHT", -26, 4)
    f.optScroll = optScroll

    local OPT_ROW_H = 18
    local OPT_ROWS = 8
    local optRows = {}

    for i = 1, OPT_ROWS do
        local row = CreateFrame("Button", nil, optionsArea)
        row:SetHeight(OPT_ROW_H)
        row:SetPoint("TOPLEFT", optionsArea, "TOPLEFT", 8, -6 - (i - 1) * OPT_ROW_H)
        row:SetPoint("TOPRIGHT", optionsArea, "TOPRIGHT", -8, -6 - (i - 1) * OPT_ROW_H)
        row:RegisterForClicks("LeftButtonUp")

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(row)
        bg:Hide()
        row.bg = bg

        local btnAccQuick = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btnAccQuick:SetSize(22, OPT_ROW_H - 2)
        btnAccQuick:SetPoint("LEFT", row, "LEFT", 0, 0)
        btnAccQuick:SetText("A")
        row.btnAccQuick = btnAccQuick

        local btnCharQuick = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btnCharQuick:SetSize(22, OPT_ROW_H - 2)
        btnCharQuick:SetPoint("LEFT", btnAccQuick, "RIGHT", 4, 0)
        btnCharQuick:SetText("C")
        row.btnCharQuick = btnCharQuick

        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", btnCharQuick, "RIGHT", 6, 0)
        fs:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        row.text = fs

        AttachTruncatedTooltip(row, fs, function()
            return fs:GetText() or ""
        end)

        row:Hide()
        optRows[i] = row
    end

    function f:RefreshOptionsList()
        if not (C_GossipInfo and C_GossipInfo.GetOptions) then
            self._currentOptions = {}
            optEmpty:SetText("Gossip API not available")
            optEmpty:Show()
            for i = 1, OPT_ROWS do optRows[i]:Hide() end
            return
        end

        local options = C_GossipInfo.GetOptions() or {}
        table.sort(options, function(a, b)
            return (a and a.gossipOptionID or 0) < (b and b.gossipOptionID or 0)
        end)
        self._currentOptions = options

        optEmpty:SetShown(#options == 0)
        optEmpty:SetText(#options == 0 and "Open a gossip window" or "")

        if FauxScrollFrame_Update then
            FauxScrollFrame_Update(optScroll, #options, OPT_ROWS, OPT_ROW_H)
        end

        local offset = 0
        if FauxScrollFrame_GetOffset then
            offset = FauxScrollFrame_GetOffset(optScroll)
        end

        for i = 1, OPT_ROWS do
            local idx = offset + i
            local row = optRows[i]
            local opt = options[idx]
            if not opt then
                row:Hide()
            else
                row:Show()
                local zebra = (idx % 2) == 0
                row.bg:SetShown(zebra)
                row.bg:SetColorTexture(1, 1, 1, zebra and 0.05 or 0)
                local optionID = opt.gossipOptionID
                local text = opt.name
                if type(text) ~= "string" or text == "" then
                    text = "(no text)"
                end
                row.text:SetText(string.format("%d: %s", optionID or 0, text))

                local function QuickAdd(scope)
                    InitSV()
                    local npcID = GetCurrentNpcID()
                    if not npcID then
                        Print("Open a gossip window first (need an NPC).")
                        return
                    end
                    if not optionID then
                        return
                    end
                    local optInfo = FindOptionInfoByID(optionID)
                    local optName = (optInfo and optInfo.name) or text
                    local optType = optInfo and (rawget(optInfo, "type") or rawget(optInfo, "optionType")) or nil

                    if HasRule(scope, npcID, optionID) then
                        -- Toggle disable/enable for existing rule.
                        local nowDisabled = not IsDisabled(scope, npcID, optionID)
                        SetDisabled(scope, npcID, optionID, nowDisabled)
                    else
                        AddRule(scope, npcID, optionID, optName, optType)
                    end

                    if f.RefreshRulesList then f:RefreshRulesList(npcID) end
                    if f.RefreshBrowserList then f:RefreshBrowserList() end
                    if f.UpdateFromInput then f:UpdateFromInput() end

                    CloseOptionsWindow()
                    CloseGossipWindow()
                end

                row.btnCharQuick:SetScript("OnClick", function() QuickAdd("char") end)
                row.btnAccQuick:SetScript("OnClick", function() QuickAdd("acc") end)

                row.btnCharQuick:SetScript("OnEnter", function()
                    if GameTooltip then
                        GameTooltip:SetOwner(row.btnCharQuick, "ANCHOR_RIGHT")
                        GameTooltip:SetText("Character")
                        GameTooltip:AddLine("Add/enable this option for this character.", 1, 1, 1, true)
                        GameTooltip:Show()
                    end
                end)
                row.btnCharQuick:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

                row.btnAccQuick:SetScript("OnEnter", function()
                    if GameTooltip then
                        GameTooltip:SetOwner(row.btnAccQuick, "ANCHOR_RIGHT")
                        GameTooltip:SetText("Account")
                        GameTooltip:AddLine("Add/enable this option account-wide.", 1, 1, 1, true)
                        GameTooltip:Show()
                    end
                end)
                row.btnAccQuick:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

                row:SetScript("OnClick", nil)
            end
        end
    end

    optScroll:SetScript("OnVerticalScroll", function(self, offset)
        if FauxScrollFrame_OnVerticalScroll then
            FauxScrollFrame_OnVerticalScroll(self, offset, OPT_ROW_H, function()
                if f.RefreshOptionsList then
                    f:RefreshOptionsList()
                end
            end)
        end
    end)

    function f:UpdateFromInput()
        InitSV()
        local npcID = GetCurrentNpcID() or f.selectedNpcID
        local npcName = GetCurrentNpcName() or f.selectedNpcName or ""

        nameLabel:SetText(npcName or "")
        if npcID then
            reasonLabel:SetText(tostring(npcID))
            if f.RefreshRulesList then f:RefreshRulesList(npcID) end
        else
            reasonLabel:SetText("")
            if f.RefreshRulesList then f:RefreshRulesList(nil) end
        end
    end

    edit:SetScript("OnTextChanged", function()
        if f.UpdateFromInput then f:UpdateFromInput() end
    end)

    f:UpdateFromInput()
    if f.RefreshOptionsList then
        f:RefreshOptionsList()
    end

    -- Keep the option list in sync when the frame is shown.
    f:SetScript("OnShow", function()
        if f.SelectTab then
            f:SelectTab(1)
        end
        if f.RefreshOptionsList then
            f:RefreshOptionsList()
        end
        if f.RefreshBrowserList then
            f:RefreshBrowserList()
        end
        if f.UpdateFromInput then
            f:UpdateFromInput()
        end
    end)

    -- Toggles tab content
    do
        local BTN_W, BTN_H = 260, 22
        local START_Y = -64
        local GAP_Y = 10

        local function SetAcc2StateText(btn, label, enabled)
            if enabled then
                btn:SetText(label .. ": |cff00ccffON ACC|r")
            else
                btn:SetText(label .. ": |cffff0000OFF ACC|r")
            end
        end

        local btnTutorial = CreateFrame("Button", nil, togglesPanel, "UIPanelButtonTemplate")
        btnTutorial:SetSize(BTN_W, BTN_H)
        btnTutorial:SetPoint("TOP", togglesPanel, "TOP", 0, START_Y)
        f.btnTutorial = btnTutorial

        local function UpdateTutorialButton()
            InitSV()
            local enabled = (AutoGossip_Settings and AutoGossip_Settings.tutorialEnabledAcc) and true or false
            SetAcc2StateText(btnTutorial, "Tutorials", enabled)
        end

        btnTutorial:SetScript("OnClick", function()
            InitSV()
            AutoGossip_Settings.tutorialEnabledAcc = not (AutoGossip_Settings.tutorialEnabledAcc and true or false)
            AutoGossip_Settings.tutorialOffAcc = not AutoGossip_Settings.tutorialEnabledAcc
            if ns and ns.ApplyTutorialSetting then
                ns.ApplyTutorialSetting(true)
            end
            UpdateTutorialButton()
        end)
        btnTutorial:SetScript("OnEnter", function()
            if GameTooltip then
                GameTooltip:SetOwner(btnTutorial, "ANCHOR_RIGHT")
                GameTooltip:SetText("Tutorials")
                GameTooltip:AddLine("ON ACC: attempts to keep tutorials enabled.", 1, 1, 1, true)
                GameTooltip:AddLine("OFF ACC: applies HideTutorial logic.", 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        btnTutorial:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)

        UpdateTutorialButton()

        local btnBorder = CreateFrame("Button", nil, togglesPanel, "UIPanelButtonTemplate")
        btnBorder:SetSize(BTN_W, BTN_H)
        btnBorder:SetPoint("TOP", btnTutorial, "BOTTOM", 0, -GAP_Y)
        f.btnBorder = btnBorder

        local function UpdateBorderButton()
            InitSV()
            local hidden = (AutoGossip_Settings and AutoGossip_Settings.hideTooltipBorderAcc) and true or false
            if hidden then
                btnBorder:SetText("Tooltip Border: |cff00ccffHIDE ACC|r")
            else
                btnBorder:SetText("Tooltip Border: |cffff0000OFF ACC|r")
            end
        end

        btnBorder:SetScript("OnClick", function()
            InitSV()
            AutoGossip_Settings.hideTooltipBorderAcc = not (AutoGossip_Settings.hideTooltipBorderAcc and true or false)
            if ns and ns.ApplyTooltipBorderSetting then
                ns.ApplyTooltipBorderSetting(true)
            end
            UpdateBorderButton()
        end)
        btnBorder:SetScript("OnEnter", function()
            if GameTooltip then
                GameTooltip:SetOwner(btnBorder, "ANCHOR_RIGHT")
                GameTooltip:SetText("Tooltip Border")
                GameTooltip:AddLine("HIDE ACC: hide tooltip borders.", 1, 1, 1, true)
                GameTooltip:AddLine("OFF ACC: stop forcing hide (does not restore).", 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        btnBorder:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)

        UpdateBorderButton()

        local btnQueueAccept = CreateFrame("Button", nil, togglesPanel, "UIPanelButtonTemplate")
        btnQueueAccept:SetSize(BTN_W, BTN_H)
        btnQueueAccept:SetPoint("TOP", btnBorder, "BOTTOM", 0, -GAP_Y)
        f.btnQueueAccept = btnQueueAccept

        local function UpdateQueueAcceptButton()
            local state = GetQueueAcceptState()
            if state == "acc" then
                btnQueueAccept:SetText("Queue Accept: |cff00ccffACC ON|r")
            elseif state == "char" then
                btnQueueAccept:SetText("Queue Accept: |cff00ccffON|r")
            else
                btnQueueAccept:SetText("Queue Accept: |cffff0000OFF|r")
            end
        end

        btnQueueAccept:SetScript("OnClick", function()
            local state = GetQueueAcceptState()
            if state == "acc" then
                SetQueueAcceptState("char")
            elseif state == "char" then
                SetQueueAcceptState("off")
            else
                SetQueueAcceptState("acc")
            end
            UpdateQueueAcceptButton()
            ShowQueueOverlayIfNeeded()
        end)
        btnQueueAccept:SetScript("OnEnter", function()
            if GameTooltip then
                GameTooltip:SetOwner(btnQueueAccept, "ANCHOR_RIGHT")
                GameTooltip:SetText("Queue Accept")
                GameTooltip:AddLine("ACC ON: enable for all characters.", 1, 1, 1, true)
                GameTooltip:AddLine("ON: enable only this character.", 1, 1, 1, true)
                GameTooltip:AddLine("OFF: disable.", 1, 1, 1, true)
                GameTooltip:AddLine("When a dungeon queue pops, clicking the world will accept.", 1, 1, 1, true)
                GameTooltip:AddLine("Clicks on other UI should not accept.", 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        btnQueueAccept:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)

        UpdateQueueAcceptButton()

        local btnDebug = CreateFrame("Button", nil, togglesPanel, "UIPanelButtonTemplate")
        btnDebug:SetSize(BTN_W, BTN_H)
        btnDebug:SetPoint("TOP", btnQueueAccept, "BOTTOM", 0, -GAP_Y)
        f.btnDebug = btnDebug

        local function UpdateDebugButton()
            InitSV()
            local on = (AutoGossip_Settings and AutoGossip_Settings.debugAcc) and true or false
            SetAcc2StateText(btnDebug, "Debug", on)
        end

        btnDebug:SetScript("OnClick", function()
            InitSV()
            AutoGossip_Settings.debugAcc = not (AutoGossip_Settings.debugAcc and true or false)
            UpdateDebugButton()
        end)
        btnDebug:SetScript("OnEnter", function()
            if GameTooltip then
                GameTooltip:SetOwner(btnDebug, "ANCHOR_RIGHT")
                GameTooltip:SetText("Debug")
                GameTooltip:AddLine("ON ACC: print 'NPCID: Character Name' on gossip show.", 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        btnDebug:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)

        UpdateDebugButton()

        f.UpdateToggleButtons = function()
            UpdateTutorialButton()
            UpdateBorderButton()
            UpdateQueueAcceptButton()
            UpdateDebugButton()
        end
    end

    -- Default tab
    if f.SelectTab then
        f:SelectTab(1)
    end
    if f.RefreshBrowserList then
        f:RefreshBrowserList()
    end
    f:Hide()
end

local function ToggleUI(optionID)
    CreateOptionsWindow()
    if AutoGossipOptions:IsShown() then
        AutoGossipOptions:Hide()
    else
        AutoGossipOptions:Show()
        if AutoGossipOptions.RefreshBrowserList then
            AutoGossipOptions:RefreshBrowserList()
        end
        if AutoGossipOptions.SelectTab then
            AutoGossipOptions:SelectTab(1)
        end
        AutoGossipOptions.edit:SetText(optionID and tostring(optionID) or "")
        AutoGossipOptions.edit:HighlightText()
        if AutoGossipOptions.UpdateFromInput then
            AutoGossipOptions:UpdateFromInput()
        end
    end
end

local function PrintCurrentOptions()
    if not (C_GossipInfo and C_GossipInfo.GetOptions) then
        Print("Gossip API not available")
        return
    end

    local options = C_GossipInfo.GetOptions() or {}
    -- If there's only one option, the addon will auto-select it anyway; avoid chat spam.
    if #options <= 1 then
        return
    end

    local npcID = GetCurrentNpcID()
    local npcName = GetCurrentNpcName() or ""
    if npcID then
        Print(string.format("NPC: %s (%d)", npcName, npcID))
    end
    for _, opt in ipairs(options) do
        if opt and opt.gossipOptionID then
            Print(string.format("OptionID %d: %s", opt.gossipOptionID, opt.name or ""))
        end
    end
end

local lastDebugPrintAt = 0
local lastDebugPrintKey = nil

local function PrintDebugOptionsOnShow()
    InitSV()

    -- Don't print debug on characters that already have at least one character-scoped rule.
    -- (Keeps chat clean on established characters; still prints for fresh characters.)
    do
        local db = AutoGossip_Char
        if type(db) == "table" then
            for _, npcTable in pairs(db) do
                if type(npcTable) == "table" and next(npcTable) ~= nil then
                    return
                end
            end
        end
    end

    if not (C_GossipInfo and C_GossipInfo.GetOptions) then
        return
    end

    local options = C_GossipInfo.GetOptions() or {}
    if #options <= 1 then
        return
    end

    local npcID = GetCurrentNpcID()
    local npcName = GetCurrentNpcName() or ""

    -- Debounce: both GOSSIP_SHOW and PLAYER_INTERACTION_MANAGER_FRAME_SHOW can fire for the
    -- same interaction, which would otherwise print the same block twice.
    do
        local ids = {}
        for _, opt in ipairs(options) do
            local optionID = opt and opt.gossipOptionID
            if optionID then
                ids[#ids + 1] = optionID
            end
        end
        table.sort(ids)
        local key = tostring(npcID or "?") .. ":" .. tostring(#options) .. ":" .. table.concat(ids, ",")

        local now = (GetTime and GetTime()) or 0
        if lastDebugPrintKey == key and (now - (lastDebugPrintAt or 0)) < 0.20 then
            return
        end
        lastDebugPrintKey = key
        lastDebugPrintAt = now
    end

    -- Don't print debug if we'd auto-select for this NPC/options.
    if npcID and (not IsShiftKeyDown()) and (not InCombatLockdown()) then
        for _, opt in ipairs(options) do
            local optionID = opt and opt.gossipOptionID
            if optionID then
                if HasRule("char", npcID, optionID) and (not IsDisabled("char", npcID, optionID)) then
                    return
                end
                if HasRule("acc", npcID, optionID) and (not IsDisabled("acc", npcID, optionID)) then
                    return
                end
                if HasDbRule(npcID, optionID) and (not IsDisabledDB(npcID, optionID)) then
                    return
                end
            end
        end
    end

    if npcID then
        Print(string.format("%d: %s", npcID, npcName))
    else
        Print(string.format("?: %s", npcName))
    end

    for _, opt in ipairs(options) do
        local optionID = opt and opt.gossipOptionID
        if optionID then
            local text = opt.name
            if type(text) ~= "string" or text == "" then
                text = "(no text)"
            end
            Print(string.format("OptionID %d: %s", optionID, text))
        end
    end
end

SLASH_FROZENGOSSIPOPTION1 = "/fgo"
---@diagnostic disable-next-line: duplicate-set-field
SlashCmdList["FROZENGOSSIPOPTION"] = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" then
        ToggleUI()
        return
    end
    local n = tonumber(msg)
    if n then
        ToggleUI(n)
        return
    end
    if msg == "list" then
        PrintCurrentOptions()
        return
    end

    Print("/fgo           - open/toggle window")
    Print("/fgo <id>      - open window + set option id")
    Print("/fgo list      - print current gossip options")
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("GOSSIP_SHOW")
frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
frame:RegisterEvent("LFG_PROPOSAL_SHOW")
frame:RegisterEvent("LFG_PROPOSAL_UPDATE")
frame:RegisterEvent("LFG_PROPOSAL_FAILED")
frame:RegisterEvent("LFG_PROPOSAL_SUCCEEDED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        InitSV()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        InitSV()
        if queueOverlayPendingHide then
            HideQueueOverlay()
        end
        ShowQueueOverlayIfNeeded()
        return
    end

    if event == "LFG_PROPOSAL_SHOW" then
        -- Start a new proposal session.
        queueOverlayProposalToken = (queueOverlayProposalToken or 0) + 1
        queueOverlayDismissedToken = 0
        InitSV()
        ShowQueueOverlayIfNeeded()
        return
    end

    if event == "LFG_PROPOSAL_UPDATE" then
        -- Some edge cases (e.g., /reload mid-proposal) may not fire SHOW again.
        if (queueOverlayProposalToken or 0) == 0 and HasActiveLfgProposal() then
            queueOverlayProposalToken = 1
            queueOverlayDismissedToken = 0
        end
        InitSV()
        ShowQueueOverlayIfNeeded()
        return
    end
    if event == "LFG_PROPOSAL_FAILED" or event == "LFG_PROPOSAL_SUCCEEDED" then
        queueOverlayProposalToken = 0
        queueOverlayDismissedToken = 0
        HideQueueOverlay()
        return
    end

    if event == "GOSSIP_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        InitSV()

        -- Debug: print NPC header + options list.
        if AutoGossip_Settings and AutoGossip_Settings.debugAcc then
            PrintDebugOptionsOnShow()
        elseif AutoGossip_UI and AutoGossip_UI.printOnShow then
            -- Helpful when building rules.
            PrintCurrentOptions()
        end

        if AutoGossipOptions and AutoGossipOptions:IsShown() and AutoGossipOptions.UpdateFromInput then
            AutoGossipOptions:UpdateFromInput()
        end
        if AutoGossipOptions and AutoGossipOptions:IsShown() and AutoGossipOptions.RefreshOptionsList then
            AutoGossipOptions:RefreshOptionsList()
        end
        TryAutoSelect()
    end
end)
