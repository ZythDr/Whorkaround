-- LibWho-Compat.lua  (Whorkaround_LibWho)
--
-- Registers a WIM module that fires on every whisper window creation to
-- trigger a live Whorkaround lookup, bypassing WIM's "Who Lookups" setting
-- and LibWho-2.0 entirely.  Also pre-populates LibWho's cache at login so
-- any other LibWho-2.0 consumer (not just WIM) gets class/level/race data.
--
-- Flow
-- ----
-- 1. PLAYER_LOGIN
--    - Pre-populate LibWho-2.0's internal cache from Whorkaround_DB.
--    - Register our module into WIM.modules so CallModuleFunction fires it.
--
-- 2. OnWindowCreated (fires for every whisper window WIM opens)
--    - Serve whatever Whorkaround_DB already has -> WIM shows data instantly.
--    - Wrap obj.SendWho so the "click to update" button also triggers us.
--    - Call Whorkaround:Query() for a live lookup (friends list / WhorkComm).
--    - Register a watcher to re-fire WhoCallback when Whorkaround writes
--      newer data (covers both first-time players and stale cache).
--
-- 3. Watcher frame
--    - Polls Whorkaround_DB twice per second.
--    - When an entry's lastSeen advances past the snapshot taken at query
--      time, WIM's WhoCallback is called again with the fresh data.

-- ── Constants ─────────────────────────────────────────────────────────────

-- How long to wait for Whorkaround to come back with data (seconds).
-- Whorkaround's friends-list path resolves in ~1-2 s; WhorkComm ~5 s.
local REFRESH_DEADLINE_SEC = 8

-- ── Race token (UnitRace English 2nd return) -> display name ─────────────
local RACE_DISPLAY = {
    Human    = "Human",
    Dwarf    = "Dwarf",
    NightElf = "Night Elf",
    Gnome    = "Gnome",
    Draenei  = "Draenei",
    Orc      = "Orc",
    Scourge  = "Undead",    -- Forsaken token is "Scourge"
    Tauren   = "Tauren",
    Troll    = "Troll",
    BloodElf = "Blood Elf",
}

-- ── Helpers ───────────────────────────────────────────────────────────────

local function LocalizeClass(token)
    if not token then return "" end
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or token
end

local function GetWhorkaroundAPI()
    local api = _G and _G.WhorkaroundAPI
    if api and type(api.Query) == "function" then
        return api
    end
end

local function GetEntry(name)
    local api = GetWhorkaroundAPI()
    if api and type(api.GetEntry) == "function" then
        local entry = api.GetEntry(name)
        if entry then
            return entry
        end
    end
    if type(name) ~= "string" then return nil end
    local key = name:lower()
    return Whorkaround_DB and Whorkaround_DB[key]
end

-- We need at least class or level to show something useful in WIM.
local function HasMinimalData(entry)
    return entry ~= nil and (entry.class ~= nil or entry.level ~= nil)
end

-- Capitalise first letter, lower-case rest.
local function CapFirst(s)
    if not s or s == "" then return s end
    return s:sub(1,1):upper() .. s:sub(2):lower()
end

-- Build a LibWho-2.0 result table from a Whorkaround_DB entry.
-- name must exactly match win.theUser (WIM checks result.Name == obj.theUser).
local function BuildResult(name, entry)
    return {
        Name   = name,
        Online = true,
        Class  = LocalizeClass(entry and entry.class),
        Level  = (entry and entry.level) or "",
        Race   = (entry and entry.race and RACE_DISPLAY[entry.race]) or (entry and entry.faction) or "",
        Guild  = (entry and entry.guild) or "",
        Zone   = (entry and entry.zone) or "",  -- Whorkaround now supplies zone from cache
    }
end

-- ── LibWho-2.0 cache injection (secondary, for non-WIM consumers) ─────────

local libWho   -- set at PLAYER_LOGIN if LibWho-2.0 is available

local function InjectLibWhoCache(result, lastSeen)
    if not libWho then return end
    local name = result.Name
    if not libWho.Cache[name] then
        libWho.Cache[name] = { callback = {} }
    end
    local slot   = libWho.Cache[name]
    slot.valid   = true
    slot.inqueue = false
    slot.data    = result
    slot.last    = lastSeen or time()
end

-- ── Pending-callback table ────────────────────────────────────────────────
-- pendingCallbacks[nameLower] = {
--   callbacks   = array of { callback = WhoCallback, name = win.theUser },
--   snapshotAge = entry.lastSeen when the lookup was started
--                 (0 = no existing data; fires on first write for this name),
--   deadline    = GetTime() value after which we give up,
-- }
local pendingCallbacks = {}

-- ── Watcher frame ─────────────────────────────────────────────────────────

local watchFrame = CreateFrame("Frame")
watchFrame:Hide()
watchFrame:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + elapsed
    if self.t < 0.5 then return end
    self.t = 0

    local now     = GetTime()
    local anyLeft = false

    for nameLower, pending in pairs(pendingCallbacks) do
        local entry = GetEntry(nameLower)
        if entry and HasMinimalData(entry) and (entry.lastSeen or 0) > pending.snapshotAge then
            -- Fresh data arrived. Build result and push to all waiting windows.
            for _, watcher in ipairs(pending.callbacks) do
                local result = BuildResult(watcher.name, entry)
                InjectLibWhoCache(result, entry.lastSeen)
                watcher.callback(result)
            end
            pendingCallbacks[nameLower] = nil
        elseif now > pending.deadline then
            pendingCallbacks[nameLower] = nil   -- timed out; give up silently
        else
            anyLeft = true
        end
    end

    if not anyLeft then self:Hide() end
end)

-- ── Core lookup trigger ───────────────────────────────────────────────────

-- Register (or update) the watcher for a name/callback pair.
-- Handles multiple open windows for the same player and repeated "click to
-- update" presses by de-duplicating callbacks and resetting the deadline.
local function RegisterWatcher(nameLower, whoCb, expectedName, snapshotAge)
    local pending = pendingCallbacks[nameLower]
    if pending then
        pending.snapshotAge = math.min(pending.snapshotAge, snapshotAge)
        pending.deadline    = GetTime() + REFRESH_DEADLINE_SEC
        local found = false
        for _, watcher in ipairs(pending.callbacks) do
            if watcher.callback == whoCb and watcher.name == expectedName then
                found = true
                break
            end
        end
        if not found then
            table.insert(pending.callbacks, {
                callback = whoCb,
                name = expectedName,
            })
        end
    else
        pendingCallbacks[nameLower] = {
            callbacks   = {
                {
                    callback = whoCb,
                    name = expectedName,
                },
            },
            snapshotAge = snapshotAge,
            deadline    = GetTime() + REFRESH_DEADLINE_SEC,
        }
    end
    watchFrame:Show()
end

-- Called on window creation and on every "click to update".
-- Serves cached data immediately, triggers a live Whorkaround lookup,
-- and registers a watcher to push the result to WIM when it arrives.
local function TriggerForWindow(win, forceRefresh)
    if not win or not win.theUser then return end

    local name      = win.theUser          -- use WIM's own name verbatim
    local nameLower = name:lower()
    local entry     = GetEntry(name)

    local snapshotAge = (entry and entry.lastSeen) or 0

    -- Serve whatever we already have so WIM shows something immediately.
    if HasMinimalData(entry) then
        local result = BuildResult(name, entry)
        InjectLibWhoCache(result, entry.lastSeen)
        win.WhoCallback(result)
    end

    local api = GetWhorkaroundAPI()
    if not api then return end

    -- Trigger a live Whorkaround lookup every time.
    -- Query() runs: unit frames -> guild roster -> friends list (AddFriend)
    --   -> WhorkComm broadcast to peers.
    -- Forced refreshes can use the smarter API path for enemy-faction players.
    local displayName = (entry and entry.name) or CapFirst(name)
    if forceRefresh and type(api.Refresh) == "function" then
        api.Refresh(displayName, true)
    else
        api.Query(displayName, true)   -- silent=true suppresses chat output
    end

    -- Register the watcher so WIM re-fires when Whorkaround writes new data.
    RegisterWatcher(nameLower, win.WhoCallback, name, snapshotAge)
end

-- ── WIM module ────────────────────────────────────────────────────────────
-- WIM calls CallModuleFunction("OnWindowCreated", obj) every time a whisper
-- window frame is assigned to a user -- both for recycled soup-bowl frames
-- and freshly created ones -- AFTER theUser, type, and WhoCallback are set.

local WhorkaroundModule = {
    enabled    = true,
    canDisable = false,   -- always active; no WIM options entry

    OnWindowCreated = function(self, win)
        if win.type ~= "whisper" or win.isBN or win.isGM then return end

        if not win.__WhorkaroundLibWhoOrigSendWho then
            win.__WhorkaroundLibWhoOrigSendWho = win.SendWho
        end

        -- Wrap SendWho so WIM's "click to update" location shortcut button
        -- always triggers our lookup path, regardless of db.whoLookups or
        -- whether libs.WhoLib is available.
        win.SendWho = function(self)
            win.__WhorkaroundLibWhoOrigSendWho(self)  -- let WIM try its own LibWho path
            TriggerForWindow(self, true)  -- also trigger Whorkaround directly
        end

        -- Trigger on window open.
        TriggerForWindow(win, false)
    end,
}

-- ── Bootstrap ─────────────────────────────────────────────────────────────
-- By PLAYER_LOGIN all addons have executed their top-level Lua, so:
--   - Whorkaround_DB (SavedVariables) is fully loaded.
--   - WIM.modules exists and WIM.initialize() has already run.
--   - LibWho-2.0 (embedded in WIM) is registered in LibStub.

local shimFrame = CreateFrame("Frame")
shimFrame:RegisterEvent("PLAYER_LOGIN")
shimFrame:SetScript("OnEvent", function(self, event)
    self:UnregisterEvent("PLAYER_LOGIN")

    -- Secondary: seed LibWho-2.0's cache for any non-WIM consumers.
    if LibStub then
        local ok, l = pcall(LibStub.GetLibrary, LibStub, "LibWho-2.0")
        if ok and l and type(l.UserInfo) == "function" then
            libWho = l
            if Whorkaround_DB then
                for _, entry in pairs(Whorkaround_DB) do
                    if entry.name and HasMinimalData(entry) then
                        InjectLibWhoCache(BuildResult(entry.name, entry), entry.lastSeen)
                    end
                end
            end
        end
    end

    -- Primary: register our WIM module.
    -- CallModuleFunction iterates WIM.modules and calls
    -- tData[funName](tData, ...) for every entry with .enabled == true.
    if _G.WIM and _G.WIM.modules then
        _G.WIM.modules["WhorkaroundLibWho"] = WhorkaroundModule
    end
end)
