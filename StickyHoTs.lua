-- StickyHoTs - HoT Counter Addon
-- Counts active Heal over Time effects on the player and displays current/8

-- ============================================================================
-- Namespace
-- ============================================================================

StickyHoTs = {}

local SH = StickyHoTs

-- Addon metadata
SH.name = "StickyHoTs"
SH.version = "1.0.0"
SH.author = "Kickimanjaro"

-- Constants
SH.MAX_HOTS = 8
SH.UPDATE_INTERVAL_MS = 1000
SH.BATTLE_SPIRIT_ID = 999014

-- State
SH.hotCount = 0
SH.battleSpiritActive = false
SH.controls = {}
SH.savedVars = nil
SH.initialized = false

-- Window manager reference
local wm = GetWindowManager()

-- ============================================================================
-- HoT Counting
-- ============================================================================

--[[
    Count active Heal over Time effects on the player.
    
    Filters for buffs (not debuffs) with abilityType == ABILITY_TYPE_HEAL
    that have a duration (timeEnding > timeStarted and timeEnding > 0).
    
    @return number  Count of active HoT effects
]]--
function SH.CountHoTs()
    local count = 0
    local numBuffs = GetNumBuffs("player")
    local now = GetGameTimeSeconds()

    for i = 1, numBuffs do
        local buffName, timeStarted, timeEnding, buffSlot, stackCount, iconFilename,
              deprecatedBuffType, effectType, abilityType, statusEffectType, abilityId,
              canClickOff, castByPlayer = GetUnitBuffInfo("player", i)

        -- A HoT is a buff (not debuff) with ABILITY_TYPE_HEAL and a remaining duration
        if effectType == BUFF_EFFECT_TYPE_BUFF
           and abilityType == ABILITY_TYPE_HEAL
           and timeEnding > 0
           and timeEnding > now then
            count = count + 1
        end
    end

    return count
end

-- ============================================================================
-- Display Update
-- ============================================================================

--[[
    Update the HoT counter display label.
    Colors the text to warn as count approaches the U49 healing debuff cap (8 HoTs):
      - Red (>= 8): healing debuff active (-33% healing taken)
      - Yellow (6-7): approaching cap, danger zone
      - Green (1-5): safe
      - White (0): no HoTs
    
    @param count  number  Current number of active HoTs
]]--
function SH.UpdateDisplay(count)
    SH.hotCount = count

    local label = SH.controls.label
    if not label then return end

    label:SetText(count .. "/" .. SH.MAX_HOTS)

    -- Color thresholds: warn as HoT count approaches the debuff cap
    if count >= SH.MAX_HOTS then
        label:SetColor(1.0, 0.3, 0.3, 1) -- red: debuff active
    elseif count >= 6 then
        label:SetColor(1.0, 1.0, 0.2, 1) -- yellow: approaching cap
    elseif count >= 1 then
        label:SetColor(0.2, 1.0, 0.2, 1) -- green: safe
    else
        label:SetColor(1.0, 1.0, 1.0, 1) -- white: no HoTs
    end
end

--[[
    Recount HoTs and refresh the display. Called by both event handlers
    and the periodic fallback scan.
]]--
function SH.RefreshCount()
    local count = SH.CountHoTs()
    SH.UpdateDisplay(count)
end

-- ============================================================================
-- Battle Spirit Detection
-- ============================================================================

--[[
    Check whether Battle Spirit is currently active on the player.
    Battle Spirit is a hidden passive buff (ID 999014) applied in PvP zones.
    It doesn't appear in GetNumBuffs/GetUnitBuffInfo, so we track it via
    EVENT_EFFECT_CHANGED only.
]]--

--[[
    Update visibility based on Battle Spirit state.
    Shows the window when Battle Spirit is active and HUD is visible;
    hides it otherwise.
]]--
function SH.UpdateBattleSpiritVisibility()
    if not SH.controls.window then return end

    if SH.battleSpiritActive then
        -- Show if HUD is active
        local hudScene = SCENE_MANAGER:GetScene("hud")
        local hudUiScene = SCENE_MANAGER:GetScene("hudui")
        local hudVisible = (hudScene and hudScene:GetState() == SCENE_SHOWN)
                        or (hudUiScene and hudUiScene:GetState() == SCENE_SHOWN)
        SH.controls.window:SetHidden(not hudVisible)
    else
        SH.controls.window:SetHidden(true)
    end
end

-- ============================================================================
-- UI Creation
-- ============================================================================

--[[
    Create the movable HoT counter UI element.
    
    Structure:
      StickyHoTsUI (TopLevelWindow, movable)
        └── Backdrop (CT_BACKDROP, semi-transparent black)
        └── Label (CT_LABEL, "0/8" text)
]]--
function SH.CreateUI()
    -- Top-level movable window
    local tlw = wm:CreateTopLevelWindow("StickyHoTsUI")
    tlw:SetDimensions(80, 32)
    tlw:SetMovable(true)
    tlw:SetMouseEnabled(true)
    tlw:SetClampedToScreen(true)
    tlw:SetHidden(true)

    -- Save position on drag
    tlw:SetHandler("OnMoveStop", function()
        SH.SaveWindowPosition()
    end)

    SH.controls.window = tlw

    -- Semi-transparent backdrop
    local bg = wm:CreateControl("$(parent)BG", tlw, CT_BACKDROP)
    bg:SetAnchorFill(tlw)
    bg:SetCenterColor(0, 0, 0, 0.6)
    bg:SetEdgeColor(0, 0, 0, 0.8)
    SH.controls.backdrop = bg

    -- Counter label
    local label = wm:CreateControl("$(parent)Label", tlw, CT_LABEL)
    label:SetFont("ZoFontGameLarge")
    label:SetColor(1, 1, 1, 1)
    label:SetText("0/" .. SH.MAX_HOTS)
    label:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    label:SetAnchorFill(tlw)
    label:SetDrawLayer(1)
    SH.controls.label = label

    -- Restore saved position or default to center
    SH.RestoreWindowPosition()
end

-- ============================================================================
-- Window Position Persistence
-- ============================================================================

function SH.SaveWindowPosition()
    if not SH.savedVars then return end
    SH.savedVars.position = SH.savedVars.position or {}
    SH.savedVars.position.x = SH.controls.window:GetLeft()
    SH.savedVars.position.y = SH.controls.window:GetTop()
end

function SH.RestoreWindowPosition()
    local win = SH.controls.window
    if not win then return end

    win:ClearAnchors()
    if SH.savedVars and SH.savedVars.position and SH.savedVars.position.x then
        win:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, SH.savedVars.position.x, SH.savedVars.position.y)
    else
        win:SetAnchor(CENTER, GuiRoot, CENTER, 0, -200)
    end
end

-- ============================================================================
-- Scene Visibility (show only on HUD)
-- ============================================================================

function SH.OnSceneStateChange(oldState, newState)
    if not SH.controls.window then return end

    -- Only show when both Battle Spirit is active and HUD is visible
    if newState == SCENE_SHOWN and SH.battleSpiritActive then
        SH.controls.window:SetHidden(false)
    elseif newState == SCENE_HIDDEN then
        SH.controls.window:SetHidden(true)
    end
end

function SH.RegisterSceneCallbacks()
    local hudScene = SCENE_MANAGER:GetScene("hud")
    local hudUiScene = SCENE_MANAGER:GetScene("hudui")

    if hudScene then
        hudScene:RegisterCallback("StateChange", SH.OnSceneStateChange)
    end
    if hudUiScene then
        hudUiScene:RegisterCallback("StateChange", SH.OnSceneStateChange)
    end
end

-- ============================================================================
-- Event Handlers
-- ============================================================================

--[[
    EVENT_EFFECT_CHANGED handler.
    Fires when any buff/debuff is gained, faded, or updated on the player.
    We recount all HoTs on each change to keep the display accurate.
]]--
function SH.OnEffectChanged(eventCode, changeType, effectSlot, effectName,
        unitTag, beginTime, endTime, stackCount, iconName, deprecatedBuffType,
        effectType, abilityType, statusEffectType, unitName, unitId, abilityId,
        sourceType)
    -- Track Battle Spirit gained/lost to control visibility
    if abilityId == SH.BATTLE_SPIRIT_ID then
        if changeType == EFFECT_RESULT_GAINED or changeType == EFFECT_RESULT_UPDATED then
            SH.battleSpiritActive = true
            SH.UpdateBattleSpiritVisibility()
            SH.RefreshCount()
        elseif changeType == EFFECT_RESULT_FADED then
            SH.battleSpiritActive = false
            SH.UpdateBattleSpiritVisibility()
        end
        return
    end

    -- Only care about buff changes that could affect HoT count
    if changeType == EFFECT_RESULT_GAINED
       or changeType == EFFECT_RESULT_FADED
       or changeType == EFFECT_RESULT_UPDATED then
        SH.RefreshCount()
    end
end

--[[
    EVENT_PLAYER_ACTIVATED handler.
    Fires after every loading screen. Buff lists reset on zone transitions,
    so we must rescan immediately.
]]--
function SH.OnPlayerActivated()
    -- Battle Spirit is a hidden buff that won't appear in GetNumBuffs/GetUnitBuffInfo.
    -- It fires via EVENT_EFFECT_CHANGED on zone entry, which may arrive before or after
    -- EVENT_PLAYER_ACTIVATED. We rely on the effect handler to set battleSpiritActive.
    -- On zone transitions out of PvP, EVENT_EFFECT_CHANGED FADED should fire, but as a
    -- safety net we also clear battleSpiritActive here and let the effect handler re-set it.
    SH.battleSpiritActive = false

    -- Delay visibility update to give EVENT_EFFECT_CHANGED time to fire for Battle Spirit
    zo_callLater(function()
        SH.RefreshCount()
        SH.UpdateBattleSpiritVisibility()
    end, 500)
end

-- ============================================================================
-- Initialization
-- ============================================================================

function SH.OnAddOnLoaded(eventCode, addonName)
    if addonName ~= SH.name then return end
    EVENT_MANAGER:UnregisterForEvent(SH.name, EVENT_ADD_ON_LOADED)

    -- Initialize SavedVariables (account-wide)
    local defaults = {
        position = nil, -- { x = number, y = number }
    }
    SH.savedVars = ZO_SavedVars:NewAccountWide("StickyHoTsVars", 1, nil, defaults)

    -- Create UI
    SH.CreateUI()

    -- Register for buff change events on the player
    EVENT_MANAGER:RegisterForEvent(SH.name, EVENT_EFFECT_CHANGED, SH.OnEffectChanged)
    EVENT_MANAGER:AddFilterForEvent(SH.name, EVENT_EFFECT_CHANGED, REGISTER_FILTER_UNIT_TAG, "player")

    -- Periodic fallback scan (catches silent buff expirations)
    EVENT_MANAGER:RegisterForUpdate(SH.name .. "Scan", SH.UPDATE_INTERVAL_MS, SH.RefreshCount)

    -- Register for zone transitions
    EVENT_MANAGER:RegisterForEvent(SH.name, EVENT_PLAYER_ACTIVATED, SH.OnPlayerActivated)

    -- Scene callbacks for HUD visibility
    SH.RegisterSceneCallbacks()

    -- Slash command to toggle visibility
    SLASH_COMMANDS["/stickyhots"] = function()
        if SH.controls.window then
            local isHidden = SH.controls.window:IsHidden()
            SH.controls.window:SetHidden(not isHidden)
            if isHidden then
                d("|c00FF00[StickyHoTs]|r Shown — drag to reposition")
            else
                d("|c00FF00[StickyHoTs]|r Hidden")
            end
        end
    end

    -- Initial scan
    SH.RefreshCount()

    SH.initialized = true
end

-- Register for addon loaded
EVENT_MANAGER:RegisterForEvent(SH.name, EVENT_ADD_ON_LOADED, SH.OnAddOnLoaded)
