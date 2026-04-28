local addonName, Whorkaround = ...

Whorkaround.pendingQueries = Whorkaround.pendingQueries or {}
Whorkaround.removingFriends = Whorkaround.removingFriends or {}
Whorkaround.addedSuppression = Whorkaround.addedSuppression or {}
Whorkaround.networkWaiters = Whorkaround.networkWaiters or {}
Whorkaround.bestNetworkHits = Whorkaround.bestNetworkHits or {}
Whorkaround.queryThrottle = Whorkaround.queryThrottle or {}
Whorkaround.broadcastThrottle = Whorkaround.broadcastThrottle or {}
Whorkaround.sightingThrottle = Whorkaround.sightingThrottle or {}
Whorkaround.printThrottle = Whorkaround.printThrottle or {}

-- Class lookup table for 3.3.5 (Project Epoch: No Death Knights)
local localizedClassMap = {
    ["Warrior"] = "WARRIOR", ["Paladin"] = "PALADIN", ["Hunter"] = "HUNTER",
    ["Rogue"] = "ROGUE", ["Priest"] = "PRIEST", ["Shaman"] = "SHAMAN",
    ["Mage"] = "MAGE", ["Warlock"] = "WARLOCK", ["Druid"] = "DRUID",
}
local validClasses = {
    ["WARRIOR"] = true, ["PALADIN"] = true, ["HUNTER"] = true, ["ROGUE"] = true,
    ["PRIEST"] = true, ["SHAMAN"] = true, ["MAGE"] = true, ["WARLOCK"] = true,
    ["DRUID"] = true,
}

-- Race Token to Faction mapping for 3.3.5
local raceFactionMap = {
    ["Human"] = "Alliance",
    ["Dwarf"] = "Alliance",
    ["NightElf"] = "Alliance",
    ["Gnome"] = "Alliance",
    ["Draenei"] = "Alliance",
    ["Orc"] = "Horde",
    ["Undead"] = "Horde",
    ["Scourge"] = "Horde",
    ["Tauren"] = "Horde",
    ["Troll"] = "Horde",
    ["BloodElf"] = "Horde",
}

-- Helper to escape pattern characters
local function EscapePattern(text)
    if not text then return "" end
    return text:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

-- Patterns for system message suppression (with fallbacks)
local addedPattern = EscapePattern(ERR_FRIEND_ADDED_S or "%s added to friends."):gsub("%%%%s", "(.+)")
local removedPattern = EscapePattern(ERR_FRIEND_REMOVED_S or "%s removed from friends list."):gsub("%%%%s", "(.+)")
local joinPattern = EscapePattern(ERR_CHANNEL_JOIN_S or "You have joined the channel: %s"):gsub("%%%%s", "(.+)")
local leavePattern = EscapePattern(ERR_CHANNEL_LEAVE_S or "You have left the channel: %s"):gsub("%%%%s", "(.+)")

-- Helper to get player info from guild roster
local function GetPlayerInfoFromGuild(targetName)
    if not IsInGuild() then return end
    for i = 1, GetNumGuildMembers() do
        local name, rank, rankIndex, level, class, zone, note, officernote, online, status, classFileName =
        GetGuildRosterInfo(i)
        if name and name:match("^([^%-]+)") == targetName then
            if level and level > 0 and class then return level, class, (online and zone or "Offline") end
        end
    end
end

-- Improved Class Color Detector (fast-path + cache + faction detection)
local function GetClassColorCode(className, name)
    if name then
        local units = { "player", "target", "focus", "mouseover", "party1", "party2", "party3", "party4", "raid1",
            "raid2" }
        for _, unit in ipairs(units) do
            local uName = UnitName(unit)
            if uName and uName:lower() == name:lower() then
                local _, classTag = UnitClass(unit)
                local race = UnitRace(unit)
                if classTag then
                    local color = RAID_CLASS_COLORS[classTag]
                    if Whorkaround_DB then
                        local cleanName = name:lower()
                        Whorkaround_DB[cleanName] = Whorkaround_DB[cleanName] or {}
                        Whorkaround_DB[cleanName].class = classTag
                        Whorkaround_DB[cleanName].level = UnitLevel(unit)
                        Whorkaround_DB[cleanName].faction = raceFactionMap[race] or UnitFactionGroup(unit)
                        Whorkaround_DB[cleanName].lastSeen = time()
                    end
                    if color then return string.format("|cff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255) end
                end
            end
        end
        if not className and Whorkaround.GetElvUIClass then className = Whorkaround:GetElvUIClass(name) end
        if not className and Whorkaround_DB then
            local dbKey = name:lower()
            if Whorkaround_DB[dbKey] and Whorkaround_DB[dbKey].class then
                className = Whorkaround_DB[dbKey].class
            end
        end
    end
    local tag = localizedClassMap[className] or (className and className:upper())
    local color = RAID_CLASS_COLORS[tag]
    if color then return string.format("|cff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255) end
    return "|cffffffff"
end

-- Helper to get the correct output chat frames (Supports comma-separated list)
local function GetOutputFrames()
    local frames = {}
    if Whorkaround_Settings and Whorkaround_Settings.outputTab and Whorkaround_Settings.outputTab ~= "" then
        for tabName in Whorkaround_Settings.outputTab:gmatch("([^,]+)") do
            tabName = tabName:gsub("^%s*(.-)%s*$", "%1") -- trim whitespace
            for i = 1, NUM_CHAT_WINDOWS do
                local name = GetChatWindowInfo(i)
                if name and name:lower() == tabName:lower() then
                    table.insert(frames, _G["ChatFrame" .. i])
                end
            end
        end
    end
    
    -- Fallback to default if no valid tabs found
    if #frames == 0 then table.insert(frames, DEFAULT_CHAT_FRAME) end
    return frames
end

-- Helper for relative time strings
local function GetRelativeTime(timestamp)
    if not timestamp or timestamp == 0 then return "Unknown" end
    local diff = time() - timestamp
    if diff < 60 then
        return "1 min ago"
    elseif diff < 3600 then
        return string.format("%d min ago", diff / 60)
    elseif diff < 86400 then
        return string.format("%d hours ago", diff / 3600)
    else
        return string.format("%d days ago", diff / 86400)
    end
end

-- Function to print the "Who" result
function Whorkaround:PrintWhoResult(name, level, class, area, cached, source, faction, timestamp, isProxy)
    local cleanName = name:lower():gsub("^%s*(.-)%s*$", "%1")
    
    -- DEDUPLICATION: Prevent double-prints within 100ms
    Whorkaround.lastPrint = Whorkaround.lastPrint or {}
    local now = GetTime()
    if Whorkaround.lastPrint[cleanName] and (now - Whorkaround.lastPrint[cleanName] < 0.1) then return end
    Whorkaround.lastPrint[cleanName] = now

    local prefix = "|cff1abc9cWhorkaround:|r "
    local playerFaction = UnitFactionGroup("player")
    local enemyFaction = (playerFaction == "Horde") and "Alliance" or "Horde"
    local cachedData = Whorkaround_DB and Whorkaround_DB[cleanName]
    timestamp = timestamp or time()

    if not faction then
        if level == 0 then faction = enemyFaction else faction = playerFaction end
    end

    local classColor = GetClassColorCode(class, name)
    local isLive = (time() - timestamp < 10)
    local timeText = isLive and "" or string.format(" |cff888888(%s)|r", GetRelativeTime(timestamp))

    -- OFFLINE OR ENEMY DETECTION (Trigger network search)
    if (not level or level == 0) and source ~= "WhorkComm" and source ~= "SILENT" and source ~= "TIMEOUT" then
        if Whorkaround.Request and not Whorkaround.networkWaiters[cleanName] then
            local isFresh = cachedData and cachedData.level and cachedData.level > 0 and (time() - timestamp < 10)
            if not isFresh then
                local statusMsg = (level == 0) and "identified as " .. faction or "appears to be offline"
                for _, frame in ipairs(GetOutputFrames()) do
                    frame:AddMessage(string.format("%s|Hplayer:%s|h[|r%s%s|r]|h %s. Scanning network...", prefix, name, classColor, name, statusMsg), 1, 1, 0)
                end
                Whorkaround.networkWaiters[cleanName] = GetTime()
                local targetFactionTag = (faction == "Horde") and "H" or (faction == "Alliance" and "A" or "U")
                Whorkaround:Request(name, targetFactionTag)
                return
            end
        end
    end

    Whorkaround.networkWaiters[cleanName] = nil

    -- Format the message
    if (level and level > 0) or (cachedData and cachedData.level and cachedData.level > 0) then
        local displayLevel = (level and level > 0 and level <= 60) and level or (cachedData and cachedData.level)
        local displayArea = (area and area ~= "Unknown") and area or (cachedData and cachedData.zone) or "Unknown"
        local displayFaction = faction or cachedData.faction or "Unknown"
        local line1 = string.format("%s|Hplayer:%s|h[|r%s%s|r]|h: Level %d %s %s - %s%s", prefix, name, classColor, name, displayLevel, displayFaction, class or "Unknown", displayArea, timeText)

        if source == "Whorkaround" or source == "TIMEOUT" then
            local statusLabel = isLive and "|cff00ff00(Live)|r" or "|cffffd100(Cached)|r"
            local line2 = string.format("%sData %s was successfully fetched from network.", prefix, statusLabel)
            for _, frame in ipairs(GetOutputFrames()) do
                frame:AddMessage(line1, 1, 1, 0)
                frame:AddMessage(line2, 1, 1, 0)
            end
        else
            for _, frame in ipairs(GetOutputFrames()) do
                frame:AddMessage(line1, 1, 1, 0)
            end
        end
    else
        if source == "TIMEOUT" then
            local factionColor = (faction == "Horde") and "|cffff2020" or "|cff0070dd"
            local failMsg = "No community data was found."
            if faction == playerFaction then failMsg = "User is offline and no community data was found." end

            for _, frame in ipairs(GetOutputFrames()) do
                frame:AddMessage(string.format("%s|Hplayer:%s|h[|r%s%s|r]|h: %s%s|r", prefix, name, classColor, name, factionColor, faction), 1, 1, 0)
                frame:AddMessage(prefix .. failMsg, 1, 1, 0)
            end
        end
    end

    -- Update Database (Enforce Level > 0)
    if Whorkaround_DB and level and level > 0 then
        local isNew = not Whorkaround_DB[cleanName]
        Whorkaround_DB[cleanName] = {
            class = class,
            level = level,
            zone = (area ~= "Unknown") and area or (cachedData and cachedData.zone),
            faction = faction,
            lastSeen = timestamp,
            source = source or (cached and "Cache" or "FriendsList")
        }
        if Whorkaround.SyncBrowser then Whorkaround:SyncBrowser(isNew) end
    end

    local now = GetTime()
    local canBroadcast = not Whorkaround.broadcastThrottle[cleanName] or (now - Whorkaround.broadcastThrottle[cleanName] > 60)
    if canBroadcast and (not cached or source == "FriendsList" or source == "Manual") and level and level > 0 and level <= 60 and Whorkaround.Broadcast then
        Whorkaround.broadcastThrottle[cleanName] = now
        Whorkaround:Log("Broadcasting live data for " .. name, "NETWORK")
        Whorkaround:Broadcast(name, level, class, area, faction, timestamp)
    end

    -- Compatibility: Set flag to fire a fake Who event to stop other addons (like ElvUI) from retrying
    if source ~= "WhorkComm" and source ~= "SILENT" then
        Whorkaround.fakeWhoTriggered = true
    end
end

-- Resolves a network wait by collecting hits over a 5s window
function Whorkaround:ResolveNetworkWait(name, level, class, zone, faction, timestamp, isProxy)
    local cleanName = name:lower():gsub("^%s*(.-)%s*$", "%1")
    if Whorkaround.networkWaiters[cleanName] then
        local currentBest = Whorkaround.bestNetworkHits[cleanName]
        local newIsLive = (isProxy == "P" or isProxy == true)
        
        -- Priority: Live results > Cached results, then Newest > Oldest
        local isBetter = false
        if not currentBest then
            isBetter = true
        elseif newIsLive and not currentBest.isLive then
            isBetter = true
        elseif (newIsLive == currentBest.isLive) and (timestamp > currentBest.timestamp) then
            isBetter = true
        end

        if isBetter then
            Whorkaround.bestNetworkHits[cleanName] = {
                level = level, class = class, zone = zone,
                faction = faction, timestamp = timestamp, isLive = newIsLive
            }
        end
    end
end

-- Fallback check for all secondary sources
function Whorkaround:TryAllOtherSources(name, silent)
    local cleanName = name:lower():gsub("^%s*(.-)%s*$", "%1")
    local gLevel, gClass, gZone = GetPlayerInfoFromGuild(name)
    if gLevel and gLevel > 0 then
        if not silent then
            local isOffline = (gZone == "Offline")
            Whorkaround:PrintWhoResult(name, isOffline and 0 or gLevel, gClass, gZone, false, "GuildRoster",
                UnitFactionGroup("player"))
        end
        return true
    end
    local data = Whorkaround_DB and Whorkaround_DB[cleanName]
    if data and data.class then
        if not silent then Whorkaround:PrintWhoResult(name, 0, data.class, data.zone or "Unknown", true, "Cache",
                data.faction) end
        return true
    end
    return false
end

-- Statistics Command
function Whorkaround:ShowStats()
    if not Whorkaround_DB then return end
    local total, sources, factions = 0,
        { FriendsList = 0, GuildRoster = 0, ElvUI = 0, ElvUI_Enhanced = 0, WhorkComm = 0, Cache = 0, Sighting = 0 },
        { Alliance = 0, Horde = 0, Unknown = 0 }
    for name, data in pairs(Whorkaround_DB) do
        if type(data) == "table" then
            total = total + 1
            if data.source and sources[data.source] ~= nil then sources[data.source] = sources[data.source] + 1 end
            if data.faction then factions[data.faction] = (factions[data.faction] or 0) + 1 else factions.Unknown =
                factions.Unknown + 1 end
        end
    end
    local output = GetOutputFrames()
    for _, frame in ipairs(output) do
        frame:AddMessage("|cff1abc9cWhorkaround Stats:|r")
        frame:AddMessage(string.format("- Total Cached Players: |cffffd100%d|r", total))
        frame:AddMessage(string.format("- Factions: Alliance (|cff0070dd%d|r), Horde (|cffff2020%d|r)",
            factions.Alliance or 0, factions.Horde or 0))
        frame:AddMessage("- Sources: Manual: " ..
        sources.FriendsList ..
        ", Guild: " .. sources.GuildRoster .. ", Sightings: " .. sources.Sighting .. ", Comm: " .. sources.WhorkComm)
    end
end

-- Database Maintenance & Ghost Cleanup
local NOTE_ID = "Whorkaround:Tag"
function Whorkaround:CleanGhostFriends()
    local num = GetNumFriends()
    local cleaned = 0
    for i = num, 1, -1 do
        local name, _, _, _, _, _, note = GetFriendInfo(i)
        if note and note:find("^Whorkaround:") then
            Whorkaround:Log("Cleaning ghost friend: " .. name, "CLEANUP")
            RemoveFriend(name)
            cleaned = cleaned + 1
        end
    end
    if cleaned > 0 then Whorkaround:Log("Cleanup complete. Removed " .. cleaned .. " temporary friends.", "CLEANUP") end
end

-- Automatic Database Pruning
function Whorkaround:PurgeOldData()
    if not Whorkaround_DB or not Whorkaround_Settings then return end
    local weeks = Whorkaround_Settings.retentionWeeks or 4
    local cutoff = time() - (weeks * 7 * 24 * 3600)
    local count = 0
    for name, data in pairs(Whorkaround_DB) do
        if type(data) == "table" and data.lastSeen and data.lastSeen < cutoff then
            Whorkaround_DB[name] = nil
            count = count + 1
        end
    end
    if count > 0 then
        print(string.format("|cff1abc9cWhorkaround:|r Cleaned up |cffffd100%d|r expired records (older than %d weeks).", count, weeks))
    end
end

-- Passive Data Collection (Sightings)
function Whorkaround:Sighting(unit)
    if not unit or not UnitIsPlayer(unit) then return end
    local name = UnitName(unit)
    if not name or name == "Unknown" or name == UnitName("player") then return end
    local cleanName = name:lower():gsub("^%s*(.-)%s*$", "%1")

    local now = GetTime()
    if Whorkaround.sightingThrottle[cleanName] and now - Whorkaround.sightingThrottle[cleanName] < 10 then return end
    Whorkaround.sightingThrottle[cleanName] = now

    local level = UnitLevel(unit)
    local _, class = UnitClass(unit)
    local _, raceToken = UnitRace(unit)
    local faction = raceFactionMap[raceToken] or UnitFactionGroup(unit)
    local zone = GetRealZoneText()
    if Whorkaround_DB and level and level > 0 then
        Whorkaround_DB[cleanName] = {
            class = class,
            level = level,
            zone = zone,
            faction = faction,
            lastSeen = time(),
            source = "Sighting"
        }
        if Whorkaround.SyncBrowser then Whorkaround:SyncBrowser(false) end
    end
end

-- System Message Filter
local function SystemMessageFilter(self, event, msg)
    if not msg then return end
    local nameAdded = msg:match(addedPattern)
    if nameAdded then
        local cleanName = nameAdded:lower():gsub("^%s*(.-)%s*$", "%1")
        if (Whorkaround.pendingQueries[cleanName] or Whorkaround.addedSuppression[cleanName]) then return true end
    end
    local nameRemoved = msg:match(removedPattern)
    if nameRemoved then
        local cleanName = nameRemoved:lower():gsub("^%s*(.-)%s*$", "%1")
        if Whorkaround.removingFriends[cleanName] then return true end
    end
    local chJoined = msg:match(joinPattern)
    if chJoined and (chJoined:find("WhorkComm") or chJoined:find("1. WhorkComm")) then return true end
    local chLeft = msg:match(leavePattern)
    if chLeft and (chLeft:find("WhorkComm") or chLeft:find("1. WhorkComm")) then return true end
    if msg == ERR_FRIEND_NOT_FOUND then
        for name, startTime in pairs(Whorkaround.pendingQueries) do
            if type(startTime) == "number" and GetTime() - startTime < 2 then
                Whorkaround:PrintWhoResult(name, nil, nil, nil, false, "Manual")
                Whorkaround.pendingQueries[name] = nil
                return true
            end
        end
    end
end
ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", SystemMessageFilter)

-- Event handling
local frame = CreateFrame("Frame")
frame:RegisterEvent("FRIENDLIST_UPDATE"); frame:RegisterEvent("CHAT_MSG_SYSTEM"); frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT"); frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:SetScript("OnUpdate", function(self, elapsed)
    self.timer = (self.timer or 0) + elapsed
    if self.timer > 0.1 then
        self.timer = 0; local now = GetTime()
        for name, startTime in pairs(Whorkaround.pendingQueries) do
            if type(startTime) == "number" then
                local diff = now - startTime
                if diff > 1.5 and Whorkaround.pendingQueries[name] ~= "TIMEOUT" and Whorkaround.pendingQueries[name] ~= "PROXY" then
                    Whorkaround:PrintWhoResult(name, nil, nil, nil, false, "Manual")
                    Whorkaround.pendingQueries[name] = "TIMEOUT"; Whorkaround.removingFriends[name] = GetTime(); RemoveFriend(name)
                end
                if diff > 5 then
                    Whorkaround.pendingQueries[name] = nil; Whorkaround.addedSuppression[name] = nil; Whorkaround.removingFriends[name] = nil
                end
            end
        end
        for name, waitTime in pairs(Whorkaround.networkWaiters) do
            if now - waitTime > 5.0 then
                Whorkaround.networkWaiters[name] = nil
                local best = Whorkaround.bestNetworkHits[name]
                if best then
                    Whorkaround:PrintWhoResult(name, best.level, best.class, best.zone, not best.isLive, "WhorkComm", best.faction, best.timestamp)
                else
                    local data = Whorkaround_DB and Whorkaround_DB[name]
                    Whorkaround:PrintWhoResult(name, 0, data and data.class, "Unknown", true, "TIMEOUT", data and data.faction)
                end
                -- Final Cleanup
                Whorkaround.bestNetworkHits[name] = nil
                Whorkaround.networkWaiters[name] = nil
            end
        end
    end
end)

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "UPDATE_MOUSEOVER_UNIT" then
        Whorkaround:Sighting("mouseover")
    elseif event == "PLAYER_TARGET_CHANGED" then
        Whorkaround:Sighting("target")
    elseif event == "ADDON_LOADED" then
        local name = ...; if name == "Whorkaround" then
            Whorkaround_DB = Whorkaround_DB or {}
            
            -- DB MIGRATION: Convert all keys to lowercase and PURGE invalid classes
            local migratedDB = {}
            for k, v in pairs(Whorkaround_DB) do
                local class = v.class and v.class:upper()
                if validClasses[class] then
                    migratedDB[k:lower()] = v
                end
            end
            Whorkaround_DB = migratedDB
            
            Whorkaround_Settings = Whorkaround_Settings or {}
            if Whorkaround_Settings.overrideWho == nil then Whorkaround_Settings.overrideWho = true end
            if Whorkaround_Settings.allowProxy == nil then Whorkaround_Settings.allowProxy = false end
            if Whorkaround_Settings.outputTab == nil then Whorkaround_Settings.outputTab = "" end
            if Whorkaround_Settings.retentionWeeks == nil then Whorkaround_Settings.retentionWeeks = 4 end
            Whorkaround:CleanGhostFriends()
            Whorkaround:PurgeOldData()
            if Whorkaround_DB then
                local cleaned = 0
                for name, data in pairs(Whorkaround_DB) do
                    if type(data) == "table" and (not data.level or data.level == 0) then
                        Whorkaround_DB[name] = nil
                        cleaned = cleaned + 1
                    end
                end
                if cleaned > 0 then Whorkaround:Log("Pruned " .. cleaned .. " invalid level-0 records.", "INIT") end
            end
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "FRIENDLIST_UPDATE" then
        local processed = {}
        for i = 1, GetNumFriends() do
            local name, level, class, area, connected, _, note = GetFriendInfo(i)
            if name then
                local cleanName = name:lower():gsub("^%s*(.-)%s*$", "%1")
                if Whorkaround.pendingQueries[cleanName] and not processed[cleanName] then
                    processed[cleanName] = true
                    if not note or note == "" then 
                        Whorkaround:Log("Tagging friend: " .. name, "LOCAL")
                        SetFriendNotes(name, NOTE_ID) 
                    end
                    if Whorkaround.pendingQueries[cleanName] == "PROXY" then
                        if connected then
                            local faction = UnitFactionGroup("player")
                            Whorkaround.pendingQueries[cleanName] = nil -- Clear FIRST to prevent double-trigger
                            Whorkaround:Log("Proxy hit! Sending broadcast for " .. name, "PROXY")
                            
                            -- DE-DUPLICATION: Cancel any pending cached response schedule
                            if Whorkaround.CancelScheduledResponse then Whorkaround:CancelScheduledResponse(name) end
                            
                            Whorkaround:Broadcast(name, level, class, area, faction, time(), true)
                            Whorkaround.removingFriends[cleanName] = GetTime(); RemoveFriend(name)
                        else
                            Whorkaround:Log("Proxy check: " .. name .. " is offline/enemy.", "PROXY")
                            Whorkaround.removingFriends[cleanName] = GetTime(); RemoveFriend(name); Whorkaround.pendingQueries[cleanName] = nil
                        end
                    elseif Whorkaround.pendingQueries[cleanName] ~= "TIMEOUT" then
                        if connected then
                            Whorkaround.pendingQueries[cleanName] = nil -- Clear FIRST to prevent double-trigger
                            Whorkaround:Log("Manual query success: " .. name, "LOCAL")
                            Whorkaround:PrintWhoResult(name, level, class, area, false, "FriendsList")
                            Whorkaround.removingFriends[cleanName] = GetTime(); RemoveFriend(name)
                        else
                            Whorkaround.pendingQueries[cleanName] = nil -- Clear FIRST to prevent double-trigger
                            Whorkaround:Log("Manual query failed (offline): " .. name, "LOCAL")
                            Whorkaround:PrintWhoResult(name, nil, nil, nil, false, "Manual")
                            Whorkaround.removingFriends[cleanName] = GetTime(); RemoveFriend(name)
                        end
                    end
                end
            end
        end
    end
end)

C_Timer.NewTicker(60, function() Whorkaround:CleanGhostFriends() end)

function Whorkaround:ProxyQuery(name)
    if not name or name == "" or GetNumFriends() >= 100 then return end
    name = name:lower():gsub("^%s*(.-)%s*$", "%1") -- Clean key
    if Whorkaround.pendingQueries[name] or Whorkaround.networkWaiters[name] then return end
    
    local displayName = name:gsub("^%l", string.upper)

    -- OPTIMIZATION: Check Target/Mouseover for INSTANT unit data
    local units = {"target", "mouseover"}
    for _, unit in ipairs(units) do
        if UnitIsPlayer(unit) and UnitName(unit):lower() == name then
            Whorkaround:Log("Unit match (" .. unit .. ") for " .. displayName .. "! Broadcasting immediately.", "PROXY")
            local level = UnitLevel(unit)
            local _, class = UnitClass(unit)
            local zone = GetRealZoneText() -- Same-zone assumption for units
            local faction = UnitFactionGroup(unit)
            
            if Whorkaround.CancelScheduledResponse then Whorkaround:CancelScheduledResponse(name) end
            Whorkaround:Broadcast(displayName, level, class, zone, faction, time(), true)
            return
        end
    end

    -- NEW: Check Guild/Cache for INSTANT proxy response
    local gLevel, gClass, gZone = GetPlayerInfoFromGuild(displayName)
    local cached = Whorkaround_DB and Whorkaround_DB[name]
    
    if (gLevel and gLevel > 0) or (cached and cached.level and cached.level > 0 and (time() - (cached.lastSeen or 0) < 60)) then
        Whorkaround:Log("Instant Proxy match for " .. displayName .. "! Broadcasting immediately.", "PROXY")
        local level = gLevel or cached.level
        local class = gClass or cached.class
        local zone = gZone or cached.zone
        local faction = (cached and cached.faction) or UnitFactionGroup("player")
        local timestamp = (gLevel and gLevel > 0) and time() or cached.lastSeen
        
        -- DE-DUPLICATION: Cancel any pending cached response schedule
        if Whorkaround.CancelScheduledResponse then Whorkaround:CancelScheduledResponse(name) end
        
        Whorkaround:Broadcast(displayName, level, class, zone, faction, timestamp, true)
        return
    end

    Whorkaround:Log("Starting Friends-List Proxy lookup for " .. displayName, "PROXY")
    Whorkaround.pendingQueries[name] = "PROXY"; Whorkaround.addedSuppression[name] = GetTime()
    AddFriend(displayName)
    SetFriendNotes(displayName, "Whorkaround:Tag")
end

function Whorkaround:Query(name, silent)
    if not name or name == "" then return end
    name = name:lower():gsub("^%s*(.-)%s*$", "%1") -- Clean key
    if Whorkaround.pendingQueries[name] or Whorkaround.networkWaiters[name] then return end 
    
    local displayName = name:gsub("^%l", string.upper)
    Whorkaround:Log("Query triggered for: " .. displayName .. (silent and " (Silent)" or ""), "LOCAL")

    -- SPECIAL: Self-Lookup
    if name == UnitName("player"):lower() then
        local level = UnitLevel("player")
        local _, class = UnitClass("player")
        local faction = UnitFactionGroup("player")
        Whorkaround:Log("Self-lookup hit for " .. displayName .. "!", "LOCAL")
        if not silent then Whorkaround:PrintWhoResult(displayName, level, class, GetRealZoneText(), false, "Manual", faction) end
        return
    end

    -- OPTIMIZATION: Check Target/Mouseover for INSTANT unit data
    local units = {"target", "mouseover"}
    for _, unit in ipairs(units) do
        if UnitIsPlayer(unit) and UnitName(unit):lower() == name then
            Whorkaround:Log("Unit match (" .. unit .. ") hit for " .. displayName .. "!", "LOCAL")
            local level = UnitLevel(unit)
            local _, class = UnitClass(unit)
            local faction = UnitFactionGroup(unit)
            if not silent then Whorkaround:PrintWhoResult(displayName, level, class, GetRealZoneText(), false, "Manual", faction) end
            return
        end
    end

    -- STABILITY: 30s Query Throttle
    local now = GetTime()
    if Whorkaround.queryThrottle[name] and (now - Whorkaround.queryThrottle[name] < 30) then 
        Whorkaround:Log("Query throttled for " .. displayName, "LOCAL")
        return 
    end
    Whorkaround.queryThrottle[name] = now

    -- NEW: Check Guild Roster FIRST (Live info)
    local gLevel, gClass, gZone = GetPlayerInfoFromGuild(displayName)
    if gLevel and gLevel > 0 then
        Whorkaround:Log("Guild hit for " .. displayName .. "! Skipping Friends List.", "LOCAL")
        if not silent then 
            local isOffline = (gZone == "Offline")
            Whorkaround:PrintWhoResult(displayName, isOffline and 0 or gLevel, gClass, gZone, false, "GuildRoster") 
        end
        return
    end

    -- NEW: Check Cache (If fresh)
    local cached = Whorkaround_DB and Whorkaround_DB[name]
    if cached and cached.level and cached.level > 0 and (time() - (cached.lastSeen or 0) < 30) then
        Whorkaround:Log("Fresh cache hit for " .. displayName .. ". Skipping Friends List.", "LOCAL")
        if not silent then
            Whorkaround:PrintWhoResult(displayName, cached.level, cached.class, cached.zone, true, "Cache", cached.faction, cached.lastSeen)
        end
        return
    end

    for i = 1, GetNumFriends() do
        local fName, level, class, area, connected = GetFriendInfo(i)
        if fName and fName:lower() == name then 
            if not silent then Whorkaround:PrintWhoResult(fName, connected and level or 0, class, area, false, "FriendsList") end
            return 
        end
    end

    if GetNumFriends() >= 100 then print("|cff1abc9cWhorkaround:|r List full!"); return end
    Whorkaround.pendingQueries[name] = silent and "SILENT" or GetTime(); Whorkaround.addedSuppression[name] = GetTime(); AddFriend(displayName)
end

local function OnEditBoxTextChanged(self)
    local text = self:GetText()
    if not text then return end
    local function TriggerQuery(name)
        local dbKey = name:lower()
        local data = Whorkaround_DB and Whorkaround_DB[dbKey]
        if not data or (time() - (data.lastSeen or 0) > 3600) then Whorkaround:Query(dbKey, true) end
    end
    for name in text:gmatch("%[([%a]+)%]") do TriggerQuery(name) end
    for name in text:gmatch("@([%a]+)%s") do TriggerQuery(name) end
end

local function HookChat()
    local orig = ChatFrame_OnHyperlinkShow
    ChatFrame_OnHyperlinkShow = function(...)
        local link, text, button; local arg1 = ...
        if type(arg1) == "table" then _, link, text, button = ... else link, text, button = ... end
        if type(link) == "string" and link:sub(1, 7) == "player:" then
            local name = link:match("player:([^:]+)")
            if name then
                if IsShiftKeyDown() then
                    Whorkaround:Query(name, true)
                    return
                elseif button == "RightButton" then
                    FriendsFrame_ShowDropdown(name, 1); return
                end
            end
        end
        return orig(...)
    end
    for i = 1, 10 do
        local eb = _G["ChatFrame" .. i .. "EditBox"]; if eb then eb:HookScript("OnTextChanged", OnEditBoxTextChanged) end
    end
end
HookChat()

function Whorkaround:Find(query)
    if not query or query == "" then return end
    query = query:lower(); local results = {}; local count = 0
    for name, data in pairs(Whorkaround_DB) do
        if type(data) == "table" then
            if name:lower():find(query) or (data.class and data.class:lower():find(query)) or (data.zone and data.zone:lower():find(query)) then
                table.insert(results, { name = name, data = data }); count = count + 1
            end
        end
    end
    print("|cff1abc9cWhorkaround:|r Found " .. count .. " matching players:")
    table.sort(results, function(a, b) return (a.data.lastSeen or 0) > (b.data.lastSeen or 0) end)
    for i = 1, math.min(15, count) do
        local r = results[i]; local color = GetClassColorCode(r.data.class, r.name)
        print(string.format("- |Hplayer:%s|h%s%s|r|h: Lvl %d %s %s", r.name, color, r.name, r.data.level or 0,
            r.data.faction or "", r.data.zone or "Unknown"))
    end
end

local function ChatLinkFilter(self, event, msg, ...)
    if type(msg) == "string" and (msg:find("%[") or msg:find("@")) then
        msg = msg:gsub("(|H.-|h.-|h)",
            function(link) return link:gsub("%[", "\002"):gsub("%]", "\003"):gsub("@", "\004") end)
        local function ReplacementFunc(name)
            local dbKey = name:lower()
            local data = Whorkaround_DB and Whorkaround_DB[dbKey]
            local color = GetClassColorCode(data and data.class, name)
            local displayName = name:gsub("^%l", string.upper)
            return string.format("|Hplayer:%s|h%s[%s]|r|h", name, color, displayName)
        end
        msg = msg:gsub("%[([%a]+)%]", ReplacementFunc):gsub("@([%a]+)", ReplacementFunc)
        msg = msg:gsub("\002", "["):gsub("\003", "]"):gsub("\004", "@")
        return false, msg, ...
    end
end
local chatEvents = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_CHANNEL", "CHAT_MSG_EMOTE" }
for _, event in ipairs(chatEvents) do ChatFrame_AddMessageEventFilter(event, ChatLinkFilter) end

-- REGISTER SLASH COMMANDS (THE SIMPLE YESTERDAY WAY)
SLASH_WHORK1 = "/whork"
SLASH_WHORK2 = "/whorkaround"
SLASH_WHORK3 = "/whom"
SlashCmdList["WHORK"] = function(msg) Whorkaround:Query(msg) end

-- SAFE OVERRIDE: Using a unique tag to capture the native /who command
SLASH_WHORKWHO1 = "/who"
SlashCmdList["WHORKWHO"] = function(msg)
    if Whorkaround_Settings and Whorkaround_Settings.overrideWho then
        Whorkaround:Query(msg)
    else
        SendWho(msg)
    end
end

-- UTILITY COMMANDS
SLASH_WSTATS1 = "/whostats"; SlashCmdList["WSTATS"] = function() Whorkaround:ShowStats() end
SLASH_WCLEAR1 = "/whocleardb"; SlashCmdList["WCLEAR"] = function()
    Whorkaround_DB = {}; print("|cff1abc9cWhorkaround:|r Database cleared.")
end
SLASH_WFIND1 = "/whofind"; SlashCmdList["WFIND"] = function(msg) Whorkaround:Find(msg) end
SLASH_WDEBUG1 = "/whodebug"; SlashCmdList["WDEBUG"] = function() Whorkaround:ToggleDebug() end
SLASH_WGUI1 = "/whogui"; SlashCmdList["WGUI"] = function() 
    if not FriendsFrame:IsShown() then ShowUIPanel(FriendsFrame) end
    -- Dynamically find the WHO tab to support different tab orders/localizations
    for i = 1, 5 do
        local tab = _G["FriendsFrameTab"..i]
        if tab and tab:GetText() == (WHO or "Who") then
            tab:Click()
            break
        end
    end
    if Whorkaround.ToggleButton and not WhorkaroundSettingsPanel:IsShown() then 
        Whorkaround.ToggleButton:Click() 
    end 
end


print("|cff1abc9cWhorkaround|r loaded.")
