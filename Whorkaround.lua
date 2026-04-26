local addonName, Whorkaround = ...

local pendingQueries = {}
local removingFriends = {}
local addedSuppression = {}

-- Class lookup table for 3.3.5 (Project Epoch: No Death Knights)
local localizedClassMap = {
    ["Warrior"] = "WARRIOR", ["Paladin"] = "PALADIN", ["Hunter"] = "HUNTER",
    ["Rogue"] = "ROGUE", ["Priest"] = "PRIEST", ["Shaman"] = "SHAMAN", 
    ["Mage"] = "MAGE", ["Warlock"] = "WARLOCK", ["Druid"] = "DRUID",
}

-- Race to Faction mapping for 3.3.5
local raceFactionMap = {
    ["Human"] = "Alliance", ["Dwarf"] = "Alliance", ["Night Elf"] = "Alliance", ["Gnome"] = "Alliance", ["Draenei"] = "Alliance",
    ["Orc"] = "Horde", ["Undead"] = "Horde", ["Scourge"] = "Horde", ["Tauren"] = "Horde", ["Troll"] = "Horde", ["Blood Elf"] = "Horde",
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
        local name, rank, rankIndex, level, class, zone, note, officernote, online, status, classFileName = GetGuildRosterInfo(i)
        if name and name:match("^([^%-]+)") == targetName then
            if level and level > 0 and class then return level, class, (online and zone or "Offline") end
        end
    end
end

-- Improved Class Color Detector (fast-path + cache + faction detection)
local function GetClassColorCode(className, name)
    if name then
        local units = {"player", "target", "focus", "mouseover", "party1", "party2", "party3", "party4", "raid1", "raid2"}
        for _, unit in ipairs(units) do
            if UnitName(unit) == name then
                local _, classTag = UnitClass(unit)
                local race = UnitRace(unit)
                if classTag then
                    local color = RAID_CLASS_COLORS[classTag]
                    if Whorkaround_DB then
                        Whorkaround_DB[name] = Whorkaround_DB[name] or {}
                        Whorkaround_DB[name].class = classTag
                        Whorkaround_DB[name].level = UnitLevel(unit)
                        Whorkaround_DB[name].faction = raceFactionMap[race] or UnitFactionGroup(unit)
                        Whorkaround_DB[name].lastSeen = time()
                    end
                    if color then return string.format("|cff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255) end
                end
            end
        end
        if not className and Whorkaround.GetElvUIClass then className = Whorkaround:GetElvUIClass(name) end
        if not className and Whorkaround_DB and Whorkaround_DB[name] and Whorkaround_DB[name].class then className = Whorkaround_DB[name].class end
    end
    local tag = localizedClassMap[className] or (className and className:upper())
    local color = RAID_CLASS_COLORS[tag]
    if color then return string.format("|cff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255) end
    return "|cffffffff"
end

-- Function to print the "Who" result
local function PrintWhoResult(name, level, class, area, cached, source, faction)
    local playerFaction = UnitFactionGroup("player")
    local enemyFaction = (playerFaction == "Alliance") and "Horde" or "Alliance"
    local prefix = "|cff1abc9cWhorkaround:|r "
    
    if not faction then
        if level == 0 then faction = enemyFaction
        else faction = playerFaction end
    end

    local msg
    if level == 0 then
        msg = string.format("%s|Hplayer:%s|h[%s]|h: Could not find info, maybe they're %s?", prefix, name, name, faction or enemyFaction)
    else
        level = level or 0; area = area or "Unknown"; class = class or "Unknown"
        local classColor = GetClassColorCode(class, name)
        local levelColor = (level == 60) and "|cffffd100" or "|cffffffff"
        local status = cached and "|cff888888- Offline (Cached)|r" or string.format("- %s", area)
        msg = string.format("%s|Hplayer:%s|h[|r%s%s|r]|h: Level %s%d|r %s%s|r %s", prefix, name, classColor, name, levelColor, level, classColor, class, status)
    end

    if Whorkaround_DB then
        Whorkaround_DB[name] = { class = class, level = level, zone = area, faction = faction, lastSeen = time(), source = source or (cached and "Cache" or "FriendsList") }
    end
    
    -- BROADCAST logic: Broadcast if it's live data OR if it's a manual source (not just a background passive harvest)
    if (not cached or source == "FriendsList" or source == "Manual") and level > 0 and level <= 60 and Whorkaround.Broadcast then 
        Whorkaround:Broadcast(name, level, class, area, faction) 
    end
    DEFAULT_CHAT_FRAME:AddMessage(msg, 1.0, 1.0, 0.0)
end

-- Fallback check for all secondary sources
function Whorkaround:TryAllOtherSources(name, silent)
    local gLevel, gClass, gZone = GetPlayerInfoFromGuild(name)
    if gLevel and gLevel > 0 then
        if not silent then PrintWhoResult(name, gLevel, gClass, gZone, false, "GuildRoster", UnitFactionGroup("player")) end
        return true
    end
    if Whorkaround.GetElvUIClass then Whorkaround:GetElvUIClass(name) end
    local data = Whorkaround_DB and Whorkaround_DB[name]
    if data and data.level and data.level > 0 then
        if not silent then PrintWhoResult(name, data.level, data.class, data.zone, true, data.source, data.faction) end
        return true
    end
    return false
end

-- Statistics Command
function Whorkaround:ShowStats()
    if not Whorkaround_DB then return end
    local total, sources, factions = 0, { FriendsList = 0, GuildRoster = 0, ElvUI = 0, WhorkComm = 0, Cache = 0 }, { Alliance = 0, Horde = 0, Unknown = 0 }
    for name, data in pairs(Whorkaround_DB) do
        if type(data) == "table" then
            total = total + 1
            if data.source and sources[data.source] ~= nil then sources[data.source] = sources[data.source] + 1 end
            if data.faction then factions[data.faction] = (factions[data.faction] or 0) + 1 else factions.Unknown = factions.Unknown + 1 end
        end
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff1abc9cWhorkaround Stats:|r")
    DEFAULT_CHAT_FRAME:AddMessage(string.format("- Total Cached Players: |cffffd100%d|r", total))
    DEFAULT_CHAT_FRAME:AddMessage(string.format("- Factions: Alliance (|cff0070dd%d|r), Horde (|cffff2020%d|r)", factions.Alliance or 0, factions.Horde or 0))
    DEFAULT_CHAT_FRAME:AddMessage("- Sources: Manual: "..sources.FriendsList..", Guild: "..sources.GuildRoster..", ElvUI: "..sources.ElvUI..", Comm: "..sources.WhorkComm)
end

-- System Message Filter
local function SystemMessageFilter(self, event, msg)
    if not msg then return end
    
    -- Suppress Friends List activity
    local nameAdded = msg:match(addedPattern)
    if nameAdded and (pendingQueries[nameAdded] or addedSuppression[nameAdded]) then return true end
    local nameRemoved = msg:match(removedPattern)
    if nameRemoved and removingFriends[nameRemoved] then return true end
    
    -- Suppress "You have joined the channel: WhorkComm" spam
    local chJoined = msg:match(joinPattern)
    if chJoined and (chJoined:find("WhorkComm") or chJoined:find("1. WhorkComm")) then return true end
    local chLeft = msg:match(leavePattern)
    if chLeft and (chLeft:find("WhorkComm") or chLeft:find("1. WhorkComm")) then return true end

    if msg == ERR_FRIEND_NOT_FOUND then
        for name, startTime in pairs(pendingQueries) do if type(startTime) == "number" and GetTime() - startTime < 1 then return true end end
    end
end
ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", SystemMessageFilter)

-- Event handling
local frame = CreateFrame("Frame")
frame:RegisterEvent("FRIENDLIST_UPDATE"); frame:RegisterEvent("CHAT_MSG_SYSTEM"); frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnUpdate", function(self, elapsed)
    self.timer = (self.timer or 0) + elapsed
    if self.timer > 0.1 then
        self.timer = 0; local now = GetTime()
        for name, startTime in pairs(pendingQueries) do
            if type(startTime) == "number" then
                local diff = now - startTime
                if diff > 0.3 and pendingQueries[name] ~= "TIMEOUT" then
                    local found = Whorkaround:TryAllOtherSources(name, pendingQueries[name] == "SILENT")
                    if found then pendingQueries[name] = "TIMEOUT"; removingFriends[name] = GetTime(); RemoveFriend(name) end
                end
                if diff > 5 then pendingQueries[name] = nil; addedSuppression[name] = nil; removingFriends[name] = nil end
            end
        end
    end
end)

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...; if name == "Whorkaround" then 
            Whorkaround_DB = Whorkaround_DB or {}
            Whorkaround_Settings = Whorkaround_Settings or { overrideWho = true }
            self:UnregisterEvent("ADDON_LOADED") 
        end
    elseif event == "FRIENDLIST_UPDATE" then
        for i = 1, GetNumFriends() do
            local name, level, class, area, connected = GetFriendInfo(i)
            if name and pendingQueries[name] and pendingQueries[name] ~= "TIMEOUT" then
                if connected then
                    if pendingQueries[name] ~= "SILENT" then PrintWhoResult(name, level, class, area, false, "FriendsList") end
                    removingFriends[name] = GetTime(); RemoveFriend(name); pendingQueries[name] = nil
                end
            end
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        local msg = ...; if msg == ERR_FRIEND_NOT_FOUND then for name in pairs(pendingQueries) do if pendingQueries[name] ~= "TIMEOUT" then Whorkaround:TryAllOtherSources(name) end; pendingQueries[name] = nil end end
    end
end)

function Whorkaround:Query(name, silent)
    if not name or name == "" then return end
    name = name:gsub("^%s*(.-)%s*$", "%1"):lower():gsub("^%l", string.upper)
    if pendingQueries[name] then return end -- Already querying
    pendingQueries[name] = silent and "SILENT" or GetTime(); addedSuppression[name] = GetTime(); AddFriend(name); ShowFriends() 
end

local function GetFocusedEditBox()
    for i = 1, 10 do local eb = _G["ChatFrame"..i.."EditBox"]; if eb and eb:HasFocus() then return eb end end
    if ChatFrameEditBox and ChatFrameEditBox:HasFocus() then return ChatFrameEditBox end
end

-- Smarter Chat Link Filter
local function ChatLinkFilter(self, event, msg, ...)
    if type(msg) == "string" and (msg:find("%[") or msg:find("@")) then
        msg = msg:gsub("(|H.-|h.-|h)", function(link) return link:gsub("%[", "\002"):gsub("%]", "\003"):gsub("@", "\004") end)
        local function ReplacementFunc(name)
            local data = Whorkaround_DB and Whorkaround_DB[name]
            local color = GetClassColorCode(data and data.class, name)
            return string.format("|Hplayer:%s|h[|r%s%s|r]|h", name, color, name)
        end
        msg = msg:gsub("%[([%a]+)%]", ReplacementFunc)
        msg = msg:gsub("@([%a]+)", ReplacementFunc)
        msg = msg:gsub("\002", "["):gsub("\003", "]"):gsub("\004", "@")
        return false, msg, ...
    end
end
local chatEvents = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL", "CHAT_MSG_EMOTE" }
for _, event in ipairs(chatEvents) do ChatFrame_AddMessageEventFilter(event, ChatLinkFilter) end

-- Proactive Background Query while typing
local function OnEditBoxTextChanged(self)
    local text = self:GetText()
    if not text then return end
    local function TriggerQuery(name)
        local data = Whorkaround_DB and Whorkaround_DB[name]
        if not data or (time() - (data.lastSeen or 0) > 3600) then Whorkaround:Query(name, true) end
    end
    for name in text:gmatch("%[([%a]+)%]") do TriggerQuery(name) end
    for name in text:gmatch("@([%a]+)%s") do TriggerQuery(name) end
end

-- Save native handlers
local nativeWho = SlashCmdList["WHO"]

local function HookChat()
    local orig = ChatFrame_OnHyperlinkShow
    ChatFrame_OnHyperlinkShow = function(...)
        local link, text, button; local arg1 = ...
        if type(arg1) == "table" then _, link, text, button = ... else link, text, button = ... end
        local focus = GetFocusedEditBox()
        if type(link) == "string" and link:sub(1, 7) == "player:" then
            local name = link:match("player:([^:]+)")
            if name then
                if IsShiftKeyDown() then
                    if focus then
                        Whorkaround:Query(name, true)
                        focus:Insert(string.format("[%s]", name))
                    else
                        Whorkaround:Query(name)
                    end
                    return
                elseif button == "RightButton" then FriendsFrame_ShowDropdown(name, 1); return end
            end
        end
        return orig(...)
    end
    for i = 1, 10 do local eb = _G["ChatFrame"..i.."EditBox"]; if eb then eb:HookScript("OnTextChanged", OnEditBoxTextChanged) end end
    if ChatFrameEditBox then ChatFrameEditBox:HookScript("OnTextChanged", OnEditBoxTextChanged) end
end
HookChat()

SLASH_WHORK1 = "/whork"; SLASH_WHORK2 = "/whorkaround"; SLASH_WHORK3 = "/whom"; SLASH_WHORK4 = "/who"; SLASH_WSTATS1 = "/whostats"; SLASH_WTOGGLE1 = "/whotoggle"; SLASH_WCLEAR1 = "/whocleardb"; SLASH_WDEBUG1 = "/whodebug"

SlashCmdList["WHORK"] = function(msg) Whorkaround:Query(msg) end
SlashCmdList["WHO"] = function(msg)
    if Whorkaround_Settings and Whorkaround_Settings.overrideWho then
        Whorkaround:Query(msg)
    elseif nativeWho then nativeWho(msg)
    else SendWho(msg) end
end
SlashCmdList["WSTATS"] = function() Whorkaround:ShowStats() end
SlashCmdList["WTOGGLE"] = function()
    Whorkaround_Settings.overrideWho = not Whorkaround_Settings.overrideWho
    local status = Whorkaround_Settings.overrideWho and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"
    DEFAULT_CHAT_FRAME:AddMessage("|cff1abc9cWhorkaround:|r /who override is now " .. status)
end
SlashCmdList["WCLEAR"] = function()
    Whorkaround_DB = {}
    DEFAULT_CHAT_FRAME:AddMessage("|cff1abc9cWhorkaround:|r Player database has been cleared.")
end
SlashCmdList["WDEBUG"] = function()
    if Whorkaround.CheckComm then Whorkaround:CheckComm() 
    else DEFAULT_CHAT_FRAME:AddMessage("|cff1abc9cWhorkaround:|r Comm module not loaded!") end
end

print("|cff1abc9cWhorkaround|r loaded. Use /whodebug to check network.")
