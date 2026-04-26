local addonName, Whorkaround = ...

-- Only load this module if ElvUI is actually present and enabled
if not IsAddOnLoaded("ElvUI") then return end

-- Helper function to fetch class from ElvUI's massive internal cache
function Whorkaround:GetElvUIClass(name)
    local E = _G.ElvUI and unpack(_G.ElvUI)
    local CH = E and E:GetModule("Chat")
    if not CH or not CH.ClassNames then return end
    
    local elvClass = CH.ClassNames[strlower(name)]
    if elvClass then
        -- Sync back to Whorkaround_DB for offline persistence across sessions
        if Whorkaround_DB and not (Whorkaround_DB[name] and Whorkaround_DB[name].class) then
            Whorkaround_DB[name] = Whorkaround_DB[name] or {}
            Whorkaround_DB[name].class = elvClass
            Whorkaround_DB[name].lastSeen = time()
            Whorkaround_DB[name].source = "ElvUI"
        end
        return elvClass
    end
end
