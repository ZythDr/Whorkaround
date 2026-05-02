local addonName, Whorkaround = ...

-- ----------------------------------------------------------------------------
-- Ambient Scanner Module
-- ----------------------------------------------------------------------------
-- This module passively monitors the Combat Log for new player GUIDs.
-- It uses a high-performance "Sampling Pulse" to ensure zero FPS impact.
-- ----------------------------------------------------------------------------

Whorkaround.Scanner = {}
local Scanner = Whorkaround.Scanner
local lastScanTime = 0
local SCAN_INTERVAL = 0.1 -- Max 10 updates per second

-- Performance cache for this session to avoid redundant DB writes
local sessionSeen = {}

-- Deferred unit-data retry: race and guild can be unavailable on first contact because
-- the client loads character data asynchronously after UPDATE_MOUSEOVER_UNIT fires.
local unitRetryFrame = CreateFrame("Frame")
unitRetryFrame.pending = {}  -- { [unit] = { name, dbKey, deadline } }
unitRetryFrame:Hide()
unitRetryFrame:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + elapsed
    if self.t < 0.05 then return end  -- cap at 20 checks/sec regardless of framerate
    self.t = 0
    local now = GetTime()
    local anyPending = false
    for unit, info in pairs(self.pending) do
        if now >= info.deadline then
            self.pending[unit] = nil
            -- Only worth retrying if the unit is still the same person
            if UnitName(unit) == info.name and UnitIsPlayer(unit) then
                local entry = Whorkaround_DB and Whorkaround_DB[info.dbKey]
                if entry then
                    local changed = false
                    -- Retry race
                    if not entry.race then
                        local _, raceToken = UnitRace(unit)
                        if not raceToken then
                            local _, _, _, gr = GetPlayerInfoByGUID(UnitGUID(unit))
                            raceToken = gr
                        end
                        if raceToken then entry.race = raceToken; changed = true end
                    end
                    -- Retry guild
                    if not entry.guild then
                        local guildName = GetGuildInfo(unit)
                        if guildName then entry.guild = guildName; changed = true end
                    end
                    if changed and Whorkaround.SyncBrowser then
                        Whorkaround:SyncBrowser(false)
                    end
                end
            end
        else
            anyPending = true
        end
    end
    if not anyPending then self:Hide() end
end)

local scannerFrame = CreateFrame("Frame")
scannerFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
scannerFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
scannerFrame:RegisterEvent("PLAYER_TARGET_CHANGED")

scannerFrame:SetScript("OnEvent", function(self, event, ...)
    -- 1. Check if the feature is enabled in settings
    if not Whorkaround_Settings or not Whorkaround_Settings.enableScanner then return end

    local now = GetTime()
    local debugLevel = Whorkaround_Settings.debugLevel or 1

    -- Interactive Scrape runs FIRST, before the throttle, so it is never dropped.
    -- These events are infrequent and provide the only reliable source of guild data.
    if event == "UPDATE_MOUSEOVER_UNIT" or event == "PLAYER_TARGET_CHANGED" then
        local unit = (event == "UPDATE_MOUSEOVER_UNIT") and "mouseover" or "target"
        local name = UnitName(unit)
        if name and name ~= UNKNOWN and UnitIsPlayer(unit) then
            local _, class = UnitClass(unit)
            local level = UnitLevel(unit)
            local _, raceToken = UnitRace(unit)  -- english token (2nd return), consistent with combat log path
            -- Immediate GUID fallback: different cache path, may have race when UnitRace() doesn't yet
            if not raceToken then
                local _, _, _, gr = GetPlayerInfoByGUID(UnitGUID(unit))
                raceToken = gr
            end
            local guildName = GetGuildInfo(unit)
            local faction = UnitFactionGroup(unit)
            local dbKey = name:lower()

            Whorkaround_DB[dbKey] = Whorkaround_DB[dbKey] or {}
            local entry = Whorkaround_DB[dbKey]
            entry.name = name
            entry.class = class
            entry.race = raceToken or entry.race  -- preserve cached value if both lookups missed
            entry.level = (level and level > 0) and level or entry.level
            entry.guild = guildName or entry.guild
            entry.faction = faction or entry.faction
            entry.zone = GetRealZoneText()
            entry.lastSeen = time()
            entry.source = "Sighting"

            -- If race or guild is still unknown, schedule a 0.4s deferred retry.
            -- Guild data in particular loads async and is often unavailable at the instant the event fires.
            if not entry.race or not entry.guild then
                unitRetryFrame.pending[unit] = { name = name, dbKey = dbKey, deadline = GetTime() + 0.4 }
                unitRetryFrame:Show()
            end

            if Whorkaround_Settings.debug and debugLevel >= 2 then
                Whorkaround:Log("Scanner: Scraped " .. name .. " from " .. unit, "LOCAL")
            end
        end
        return
    end

    -- Heartbeat Debug: Only in Verbose (Level 2)
    if Whorkaround_Settings.debug and debugLevel >= 2 and (not self.lastHeartbeat or now - self.lastHeartbeat > 2.0) then
        Whorkaround:Log("Scanner: Event Heartbeat (Listening...)", "LOCAL")
        self.lastHeartbeat = now
    end

    -- 2. The Sampling Pulse: Only look at one event every 0.1 seconds
    if now - lastScanTime < SCAN_INTERVAL then return end

    -- 3. Extract GUIDs and Flags from the Combat Log event (3.3.5 Indices)
    -- 1:timestamp, 2:event, 3:sourceGUID, 4:sourceName, 5:sourceFlags, 6:destGUID, 7:destName, 8:destFlags
    local _, _, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags = ...

    -- Prioritize Source, fallback to Dest
    local targetGUID = sourceGUID
    local targetName = sourceName
    local targetFlags = sourceFlags

    -- Quick check: In 3.3.5, Player GUIDs are hex strings starting with 0x0...
    if not targetGUID or type(targetGUID) ~= "string" or targetGUID:sub(1,3) ~= "0x0" then
        targetGUID = destGUID
        targetName = destName
        targetFlags = destFlags
    end

    -- Discard if it's not a player or we don't have a name
    if not targetGUID or type(targetGUID) ~= "string" or targetGUID:sub(1,3) ~= "0x0" or not targetName or targetName == "" then 
        return 
    end

    -- 4. Fast Discard: Skip if we've seen them very recently this session
    if sessionSeen[targetGUID] and (now - sessionSeen[targetGUID] < 60) then
        return
    end

    -- 5. Data Extraction
    if Whorkaround_Settings.debug and debugLevel >= 2 then
        Whorkaround:Log("Scanner: Pulse matched " .. targetName .. ". Attempting scrape...", "LOCAL")
    end

    local _, englishClass, _, englishRace, sex, name = GetPlayerInfoByGUID(targetGUID)

    if name and englishClass then
        -- Mark as seen to throttle further processing of this player
        sessionSeen[targetGUID] = now
        lastScanTime = now 

        local dbKey = name:lower()
        local data = Whorkaround_DB and Whorkaround_DB[dbKey]
        
        -- Only write to DB if data is missing or older than 5 minutes
        if not data or (time() - (data.lastSeen or 0) > 300) then
            Whorkaround_DB[dbKey] = Whorkaround_DB[dbKey] or {}
            local entry = Whorkaround_DB[dbKey]
            
            entry.name = name
            entry.class = englishClass
            entry.race = englishRace or entry.race  -- preserve cached value if GetPlayerInfoByGUID returned nil
            entry.gender = (sex == 2 and "Male") or (sex == 3 and "Female") or "Unknown"
            entry.lastSeen = time()
            entry.source = "Scanner"
            entry.zone = GetRealZoneText()

            -- Smart Level Detection
            local units = {"target", "mouseover", "focus", "party1", "party2", "party3", "party4"}
            for _, unit in ipairs(units) do
                if UnitGUID(unit) == targetGUID then
                    local level = UnitLevel(unit)
                    if level and level > 0 then entry.level = level end
                    break
                end
            end
            -- If level is still unknown (no unit frame matched), mark with sentinel so
            -- the startup cleanup doesn't prune this entry on reload.
            if not entry.level then entry.level = "?" end

            -- Faction Mapping (Primary: Race, Secondary: Reaction Flags)
            if englishRace then
                local raceToFaction = {
                    ["Orc"] = "Horde", ["Scourge"] = "Horde", ["Tauren"] = "Horde", ["Troll"] = "Horde", ["BloodElf"] = "Horde",
                    ["Human"] = "Alliance", ["Dwarf"] = "Alliance", ["NightElf"] = "Alliance", ["Gnome"] = "Alliance", ["Draenei"] = "Alliance"
                }
                entry.faction = raceToFaction[englishRace]
            end

            -- Fallback Faction check via Combat Log Flags (Reaction)
            if not entry.faction and targetFlags then
                local playerFaction = UnitFactionGroup("player")
                local isHostile = bit.band(targetFlags, 0x00000040) > 0 -- HOSTILE
                local isFriendly = bit.band(targetFlags, 0x00000010) > 0 -- FRIENDLY
                
                if playerFaction == "Horde" then
                    if isFriendly then entry.faction = "Horde" elseif isHostile then entry.faction = "Alliance" end
                elseif playerFaction == "Alliance" then
                    if isFriendly then entry.faction = "Alliance" elseif isHostile then entry.faction = "Horde" end
                end
            end

            -- Debug logging (Verbose only for saves)
            if Whorkaround_Settings.debug and debugLevel >= 2 then
                Whorkaround:Log("Scanner: Saved " .. name .. " (Lvl: " .. (entry.level or "??") .. ") in " .. entry.zone, "LOCAL")
            end
        elseif Whorkaround_Settings.debug and debugLevel >= 2 then
            Whorkaround:Log("Scanner: " .. name .. " is already fresh in DB.", "LOCAL")
        end
    elseif Whorkaround_Settings.debug and debugLevel >= 2 then
        Whorkaround:Log("Scanner: Unit Cache miss for " .. targetName .. " (No data returned)", "LOCAL")
    end
end)

-- ---------------------------------------------------------------------------
-- GameTooltip scrape: fires after the tooltip is fully shown, by which point
-- the client has loaded all unit data (race, guild, level, class, faction).
-- OnShow is used instead of OnTooltipSetUnit for 3.3.5 compatibility.
-- GetUnit() filters out non-unit tooltips (items, spells, NPCs) immediately.
-- ---------------------------------------------------------------------------
GameTooltip:HookScript("OnShow", function(self)
    if not Whorkaround_Settings or not Whorkaround_Settings.enableScanner then return end

    local _, unit = self:GetUnit()
    if not unit or not UnitIsPlayer(unit) then return end

    local name = UnitName(unit)
    if not name or name == UNKNOWN or name == UnitName("player") then return end

    local guid = UnitGUID(unit)
    local _, class     = UnitClass(unit)
    local _, raceToken = UnitRace(unit)
    local level        = UnitLevel(unit)
    local guildName    = GetGuildInfo(unit)
    local faction      = UnitFactionGroup(unit)

    -- GUID fallback for race (different cache, sometimes populated when UnitRace is not)
    if not raceToken and guid then
        local _, _, _, gr = GetPlayerInfoByGUID(guid)
        raceToken = gr
    end

    if not class then return end  -- unit cache not usable yet, bail out

    local dbKey = name:lower()
    if not Whorkaround_DB then return end
    Whorkaround_DB[dbKey] = Whorkaround_DB[dbKey] or {}
    local entry = Whorkaround_DB[dbKey]

    local changed = false
    if class                                          then entry.class   = class;     changed = true end
    if raceToken  and raceToken  ~= entry.race        then entry.race    = raceToken; changed = true end
    if guildName  and guildName  ~= entry.guild       then entry.guild   = guildName; changed = true end
    if level and level > 0 and level ~= entry.level   then entry.level   = level;     changed = true end
    if faction    and faction    ~= entry.faction     then entry.faction = faction;   changed = true end

    entry.name     = name
    entry.zone     = GetRealZoneText()
    entry.lastSeen = time()
    entry.source   = "Sighting"

    -- Cancel any pending deferred retry — OnShow is authoritative
    unitRetryFrame.pending[unit] = nil

    if changed and Whorkaround.SyncBrowser then
        Whorkaround:SyncBrowser(false)
    end

    local debugLevel = Whorkaround_Settings.debugLevel or 1
    if Whorkaround_Settings.debug and debugLevel >= 2 then
        Whorkaround:Log("Scanner: Tooltip scrape for " .. name .. " (race=" .. (raceToken or "nil") .. ", guild=" .. (guildName or "nil") .. ")", "LOCAL")
    end
end)

Whorkaround:Log("Scanner module loaded (Disabled by default)", "LOCAL")
