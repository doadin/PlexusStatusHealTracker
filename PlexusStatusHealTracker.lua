--[[--------------------------------------------------------------------
    PlexusStatusHealTracker
    Shows in Plexus who was healed by your multi-target heals.
    Copyright (c) 2010-2011 Akkorian <akkorian@armord.net>. All rights reserved.
    Copyright (c) 2011-2018 Phanx <addons@phanx.net>. All rights reserved.
    Copyright (c) 2020 Doadin <doadinaddons@gmail.com>. All rights reserved.

    TODO:
    Listen for totem/guardian create/destroy events in CLEU, keep a list
    of their GUIDs, and match against the list instead of only matching
    against the player's GUID, so heals from totems/mushrooms/etc can
    be traced.
----------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L
local GetSpellInfo = GetSpellInfo

local PlexusStatusHealTracker = Plexus:NewStatusModule("PlexusStatusHealTracker") --luacheck: ignore 113
local active, spellOrder, playerGUID, settings, spells = {}, {}

------------------------------------------------------------------------

PlexusStatusHealTracker.defaultDB = {
    alert_healTrace = {
        color = { r = 0.8, g = 1.0, b = 0.2, a = 1 },
        enable = true,
        holdTime = 1,
        priority = 75,
        range = false,
        spells = {},
    }
}
for _, spellID in ipairs({
    -- Druid
    391888,    -- Adaptive Swarm
    392325,    -- Verdancy
    145108,    -- Ysera's Gift
    -- Monk
    123986, -- Chi Burst
    115098, -- Chi Wave
    196725, -- Refreshing Jade Wind
    274586, -- Invigorating Mists
    274909, -- Rising Mist (talent)
    388024, -- Ancient Teachings
    388193, -- Faeline Stomp
    388779, -- Awakened Faeline
    388038, -- Yu'lon's Whisper
    399491, -- Sheilun's Gift
    -- Paladin
    119952, -- Arcing Light (talent: Light's Hammer)
    114852, -- Holy Prism (talent, cast on enemy target)
    114165, -- Holy Prism (talent, cast on friendly target)
    85222,  -- Light of Dawn
    200652, -- Tyr's Deliverance
    -- Priest
    368276,  -- Binding Heal
    204883, -- Circle of Healing
    110744, -- Divine Star (talent)
    122121, -- Divine Star (talent,Disc Shadow Covenant)
    120517, -- Halo (talent)
    120644, -- Halo (talent,Disc Shadow Covenant)
    132157, -- Holy Nova
    34861,  -- Holy Word: Sanctify
    194509, -- Power Word: Radiance
    596,    -- Prayer of Healing
    200128, -- Trail of Light
    197419  , -- Contrition
    -- Shaman
    1064,   -- Chain Heal
    157503, -- Cloudburst
    383222, -- Overflowing Shores
    114911, -- Ancestral Guidance
    --5394,   -- Healing Stream Totem (doesn't work, caster not player)
    108280, -- Healing Tide Totem
    294020, -- Restorative Mists (talent: Ascendance)
    207778, -- Downpour
    197995, -- Wellspring
    -- Evoker
    370960, --Emerald Communion (talent, 40yrds)
    371832, --Cycle of Life (talent)
    355913, --Emerald Blossom
    367226, --Spiritbloom
}) do
    local name, _, icon = GetSpellInfo(spellID) --luacheck: ignore 113
    if name then
        PlexusStatusHealTracker.defaultDB.alert_healTrace.spells[name] = icon
    end
end

------------------------------------------------------------------------

local optionsForStatus = {
    holdTime = {
        order = -3,
        width = "double",
        name = L["Hold time"],
        desc = L["Show the status for this many seconds."],
        type = "range",
        min = 0.25,
        max = 5,
        step = 0.25,
        get = function()
            return PlexusStatusHealTracker.db.profile.alert_healTrace.holdTime
        end,
        set = function(_, v)
            PlexusStatusHealTracker.db.profile.alert_healTrace.holdTime = v
        end,
    },
    addSpell = {
        order = -2,
        width = "double",
        name = L["Add new spell"],
        desc = L["Add another healing spell to trace."],
        type = "input",
        usage = L["<spell name or spell ID>"],
        get = false,
        set = function(_, v)
            PlexusStatusHealTracker:AddSpell(string.trim(v)) --luacheck: ignore 143
        end,
    },
    removeSpell = {
        order = -1,
        name = L["Remove spell"],
        desc = L["Remove a spell from the trace list."],
        type = "group", dialogInline = true,
        args = {},
    },
}

------------------------------------------------------------------------

do
    local function removeSpell_func(info)
        PlexusStatusHealTracker:RemoveSpell(info.arg)
    end

    function PlexusStatusHealTracker:AddSpell(name, icon)
        if name:match("^(%d+)$") then
            local _
            name, _, icon = GetSpellInfo(name) --luacheck: ignore 113
        end

        if not name then return end

        if type(icon) == "boolean" then
            icon = nil
        end

        self.db.profile.alert_healTrace.spells[name] = icon or true

        optionsForStatus.removeSpell.args[name] = {
            name = string.format("\124T%s:0:0:0:0:32:32:3:29:3:29\124t %s", icon or "Interface\\ICONS\\INV_Misc_QuestionMark", name), --luacheck: ignore 631
            desc = string.format(L["Remove %s from the trace list."], name),
            type = "execute",
            func = removeSpell_func,
            arg = name,
        }

        if not spellOrder[name] then
            spellOrder[name] = true
            spellOrder[#spellOrder + 1] = name
            table.sort(spellOrder)
            for i = 1, #spellOrder do
                optionsForStatus.removeSpell.args[spellOrder[i]].order = i
            end
        end
    end

    function PlexusStatusHealTracker:RemoveSpell(name)
        self.db.profile.alert_healTrace.spells[name] = nil
        optionsForStatus.removeSpell.args[name] = nil
    end
end

------------------------------------------------------------------------

function PlexusStatusHealTracker:PostInitialize()
    self:RegisterStatus("alert_healTrace", "Heal Tracker", optionsForStatus, true)

    settings = self.db.profile.alert_healTrace
    spells = settings.spells

    if not settings.version or settings.version < 1 then
        wipe(spells) --luacheck: ignore 113
        for k, v in pairs(self.defaultDB.alert_healTrace.spells) do
            spells[k] = v
        end
        settings.version = 1
    end

    for name, icon in pairs(spells) do
        self:AddSpell(name, icon)
    end
end

function PlexusStatusHealTracker:PostEnable()
    playerGUID = UnitGUID("player") --luacheck: ignore 113
    self:RegisterEvent("SPELLS_CHANGED", "OnStatusEnable")
end

function PlexusStatusHealTracker:OnStatusEnable(status)
    for name in pairs(spells) do
        if GetSpellInfo(name) then --luacheck: ignore 113
            return self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        end
    end
    self:OnStatusDisable(status)
end

function PlexusStatusHealTracker:OnStatusDisable(status) --luacheck: ignore 212
    self:UnregisterAllEvents()
    self.core:SendStatusLostAllUnits("alert_healTrace")
end

function PlexusStatusHealTracker:PostReset()
    self.core:SendStatusLostAllUnits("alert_healTrace")

    settings = self.db.profile.alert_healTrace
    spells = settings.spells
    for name in pairs(optionsForStatus.removeSpell.args) do
        if not spells[name] then
            optionsForStatus.removeSpell.args[name] = nil
        end
    end
    for name, icon in pairs(spells) do
        if not optionsForStatus.removeSpell.args[name] then
            self:AddSpell(name, icon)
        end
    end
    if self.db.profile.alert_healTrace.enable then
        self:RegisterEvent("SPELLS_CHANGED", "OnStatusEnable")
    end
end

------------------------------------------------------------------------

local timerFrame = CreateFrame("Frame") --luacheck: ignore 113
timerFrame:Hide()
timerFrame:SetScript("OnUpdate", function(self, elapsed)
    local i = 0
    for destGUID, holdTime in pairs(active) do
        holdTime = holdTime - elapsed
        if holdTime <= 0 then
            PlexusStatusHealTracker.core:SendStatusLost(destGUID, "alert_healTrace")
            active[destGUID] = nil
        else
            active[destGUID] = holdTime
            i = i + 1
        end
    end
    if i == 0 then
        self:Hide()
    end
end)

local totemguid
function PlexusStatusHealTracker:COMBAT_LOG_EVENT_UNFILTERED() --luacheck: ignore 212 _, _, event
    local _, eventType, _, sourceGUID, _, _, _, destGUID, _, _, _, spellID, spellName = CombatLogGetCurrentEventInfo() --luacheck: ignore 631 113 211
    if sourceGUID == playerGUID and eventType == "SPELL_SUMMON" and spells[spellName] then
        totemguid = destGUID -- healing tide fix
    end
    if (eventType == "SPELL_HEAL" or eventType == "SPELL_PERIODIC_HEAL") and ((sourceGUID == playerGUID and spells[spellName]) or sourceGUID == totemguid) then
        local _, _, spellIcon = GetSpellInfo(spellID) --luacheck: ignore 113
        self.core:SendStatusGained(destGUID, "alert_healTrace",
            settings.priority,
            settings.range,
            settings.color,
            spellName,
            nil,
            nil,
            spellIcon
        )
        if destGUID then
            active[destGUID] = settings.holdTime
        end
        timerFrame:Show()
    end
end
