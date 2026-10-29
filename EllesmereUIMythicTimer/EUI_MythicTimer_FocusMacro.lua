if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  EUI_MythicTimer_FocusMacro.lua
--  Kick Tracker (Mythic+ Tools), the Set Focus macro and marker clashes.
--
--  The Set Focus macro (EUI_Focus, an account macro) is written from the
--  Kick Tracker's Focus Marker, so changing the marker rewrites the macro and
--  nobody edits a marker number by hand. Its body: /focus on a hostile
--  mouseover (else the target), then, while a marker is set,
--  /tm [@focus] ~N (the ~ declines to overwrite a marker a group member
--  already placed), and with Ping Focus on, /ping [@focus] 3 (the numeric
--  alias, On My Way: the word forms only match on English clients). The
--  party is told the marker by Focus Announce's ready-check line alone
--  (EUI_MythicTimer_KickPlates.lua), never by the macro.
--
--  A clash: a party member's Kick Tracker tells, on the addon channel, the
--  marker that is yours. The options page's marker list names who holds
--  each marker, and a clash heard asks once (per member and marker, per
--  instance) whether to switch to a free marker. The free marker is worked
--  out at the click, so when both players of a clash answer, the second
--  sees the first's new marker and keeps theirs.
--
--  The macro is written from KT_Refresh (a settings write, a profile switch,
--  the module's enable) and once the session's macros are in, only when its
--  body changed; in combat the write waits for combat to end. Nothing runs on
--  WoW Forever (no Set Focus macro there: /tm's ~ is a retail extension).
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local PlainString = EllesmereUI.PlainString

local MACRO_NAME = "EUI_Focus"
local MACRO_ICON = 236203
local FOCUS_LINE = "/focus [@mouseover,harm,nodead] []"
-- A free marker is looked for from Skull down, the order groups mark in.
local FREE_ORDER = { 8, 7, 6, 5, 4, 3, 2, 1 }
local PARTY_UNITS = { "party1", "party2", "party3", "party4" }
local MARKER_ICON = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:0|t"

local function Cfg()
    local db = _G._EMT_AceDB
    local p = db and db.profile
    return p and p.kickTracker
end

-- A stored marker as 1-8, or nil (None, or a value edited out of range).
local function ValidMarker(v)
    v = tonumber(v)
    if v and v >= 1 and v <= 8 and v == math.floor(v) then return v end
    return nil
end

local function Body(cfg)
    local lines = { FOCUS_LINE }
    local mark = cfg and ValidMarker(cfg.focusMarker)
    local ping = cfg and cfg.focusMacroPing == true
    if mark or ping then
        -- Every trailing line acts on the focus: none acquired, none runs.
        lines[#lines + 1] = "/stopmacro [@focus,noexists]"
        if mark then lines[#lines + 1] = "/tm [@focus] ~" .. mark end
        if ping then lines[#lines + 1] = "/ping [@focus] 3" end
    end
    return table.concat(lines, "\n")
end

function ns.FM_Exists()
    return not EllesmereUI.IS_FOREVER and GetMacroIndexByName(MACRO_NAME) ~= 0
end

-- The macro brought in line with the settings, if the player has it.
local function Sync()
    if EllesmereUI.IS_FOREVER then return end
    local idx = GetMacroIndexByName(MACRO_NAME)
    if idx == 0 then return end
    if InCombatLockdown() then
        EllesmereUI.CombatQueue.Defer("KickTracker:FocusMacro", Sync)
        return
    end
    local body = Body(Cfg())
    if GetMacroBody(idx) ~= body then EditMacro(idx, nil, nil, body) end
end

-- Create and Delete run from a click, never in combat (both are protected
-- there); each answers whether it went through.
function ns.FM_Create()
    if EllesmereUI.IS_FOREVER or InCombatLockdown() then return false end
    if GetMacroIndexByName(MACRO_NAME) == 0 then
        CreateMacro(MACRO_NAME, MACRO_ICON, Body(Cfg()), nil)
    end
    return GetMacroIndexByName(MACRO_NAME) ~= 0
end

function ns.FM_Delete()
    if InCombatLockdown() then return false end
    if GetMacroIndexByName(MACRO_NAME) ~= 0 then DeleteMacro(MACRO_NAME) end
    return true
end

-- The Set Focus toggles used to live on the Macro Factory's Set Focus button
-- (EllesmereUIDB.macroFactory.EUI_Focus, account-wide). Moved once into the
-- profile in use: Auto Mark carries its marker over while no Focus Marker is
-- set (the macro marks whenever one is), Announce Focus is gone (Focus
-- Announce tells the party instead).
local migrated = false
local function Migrate(cfg)
    if migrated then return end
    migrated = true
    local mf = type(EllesmereUIDB) == "table" and EllesmereUIDB.macroFactory
    local old = type(mf) == "table" and mf[MACRO_NAME]
    if type(old) ~= "table" then return end
    mf[MACRO_NAME] = nil
    if old.autoMark and not ValidMarker(cfg.focusMarker) then
        cfg.focusMarker = ValidMarker(old.markIcon) or 8
    end
    if old.ping then cfg.focusMacroPing = true end
end

-- From KT_Refresh, ahead of Focus Announce reading the marker.
function ns.FM_Refresh(cfg)
    if not cfg or EllesmereUI.IS_FOREVER then return end
    Migrate(cfg)
    Sync()
end

-- At login the macros are not in when the module enables: one look on the
-- first loading screen and the first macro update, then nothing listens.
if not EllesmereUI.IS_FOREVER then
    local login = CreateFrame("Frame")
    login:SetScript("OnEvent", function(self, event)
        self:UnregisterEvent(event)
        Sync()
    end)
    login:RegisterEvent("PLAYER_ENTERING_WORLD")
    login:RegisterEvent("UPDATE_MACROS")
end

--------------------------------------------------------------------------------
--  Clashes
--------------------------------------------------------------------------------
-- marker -> the name of the party member whose Kick Tracker told it (the
-- first one, in party order). Only EllesmereUI users with the tracker on
-- tell their marker, so a marker absent here may still be someone's.
function ns.FM_MarkerUsers()
    local users = {}
    if not ns.KT_MarkerOf or IsInRaid() then return users end
    for i = 1, #PARTY_UNITS do
        local u = PARTY_UNITS[i]
        local guid = PlainString(UnitGUID(u))
        local mk = guid and ValidMarker(ns.KT_MarkerOf(guid))
        if mk and not users[mk] then users[mk] = PlainString(UnitName(u)) or "?" end
    end
    return users
end

-- Your marker while a party member uses it too, else nil.
function ns.FM_Clash()
    local cfg = Cfg()
    local mine = cfg and ValidMarker(cfg.focusMarker)
    if mine and ns.FM_MarkerUsers()[mine] then return mine end
    return nil
end

-- Moves your marker to the first one no party member uses, worked out now:
-- if the clash has gone (the other player switched first), nothing changes.
-- The settings write runs the usual refresh: the macro is rewritten and,
-- inside a dungeon, the new marker goes out on the addon channel.
function ns.FM_SwitchToFree()
    local cfg = Cfg()
    if not cfg then return end
    local users = ns.FM_MarkerUsers()
    local mine = ValidMarker(cfg.focusMarker)
    if mine and not users[mine] then return end
    for i = 1, #FREE_ORDER do
        local m = FREE_ORDER[i]
        if not users[m] then
            cfg.focusMarker = m
            if ns.KT_Refresh then ns.KT_Refresh() end
            EllesmereUI:RefreshPage()
            return
        end
    end
end

local asked = {}  -- "instance:guid:marker" -> true: each clash asks once

-- From the marker frame (EUI_MythicTimer_KickPlates.lua): a party member's
-- marker was heard on the addon channel.
function ns.FM_OnMarkerHeard(guid, marker)
    local cfg = Cfg()
    local mine = cfg and cfg.enabled == true and ValidMarker(cfg.focusMarker)
    if not mine or marker ~= mine then return end
    local _, _, _, _, _, _, _, inst = GetInstanceInfo()
    local key = tostring(inst) .. ":" .. guid .. ":" .. marker
    if asked[key] then return end
    asked[key] = true
    local name = ns.FM_MarkerUsers()[marker]
    if not name then return end
    local markerText = MARKER_ICON:format(marker) .. " " .. (_G["RAID_TARGET_" .. marker] or tostring(marker))
    EllesmereUI:ShowConfirmPopup({
        title = "Focus Marker Clash",
        message = EllesmereUI.Lf("%s also uses %s as their focus marker. Switch yours to a free marker? Your Set Focus macro updates with it.", name, markerText),
        confirmText = "Switch",
        cancelText = "Keep",
        onConfirm = ns.FM_SwitchToFree,
    })
end
