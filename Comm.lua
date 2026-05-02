local addonName, Whorkaround = ...

local CH_NAME = "WhorkComm"
local CH_ID = nil
local MSG_PREFIX = "WK:" 
local VERSION_PREFIX = "WKV:"
local REQ_PREFIX = "WKR:"
local GITHUB_URL = "https://github.com/ZythDr/Whorkaround"
local currentVersion = GetAddOnMetadata(addonName, "Version") or "1.0"
local notifiedUpdate = false
local hasAnnounced = false

local scheduledResponses = {}
local scheduledProxy = {} -- New: For live friends-list lookups
local tempFields = {} -- RECYCLABLE TABLE: Used for message parsing to reduce garbage

-- Passive Proxy Peer Tracking
Whorkaround.proxyPeers = Whorkaround.proxyPeers or {}
Whorkaround.networkPeers = Whorkaround.networkPeers or {}


local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHANNEL_UI_UPDATE")
frame:RegisterEvent("CHAT_MSG_CHANNEL")
frame:RegisterEvent("CHAT_MSG_CHANNEL_LEAVE")

-- Strict Validation Tables (Using shared table from core)
local validClasses = Whorkaround.validClasses
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

local function AnnouncePresence()
    if hasAnnounced then return end
    if not Whorkaround_Settings then return end -- Settings not yet loaded (early /checkcomm call)
    local id = GetChannelName(CH_NAME)
    if not id or id == 0 then return end
    local proxyFlag = Whorkaround_Settings.allowProxy and "P" or "N"
    local msg = VERSION_PREFIX .. currentVersion .. ":" .. proxyFlag
    if _G.ChatThrottleLib then
        _G.ChatThrottleLib:SendChatMessage("BULK", "Whork", msg, "CHANNEL", nil, id)
    else
        SendChatMessage(msg, "CHANNEL", nil, id)
    end
    hasAnnounced = true
    Whorkaround:Log("Announced presence: v" .. currentVersion .. " (" .. proxyFlag .. ")", "NETWORK")
end

local function JoinCommChannel()
    local id, name = GetChannelName(CH_NAME)
    if id and id > 0 then CH_ID = id; AnnouncePresence(); return end
    JoinChannelByName(CH_NAME)
    
    local t = 0
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self, elapsed)
        t = t + elapsed
        if t > 2 then
            local newId = GetChannelName(CH_NAME)
            if newId and newId > 0 then
                CH_ID = newId
                AnnouncePresence()
                self:SetScript("OnUpdate", nil)
            end
        end
    end)
end

local joinTimer = 0
local expiredResponses = {}
local expiredProxy = {}
local lastPrune = 0

frame:SetScript("OnUpdate", function(self, elapsed)
    if joinTimer > 0 then
        joinTimer = joinTimer - elapsed
        if joinTimer <= 0 then JoinCommChannel() end
    end

    self.timer = (self.timer or 0) + elapsed
    if self.timer < 0.1 then return end
    self.timer = 0

    local now = GetTime()

    -- Periodic Pruning (Every 60 seconds) to prevent memory buildup
    if now - lastPrune > 60 then
        lastPrune = now
        local pruneCutoff = now - 300 -- 5 minute stale cutoff
        for name, lastSeen in pairs(Whorkaround.networkPeers or {}) do if now - lastSeen > pruneCutoff then Whorkaround.networkPeers[name] = nil end end
        for name, lastSeen in pairs(Whorkaround.proxyPeers or {}) do if now - lastSeen > pruneCutoff then Whorkaround.proxyPeers[name] = nil end end
        for name, reqTime in pairs(Whorkaround.recentRequests or {}) do if now - reqTime > 600 then Whorkaround.recentRequests[name] = nil end end
        for name, throttleTime in pairs(Whorkaround.broadcastThrottle or {}) do if now - throttleTime > 10 then Whorkaround.broadcastThrottle[name] = nil end end
    end

    -- Skip expensive work when there's nothing to process
    if joinTimer <= 0 and not next(scheduledResponses) and not next(scheduledProxy) then return end

    -- Process scheduled responses (Seniority Suppression logic)
    if next(scheduledResponses) then
        wipe(expiredResponses)
        for name, sendTime in pairs(scheduledResponses) do
            if now >= sendTime then
                local data = Whorkaround_DB and Whorkaround_DB[name]
                if data and type(data.level) == "number" and data.level > 0 then
                    local isLocal = (data.source == "FriendsList" or data.source == "Manual" or data.source == "Sighting")
                    if isLocal then
                        if Whorkaround.DebugMode or (Whorkaround_Settings and Whorkaround_Settings.debug) then
                            Whorkaround:Log("Broadcasting cached data for " .. name .. " (Timeout phase)", "NETWORK")
                        end
                        Whorkaround:Broadcast(name, data.level, data.class, data.zone, data.faction, data.lastSeen, false, "BULK")
                    end
                end
                table.insert(expiredResponses, name)
            end
        end
        for _, name in ipairs(expiredResponses) do scheduledResponses[name] = nil end
    end

    -- Process scheduled proxy lookups
    if next(scheduledProxy) then
        wipe(expiredProxy)
        for name, sendTime in pairs(scheduledProxy) do
            if now >= sendTime then table.insert(expiredProxy, name) end
        end
        for _, name in ipairs(expiredProxy) do
            if Whorkaround.ProxyQuery then Whorkaround:ProxyQuery(name) end
            scheduledProxy[name] = nil
        end
    end
end)

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        joinTimer = 10
        hasAnnounced = false -- Reset so we re-announce after disconnect/reload
    elseif event == "CHANNEL_UI_UPDATE" then
        CH_ID = GetChannelName(CH_NAME)
    elseif event == "CHAT_MSG_CHANNEL" then
        local msg, sender, lang, chNameWithID, sender2, flags, zoneID, chID, chName = ...
        local myName = UnitName("player")
        if chName == CH_NAME and sender and myName and sender:lower() ~= myName:lower() then
            -- Passively track all WhorkComm users
            Whorkaround.networkPeers[sender:lower()] = GetTime()
            -- Handle Network Requests (WKR:F:Name)
            if msg:find("^" .. REQ_PREFIX) then
                local targetFaction, targetName
                -- Check if the 6th character is a colon, meaning it uses the new WKR:F:Name format
                if msg:sub(#REQ_PREFIX + 2, #REQ_PREFIX + 2) == ":" then
                    targetFaction = msg:sub(#REQ_PREFIX + 1, #REQ_PREFIX + 1)
                    targetName = msg:sub(#REQ_PREFIX + 3)
                else
                    -- Older clients that just send WKR:Name
                    targetFaction = "U"
                    targetName = msg:sub(#REQ_PREFIX + 1)
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
                local hasFreshCache = data and type(data.level) == "number" and data.level > 0 and (time() - (data.lastSeen or 0) < 60)
                
                local now = GetTime()
                local proxyCooldown = Whorkaround_Settings.proxyCooldown or 5
                local canProxy = not (Whorkaround_Settings.proxyOutCombat and InCombatLockdown())
                local cooldownReady = not Whorkaround.lastProxyTime or (now - Whorkaround.lastProxyTime >= proxyCooldown)

                if Whorkaround_Settings.allowProxy and canProxy and cooldownReady and isCorrectFaction and not scheduledProxy[cleanName] and not hasFreshCache then
                    Whorkaround:Log("Scheduling proxy lookup for: " .. targetName, "PROXY")
                    Whorkaround.lastProxyTime = now
                    local proxyDelay = 0.1 + (math.random() * 0.7) -- Restored stable proxy timing
                    scheduledProxy[cleanName] = GetTime() + proxyDelay
                    
                    -- If we had a cached response scheduled, cancel it if we are doing a proxy
                    scheduledResponses[cleanName] = nil
                end

                if data and type(data.level) == "number" and data.level > 0 then
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

            -- Handle Version / Presence Announcements (WKV:)
            elseif msg:sub(1, #VERSION_PREFIX) == VERSION_PREFIX then
                local rawVer = msg:sub(#VERSION_PREFIX + 1)
                local verFields = {}
                for part in rawVer:gmatch("([^:]+)") do table.insert(verFields, part) end
                local remoteVer = verFields[1]
                local proxyFlag = verFields[2] -- "P", "N", or nil (old client)

                -- Version update notification
                if remoteVer and not notifiedUpdate and IsNewerVersion(remoteVer, currentVersion) then
                    local pfx = "|cff1abc9cWhorkaround Update:|r "
                    DEFAULT_CHAT_FRAME:AddMessage(pfx .. "A newer version (|cffffd100v" .. remoteVer .. "|r) is available!")
                    notifiedUpdate = true
                end

                -- Peer tracking (new clients send P/N, old clients send nothing = treat as non-proxy)
                local senderLower = sender:lower()
                Whorkaround.networkPeers[senderLower] = GetTime()
                if proxyFlag == "P" then
                    Whorkaround.proxyPeers[senderLower] = GetTime()
                    Whorkaround:Log("Peer announced: " .. sender .. " v" .. (remoteVer or "?") .. " (Proxy)", "NETWORK")
                else
                    Whorkaround.proxyPeers[senderLower] = nil
                    Whorkaround:Log("Peer announced: " .. sender .. " v" .. (remoteVer or "?") .. " (No Proxy)", "NETWORK")
                end

            -- Handle Data Broadcasts (WK:Ver:Name:...)
            elseif msg:find("^" .. MSG_PREFIX) then
                local rawData = msg:sub(#MSG_PREFIX + 1)
                
                -- RECYCLED PARSING: Avoid creating a new table for every network message
                wipe(tempFields)
                for part in rawData:gmatch("([^:]+)") do
                    if not part:find("^%a+=") then
                        table.insert(tempFields, part)
                    end
                end

                -- Mapping based on core field indices
                local remoteVer = tempFields[1]
                local name = tempFields[2]
                local level = tonumber(tempFields[3])
                local class = tempFields[4]
                local zone = tempFields[5]
                local f = tempFields[6]
                local timestamp = tonumber(tempFields[7])
                local isProxy = tempFields[8]

                -- DATA QUALITY: Ignore responses with placeholder/unknown data
                if not name or not class or class:upper() == "UNKNOWN" or not zone or zone:upper() == "UNKNOWN" or (level or 0) == 0 or (f ~= "A" and f ~= "H") then
                    return
                end

                -- PROXY TRACKING: If they send a proxy response, they are a proxy peer
                if isProxy == "P" then
                    local senderLower = sender:lower()
                    if not Whorkaround.proxyPeers[senderLower] then
                        Whorkaround:Log("Peer " .. sender .. " identified as Proxy via network activity.", "NETWORK")
                    end
                    Whorkaround.proxyPeers[senderLower] = GetTime()
                end

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
                    if level and level > 0 and level <= 60 and Whorkaround.validClasses[class] and (faction == "Alliance" or faction == "Horde") and zone and zone:len() < 50 then
                        if Whorkaround_DB then
                            local hasWaiter = Whorkaround.networkWaiters and Whorkaround.networkWaiters[cleanName]
                            if not Whorkaround_DB[cleanName] or timestamp > (Whorkaround_DB[cleanName].lastSeen or 0) then
                                Whorkaround:Log("Incoming network data for " .. name .. " (" .. (isProxy == "P" and "Live" or "Cache") .. ")", "NETWORK")
                                local existing = Whorkaround_DB[cleanName] or {}
                                existing.class = class
                                existing.level = level
                                existing.zone = zone
                                existing.faction = faction
                                existing.lastSeen = timestamp
                                existing.source = "WhorkComm"
                                -- Preserve race/guild gathered by the local scanner; network peers don't transmit them
                                Whorkaround_DB[cleanName] = existing
                            end
                            -- Always resolve the waiter even if our DB entry is newer —
                            -- otherwise the timestamp suppression silently eats the response.
                            if hasWaiter and Whorkaround.ResolveNetworkWait then
                                Whorkaround:ResolveNetworkWait(cleanName, level, class, zone, faction, timestamp, isProxy)
                            end
                        end
                    end
                end
            end
        end
    elseif event == "CHAT_MSG_CHANNEL_LEAVE" then
        local _, sender, _, _, _, _, _, _, chName = ...
        if chName == CH_NAME and sender then
            local senderLower = sender:lower()
            Whorkaround.proxyPeers[senderLower] = nil
            Whorkaround.networkPeers[senderLower] = nil
            Whorkaround:Log("Peer left: " .. sender, "NETWORK")
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
        if Whorkaround.broadcastThrottle[cleanName] and (GetTime() - Whorkaround.broadcastThrottle[cleanName] < 2) then 
            return 
        end
        Whorkaround.broadcastThrottle[cleanName] = GetTime()

        name = name:gsub("^%l", string.upper)
        
        -- TitleCase class and validate before broadcasting
        local dClass = (class or "Unknown")
        if dClass:lower() ~= "unknown" then
            dClass = dClass:lower():gsub("(%a)([%w_']*)", function(first, rest) return first:upper() .. rest end)
        end
        
        -- DATA QUALITY: Abort broadcast if we don't have full info
        if not zone or zone:lower() == "unknown" or dClass == "Unknown" or (tonumber(level) or 0) == 0 then
            return
        end

        timestamp = timestamp or time()
        local f = (faction == "Alliance") and "A" or (faction == "Horde" and "H" or "U")
        if f == "U" then return end -- DATA QUALITY: Never broadcast unknown faction
        local p = isProxy and "P" or "C"
        -- Include version, timestamp, and proxy flag in the broadcast
        local msg = string.format("%s%s:%s:%d:%s:%s:%s:%d:%s", MSG_PREFIX, currentVersion, name, level, dClass:upper(), zone, f, timestamp, p)
        
        Whorkaround:Log("Broadcasting: " .. msg, "NETWORK")
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
        if Whorkaround.recentRequests[cleanName] and (GetTime() - Whorkaround.recentRequests[cleanName] < 10) then 
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
        local peerCount, proxyCount = 0, 0
        for _ in pairs(Whorkaround.networkPeers or {}) do peerCount = peerCount + 1 end
        for _ in pairs(Whorkaround.proxyPeers or {}) do proxyCount = proxyCount + 1 end
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. "Network Peers: |cffffd100" .. peerCount .. "|r (|cff9b59b6" .. proxyCount .. " proxies|r)")
    else
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. "Comm channel NOT active. Attempting rejoin...")
        JoinCommChannel()
    end
end
