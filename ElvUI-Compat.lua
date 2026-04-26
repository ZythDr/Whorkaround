local addonName, Whorkaround = ...

-- Only load this module if ElvUI is actually present and enabled
if not IsAddOnLoaded("ElvUI") then return end

-- Mapping for ElvUI Enhanced's numeric Class IDs (3.3.5 standards)
local elvEnhancedClassMap = {
    [1] = "WARRIOR",
    [2] = "PALADIN",
    [3] = "HUNTER",
    [4] = "ROGUE",
    [5] = "PRIEST",
    [6] = "DEATHKNIGHT", -- Project Epoch: No DKs, but we'll include it for API completeness
    [7] = "SHAMAN",
    [8] = "MAGE",
    [9] = "WARLOCK",
    [10] = "DRUID",
}

-- Helper function to fetch class from ElvUI's internal caches (Runtime + Persistent)
function Whorkaround:GetElvUIClass(name)
    local E = _G.ElvUI and unpack(_G.ElvUI)
    local CH = E and E:GetModule("Chat")
    local elvClass = nil
    local source = "ElvUI"

    -- 1. Try ElvUI's short-term memory (Runtime Cache)
    if CH and CH.ClassNames then
        elvClass = CH.ClassNames[strlower(name)]
    end

    -- 2. Try ElvUI Enhanced's long-term memory (Persistent DB)
    if not elvClass and _G.EnhancedDB and _G.EnhancedDB.UnitClass then
        local classID = _G.EnhancedDB.UnitClass[name]
        if classID and elvEnhancedClassMap[classID] then
            elvClass = elvEnhancedClassMap[classID]
            source = "ElvUI_Enhanced"
        end
    end

    if elvClass then
        -- Sync back to Whorkaround_DB for offline persistence across sessions
        if Whorkaround_DB and not (Whorkaround_DB[name] and Whorkaround_DB[name].class) then
            Whorkaround_DB[name] = Whorkaround_DB[name] or {}
            Whorkaround_DB[name].class = elvClass
            Whorkaround_DB[name].lastSeen = time()
            Whorkaround_DB[name].source = source
        end
        return elvClass
    end
end
