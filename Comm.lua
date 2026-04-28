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
local scheduledProxy = {} -- New: For live friends-list lookups
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
                local isLocal = (data.source == "FriendsList" or data.source == "Manual" or data.source == "Sighting")
                if isLocal then
                    Whorkaround:Log("Broadcasting cached data for " .. name .. " (Timeout phase)", "NETWORK")
                    Whorkaround:Broadcast(name, data.level, data.class, data.zone, data.faction, data.lastSeen, false, "BULK")
                end
            end
            scheduledResponses[name] = nil
        end
    end

    -- Process scheduled proxy lookups
    for name, sendTime in pairs(scheduledProxy) do
        if now >= sendTime then
            if Whorkaround.ProxyQuery then
                Whorkaround:ProxyQuery(name)
            end
            scheduledProxy[name] = nil
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
        local myName = UnitName("player")
        if chName == CH_NAME and sender and myName and sender:lower() ~= myName:lower() then
            -- Handle Data Requests (WKR:Faction:Name)
            if msg:sub(1, #REQ_PREFIX) == REQ_PREFIX then
                local content = msg:sub(#REQ_PREFIX + 1)
                local targetFaction, targetName = content:match("^(.-):(.+)$")
                
                -- Support older clients that don't send a faction tag
                if not targetName then
                    targetName = content
                    targetFaction = "U" -- Unknown/Any
                end

                if not targetName or targetName == "" then return end

                -- SELF-RESPONSE FEATURE:
                if targetName == UnitName("player") then
                    local _, class = UnitClass("player")
                    local race = UnitRace("player")
                    local faction = (UnitFactionGroup("player") == "Alliance") and "Alliance" or "Horde"
                    Whorkaround:Log("Received network request for SELF. Broadcasting my info.", "NETWORK")
                    Whorkaround:Broadcast(targetName, UnitLevel("player"), class, GetRealZoneText(), faction, time(), true)
                    return
                end

                local cleanName = targetName:lower():gsub("^%s*(.-)%s*$", "%1")
                local data = Whorkaround_DB and Whorkaround_DB[cleanName]
                local myFactionTag = (UnitFactionGroup("player") == "Alliance") and "A" or "H"
                local isCorrectFaction = (targetFaction == "U" or targetFaction == myFactionTag)

                -- IMMEDIATE PROXY CHECK: If they are already on our friends list, don't try to add them again
                local onList = false
                for i = 1, GetNumFriends() do
                    local fName, level, class, area, connected = GetFriendInfo(i)
                    if fName and fName:lower() == cleanName then
                        onList = true
                        if connected then
                            Whorkaround:Log("Immediate friends-list hit for " .. targetName .. "! Broadcasting :P", "PROXY")
                            Whorkaround:Broadcast(fName, level, class, area, UnitFactionGroup("player"), time(), true, "NORMAL")
                            return -- Online friend handled instantly
                        end
                        break
                    end
                end
                
                if onList then 
                    return 
                end
                
                -- PROXY LOGIC: Allow proxy if no cache OR cache is older than 60s
                local hasFreshCache = data and data.level and data.level > 0 and (time() - (data.lastSeen or 0) < 60)
                
                if Whorkaround_Settings.allowProxy and isCorrectFaction and not scheduledProxy[cleanName] and not hasFreshCache then
                    Whorkaround:Log("Scheduling proxy lookup for: " .. targetName, "PROXY")
                    local proxyDelay = 0.1 + (math.random() * 0.7) -- Restored stable proxy timing
                    scheduledProxy[cleanName] = GetTime() + proxyDelay
                    
                    -- If we had a cached response scheduled, cancel it if we are doing a proxy
                    scheduledResponses[cleanName] = nil
                end

                if data and data.level and data.level > 0 then
                    -- SENIORITY SUPPRESSION (CACHED DATA):
                    local age = time() - (data.lastSeen or 0)
                    local isFresh = (age < 30)
                    
                    -- Check broadcast throttle before scheduling (Anti-Echo)
                    local now = GetTime()
                    local canBroadcast = not (Whorkaround.broadcastThrottle and Whorkaround.broadcastThrottle[cleanName]) or (now - (Whorkaround.broadcastThrottle[cleanName] or 0) > 1)
                    if not canBroadcast then return end

                    -- Cache delay starts AFTER the proxy window (approx 1.5s)
                    local baseDelay = 2.0 + (isFresh and 0 or 1.5) -- Restored stable cache base
                    local ageFactor = (age / 86400) * 0.5
                    local randomBuffer = math.random() * 2.0
                    
                    if not scheduledResponses[cleanName] then
                        Whorkaround:Log("Scheduling cached response for: " .. targetName, "NETWORK")
                        scheduledResponses[cleanName] = GetTime() + baseDelay + ageFactor + randomBuffer
                    end
                end
                
                -- Global request tracking: Record that a request was sent (by anyone)
                Whorkaround.recentRequests = Whorkaround.recentRequests or {}
                Whorkaround.recentRequests[cleanName] = GetTime()

            -- Handle Data Broadcasts (WK:)
            elseif msg:sub(1, #MSG_PREFIX) == MSG_PREFIX then
                local rawData = msg:sub(#MSG_PREFIX + 1)
                
                -- FUTURE-PROOF PARSING: Split by colons and filter out "Key=Value" tags
                local fields = {}
                for part in rawData:gmatch("([^:]+)") do
                    if not part:find("^%a+=") then -- Skip any part that is a tag (e.g. G=Guild)
                        table.insert(fields, part)
                    end
                end

                -- Mapping based on core field indices
                local remoteVer = fields[1]
                local name = fields[2]
                local level = tonumber(fields[3])
                local class = fields[4]
                local zone = fields[5]
                local f = fields[6]
                local timestamp = tonumber(fields[7])
                local isProxy = fields[8]
                
                if remoteVer and not notifiedUpdate and IsNewerVersion(remoteVer, currentVersion) then
                    local prefix = "|cff1abc9cWhorkaround Update:|r "
                    DEFAULT_CHAT_FRAME:AddMessage(prefix .. "A newer version (|cffffd100v" .. remoteVer .. "|r) is available!")
                    notifiedUpdate = true
                end

                -- SMART SUPPRESSION: Only cancel if their data is better or equal to ours
                if name then 
                    local cleanName = name:lower():gsub("^%s*(.-)%s*$", "%1")
                    local otherIsLive = (isProxy == "P")
                    local otherTime = timestamp or 0
                    local myData = Whorkaround_DB and Whorkaround_DB[cleanName]
                    local myTime = myData and myData.lastSeen or 0

                    -- Anti-Echo: Record that we heard data from the network
                    Whorkaround.broadcastThrottle = Whorkaround.broadcastThrottle or {}
                    Whorkaround.broadcastThrottle[cleanName] = GetTime()
                    
                    if scheduledProxy[cleanName] then
                        -- We have a timer pending. Cancel if ANY data arrives.
                        if otherIsLive or (otherTime > (time() - 30)) then
                            Whorkaround:Log("Canceling pending proxy timer for " .. name .. " (Data heard)", "PROXY")
                            scheduledProxy[cleanName] = nil 
                        end
                    end

                    -- NEW: If we already ADDED the friend for a proxy lookup, cancel it too
                    if Whorkaround.pendingQueries and Whorkaround.pendingQueries[cleanName] == "PROXY" then
                         if otherIsLive or (otherTime > (time() - 30)) then
                            Whorkaround:Log("Canceling active proxy query for " .. name .. " (Data heard)", "PROXY")
                            Whorkaround.pendingQueries[cleanName] = nil
                            -- Note: The friend stays in the list until CleanGhostFriends runs, but we won't broadcast it.
                        end
                    end

                    if scheduledResponses[cleanName] then
                        -- We have cache pending. Cancel if they have live OR newer/equal cache.
                        if otherIsLive or otherTime >= myTime then
                            Whorkaround:Log("Canceling pending cache for " .. name .. " (Better/Equal data heard)", "NETWORK")
                            scheduledResponses[cleanName] = nil
                        end
                    end
                end

                if name and name:len() <= 12 and name:match("^[%a]+$") then
                    if not level or level > 60 or level < 0 then return end
                    local cleanName = name:lower():gsub("^%s*(.-)%s*$", "%1")
                    class = (class or ""):upper()
                    timestamp = timestamp or time()
                    local faction = (f == "A") and "Alliance" or (f == "H" and "Horde" or "Unknown")
                    if level and level > 0 and level <= 60 and validClasses[class] and validFactions[faction] and zone:len() < 50 then
                        if Whorkaround_DB then
                            if not Whorkaround_DB[cleanName] or timestamp > (Whorkaround_DB[cleanName].lastSeen or 0) then
                                Whorkaround:Log("Incoming network data for " .. name .. " (" .. (isProxy == "P" and "Live" or "Cache") .. ")", "NETWORK")
                                Whorkaround_DB[cleanName] = {
                                    class = class, level = level, zone = zone,
                                    faction = faction, lastSeen = timestamp, source = "WhorkComm"
                                }
                                if Whorkaround.ResolveNetworkWait then
                                    Whorkaround:ResolveNetworkWait(cleanName, level, class, zone, faction, timestamp, isProxy)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

function Whorkaround:CancelScheduledResponse(name)
    if name then
        local cleanName = name:lower():gsub("^%s*(.-)%s*$", "%1")
        scheduledResponses[cleanName] = nil
    end
end

function Whorkaround:Broadcast(name, level, class, zone, faction, timestamp, isProxy, priorityOverride)
    local id = GetChannelName(CH_NAME)
    if id and id > 0 then
        local cleanName = name:lower():gsub("^%s*(.-)%s*$", "%1")
        Whorkaround.broadcastThrottle = Whorkaround.broadcastThrottle or {}
        Whorkaround.broadcastThrottle[cleanName] = GetTime()

        name = name:gsub("^%l", string.upper)
        class = (class or "Unknown"):upper()
        timestamp = timestamp or time()
        local f = (faction == "Alliance") and "A" or (faction == "Horde" and "H" or "U")
        local p = isProxy and "P" or "C"
        -- Include version, timestamp, and proxy flag in the broadcast
        local msg = string.format("%s%s:%s:%d:%s:%s:%s:%d:%s", MSG_PREFIX, currentVersion, name, level, class, zone or "Unknown", f, timestamp, p)
        
        if _G.ChatThrottleLib then
            -- Default priority logic if no override: Live/Fresh = NORMAL, Stale = BULK
            local priority = priorityOverride or ((isProxy or timestamp > (time() - 10)) and "NORMAL" or "BULK")
            _G.ChatThrottleLib:SendChatMessage(priority, "Whork", msg, "CHANNEL", nil, id)
        else
            SendChatMessage(msg, "CHANNEL", nil, id)
        end
    end
end

function Whorkaround:Request(name, factionTag)
    local id = GetChannelName(CH_NAME)
    if id and id > 0 then
        local cleanName = name:lower():gsub("^%s*(.-)%s*$", "%1")
        -- Don't request the same name more than once every 30 seconds globally
        Whorkaround.recentRequests = Whorkaround.recentRequests or {}
        if Whorkaround.recentRequests[cleanName] and (GetTime() - Whorkaround.recentRequests[cleanName] < 5) then 
            return 
        end
        Whorkaround.recentRequests[cleanName] = GetTime()
        
        -- Default to 'U' (Unknown) only if no tag provided, but we aim for A/H
        local msg = REQ_PREFIX .. (factionTag or "U") .. ":" .. name
        Whorkaround:Log("Broadcasting network REQUEST for " .. name .. " (Target Faction: " .. (factionTag or "U") .. ")", "NETWORK")
        
        if _G.ChatThrottleLib then
            _G.ChatThrottleLib:SendChatMessage("NORMAL", "Whork", msg, "CHANNEL", nil, id)
        else
            SendChatMessage(msg, "CHANNEL", nil, id)
        end
    end
end

function Whorkaround:CheckComm()
    local id, name = GetChannelName(CH_NAME)
    local prefix = "|cff1abc9cWhorkaround Debug:|r "
    if id and id > 0 then
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. "Comm channel active at index " .. id)
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. "Current Version: |cffffd100v" .. currentVersion .. "|r")
    else
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. "Comm channel NOT active. Attempting rejoin...")
        JoinCommChannel()
    end
end
