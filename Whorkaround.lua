local addonName, Whorkaround = ...

local publicAPI = _G.WhorkaroundAPI or {}
_G.WhorkaroundAPI = publicAPI

local function NormalizeApiName(name)
    if type(name) ~= "string" then return nil end
    name = name:lower():gsub("^%s*(.-)%s*$", "%1")
    if name == "" then return nil end
    return name
end

function publicAPI.Query(name, silent)
    return Whorkaround:Query(name, silent)
end

function publicAPI.Refresh(name, silent)
    local key = NormalizeApiName(name)
    if not key then return end

    local entry = Whorkaround_DB and Whorkaround_DB[key]
    local playerFaction = UnitFactionGroup("player") or "Unknown"
    local targetFaction = entry and entry.faction

    if targetFaction and targetFaction ~= "Unknown" and targetFaction ~= playerFaction and Whorkaround.Request then
        if not Whorkaround.networkWaiters[key] then
            local displayName = (entry and entry.name) or name:gsub("^%l", string.upper)
            local tag = (targetFaction == "Horde") and "H" or "A"
            Whorkaround.networkWaiters[key] = { startTime = GetTime(), silent = not not silent }
            Whorkaround.bestNetworkHits[key] = nil
            Whorkaround:Request(displayName, tag)
        end
        return
    end

    return Whorkaround:Query(name, silent)
end

function publicAPI.GetEntry(name)
    local key = NormalizeApiName(name)
    local entry = key and Whorkaround_DB and Whorkaround_DB[key]
    if type(entry) ~= "table" then return nil end
    return {
        name = entry.name,
        class = entry.class,
        level = entry.level,
        race = entry.race,
        guild = entry.guild,
        faction = entry.faction,
        zone = entry.zone,
        lastSeen = entry.lastSeen,
        source = entry.source,
    }
end

Whorkaround.pendingQueries = Whorkaround.pendingQueries or {}
Whorkaround.removingFriends = Whorkaround.removingFriends or {}
Whorkaround.addedSuppression = Whorkaround.addedSuppression or {}
Whorkaround.networkWaiters = Whorkaround.networkWaiters or {}
Whorkaround.bestNetworkHits = Whorkaround.bestNetworkHits or {}
Whorkaround.queryThrottle = Whorkaround.queryThrottle or {}
Whorkaround.broadcastThrottle = Whorkaround.broadcastThrottle or {}
Whorkaround.sightingThrottle = Whorkaround.sightingThrottle or {}



-- Class lookup table for 3.3.5 (Project Epoch: No Death Knights)
local localizedClassMap = {
    ["Warrior"] = "WARRIOR",
    ["Paladin"] = "PALADIN",
    ["Hunter"] = "HUNTER",
    ["Rogue"] = "ROGUE",
    ["Priest"] = "PRIEST",
    ["Shaman"] = "SHAMAN",
    ["Mage"] = "MAGE",
    ["Warlock"] = "WARLOCK",
    ["Druid"] = "DRUID",
}
local validClasses = {
    ["WARRIOR"] = true,
    ["PALADIN"] = true,
    ["HUNTER"] = true,
    ["ROGUE"] = true,
    ["PRIEST"] = true,
    ["SHAMAN"] = true,
    ["MAGE"] = true,
    ["WARLOCK"] = true,
    ["DRUID"] = true,
}
Whorkaround.validClasses = validClasses -- Shared with Comm.lua

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

-- Helper to remove friend by name
local function RemoveFriendByName(targetName)
    if not targetName then return end
    for i = 1, GetNumFriends() do
        local name = GetFriendInfo(i)
        if name and name:lower() == targetName:lower() then
            RemoveFriend(i)
            return true
        end
    end
end

-- Helper to set friend note by name
local function SetFriendNoteByName(targetName, note)
    if not targetName then return end
    for i = 1, GetNumFriends() do
        local name = GetFriendInfo(i)
        if name and name:lower() == targetName:lower() then
            SetFriendNotes(i, note)
            return true
        end
    end
end

-- Color code cache: class never changes per character, safe to cache indefinitely
local colorCodeCache = {}

-- Improved Class Color Detector (fast-path + cache + faction detection)
-- Exposed on the Whorkaround table so other modules (e.g. MentionHyperlinks) can use it.
local function GetClassColorCode(className, name)
    local nameLower = name and name:lower() or nil
    
    -- Fast path: If a specific class is provided, generate and optionally cache it immediately
    if className then
        local tag = localizedClassMap[className] or className:upper()
        local color = RAID_CLASS_COLORS[tag]
        if color then
            local code = string.format("|cff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
            if nameLower then colorCodeCache[nameLower] = code end
            return code
        end
    end

    if nameLower then
        if colorCodeCache[nameLower] then return colorCodeCache[nameLower] end

        local units = { "player", "target", "focus", "mouseover", "party1", "party2", "party3", "party4", "raid1",
            "raid2" }
        for _, unit in ipairs(units) do
            local uName = UnitName(unit)
            if uName and uName:lower() == nameLower then
                local _, classTag = UnitClass(unit)
                local race = UnitRace(unit)
                if classTag then
                    local color = RAID_CLASS_COLORS[classTag]
                    -- Only write to DB if this is new info (avoids inflating lastSeen via chat rendering)
                    if Whorkaround_DB then
                        local existing = Whorkaround_DB[nameLower]
                        if not existing or not existing.class then
                            Whorkaround_DB[nameLower] = existing or {}
                            Whorkaround_DB[nameLower].class = classTag
                            Whorkaround_DB[nameLower].level = UnitLevel(unit)
                            Whorkaround_DB[nameLower].faction = raceFactionMap[race] or UnitFactionGroup(unit)
                            Whorkaround_DB[nameLower].lastSeen = time()
                        end
                    end
                    if color then
                        local code = string.format("|cff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
                        colorCodeCache[nameLower] = code
                        return code
                    end
                end
            end
        end
        if not className and Whorkaround.GetElvUIClass then className = Whorkaround:GetElvUIClass(name) end
        if not className and Whorkaround_DB then
            local dbKey = nameLower
            if Whorkaround_DB[dbKey] and Whorkaround_DB[dbKey].class then
                className = Whorkaround_DB[dbKey].class
            end
        end
    end
    local tag = localizedClassMap[className] or (className and className:upper())
    local color = RAID_CLASS_COLORS[tag]
    if color then
        local code = string.format("|cff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
        if name then colorCodeCache[name:lower()] = code end
        return code
    end
    return "|cffffffff"
end
Whorkaround.GetClassColorCode = GetClassColorCode

-- Helper to get the correct output chat frames (cached; invalidated when outputTab setting changes)
local cachedOutputFrames = nil
local cachedOutputTab = nil

local function GetOutputFrames()
    local currentTab = Whorkaround_Settings and Whorkaround_Settings.outputTab or ""
    if cachedOutputFrames and cachedOutputTab == currentTab then
        return cachedOutputFrames
    end
    local frames = {}
    if currentTab ~= "" then
        for tabName in currentTab:gmatch("([^,]+)") do
            tabName = tabName:gsub("^%s*(.-)%s*$", "%1") -- trim whitespace
            for i = 1, NUM_CHAT_WINDOWS do
                local name = GetChatWindowInfo(i)
                if name and name:lower() == tabName:lower() then
                    table.insert(frames, _G["ChatFrame" .. i])
                end
            end
        end
    end
    if #frames == 0 then table.insert(frames, DEFAULT_CHAT_FRAME) end
    cachedOutputFrames = frames
    cachedOutputTab = currentTab
    return frames
end

-- Helper for relative time strings
local function GetRelativeTime(timestamp)
    if not timestamp or timestamp == 0 then return "Unknown" end
    local diff = time() - timestamp
    if diff < 0 then diff = 0 end -- Handle clock drift

    if diff < 60 then
        return "just now"
    elseif diff < 3600 then
        return string.format("%d min ago", math.floor(diff / 60))
    elseif diff < 86400 then
        return string.format("%d hours ago", math.floor(diff / 3600))
    else
        return string.format("%d days ago", math.floor(diff / 86400))
    end
end

-- Function to print the "Who" result
function Whorkaround:PrintWhoResult(name, level, class, area, isLive, source, faction, timestamp)
    if not name then return end

    -- Normalize the level sentinel: treat "?" or any non-positive-number as nil so that
    -- all downstream comparisons (> 0, <= 60, %d format) are safe.
    if type(level) ~= "number" or level <= 0 then level = nil end
    local prefix = "|cff1abc9cWhorkaround:|r "
    local cleanName = name:lower():gsub("^%s*(.-)%s*$", "%1")
    local displayName = name:gsub("^%l", string.upper)
    local classColor = GetClassColorCode(class, name)

    -- TitleCase the class for professional appearance
    local displayClass = class or "Unknown"
    if displayClass:lower() ~= "unknown" then
        displayClass = displayClass:lower():gsub("(%a)([%w_']*)", function(first, rest) return first:upper() .. rest end)
    end
    local cachedData = Whorkaround_DB and Whorkaround_DB[cleanName]
    local timestamp = (timestamp and timestamp ~= 0) and timestamp or (cachedData and cachedData.lastSeen)
    local isDataRecent = timestamp and (time() - timestamp < 10)
    if isLive == nil then isLive = isDataRecent or false end
    local playerFaction = UnitFactionGroup("player") or "Unknown"
    local enemyFaction = (playerFaction == "Horde") and "Alliance" or
    (playerFaction == "Alliance" and "Horde" or "Unknown")
    local timeText = isLive and "" or string.format(" |cff888888(%s)|r", GetRelativeTime(timestamp))

    -- DEDUPLICATION: Prevent double-prints within 100ms
    Whorkaround.lastPrint = Whorkaround.lastPrint or {}
    local now = GetTime()
    if Whorkaround.lastPrint[cleanName] and (now - Whorkaround.lastPrint[cleanName] < 0.1) then return end
    Whorkaround.lastPrint[cleanName] = now

    if not faction or faction == "U" then
        faction = (cachedData and cachedData.faction) or ((not level or level == 0) and enemyFaction or playerFaction)
    end

    -- State detection: Is this request supposed to be silent?
    -- We check the explicit source, or if we are resolving a waiter that was marked silent
    local isSilentSource = (source == "SILENT" or source == "PROXY" or source == "TIMEOUT_SILENT")
    local waiter = Whorkaround.networkWaiters[cleanName]
    local isWaiterSilent = (type(waiter) == "table" and waiter.silent)
    local isActualSilent = isSilentSource or isWaiterSilent

    -- OFFLINE OR ENEMY DETECTION (Trigger network search)
    -- ONLY trigger a scan if it's a truly manual user search (Manual, FriendsList) or a fresh Cache/Guild hit from a user search
    local isUserSearch = (source == "Manual" or source == "FriendsList" or source == "SILENT")
    if (not level or level == 0) and isUserSearch then
        if Whorkaround.Request and not Whorkaround.networkWaiters[cleanName] then
            -- Both same-faction and enemy-faction skip if super-fresh (< 10s)
            local isEnemy = (faction ~= playerFaction)
            local isFresh = cachedData and type(cachedData.level) == "number" and cachedData.level > 0 and
            (time() - (cachedData.lastSeen or 0) < 2)

            if not isFresh then
                local statusMsg = isEnemy and "identified as " .. faction or "appears to be offline"
                if source ~= "SILENT" and not isActualSilent then
                    for _, frame in ipairs(GetOutputFrames()) do
                        frame:AddMessage(
                        string.format("%s|Hplayer:%s|h[|r%s%s|r]|h %s. Scanning network...", prefix, name, classColor,
                            displayName, statusMsg), 1, 1, 0)
                    end
                end
                Whorkaround.networkWaiters[cleanName] = { startTime = GetTime(), silent = isActualSilent }
                Whorkaround.bestNetworkHits[cleanName] = nil -- Clear previous search results
                local targetFactionTag = (faction == "Horde") and "H" or (faction == "Alliance" and "A" or "U")
                Whorkaround:Request(name, targetFactionTag)
                return
            end
        end
    end

    Whorkaround.networkWaiters[cleanName] = nil

    -- Format the message
    if (level and level > 0) or (cachedData and type(cachedData.level) == "number" and cachedData.level > 0) then
        local displayLevel = (level and level > 0 and level <= 60) and level or (type(cachedData.level) == "number" and cachedData.level > 0 and cachedData.level)
        local displayArea = (area and area ~= "Unknown") and area or (cachedData and cachedData.zone) or "Unknown"
        local displayFaction = faction or cachedData.faction or "Unknown"

        -- DATA QUALITY: Abort if essential data is still Unknown
        if displayClass == "Unknown" or displayArea == "Unknown" then return end

        local line1 = string.format("%s|Hplayer:%s|h[|r%s%s|r]|h: Level %d %s %s - %s%s", prefix, name, classColor,
            displayName, displayLevel, displayFaction, displayClass, displayArea, timeText)

        if source == "WhorkComm" or source == "TIMEOUT" then
            local statusLabel = isLive and "|cff00ff00(Live)|r" or "|cffffd100(Cached)|r"
            local actionMsg = (source == "WhorkComm") and "fetched from network" or "recovered from cache (Network timeout)"
            local line2 = string.format("%sData %s was successfully %s.", prefix, statusLabel, actionMsg)
            if not isActualSilent then
                for _, frame in ipairs(GetOutputFrames()) do
                    frame:AddMessage(line1, 1, 1, 0)
                    frame:AddMessage(line2, 1, 1, 0)
                end
            end
        else
            if not isActualSilent then
                for _, frame in ipairs(GetOutputFrames()) do
                    frame:AddMessage(line1, 1, 1, 0)
                end
            end
        end
    elseif source == "FINAL_TIMEOUT" then
        if not isActualSilent then
            for _, frame in ipairs(GetOutputFrames()) do
                frame:AddMessage(
                string.format("%sNo data for |Hplayer:%s|h[|cffffffff%s|r]|h was found on the network.", prefix, name,
                    displayName), 1, 1, 0)
            end
        end
    else
        local isSilent = (source == "PROXY" or source == "SILENT")
        if not isSilent and (source == "TIMEOUT" or source == "Manual") then
            local factionColor = (faction == "Horde") and "|cffff2020" or "|cff0070dd"
            local failMsg = "No community data was found."
            if faction == playerFaction then failMsg = "User is offline and no community data was found." end

            if source ~= "SILENT" and source ~= "PROXY" and source ~= "TIMEOUT_SILENT" and not isActualSilent then
                for _, frame in ipairs(GetOutputFrames()) do
                    frame:AddMessage(
                    string.format("%sNo community data was found for |Hplayer:%s|h[|r%s%s|r]|h.", prefix, name,
                        classColor, displayName), 1, 1, 0)
                end
            end
        end
    end

    -- Update Database (Enforce Level > 0)
    if Whorkaround_DB and level and level > 0 then
        local isNew = not Whorkaround_DB[cleanName]
        local existing = Whorkaround_DB[cleanName] or {}
        existing.class = class
        existing.level = level
        existing.zone = (area ~= "Unknown") and area or (cachedData and cachedData.zone)
        existing.faction = faction
        existing.lastSeen = timestamp
        existing.source = source or (cachedData and "Cache" or "FriendsList")
        -- Preserve scanner-gathered fields that this source cannot provide
        -- (race and guild are only discoverable via unit inspection / mouseover)
        Whorkaround_DB[cleanName] = existing
        if Whorkaround.SyncBrowser then Whorkaround:SyncBrowser(isNew) end
    end

    local now = GetTime()
    local canBroadcast = not Whorkaround.broadcastThrottle[cleanName] or
    (now - Whorkaround.broadcastThrottle[cleanName] > 1)

    -- BROADCAST RULES:
    -- 1. Only broadcast if data is LOCAL (FriendsList, Manual, Sighting, PROXY)
    -- 2. Only if not recently broadcasted
    local isLocal = (source == "FriendsList" or source == "Manual" or source == "Sighting" or source == "PROXY")
    if isLocal and canBroadcast and level and level > 0 and level <= 60 and Whorkaround.Broadcast then
        Whorkaround:Log("Broadcasting local data for " .. name, "NETWORK")
        Whorkaround:Broadcast(name, level, class, area, faction, timestamp, false, "NORMAL")
    end

    -- Compatibility: Set flag to fire a fake Who event to stop other addons (like ElvUI) from retrying
    if source ~= "WhorkComm" and source ~= "SILENT" and source ~= "PROXY" then
        Whorkaround.fakeWhoTriggered = true
    end
end

-- Resolves a network wait by collecting hits over a 5s window
function Whorkaround:ResolveNetworkWait(name, level, class, zone, faction, timestamp, isProxy)
    local cleanName = name:lower():gsub("^%s*(.-)%s*$", "%1")
    local waiter = Whorkaround.networkWaiters[cleanName]
    if waiter then
        local startTime = (type(waiter) == "table") and waiter.startTime or waiter
        local isSilent = (type(waiter) == "table") and waiter.silent or false
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
                level = level,
                class = class,
                zone = zone,
                faction = faction,
                timestamp = timestamp,
                isLive = newIsLive
            }
        end

        -- IMMEDIATE LIVE PRINT: If we got a live hit, don't wait for the timeout
        if newIsLive then
            Whorkaround:Log("Live result received for " .. name .. "! Printing immediately.", "NETWORK")
            Whorkaround.networkWaiters[cleanName] = nil
            Whorkaround:PrintWhoResult(name, level, class, zone, true, isSilent and "SILENT" or "WhorkComm", faction, timestamp)
            Whorkaround.bestNetworkHits[cleanName] = nil
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
        if not silent then
            Whorkaround:PrintWhoResult(name, 0, data.class, data.zone or "Unknown", false, "Cache",
                data.faction)
        end
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
            if data.faction then
                factions[data.faction] = (factions[data.faction] or 0) + 1
            else
                factions.Unknown =
                    factions.Unknown + 1
            end
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
            ", Guild: " ..
            sources.GuildRoster ..
            ", Sightings: " .. sources.Sighting .. ", Comm: " .. sources.WhorkComm .. ", Cache: " .. sources.Cache)
    end
end

-- Database Maintenance & Ghost Cleanup
local NOTE_ID = "Whorkaround:Tag"
function Whorkaround:CleanGhostFriends()
    local num = GetNumFriends()
    local cleaned = 0
    for i = num, 1, -1 do
        local name, _, _, _, _, _, note = GetFriendInfo(i)
        if name then
            local cleanName = name:lower():gsub("^%s*(.-)%s*$", "%1")
            local hasNote = note and note:find("^Whorkaround:")
            local isTemp = Whorkaround_DB and Whorkaround_DB.tempFriends and Whorkaround_DB.tempFriends[cleanName]
            
            if hasNote or isTemp then
                Whorkaround:Log("Cleaning ghost friend: " .. name, "CLEANUP")
                Whorkaround.removingFriends[cleanName] = GetTime()
                RemoveFriend(i)
                cleaned = cleaned + 1
            end
        end
    end
    -- Clear out any leftover memory flags
    if Whorkaround_DB and Whorkaround_DB.tempFriends then
        for k in pairs(Whorkaround_DB.tempFriends) do
            Whorkaround_DB.tempFriends[k] = nil
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
        print(string.format("|cff1abc9cWhorkaround:|r Cleaned up |cffffd100%d|r expired records (older than %d weeks).",
            count, weeks))
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
        local existing = Whorkaround_DB[cleanName] or {}
        existing.class = class     -- Always authoritative from unit API
        existing.level = level     -- Always authoritative
        existing.faction = faction -- Always authoritative
        existing.zone = zone       -- Sighting zone = your zone (player is nearby)
        existing.lastSeen = time()
        existing.source = "Sighting"
        Whorkaround_DB[cleanName] = existing
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
        for name, qSource in pairs(Whorkaround.pendingQueries) do
            local startTime = Whorkaround.addedSuppression[name] or (type(qSource) == "number" and qSource or GetTime())
            local elapsed = GetTime() - startTime
            if elapsed < 2 then
                if qSource ~= "PROXY" and qSource ~= "SILENT" then 
                    local finalSource = (type(qSource) == "string") and qSource or "Manual"
                    Whorkaround:PrintWhoResult(name, nil, nil, nil, false, finalSource) 
                end
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
frame:RegisterEvent("PLAYER_CAMPING"); frame:RegisterEvent("PLAYER_QUITING"); frame:RegisterEvent("PLAYER_LOGOUT")

-- Recyclable tables for ticker to reduce garbage buildup
local expiredQueries = {}
local expiredWaiters = {}
local expiredRemovals = {}
local sweepRemovals = {}

frame:SetScript("OnUpdate", function(self, elapsed)
    self.timer = (self.timer or 0) + elapsed
    if self.timer < 0.1 then return end
    self.timer = 0
    local now = GetTime()
    
    -- Removed debounce logic; now handled instantly in OnEditBoxTextChanged
    -- Collect expired pendingQueries to avoid mutating during pairs()
        wipe(expiredQueries)
        for name, qSource in pairs(Whorkaround.pendingQueries) do
            local startTime = Whorkaround.addedSuppression[name] or (type(qSource) == "number" and qSource or now)
            local diff = now - startTime
            
            if diff > 1.0 and qSource ~= "TIMEOUT" and qSource ~= "PROXY" then
                local finalSource = (type(qSource) == "string") and qSource or "Manual"
                Whorkaround:PrintWhoResult(name, nil, nil, nil, false, finalSource)
                Whorkaround.pendingQueries[name] = "TIMEOUT"
                Whorkaround.removingFriends[name] = GetTime()
                RemoveFriend(name)
                if Whorkaround_DB and Whorkaround_DB.tempFriends then Whorkaround_DB.tempFriends[name] = nil end
            end
            
            if diff > 5 then
                table.insert(expiredQueries, name)
            end
        end
        for _, name in ipairs(expiredQueries) do
            Whorkaround.pendingQueries[name] = nil
            Whorkaround.addedSuppression[name] = nil
            Whorkaround.removingFriends[name] = nil
        end

        -- NETWORK SCAN TIMEOUT (safe: collect first, then remove)
        wipe(expiredWaiters)
        for name, data in pairs(Whorkaround.networkWaiters) do
            local startTime = (type(data) == "table") and data.startTime or data
            if (now - startTime) > 6 then
                table.insert(expiredWaiters, name)
            end
        end
        for _, name in ipairs(expiredWaiters) do
            if Whorkaround.DebugMode or (Whorkaround_Settings and Whorkaround_Settings.debug) then
                Whorkaround:Log("Network scan timeout for " .. name, "NETWORK")
            end
            local waiter = Whorkaround.networkWaiters[name]
            local isSilent = (type(waiter) == "table") and waiter.silent or false
            Whorkaround.networkWaiters[name] = nil

            local best = Whorkaround.bestNetworkHits[name]
            if best then
                -- Use TIMEOUT_SILENT (not "SILENT") so PrintWhoResult doesn't treat
                -- this as a new user-search and re-fire another Request.
                Whorkaround:PrintWhoResult(name, best.level, best.class, best.zone, best.isLive, isSilent and "TIMEOUT_SILENT" or "WhorkComm",
                    best.faction, best.timestamp)
            else
                local dbData = Whorkaround_DB and Whorkaround_DB[name]
                if dbData then
                    Whorkaround:PrintWhoResult(name, 0, dbData.class, dbData.zone or "Unknown", false, isSilent and "TIMEOUT_SILENT" or "TIMEOUT", dbData.faction, dbData.lastSeen)
                else
                    Whorkaround:PrintWhoResult(name, nil, nil, nil, false, isSilent and "TIMEOUT_SILENT" or "FINAL_TIMEOUT")
                end
            end
            Whorkaround.bestNetworkHits[name] = nil
        end

        -- RECENT REMOVALS CLEANUP
        wipe(expiredRemovals)
        for name, removalTime in pairs(Whorkaround.removingFriends) do
            if (now - removalTime) > 10 then table.insert(expiredRemovals, name) end
        end
        for _, name in ipairs(expiredRemovals) do Whorkaround.removingFriends[name] = nil end

        -- PERIODIC THROTTLE SWEEP (Every 5 minutes via wall-clock)
        if not self.nextSweep then self.nextSweep = now + 300 end
        if now >= self.nextSweep then
            self.nextSweep = now + 300
            Whorkaround:Log("Performing periodic memory sweep...", "CLEANUP")
            local function SweepTable(t, expiry)
                if not t then return end
                wipe(sweepRemovals)
                for k, v in pairs(t) do
                    if (now - v) > expiry then table.insert(sweepRemovals, k) end
                end
                for _, k in ipairs(sweepRemovals) do t[k] = nil end
            end
            SweepTable(Whorkaround.sightingThrottle, 30)
            SweepTable(Whorkaround.broadcastThrottle, 60)
            SweepTable(Whorkaround.queryThrottle, 300)
            SweepTable(Whorkaround.recentRequests, 30)
            SweepTable(Whorkaround.addedSuppression, 10)
        end

        -- SMART GHOST CLEANUP: Only runs 5s after the last addon action (query/proxy)
        if Whorkaround.lastActionTime and (now - Whorkaround.lastActionTime > 5) then
            if Whorkaround.DebugMode or (Whorkaround_Settings and Whorkaround_Settings.debug) then
                Whorkaround:Log("Running scheduled ghost friend cleanup...", "CLEANUP")
            end
            Whorkaround:CleanGhostFriends()
            Whorkaround.lastActionTime = nil
        end
    end
)

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "UPDATE_MOUSEOVER_UNIT" then
        Whorkaround:Sighting("mouseover")
    elseif event == "PLAYER_TARGET_CHANGED" then
        Whorkaround:Sighting("target")
    elseif event == "ADDON_LOADED" then
        local name = ...; if name == "Whorkaround" then
            -- MUST initialize Settings first — migration block reads it
            Whorkaround_Settings = Whorkaround_Settings or {}
            if Whorkaround_Settings.overrideWho == nil then Whorkaround_Settings.overrideWho = true end
            if Whorkaround_Settings.allowProxy == nil then Whorkaround_Settings.allowProxy = true end
            if Whorkaround_Settings.outputTab == nil then Whorkaround_Settings.outputTab = "" end
            if Whorkaround_Settings.retentionWeeks == nil then Whorkaround_Settings.retentionWeeks = 4 end
            if Whorkaround_Settings.factionColors == nil then Whorkaround_Settings.factionColors = false end
            if Whorkaround_Settings.proxyCooldown == nil then Whorkaround_Settings.proxyCooldown = 15 end
            if Whorkaround_Settings.proxyOutCombat == nil then Whorkaround_Settings.proxyOutCombat = true end
            if Whorkaround_Settings.debug == nil then Whorkaround_Settings.debug = false end
            if Whorkaround_Settings.debugLevel == nil then Whorkaround_Settings.debugLevel = 1 end
            if Whorkaround_Settings.enableScanner == nil then Whorkaround_Settings.enableScanner = true end
            if Whorkaround_Settings.mentionHyperlinks == nil then Whorkaround_Settings.mentionHyperlinks = false end

            Whorkaround_DB = Whorkaround_DB or {}
            Whorkaround_DB.tempFriends = Whorkaround_DB.tempFriends or {}

            -- DB MIGRATION: Convert all keys to lowercase and PURGE invalid classes
            -- Only run once (guarded by version flag)
            if not Whorkaround_Settings.dbVersion or Whorkaround_Settings.dbVersion < 3 then
                local migratedDB = {}
                for k, v in pairs(Whorkaround_DB) do
                    local class = v.class and v.class:upper()
                    if validClasses[class] then
                        local lk = k:lower()
                        -- If two keys collapse to the same lowercase key, keep the newer one
                        if not migratedDB[lk] or (v.lastSeen or 0) > (migratedDB[lk].lastSeen or 0) then
                            migratedDB[lk] = v
                        end
                    end
                end
                Whorkaround_DB = migratedDB
                Whorkaround_Settings.dbVersion = 3
            end
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
        for i = GetNumFriends(), 1, -1 do
            local name, level, class, area, connected, _, note = GetFriendInfo(i)
            if name then
                local displayName = name:gsub("^%l", string.upper)
                local cleanName = name:lower():gsub("^%s*(.-)%s*$", "%1")

                if Whorkaround.pendingQueries[cleanName] and not processed[cleanName] then
                    processed[cleanName] = true
                    if not note or note == "" then
                        Whorkaround:Log("Tagging friend: " .. name, "LOCAL")
                        SetFriendNotes(i, NOTE_ID)
                    end
                    
                    if Whorkaround.pendingQueries[cleanName] then
                        if Whorkaround.pendingQueries[cleanName] == "PROXY" then
                            if connected then
                                local faction = (Whorkaround_DB and Whorkaround_DB[cleanName] and Whorkaround_DB[cleanName].faction) or
                                "Unknown"
                                Whorkaround:Log("Proxy hit! Sending broadcast for " .. name, "PROXY")
    
                                -- DE-DUPLICATION: Cancel any pending cached response schedule
                                if Whorkaround.CancelScheduledResponse then Whorkaround:CancelScheduledResponse(name) end
    
                                Whorkaround:Broadcast(name, level, class, area, faction, time(), true)
                                -- Removed PrintWhoResult to keep proxy lookups silent for the proxying user
                                Whorkaround.removingFriends[cleanName] = GetTime(); RemoveFriend(i)
                                if Whorkaround_DB and Whorkaround_DB.tempFriends then Whorkaround_DB.tempFriends[cleanName] = nil end
                                Whorkaround.pendingQueries[cleanName] = nil
                            else
                                Whorkaround:Log("Proxy check: " .. name .. " is offline/enemy.", "PROXY")
                                Whorkaround.removingFriends[cleanName] = GetTime(); RemoveFriend(i)
                                if Whorkaround_DB and Whorkaround_DB.tempFriends then Whorkaround_DB.tempFriends[cleanName] = nil end
                                Whorkaround.pendingQueries[cleanName] = nil
                            end
                        elseif Whorkaround.pendingQueries[cleanName] ~= "TIMEOUT" then
                            if connected then
                                local qSource = Whorkaround.pendingQueries[cleanName]
                                local finalSource = (type(qSource) == "number") and "FriendsList" or qSource
                                Whorkaround:Log("Manual query success: " .. name, "LOCAL")
                                Whorkaround:PrintWhoResult(name, level, class, area, true, finalSource, nil, time())
                                Whorkaround:Broadcast(name, level, class, area, UnitFactionGroup("player"), time(), false)
                                Whorkaround.removingFriends[cleanName] = GetTime(); RemoveFriend(i)
                                if Whorkaround_DB and Whorkaround_DB.tempFriends then Whorkaround_DB.tempFriends[cleanName] = nil end
                                Whorkaround.pendingQueries[cleanName] = nil
                            else
                                local qSource = Whorkaround.pendingQueries[cleanName]
                                local finalSource = (type(qSource) == "string") and qSource or "Manual"
                                Whorkaround.pendingQueries[cleanName] = nil -- Clear FIRST
                                Whorkaround:Log("Manual query failed (offline): " .. name, "LOCAL")
                                Whorkaround:PrintWhoResult(name, nil, nil, nil, false, finalSource)
                                Whorkaround.removingFriends[cleanName] = GetTime(); RemoveFriend(i)
                                if Whorkaround_DB and Whorkaround_DB.tempFriends then Whorkaround_DB.tempFriends[cleanName] = nil end
                            end
                        end
                    end
                end
            end
        end
    elseif event == "PLAYER_CAMPING" or event == "PLAYER_QUITING" then
        Whorkaround.isLoggingOut = true
        Whorkaround:Log("Logout sequence initiated. Blocking new queries.", "SYSTEM")
    elseif event == "PLAYER_LOGOUT" then
        -- EMERGENCY PURGE: Absolute last millisecond before game closes
        if Whorkaround_DB and Whorkaround_DB.tempFriends then
            local purged = 0
            for tempName in pairs(Whorkaround_DB.tempFriends) do
                local cleanName = tempName:lower():gsub("^%s*(.-)%s*$", "%1")
                Whorkaround.removingFriends[cleanName] = GetTime()
                RemoveFriend(tempName)
                purged = purged + 1
            end
            if purged > 0 then
                Whorkaround:Log("EMERGENCY PURGE: Removed " .. purged .. " temporary friends on logout.", "CLEANUP")
            end
            -- We intentionally DO NOT wipe tempFriends here. If the RemoveFriend packet
            -- fails to reach the server because we are disconnecting, the names will remain 
            -- in tempFriends and be cleaned up flawlessly on the next login!
        end
    end
end)

C_Timer.NewTicker(60, function() Whorkaround:CleanGhostFriends() end)

function Whorkaround:ProxyQuery(name)
    if Whorkaround.isLoggingOut then return end
    if not name or name == "" or GetNumFriends() >= 100 then return end
    name = name:lower():gsub("^%s*(.-)%s*$", "%1") -- Clean key
    if Whorkaround.pendingQueries[name] or Whorkaround.networkWaiters[name] then return end

    local displayName = name:gsub("^%l", string.upper)

    -- OPTIMIZATION: Check Target/Mouseover for INSTANT unit data
    local units = { "target", "mouseover" }
    for _, unit in ipairs(units) do
        if UnitIsPlayer(unit) and UnitName(unit):lower() == name then
            Whorkaround:Log("Unit match (" .. unit .. ") for " .. displayName .. "! Broadcasting immediately.", "PROXY")
            local level = UnitLevel(unit)
            local _, class = UnitClass(unit)
            local zone = GetRealZoneText() -- Same-zone assumption for units
            local faction = UnitFactionGroup(unit)

            if Whorkaround.CancelScheduledResponse then Whorkaround:CancelScheduledResponse(name) end
            Whorkaround:Broadcast(displayName, level, class, zone, faction, time(), true)
            Whorkaround:PrintWhoResult(displayName, level, class, zone, false, "SILENT", faction)
            return
        end
    end

    -- NEW: Check Guild/Cache for INSTANT proxy response
    local gLevel, gClass, gZone = GetPlayerInfoFromGuild(displayName)
    local cached = Whorkaround_DB and Whorkaround_DB[name]

    if (gLevel and gLevel > 0) or (cached and type(cached.level) == "number" and cached.level > 0 and (time() - (cached.lastSeen or 0) < 60)) then
        Whorkaround:Log("Instant Proxy match for " .. displayName .. "! Broadcasting immediately.", "PROXY")
        local level = gLevel or (type(cached.level) == "number" and cached.level > 0 and cached.level)
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
    Whorkaround.lastActionTime = GetTime()
    Whorkaround.pendingQueries[name] = "PROXY"; Whorkaround.addedSuppression[name] = GetTime()
    -- Safety: Check if already a friend before adding
    local alreadyFriend = false
    for i = 1, GetNumFriends() do
        local fName = GetFriendInfo(i)
        if fName and fName:lower() == name then
            alreadyFriend = true; break
        end
    end

    if not alreadyFriend then
        Whorkaround_DB.tempFriends = Whorkaround_DB.tempFriends or {}
        Whorkaround_DB.tempFriends[name] = true
        AddFriend(displayName)
    else
        Whorkaround:Log("ProxyQuery: " .. displayName .. " is already on friends list. Skipping AddFriend.", "PROXY")
    end
end

function Whorkaround:Query(name, silent)
    if Whorkaround.isLoggingOut then return end
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
        local source = silent and "SILENT" or "Manual"
        Whorkaround:PrintWhoResult(displayName, level, class, GetRealZoneText(), false, source, faction)
        Whorkaround:Broadcast(displayName, level, class, GetRealZoneText(), faction, time(), false)
        return
    end

    -- OPTIMIZATION: Check Target/Mouseover for INSTANT unit data
    local units = { "target", "mouseover" }
    for _, unit in ipairs(units) do
        if UnitIsPlayer(unit) and UnitName(unit):lower() == name then
            Whorkaround:Log("Unit match (" .. unit .. ") hit for " .. displayName .. "!", "LOCAL")
            local level = UnitLevel(unit)
            local _, class = UnitClass(unit)
            local faction = UnitFactionGroup(unit)
            local source = silent and "SILENT" or "Manual"
            Whorkaround:PrintWhoResult(displayName, level, class, GetRealZoneText(), true, source, faction, time())
            Whorkaround:Broadcast(displayName, level, class, GetRealZoneText(), faction, time(), false)
            return
        end
    end

    -- STABILITY: 2s Query Throttle
    local now = GetTime()
    if Whorkaround.queryThrottle[name] and (now - Whorkaround.queryThrottle[name] < 2) then
        Whorkaround:Log("Query throttled for " .. displayName, "LOCAL")
        return
    end
    Whorkaround.queryThrottle[name] = now

    -- NEW: Check Guild Roster FIRST (Live info)
    local gLevel, gClass, gZone = GetPlayerInfoFromGuild(displayName)
    if gLevel and gLevel > 0 then
        Whorkaround:Log("Guild hit for " .. displayName .. "! Skipping Friends List.", "LOCAL")
        local isOffline = (gZone == "Offline")
        local source = silent and "SILENT" or "GuildRoster"
        Whorkaround:PrintWhoResult(displayName, isOffline and 0 or gLevel, gClass, gZone, not isOffline, source, nil, time())
        if not isOffline then
            Whorkaround:Broadcast(displayName, gLevel, gClass, gZone, UnitFactionGroup("player"), time(), false)
        end
        return
    end

    -- NEW: Check Cache (If fresh)
    local cached = Whorkaround_DB and Whorkaround_DB[name]
    local playerFaction = UnitFactionGroup("player")
    local isEnemy = cached and cached.faction and (cached.faction ~= playerFaction and cached.faction ~= "Unknown")

    -- Normal fresh cache check (Enemies < 10s, Same-faction < 5s)
    local threshold = isEnemy and 10 or 5
    if cached and type(cached.level) == "number" and cached.level > 0 and (time() - (cached.lastSeen or 0) < threshold) then
        Whorkaround:Log("Fresh cache hit for " .. displayName .. ". Skipping Friends List.", "LOCAL")
        if not silent then
            Whorkaround:PrintWhoResult(displayName, cached.level, cached.class, cached.zone, true, "Cache",
                cached.faction, cached.lastSeen)
        end
        -- Only broadcast cache hits if it was a manual query (not silent)
        if not silent then
            Whorkaround:Broadcast(displayName, cached.level, cached.class, cached.zone, cached.faction, cached.lastSeen,
                false)
        end
        return
    end

    for i = 1, GetNumFriends() do
        local fName, level, class, area, connected = GetFriendInfo(i)
        if fName and fName:lower() == name then
            local source = silent and "SILENT" or "FriendsList"
            Whorkaround:PrintWhoResult(fName, connected and level or 0, class, area, connected, source, nil, time())
            if connected then
                Whorkaround:Broadcast(fName, level, class, area, UnitFactionGroup("player"), time(), false)
            end
            return
        end
    end

    if GetNumFriends() >= 100 then
        print("|cff1abc9cWhorkaround:|r List full!"); return
    end
    Whorkaround:Log("Starting Friends-List lookup for " .. displayName, "LOCAL")
    Whorkaround.lastActionTime = GetTime()
    Whorkaround.pendingQueries[name] = silent and "SILENT" or GetTime(); Whorkaround.addedSuppression[name] = GetTime()
    Whorkaround_DB.tempFriends = Whorkaround_DB.tempFriends or {}
    Whorkaround_DB.tempFriends[name] = true
    AddFriend(displayName)
end

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
    StaticPopup_Show("WHORKAROUND_CONFIRM_CLEAR")
end
SLASH_WFIND1 = "/whofind"; SlashCmdList["WFIND"] = function(msg) Whorkaround:Find(msg) end
SLASH_WDEBUG1 = "/whodebug"; SlashCmdList["WDEBUG"] = function() Whorkaround:ToggleDebug() end
SLASH_WGUI1 = "/whogui"; SlashCmdList["WGUI"] = function()
    if not FriendsFrame:IsShown() then ShowUIPanel(FriendsFrame) end
    -- Dynamically find the WHO tab to support different tab orders/localizations
    for i = 1, 5 do
        local tab = _G["FriendsFrameTab" .. i]
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
