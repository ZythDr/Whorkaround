local addonName, Whorkaround = ...

-- ----------------------------------------------------------------------------
-- MentionHyperlinks Module (opt-in)
-- ----------------------------------------------------------------------------
-- Enables two convenience features when the "Chat Links" setting is turned on:
--
--   1. [Name] / @Name auto-linking in outgoing chat messages.
--      Any word written as [Name] or @Name in a chat box is replaced with a
--      clickable |Hplayer: hyperlink coloured by the player's class.
--
--   2. Shift-click on a player link inserts [Name] into the active edit box
--      instead of the default behaviour.
--
-- All WoW hooks are registered at load time (they cannot be reversed), but
-- every handler returns immediately when the setting is disabled, so there is
-- zero runtime cost when the feature is off.
-- ----------------------------------------------------------------------------

local function IsEnabled()
    return Whorkaround_Settings and Whorkaround_Settings.mentionHyperlinks
end

-- ---------------------------------------------------------------------------
-- Edit-box text scanner: silently pre-queries names typed as [Name] / @Name
-- so the DB is warm when the message is sent.
-- ---------------------------------------------------------------------------

-- Per-editbox cache: tracks names already queried since this editbox was opened.
-- Cleared on hide (after send or Escape), so the next time the box opens each
-- name gets exactly one fresh query. Prevents infinite re-querying on no-result names.
local editBoxQueried = {}  -- [editBox] = { [dbKey] = true }

local function OnEditBoxTextChanged(self)
    if not IsEnabled() then return end
    local text = self:GetText()
    if not text or text == "" then return end

    -- Strip |H...|h[...]|h hyperlink sequences (spell/item/achievement links)
    -- before pattern matching so they are never mistaken for player mentions.
    local plain = text:gsub("|H[^|]+|h%[[^%]]+%]|h", "")
                      :gsub("|c%x+", ""):gsub("|r", "")

    local queried = editBoxQueried[self]
    if not queried then
        queried = {}
        editBoxQueried[self] = queried
    end

    local function TriggerQuery(name)
        local dbKey = name:lower():gsub("^%s*(.-)%s*$", "%1")
        if queried[dbKey] then return end
        queried[dbKey] = true
        local data = Whorkaround_DB and Whorkaround_DB[dbKey]
        if not data or (time() - (data.lastSeen or 0) > 60) then
            if Whorkaround.DebugMode or (Whorkaround_Settings and Whorkaround_Settings.debug) then
                Whorkaround:Log("Mention pre-query: " .. name, "LOCAL")
            end
            Whorkaround:Query(dbKey, true)
        end
    end

    for name in plain:gmatch("%[([%a]+)%]") do TriggerQuery(name) end
    local startName = plain:match("^@([%a]+)%s")
    if startName then TriggerQuery(startName) end
    for name in plain:gmatch("%s@([%a]+)%s") do TriggerQuery(name) end
end

-- ---------------------------------------------------------------------------
-- Hyperlink click handler: shift-click inserts [Name] into the edit box.
-- ---------------------------------------------------------------------------
local function HookHyperlinkClick()
    local orig = ChatFrame_OnHyperlinkShow
    ChatFrame_OnHyperlinkShow = function(...)
        local link, text, button
        local arg1 = ...
        if type(arg1) == "table" then
            _, link, text, button = ...
        else
            link, text, button = ...
        end

        if type(link) == "string" and link:sub(1, 7) == "player:" then
            local name = link:match("player:([^:]+)")
            if name then
                if IsShiftKeyDown() then
                    local eb = ChatEdit_GetActiveWindow()
                    if eb then
                        -- Always insert into the edit box when it's open; never query.
                        -- Mention Links on → [Name] syntax (the outgoing filter turns it into a hyperlink).
                        -- Mention Links off → plain Name, matching default WoW behaviour.
                        if IsEnabled() then
                            eb:Insert("[" .. name:gsub("^%l", string.upper) .. "]")
                        else
                            eb:Insert(name:gsub("^%l", string.upper))
                        end
                        return
                    end
                    -- No edit box focused → query the player.
                    Whorkaround:Query(name)
                    return
                elseif button == "RightButton" then
                    FriendsFrame_ShowDropdown(name, 1)
                    return
                end
            end
        end
        return orig(...)
    end

    -- Hook every chat edit box so OnTextChanged fires for mention scanning.
    for i = 1, 10 do
        local eb = _G["ChatFrame" .. i .. "EditBox"]
        if eb then
            eb:HookScript("OnTextChanged", OnEditBoxTextChanged)
            -- Clear the per-open cache when the box closes (send or Escape)
            eb:HookScript("OnHide", function(self)
                editBoxQueried[self] = nil
            end)
        end
    end
end
HookHyperlinkClick()

-- ---------------------------------------------------------------------------
-- Outgoing message filter: rewrites [Name] and @Name in chat as clickable
-- class-coloured player hyperlinks before the message is displayed locally.
-- ---------------------------------------------------------------------------
local function ChatLinkFilter(self, event, msg, ...)
    if not IsEnabled() then return end
    if type(msg) ~= "string" then return end
    if not msg:find("%[") and not msg:find("@") then return end

    -- Protect existing hyperlinks: temporarily escape their brackets/@ chars
    -- so the replacement patterns below don't touch them.
    msg = msg:gsub("(|H.-|h.-|h)", function(link)
        return link:gsub("%[", "\002"):gsub("%]", "\003"):gsub("@", "\004")
    end)

    local function ReplaceBracket(name)
        local dbKey = name:lower()
        local data = Whorkaround_DB and Whorkaround_DB[dbKey]
        local color = Whorkaround.GetClassColorCode(data and data.class, name)
        local displayName = name:gsub("^%l", string.upper)
        return string.format("|Hplayer:%s|h%s[%s]|r|h", name, color, displayName)
    end

    local function ReplaceAt(name)
        local dbKey = name:lower()
        local data = Whorkaround_DB and Whorkaround_DB[dbKey]
        local color = Whorkaround.GetClassColorCode(data and data.class, name)
        local displayName = name:gsub("^%l", string.upper)
        return string.format("|Hplayer:%s|h%s@%s|r|h", name, color, displayName)
    end

    msg = msg:gsub("%[([%a]+)%]", ReplaceBracket)
    msg = msg:gsub("^@([%a]+)", ReplaceAt)
    msg = msg:gsub("(%s)@([%a]+)", function(space, name) return space .. ReplaceAt(name) end)

    -- Restore the escaped characters inside existing hyperlinks.
    msg = msg:gsub("\002", "["):gsub("\003", "]"):gsub("\004", "@")
    return false, msg, ...
end

local chatEvents = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_CHANNEL", "CHAT_MSG_EMOTE",
}
for _, event in ipairs(chatEvents) do
    ChatFrame_AddMessageEventFilter(event, ChatLinkFilter)
end
