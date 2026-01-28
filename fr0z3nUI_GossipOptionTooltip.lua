local addonName = ...
local _, ns = ...
ns = ns or {}

local didInit = false

local function IsHideEnabled()
    local acc = _G.AutoGossip_Settings
    if type(acc) ~= "table" then
        return true
    end
    if type(acc.hideTooltipBorderAcc) ~= "boolean" then
        return true
    end
    return acc.hideTooltipBorderAcc
end

local function ApplyBorderState(tooltip)
    local nineSlice = tooltip and tooltip.NineSlice
    if not nineSlice then
        return
    end

    local hide = IsHideEnabled()

    -- When disabled, do not force any "show" state; leave Blizzard/default styling alone.
    if not hide then
        return
    end

    for _, regionName in ipairs({
        "TopEdge", "BottomEdge", "LeftEdge", "RightEdge",
        "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    }) do
        local region = nineSlice[regionName]
        if region and region.SetAlpha then
            if region.__FGO_OrigAlpha == nil and region.GetAlpha then
                region.__FGO_OrigAlpha = region:GetAlpha()
            end
            region:SetAlpha(0)
        end
    end
end

local function HookTooltipByName(globalName)
    local tt = _G and _G[globalName]
    if not (tt and tt.HookScript) then
        return
    end

    if tt.__FGO_TooltipBorderHooked then
        ApplyBorderState(tt)
        return
    end

    tt.__FGO_TooltipBorderHooked = true
    ApplyBorderState(tt)
    tt:HookScript("OnShow", ApplyBorderState)
end

local function HookAllKnownTooltips()
    for _, name in ipairs({
        "GameTooltip",
        "ItemRefTooltip",
        "ShoppingTooltip1",
        "ShoppingTooltip2",
        "ShoppingTooltip3",
        "WorldMapTooltip",
        "BattlePetTooltip",
        "FloatingBattlePetTooltip",
        "FloatingPetBattleAbilityTooltip",
        "EmbeddedItemTooltip",
    }) do
        HookTooltipByName(name)
    end
end

local function HookTooltipDataProcessor()
    if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall) then
        return
    end
    if TooltipDataProcessor.__FGO_TooltipBorderHooked then
        return
    end
    TooltipDataProcessor.__FGO_TooltipBorderHooked = true

    if type(Enum) == "table" and type(Enum.TooltipDataType) == "table" then
        for _, tooltipDataType in pairs(Enum.TooltipDataType) do
            if type(tooltipDataType) == "number" then
                TooltipDataProcessor.AddTooltipPostCall(tooltipDataType, ApplyBorderState)
            end
        end
    end
end

local function HookBackdropStyleFunctions()
    if not (_G and _G.hooksecurefunc) then
        return
    end
    if _G.__FGO_TooltipBorderBackdropHooked then
        return
    end
    _G.__FGO_TooltipBorderBackdropHooked = true

    local sharedSetBackdropStyle = _G and rawget(_G, "SharedTooltip_SetBackdropStyle")
    if type(sharedSetBackdropStyle) == "function" then
        _G.hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tooltip)
            ApplyBorderState(tooltip)
        end)
    end

    local gameTooltipSetBackdropStyle = _G and rawget(_G, "GameTooltip_SetBackdropStyle")
    if type(gameTooltipSetBackdropStyle) == "function" then
        _G.hooksecurefunc("GameTooltip_SetBackdropStyle", function(tooltip)
            ApplyBorderState(tooltip)
        end)
    end
end

local function InitOnce()
    if didInit then
        return
    end
    didInit = true

    HookTooltipDataProcessor()
    HookBackdropStyleFunctions()
    HookAllKnownTooltips()
end

function ns.ApplyTooltipBorderSetting(force)
    InitOnce()

    -- Re-apply to existing tooltips immediately.
    if force then
        HookAllKnownTooltips()
    end
end

local function OnEvent(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        -- Initialize default if needed.
        if type(_G.AutoGossip_Settings) == "table" and type(_G.AutoGossip_Settings.hideTooltipBorderAcc) ~= "boolean" then
            _G.AutoGossip_Settings.hideTooltipBorderAcc = true
        end
        return
    end

    if event == "PLAYER_LOGIN" or event == "VARIABLES_LOADED" then
        InitOnce()
        ns.ApplyTooltipBorderSetting(true)
    end
end

local f = _G.CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("VARIABLES_LOADED")
f:SetScript("OnEvent", OnEvent)
