local addonName, Whorkaround = ...

Whorkaround.DebugMode = false

local COLORS = {
    NETWORK = "|cff3498db[Network]|r",
    LOCAL   = "|cff2ecc71[Local]|r",
    PROXY   = "|cff9b59b6[Proxy]|r",
    CLEANUP = "|cfff1c40f[Cleanup]|r",
    SYSTEM  = "|cff95a5a6[System]|r",
}

function Whorkaround:Log(msg, category)
    if not (Whorkaround.DebugMode or (Whorkaround_Settings and Whorkaround_Settings.debug)) then return end
    
    local prefix = "|cff1abc9cWhorkDebug:|r "
    local catPrefix = COLORS[category or "SYSTEM"] or COLORS.SYSTEM
    
    local chat = DEFAULT_CHAT_FRAME
    if Whorkaround_Settings and Whorkaround_Settings.outputTab and Whorkaround_Settings.outputTab ~= "" then
        local found = false
        for tabName in Whorkaround_Settings.outputTab:gmatch("([^,]+)") do
            tabName = tabName:gsub("^%s*(.-)%s*$", "%1"):lower()
            for i = 1, NUM_CHAT_WINDOWS do
                local name = GetChatWindowInfo(i)
                if name and name:lower() == tabName then
                    chat = _G["ChatFrame"..i]
                    found = true; break
                end
            end
            if found then break end
        end
    end
    
    chat:AddMessage(prefix .. catPrefix .. " " .. msg)
end

function Whorkaround:ToggleDebug()
    Whorkaround.DebugMode = not Whorkaround.DebugMode
    -- Sync to SavedVariable for persistence across sessions
    if Whorkaround_Settings then Whorkaround_Settings.debug = Whorkaround.DebugMode end
    print("|cff1abc9cWhorkaround:|r Debug logging is now " .. (Whorkaround.DebugMode and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r"))
end

