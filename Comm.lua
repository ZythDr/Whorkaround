local addonName, Whorkaround = ...

local CH_NAME = "WhorkComm"
local CH_ID = nil
local MSG_PREFIX = "WK:" 

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHANNEL_UI_UPDATE")
frame:RegisterEvent("CHAT_MSG_CHANNEL")

-- Strict Validation Tables
local validClasses = {
    ["WARRIOR"] = true, ["PALADIN"] = true, ["HUNTER"] = true, ["ROGUE"] = true,
    ["PRIEST"] = true, ["SHAMAN"] = true, ["MAGE"] = true, ["WARLOCK"] = true,
    ["DRUID"] = true,
}
local validFactions = { ["Alliance"] = true, ["Horde"] = true }

local function JoinCommChannel()
    local id, name = GetChannelName(CH_NAME)
    if id and id > 0 then 
        CH_ID = id
        return 
    end
    
    JoinChannelByName(CH_NAME)
    
    local t = 0
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self, elapsed)
        t = t + elapsed
        if t > 2 then
            local newId = GetChannelName(CH_NAME)
            if newId and newId > 0 then
                CH_ID = newId
                for i = 1, 10 do
                    local cf = _G["ChatFrame"..i]
                    if cf then ChatFrame_RemoveChannel(cf, CH_NAME) end
                end
                self:SetScript("OnUpdate", nil)
            end
        end
    end)
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
        if chName == CH_NAME and sender ~= UnitName("player") then
            if msg:sub(1, #MSG_PREFIX) == MSG_PREFIX then
                local data = msg:sub(#MSG_PREFIX + 1)
                -- Increased pattern strictness to prevent "poisoning" via malformed strings
                local name, level, class, zone, faction = data:match("^([^:]+):(%d+):([^:]+):([^:]+):([^:]+)$")
                if name and name:len() <= 12 and name:match("^[%a]+$") then
                    level = tonumber(level)
                    class = (class or ""):upper()
                    -- Strict Logic Check: If any of these are invalid, we toss the whole packet
                    if level and level > 0 and level <= 60 and validClasses[class] and validFactions[faction] and zone:len() < 50 then
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
    local id = GetChannelName(CH_NAME)
    if id and id > 0 then
        -- Sanitize outgoing data to ensure we don't accidentally send malformed strings
        name = name:match("^%a+") or name
        class = (class or "Unknown"):upper()
        zone = zone or "Unknown"
        faction = faction or "Unknown"
        
        local msg = string.format("%s%s:%d:%s:%s:%s", MSG_PREFIX, name, level, class, zone, faction)
        SendChatMessage(msg, "CHANNEL", nil, id)
    end
end

function Whorkaround:CheckComm()
    local id, name = GetChannelName(CH_NAME)
    local prefix = "|cff1abc9cWhorkaround Debug:|r "
    if id and id > 0 then
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. "Comm channel active at index " .. id)
        SendChatMessage(MSG_PREFIX .. "TEST:0:NONE:NONE:Unknown", "CHANNEL", nil, id)
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. "Sent test broadcast. If channel is enabled in settings, you should see it.")
    else
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. "Comm channel NOT active. Attempting rejoin...")
        JoinCommChannel()
    end
end
