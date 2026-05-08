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

            -- Faction Fallback has been removed!
            -- We CANNOT assume isFriendly means same-faction due to cross-faction groups on Epoch.
            -- We CANNOT assume isHostile means enemy-faction due to duels and FFA PvP zones.
            -- We will simply wait for their race data to load, or for a mouseover/target interaction.

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

-- Per-GUID tooltip cooldown: skip re-scanning a player we just scanned
local tooltipSeen = {}
local TOOLTIP_COOLDOWN = 30  -- seconds

GameTooltip:HookScript("OnShow", function(self)
    if not Whorkaround_Settings or not Whorkaround_Settings.enableScanner then return end

    local _, unit = self:GetUnit()
    if not unit or not UnitIsPlayer(unit) then return end

    local name = UnitName(unit)
    if not name or name == UNKNOWN or name == UnitName("player") then return end

    -- Skip if we've scanned this player recently
    local guid = UnitGUID(unit)
    local now = GetTime()
    if guid and tooltipSeen[guid] and (now - tooltipSeen[guid]) < TOOLTIP_COOLDOWN then return end

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

    -- Mark as seen now so even a no-change pass doesn't re-fire for 30s
    if guid then tooltipSeen[guid] = now end

    local changed = false
    if class        and class        ~= entry.class   then entry.class   = class;     changed = true end
    if raceToken    and raceToken    ~= entry.race     then entry.race    = raceToken; changed = true end
    if guildName    and guildName    ~= entry.guild    then entry.guild   = guildName; changed = true end
    if level and level > 0 and level ~= entry.level   then entry.level   = level;     changed = true end
    if faction      and faction      ~= entry.faction  then entry.faction = faction;   changed = true end

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

-- ---------------------------------------------------------------------------
-- Guild Roster Scanner
-- ---------------------------------------------------------------------------
-- Scans the guild roster on login and whenever GUILD_ROSTER_UPDATE fires
-- (which includes member logins/logouts, independent of the chat notification
-- setting). Throttled to at most GUILD_SCAN_PER_FRAME entries per OnUpdate
-- tick so large guilds never cause a stutter.
-- ---------------------------------------------------------------------------
local GUILD_SCAN_PER_FRAME = 5    -- entries processed per OnUpdate tick (~300/sec at 60fps)
local GUILD_SCAN_COOLDOWN  = 30   -- seconds between event-triggered (non-login) scans
local guildScanLastTime    = 0
local guildLoginScan       = false -- true after login, cleared on first GUILD_ROSTER_UPDATE

local guildScanFrame = CreateFrame("Frame")
guildScanFrame:Hide()
guildScanFrame.idx   = 1
guildScanFrame.total = 0

guildScanFrame:SetScript("OnUpdate", function(self)
    if not Whorkaround_DB then self:Hide(); return end
    local weeks   = (Whorkaround_Settings and Whorkaround_Settings.retentionWeeks) or 4
    local cutoff  = weeks * 7 * 24 * 3600  -- retention window in seconds
    local processed = 0
    while self.idx <= self.total and processed < GUILD_SCAN_PER_FRAME do
        -- Return values: name, rank, rankIndex, level, class, zone, note, officerNote,
        --                online, status, classFileName, achievementPoints, daysOffline
        local name, _, _, level, _, zone, _, _, online, _, classFileName, _, daysOffline = GetGuildRosterInfo(self.idx)
        self.idx    = self.idx + 1
        processed   = processed + 1
        if name and classFileName and classFileName ~= "" then
            -- Skip offline members who haven't been online within the retention window —
            -- adding them would circumvent the DB purge timer for inactive players.
            local tooStale = false
            if not online then
                local secsOffline = (daysOffline or 0) * 86400
                if secsOffline > cutoff then tooStale = true end
            end
            if not tooStale then
                local dbKey = strlower(name)
                Whorkaround_DB[dbKey] = Whorkaround_DB[dbKey] or {}
                local entry = Whorkaround_DB[dbKey]
                -- class and level are always available from the roster cache
                if classFileName ~= entry.class                       then entry.class = classFileName end
                if level and level > 0 and level ~= entry.level       then entry.level = level end
                -- faction/race not available from roster API — filled in by mouseover/tooltip/combat log
                -- zone + lastSeen only updated when the member is currently online
                if online then
                    if zone and zone ~= "" and zone ~= entry.zone     then entry.zone = zone end
                    entry.lastSeen = time()
                    entry.source   = "Guild"
                end
                entry.name = name  -- preserve display-case name
            end
        end
    end
    if self.idx > self.total then
        self:Hide()
        if Whorkaround.SyncBrowser then Whorkaround:SyncBrowser(false) end
        if Whorkaround_Settings and Whorkaround_Settings.debug then
            Whorkaround:Log("Guild scan complete (" .. self.total .. " members).", "LOCAL")
        end
    end
end)

local function StartGuildRosterScan()
    if not GetGuildInfo("player") then return end  -- not in a guild
    local total = GetNumGuildMembers()
    if not total or total == 0 then return end
    guildScanFrame.idx   = 1
    guildScanFrame.total = total
    guildScanLastTime    = GetTime()
    guildScanFrame:Show()
end

local guildEventFrame = CreateFrame("Frame")
guildEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
guildEventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
guildEventFrame:SetScript("OnEvent", function(self, event)
    if not Whorkaround_Settings or not Whorkaround_Settings.enableScanner then return end
    if event == "PLAYER_ENTERING_WORLD" then
        if GetGuildInfo("player") then
            guildLoginScan = true
            GuildRoster()  -- request fresh roster from server; GUILD_ROSTER_UPDATE fires when ready
        end
    elseif event == "GUILD_ROSTER_UPDATE" then
        if guildLoginScan then
            -- First update after login: always scan
            guildLoginScan = false
            StartGuildRosterScan()
        elseif not guildScanFrame:IsShown() and
               (GetTime() - guildScanLastTime) >= GUILD_SCAN_COOLDOWN then
            -- Member logged in or out: re-scan if cooldown expired and no scan running
            StartGuildRosterScan()
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Nameplate Scanner
-- ---------------------------------------------------------------------------
-- Uses the same "count-changed" trick as ElvUI: WorldFrame:GetNumChildren()
-- is called every frame (near-free integer read). GetChildren() is only
-- invoked when a new child appears. Each new nameplate gets a one-time
-- OnShow hook that fires whenever the plate becomes visible, extracting
-- data without any persistent per-frame iteration.
-- ---------------------------------------------------------------------------

-- Build a reverse green-channel → class map from RAID_CLASS_COLORS,
-- identical to ElvUI's approach for enemy nameplate class detection.
local npGreenToClass = {}
for class, color in pairs(RAID_CLASS_COLORS) do
    npGreenToClass[floor(color.g * 100 + 0.5) / 100] = class
end

-- Tracks names seen via nameplates this session so we don't re-fire
-- the extraction for the same player within 60 seconds.
local npSessionSeen = {}
local NP_SEEN_COOLDOWN = 30

-- Cache of party/raid unit tokens by player name for friendly class lookup.
-- Refreshed on group composition events.
local npGroupUnits = {}

local function RefreshGroupUnits()
    wipe(npGroupUnits)
    if GetNumRaidMembers() > 0 then
        for i = 1, 40 do
            local unit = "raid"..i
            if UnitExists(unit) then
                npGroupUnits[UnitName(unit)] = unit
            end
        end
    elseif GetNumPartyMembers() > 0 then
        for i = 1, 4 do
            local unit = "party"..i
            if UnitExists(unit) then
                npGroupUnits[UnitName(unit)] = unit
            end
        end
    end
end

local function OnNameplateShow(plate)
    if not Whorkaround_Settings or not Whorkaround_Settings.enableScanner then return end
    if not Whorkaround_DB then return end

    -- Get the native sub-frames the same way ElvUI does
    local healthBar = plate:GetChildren()   -- first child is always the health StatusBar
    -- ElvUI's OnCreated enumerates regions as:
    -- 1=Threat, 2=Border, 3=CastBarBorder, 4=CastBarShield, 5=CastBarIcon,
    -- 6=Highlight, 7=Name, 8=Level, 9=BossIcon, 10=RaidIcon, 11=EliteIcon
    local name
    -- 1. Try native index 7
    local reg7 = select(7, plate:GetRegions())
    if reg7 and reg7:GetObjectType() == "FontString" then
        name = reg7:GetText()
    end
    -- 2. Try addon-injected .name or .oldName (Kui Nameplates, etc.)
    if (not name or name == "") and plate.name and type(plate.name.GetObjectType) == "function" and plate.name:GetObjectType() == "FontString" then
        name = plate.name:GetText()
    end
    if (not name or name == "") and plate.oldName and type(plate.oldName.GetObjectType) == "function" and plate.oldName:GetObjectType() == "FontString" then
        name = plate.oldName:GetText()
    end
    -- 3. Brute force fallback
    if not name or name == "" then
        for _, r in ipairs({plate:GetRegions()}) do
            if r:GetObjectType() == "FontString" then
                local text = r:GetText()
                if text and text ~= "" and not tonumber(text) and text ~= "??" and text ~= "Boss" then
                    name = text
                    break
                end
            end
        end
    end

    if not name or name == "" then return end
    -- Strip cross-realm suffix (e.g. "-RealmName")
    name = name:match("^([^%-]+)") or name

    -- Throttle: skip if we've seen this name recently
    local now = GetTime()
    if npSessionSeen[name] and (now - npSessionSeen[name]) < NP_SEEN_COOLDOWN then return end

    -- Determine unit type from health bar color (ElvUI's GetUnitInfo logic)
    if not healthBar or healthBar:GetObjectType() ~= "StatusBar" then return end
    local r, g, b = healthBar:GetStatusBarColor()
    local isPlayer, isFriendly
    if r < 0.01 and b > 0.99 and g < 0.01 then
        -- Pure blue: FRIENDLY_PLAYER
        isPlayer  = true
        isFriendly = true
    elseif r < 0.01 and b < 0.01 and g > 0.99 then
        -- Pure green: FRIENDLY_NPC — skip
        return
    elseif r > 0.99 and b < 0.01 then
        -- Red variants: ENEMY_NPC — skip
        return
    elseif r > 0.5 and r < 0.6 and g > 0.5 and g < 0.6 and b > 0.5 and b < 0.6 then
        -- Grey: ENEMY_NPC — skip
        return
    else
        -- Everything else: ENEMY_PLAYER
        isPlayer  = true
        isFriendly = false
    end

    if not isPlayer then return end

    -- Mark seen immediately so overlapping OnShow calls don't double-fire
    npSessionSeen[name] = now

    local dbKey = name:lower()
    Whorkaround_DB[dbKey] = Whorkaround_DB[dbKey] or {}
    local entry = Whorkaround_DB[dbKey]

    -- Only update fields we can actually determine from a nameplate
    entry.name     = name
    entry.lastSeen = time()
    entry.source   = entry.source or "Nameplate"

    -- Level detection (robust)
    local levelRegion = select(8, plate:GetRegions())
    local lvl
    if levelRegion and levelRegion:GetObjectType() == "FontString" then
        lvl = tonumber(levelRegion:GetText())
    end
    if not lvl and plate.level and type(plate.level.GetObjectType) == "function" and plate.level:GetObjectType() == "FontString" then
        lvl = tonumber(plate.level:GetText())
    end
    if lvl and lvl > 0 then entry.level = lvl end

    -- Class detection
    local class
    if isFriendly then
        -- Friendly: try the group unit token first (reliable), then GetPlayerInfoByGUID
        local groupUnit = npGroupUnits[name]
        if groupUnit and UnitExists(groupUnit) and UnitName(groupUnit) == name then
            local _, cls = UnitClass(groupUnit)
            class = cls
            entry.faction = entry.faction or UnitFactionGroup(groupUnit)
        end
        if not class then
            -- Not in group and no unit token available — friendly stranger class
            -- cannot be decoded from the nameplate alone in 3.3.5. It will be
            -- filled in by mouseover/tooltip/combat log when the player interacts.
            -- Check mouseover as a last-ditch: if this player happens to already
            -- be under the cursor right now we can grab it cheaply.
            if UnitIsPlayer("mouseover") and UnitName("mouseover") == name then
                local _, cls = UnitClass("mouseover")
                class = cls
                entry.faction = entry.faction or UnitFactionGroup("mouseover")
            end
        end
        -- We no longer assume entry.faction = UnitFactionGroup("player") here
        -- because cross-faction groups on Epoch mean friendly players can be Horde/Alliance.
    else
        -- Enemy: decode class from green channel of health bar
        local gRounded = floor(g * 100 + 0.5) / 100
        class = npGreenToClass[gRounded]
        -- We CANNOT assume hostile means opposite faction, because same-faction
        -- players can be hostile during duels or in FFA PvP arenas.
        -- Therefore, we leave entry.faction as nil/unknown until we get better data
        -- (e.g. from mouseover/target updating the race).
    end

    if class and class ~= entry.class then
        entry.class = class
    end

    if Whorkaround.SyncBrowser then
        Whorkaround:SyncBrowser(false)
    end

    if Whorkaround_Settings.debug and (Whorkaround_Settings.debugLevel or 1) >= 2 then
        Whorkaround:Log(("Nameplate: %s class=%s faction=%s"):format(
            name, class or "?", entry.faction or "?"), "LOCAL")
    end
end

-- The watcher: throttled to 0.1s, processes ONE WorldFrame child per tick.
-- Cost per tick: one elapsed accumulation, one GetNumChildren(), one select()
-- from GetChildren(), one GetRegions() — all C-side reads, unmeasurable overhead.
local NP_SCAN_INTERVAL = 0.1
local npWatchFrame = CreateFrame("Frame")
npWatchFrame:Hide()
npWatchFrame.t   = 0
npWatchFrame.idx = 1
npWatchFrame:SetScript("OnUpdate", function(self, elapsed)
    self.t = self.t + elapsed
    if self.t < NP_SCAN_INTERVAL then return end
    self.t = 0

    if not Whorkaround_Settings or not Whorkaround_Settings.enableScanner then return end

    local n = WorldFrame:GetNumChildren()
    if n == 0 then return end
    if self.idx > n then self.idx = 1 end

    local plate = select(self.idx, WorldFrame:GetChildren())
    self.idx = self.idx + 1

    if plate and plate:IsVisible() then
        -- Nameplates always have a Texture as their first region (the targeting overlay)
        local region = plate:GetRegions()
        if region and region:GetObjectType() == "Texture" then
            OnNameplateShow(plate)
        end
    end
end)

-- Register group composition events to keep npGroupUnits fresh
local npGroupFrame = CreateFrame("Frame")
npGroupFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
npGroupFrame:RegisterEvent("RAID_ROSTER_UPDATE")
npGroupFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
npGroupFrame:SetScript("OnEvent", function() RefreshGroupUnits() end)

-- Start the watcher after the player enters the world
local npInitFrame = CreateFrame("Frame")
npInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
npInitFrame:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    RefreshGroupUnits()
    npWatchFrame:Show()
end)

Whorkaround:Log("Scanner module loaded (Disabled by default)", "LOCAL")
