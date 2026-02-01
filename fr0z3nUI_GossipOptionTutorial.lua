local addonName = ...
local _, ns = ...
ns = ns or {}

local didApplyHide
local pendingChanges

local IsAddOnLoadedSafe = (_G.C_AddOns and rawget(_G.C_AddOns, "IsAddOnLoaded")) or rawget(_G, "IsAddOnLoaded")

local function GetTutorialEnabledEffective()
    local acc = _G.AutoGossip_Settings
    if type(acc) == "table" and type(acc.tutorialEnabledAcc) == "boolean" then
        return acc.tutorialEnabledAcc
    end

    -- Back-compat: old versions stored tutorialOffAcc.
    if type(acc) == "table" and type(acc.tutorialOffAcc) == "boolean" then
        return (not acc.tutorialOffAcc)
    end

    return true
end

local function GetTutorialOffEffective()
    return not GetTutorialEnabledEffective()
end

local function ApplyMicroAlertsHook()
    -- Intentionally a no-op.
    -- Overwriting Blizzard globals (like MainMenuMicroButton_AreAlertsEnabled) is a common source of UI taint
    -- and can lead to blocked protected calls inside Blizzard_ActionBarController.
    -- The tutorial suppression in this addon relies on CVars instead.
    return
end

local function ApplyHideTutorials(force)
    if didApplyHide and not force then
        return
    end
    didApplyHide = true

    if not GetTutorialOffEffective() then
        return
    end

    if _G.C_CVar and _G.C_CVar.SetCVar then
        _G.C_CVar.SetCVar("showTutorials", 0)
        _G.C_CVar.SetCVar("showNPETutorials", 0)
        _G.C_CVar.SetCVar("hideAdventureJournalAlerts", 1)
    elseif _G.SetCVar then
        _G.SetCVar("showTutorials", 0)
        _G.SetCVar("showNPETutorials", 0)
        _G.SetCVar("hideAdventureJournalAlerts", 1)
    end

    local numTutorials = tonumber(rawget(_G, "NUM_LE_FRAME_TUTORIALS"))
    local numAccountTutorials = tonumber(rawget(_G, "NUM_LE_FRAME_TUTORIAL_ACCCOUNTS"))

    local lastInfoFrame
    if numTutorials and _G.C_CVar and _G.C_CVar.GetCVarBitfield then
        lastInfoFrame = _G.C_CVar.GetCVarBitfield("closedInfoFrames", numTutorials)
    end

    if pendingChanges or (not lastInfoFrame) then
        if numTutorials and _G.C_CVar and _G.C_CVar.SetCVarBitfield then
            for i = 1, numTutorials do
                _G.C_CVar.SetCVarBitfield("closedInfoFrames", i, true)
            end
        end
        if numAccountTutorials and _G.C_CVar and _G.C_CVar.SetCVarBitfield then
            for i = 1, numAccountTutorials do
                _G.C_CVar.SetCVarBitfield("closedInfoFramesAccountWide", i, true)
            end
        end
    end

    ApplyMicroAlertsHook()
end

local function ApplyShowTutorials()
    if _G.C_CVar and _G.C_CVar.SetCVar then
        _G.C_CVar.SetCVar("showTutorials", 1)
        _G.C_CVar.SetCVar("showNPETutorials", 1)
        _G.C_CVar.SetCVar("hideAdventureJournalAlerts", 0)
    elseif _G.SetCVar then
        _G.SetCVar("showTutorials", 1)
        _G.SetCVar("showNPETutorials", 1)
        _G.SetCVar("hideAdventureJournalAlerts", 0)
    end

    ApplyMicroAlertsHook()
end

function ns.ApplyTutorialSetting(force)
    if GetTutorialOffEffective() then
        ApplyHideTutorials(force)
    else
        ApplyShowTutorials()
    end
end

-- If you're in Exile's Reach and level 1 this cvar gets automatically enabled.
if _G.hooksecurefunc then
    _G.hooksecurefunc("NPE_CheckTutorials", function()
        if not GetTutorialOffEffective() then
            return
        end
        if _G.C_PlayerInfo and _G.C_PlayerInfo.IsPlayerNPERestricted and _G.UnitLevel and _G.SetCVar then
            if _G.C_PlayerInfo.IsPlayerNPERestricted() and _G.UnitLevel("player") == 1 then
                print("fr0z3nUI_GossipOption: Disabling NPE tutorial, please disregard Blizzard debug prints.")
                _G.SetCVar("showTutorials", 0)
            end
        end
    end)
end

local function OnEvent(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        local tocVersion = select(4, _G.GetBuildInfo())
        if type(_G.AutoGossip_Settings) == "table" and GetTutorialOffEffective() then
            if (not _G.AutoGossip_Settings.tutorialBuild) or (_G.AutoGossip_Settings.tutorialBuild < tocVersion) then
                _G.AutoGossip_Settings.tutorialBuild = tocVersion
                pendingChanges = true
            end
        end
        return
    end

    if event == "PLAYER_LOGIN" or event == "VARIABLES_LOADED" then
        ns.ApplyTutorialSetting(false)
    end
end

local f = _G.CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("VARIABLES_LOADED")
f:SetScript("OnEvent", OnEvent)
