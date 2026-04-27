local addonName, Whorkaround = ...

local CH_NAME = "WhorkComm"
local CH_ID = nil
local MSG_PREFIX = "WK:" 
local VERSION_PREFIX = "WKV:"
local REQ_PREFIX = "WKR:"
local GITHUB_URL = "https://github.com/ZythDr/Whorkaround"
local currentVersion = GetAddOnMetadata(addonName, "Version") or "1.0"
local notifiedUpdate = false

local scheduledResponses = {}
local recentRequests = {}

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

-- Version comparison
local function IsNewerVersion(newVer, oldVer)
    local newParts = {string.match(newVer, "(%d+)%.?(%d*)%.?(%d*)")}
    local oldParts = {string.match(oldVer, "(%d+)%.?(%d*)%.?(%d*)")}
    for i = 1, 3 do
        local n = tonumber(newParts[i]) or 0
        local o = tonumber(oldParts[i]) or 0
        if n > o then return true end
        if n < o then return false end
    end
    return false
end

local function JoinCommChannel()
    local id, name = GetChannelName(CH_NAME)
    if id and id > 0 then CH_ID = id; return end
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

    -- Process scheduled responses (Seniority Suppression logic)
    local now = GetTime()
    for name, sendTime in pairs(scheduledResponses) do
        if now >= sendTime then
            local data = Whorkaround_DB and Whorkaround_DB[name]
            if data and data.level and data.level > 0 then
                Whorkaround:Broadcast(name, data.level, data.class, data.zone, data.faction, data.lastSeen)
            end
            scheduledResponses[name] = nil
        end
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
            -- Handle Version Check
            if msg:sub(1, #VERSION_PREFIX) == VERSION_PREFIX then
                local remoteVersion = msg:sub(#VERSION_PREFIX + 1)
                if not notifiedUpdate and IsNewerVersion(remoteVersion, currentVersion) then
                    local prefix = "|cff1abc9cWhorkaround Update:|r "
                    DEFAULT_CHAT_FRAME:AddMessage(prefix .. "A newer version (|cffffd100v" .. remoteVersion .. "|r) is available!")
                    DEFAULT_CHAT_FRAME:AddMessage(prefix .. "Download here: |cff0070dd" .. GITHUB_URL .. "|r")
                    notifiedUpdate = true
                end
            
            -- Handle Data Requests (WKR:)
            elseif msg:sub(1, #REQ_PREFIX) == REQ_PREFIX then
                local targetName = msg:sub(#REQ_PREFIX + 1)
                local data = Whorkaround_DB and Whorkaround_DB[targetName]
                if data and data.level and data.level > 0 then
                    -- SENIORITY SUPPRESSION:
                    -- Delay is based on data age. Newest data (fresh) replies first.
                    local age = time() - (data.lastSeen or 0)
                    local baseDelay = 0.5
                    -- Age factor: 0.1s delay for every hour of age, capped at 4s
                    local ageFactor = math.min(4.0, (age / 3600) * 0.1)
                    local randomBuffer = math.random() * 0.5 -- Small random buffer to split exact ties
                    
                    if not scheduledResponses[targetName] then
                        scheduledResponses[targetName] = GetTime() + baseDelay + ageFactor + randomBuffer
                    end
                end

            -- Handle Data Broadcasts (WK:)
            elseif msg:sub(1, #MSG_PREFIX) == MSG_PREFIX then
                local data = msg:sub(#MSG_PREFIX + 1)
                -- FORMAT: WK:Version:Name:Level:Class:Zone:F:Timestamp
                local remoteVer, name, level, class, zone, f, timestamp = data:match("^(.-):(.-):(%d+):(.-):(.-):(.-):(%d+)$")
                
                if remoteVer and not notifiedUpdate and IsNewerVersion(remoteVer, currentVersion) then
                    local prefix = "|cff1abc9cWhorkaround Update:|r "
                    DEFAULT_CHAT_FRAME:AddMessage(prefix .. "A newer version (|cffffd100v" .. remoteVer .. "|r) is available!")
                    notifiedUpdate = true
                end

                -- Suppression: If we hear anyone else answer a request, cancel our own schedule
                if name then scheduledResponses[name] = nil end

                if name and name:len() <= 12 and name:match("^[%a]+$") then
                    level = tonumber(level)
                    class = (class or ""):upper()
                    timestamp = tonumber(timestamp) or time()
                    local faction = (f == "A") and "Alliance" or (f == "H" and "Horde" or "Unknown")
                    if level and level > 0 and level <= 60 and validClasses[class] and validFactions[faction] and zone:len() < 50 then
                        if Whorkaround_DB then
                            -- Only update if the network data is newer than what we have
                            if not Whorkaround_DB[name] or timestamp > (Whorkaround_DB[name].lastSeen or 0) then
                                Whorkaround_DB[name] = {
                                    class = class, level = level, zone = zone,
                                    faction = faction, lastSeen = timestamp, source = "WhorkComm"
                                }
                                -- If we were explicitly waiting for this name, trigger the UI update
                                if Whorkaround.ResolveNetworkWait then
                                    Whorkaround:ResolveNetworkWait(name, level, class, zone, faction)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

function Whorkaround:Broadcast(name, level, class, zone, faction, timestamp)
    local id = GetChannelName(CH_NAME)
    if id and id > 0 then
        name = name:match("^%a+") or name
        class = (class or "Unknown"):upper()
        timestamp = timestamp or time()
        local f = (faction == "Alliance") and "A" or (faction == "Horde" and "H" or "U")
        -- Include version and timestamp in the broadcast
        local msg = string.format("%s%s:%s:%d:%s:%s:%s:%d", MSG_PREFIX, currentVersion, name, level, class, zone or "Unknown", f, timestamp)
        SendChatMessage(msg, "CHANNEL", nil, id)
    end
end

function Whorkaround:Request(name)
    local id = GetChannelName(CH_NAME)
    if id and id > 0 then
        -- Don't request the same name more than once every 10 minutes locally
        if recentRequests[name] and (GetTime() - recentRequests[name] < 600) then return end
        recentRequests[name] = GetTime()
        SendChatMessage(REQ_PREFIX .. name, "CHANNEL", nil, id)
    end
end

function Whorkaround:CheckComm()
    local id, name = GetChannelName(CH_NAME)
    local prefix = "|cff1abc9cWhorkaround Debug:|r "
    if id and id > 0 then
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. "Comm channel active at index " .. id)
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. "Current Version: |cffffd100v" .. currentVersion .. "|r")
        SendChatMessage(VERSION_PREFIX .. currentVersion, "CHANNEL", nil, id)
    else
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. "Comm channel NOT active. Attempting rejoin...")
        JoinCommChannel()
    end
end
