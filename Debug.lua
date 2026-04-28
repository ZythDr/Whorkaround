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
    if not Whorkaround.DebugMode then return end
    
    local prefix = "|cff1abc9cWhorkDebug:|r "
    local catPrefix = COLORS[category or "SYSTEM"] or COLORS.SYSTEM
    
    local chat = DEFAULT_CHAT_FRAME
    if Whorkaround_Settings and Whorkaround_Settings.outputTab then
        for i = 1, NUM_CHAT_WINDOWS do
            local name = GetChatWindowInfo(i)
            if name and name:lower() == Whorkaround_Settings.outputTab:lower() then
                chat = _G["ChatFrame"..i]
                break
            end
        end
    end
    
    chat:AddMessage(prefix .. catPrefix .. " " .. msg)
end

function Whorkaround:ToggleDebug()
    Whorkaround.DebugMode = not Whorkaround.DebugMode
    print("|cff1abc9cWhorkaround:|r Debug logging is now " .. (Whorkaround.DebugMode and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r"))
end
