local addonName, Whorkaround = ...

local CH_NAME = "WhorkComm"
local CH_ID = nil
local MSG_PREFIX = "\001WK:" -- Non-printable prefix to prevent manual chat "poisoning"

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHANNEL_UI_UPDATE")
frame:RegisterEvent("CHAT_MSG_CHANNEL")

-- Valid data sets for verification (Project Epoch: Vanilla classes only)
local validClasses = {
    ["WARRIOR"] = true, ["PALADIN"] = true, ["HUNTER"] = true, ["ROGUE"] = true,
    ["PRIEST"] = true, ["SHAMAN"] = true, ["MAGE"] = true, ["WARLOCK"] = true,
    ["DRUID"] = true,
}
local validFactions = { ["Alliance"] = true, ["Horde"] = true }

-- Join the channel silently
local function JoinCommChannel()
    CH_ID = GetChannelName(CH_NAME)
    if CH_ID and CH_ID > 0 then return end
    JoinTemporaryChannel(CH_NAME)
    CH_ID = GetChannelName(CH_NAME)
    if CH_ID and CH_ID > 0 then
        for i = 1, 10 do
            local cf = _G["ChatFrame"..i]
            if cf then ChatFrame_RemoveChannel(cf, CH_NAME) end
        end
    end
end

local joinTimer = 0
frame:SetScript("OnUpdate", function(self, elapsed)
    if joinTimer > 0 then
        joinTimer = joinTimer - elapsed
        if joinTimer <= 0 then JoinCommChannel() end
    end
end)

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        joinTimer = 10 
    elseif event == "CHANNEL_UI_UPDATE" then
        CH_ID = GetChannelName(CH_NAME)
    elseif event == "CHAT_MSG_CHANNEL" then
        local msg, sender, lang, chNameWithID, sender2, flags, zoneID, chID, chName = ...
        
        -- Verification: Only accept messages from other users with the correct hidden prefix
        if chName == CH_NAME and sender ~= UnitName("player") then
            if msg:sub(1, #MSG_PREFIX) == MSG_PREFIX then
                local data = msg:sub(#MSG_PREFIX + 1)
                local name, level, class, zone, faction = data:match("^(.-):(%d+):(.-):(.-):(.-)$")
                
                if name then
                    level = tonumber(level)
                    class = class:upper()
                    
                    -- Content Validation: Project Epoch (Level 1-60, No DKs)
                    if level and level > 0 and level <= 60 and validClasses[class] and validFactions[faction] then
                        if Whorkaround_DB then
                            Whorkaround_DB[name] = {
                                class = class,
                                level = level,
                                zone = zone,
                                faction = faction,
                                lastSeen = time(),
                                source = "WhorkComm"
                            }
                        end
                    end
                end
            end
        end
    end
end)

function Whorkaround:Broadcast(name, level, class, zone, faction)
    CH_ID = GetChannelName(CH_NAME)
    if CH_ID and CH_ID > 0 then
        class = class:upper()
        local msg = string.format("%s%s:%d:%s:%s:%s", MSG_PREFIX, name, level, class, zone, faction or "Unknown")
        SendChatMessage(msg, "CHANNEL", nil, CH_ID)
    end
end
