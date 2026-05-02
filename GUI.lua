local addonName, Whorkaround = ...

StaticPopupDialogs["WHORKAROUND_CONFIRM_CLEAR"] = {
    text = "Are you sure you want to clear your entire Whorkaround database?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        Whorkaround_DB = {}
        if Whorkaround.SyncBrowser then Whorkaround:SyncBrowser() end
        if Whorkaround.UpdateStats then Whorkaround:UpdateStats() end
        print("|cff1abc9cWhorkaround:|r Database cleared.")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function CreateCheckBox(parent, label, setting, tooltip)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    check.text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    check.text:SetPoint("LEFT", check, "RIGHT", 5, 0)
    check.text:SetText(label)

    check:SetScript("OnShow", function(self)
        self:SetChecked(Whorkaround_Settings[setting])
    end)

    check:SetScript("OnClick", function(self)
        Whorkaround_Settings[setting] = self:GetChecked()
        PlaySound(self:GetChecked() and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
    end)

    if tooltip then
        check:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    return check
end

local function CreateButton(parent, label, width, height)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width or 120, height or 22)
    btn:SetText(label)
    return btn
end

local function CreateEditBox(parent, label, setting, tooltip, name)
    -- Fixed: Give it a name so ElvUI can find and hide the "Left/Middle/Right" textures
    local eb = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
    eb:SetSize(140, 20); eb:SetAutoFocus(false)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetTextInsets(8, 8, 0, 0)
    
    local text = eb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("BOTTOMLEFT", eb, "TOPLEFT", 0, 2); text:SetText(label)
    eb.label = text

    eb:SetScript("OnShow", function(self) self:SetText(Whorkaround_Settings[setting] or "") end)
    eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    eb:SetScript("OnEnterPressed", function(self)
        Whorkaround_Settings[setting] = self:GetText()
        self:ClearFocus()
        print("|cff1abc9cWhorkaround:|r " .. label .. " set to: |cffffd100" .. (Whorkaround_Settings[setting] ~= "" and Whorkaround_Settings[setting] or "Default") .. "|r")
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    if tooltip then
        eb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true); GameTooltip:Show()
        end)
        eb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    return eb
end

local sliderCount = 0
local function CreateSlider(parent, label, setting, minVal, maxVal, step, unit, tooltip)
    sliderCount = sliderCount + 1
    local slider = CreateFrame("Slider", "WhorkaroundSlider" .. sliderCount, parent, "OptionsSliderTemplate")
    slider:SetWidth(125); slider:SetMinMaxValues(minVal, maxVal); slider:SetValueStep(step or 1)
    _G[slider:GetName() .. "Low"]:SetText(minVal); _G[slider:GetName() .. "High"]:SetText(maxVal)

    local text = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("BOTTOM", slider, "TOP", 0, 5)

    local function UpdateText(val)
        text:SetText(string.format("%s: %d %s", label, val, unit or ""))
    end

    slider:SetScript("OnShow", function(self)
        local val = Whorkaround_Settings[setting] or maxVal
        self:SetValue(val); UpdateText(val)
    end)

    slider:SetScript("OnValueChanged", function(self, value)
        local val = math.floor(value + 0.5)
        Whorkaround_Settings[setting] = val
        UpdateText(val)
    end)

    if tooltip then
        slider:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        slider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    return slider
end

function Whorkaround:InitGUI()
    if self.GUI then return end
    self.GUI = true
    local components = {}

    local function CreateInlineEditBox(parent, label, setting, tooltip)
        local container = CreateFrame("Frame", nil, parent)
        container:SetSize(250, 26)
        local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", 0, 0); text:SetText(label)
        local eb = CreateFrame("EditBox", "WhorkaroundFreqEditBox", container, "InputBoxTemplate")
        eb:SetSize(30, 20); eb:SetPoint("LEFT", text, "RIGHT", 10, 0); eb:SetAutoFocus(false); eb:SetJustifyH("CENTER")
        eb:SetScript("OnShow", function(self) self:SetText(Whorkaround_Settings[setting] or "1.0") end)
        eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        eb:SetScript("OnEnterPressed", function(self)
            local val = tonumber(self:GetText())
            if val and val >= 0.1 then
                Whorkaround_Settings[setting] = val
            else
                self:SetText(Whorkaround_Settings
                    [setting] or "1.0")
            end
            self:ClearFocus()
        end)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        if tooltip then
            eb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(label, 1, 1, 1)
                GameTooltip:AddLine(tooltip, nil, nil, nil, true); GameTooltip:Show()
            end)
            eb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        return container
    end

    local tab1, tab2, settings, browserFactionColors
    local browserStatsAlliance, browserStatsHorde, browserStatsSeparator
    local browserStatsAllianceHit, browserStatsHordeHit
    local statsTotal, statsNetwork

    -- Browser-specific Faction Colors toggle (Repositioned to right side)
    browserFactionColors = CreateCheckBox(WhoFrame, "Faction Colors", "factionColors",
        "Colors names by faction in the browser.")
    browserFactionColors:SetPoint("TOPRIGHT", WhoFrame, "TOPRIGHT", -35, -32)
    browserFactionColors.text:ClearAllPoints()
    browserFactionColors.text:SetPoint("RIGHT", browserFactionColors, "LEFT", -2, 0)
    browserFactionColors:SetFrameLevel(WhoFrame:GetFrameLevel() + 5)
    browserFactionColors:Hide()
    components.browserFactionColors = browserFactionColors

    -- Browser Faction Counters (Conditional Positioning)
    browserStatsSeparator = WhoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    browserStatsSeparator:SetPoint("TOP", WhoFrame, "TOP", 0, -55)
    browserStatsSeparator:SetText("|")
    browserStatsSeparator:SetTextColor(0.5, 0.5, 0.5)
    browserStatsSeparator:Hide()
    components.browserStatsSeparator = browserStatsSeparator

    browserStatsAlliance = WhoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    browserStatsAlliance:SetPoint("RIGHT", browserStatsSeparator, "LEFT", -5, 0)
    browserStatsAlliance:SetJustifyH("RIGHT")
    browserStatsAlliance:Hide()
    components.browserStatsAlliance = browserStatsAlliance

    browserStatsHorde = WhoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    browserStatsHorde:SetPoint("LEFT", browserStatsSeparator, "RIGHT", 5, 0)
    browserStatsHorde:SetJustifyH("LEFT")
    browserStatsHorde:Hide()
    components.browserStatsHorde = browserStatsHorde

    -- Tooltip Hitboxes
    browserStatsAllianceHit = CreateFrame("Frame", nil, WhoFrame)
    browserStatsAllianceHit:SetSize(40, 20); browserStatsAllianceHit:SetPoint("CENTER", browserStatsAlliance); browserStatsAllianceHit
        :EnableMouse(true); browserStatsAllianceHit:Hide()
    browserStatsAllianceHit:SetFrameLevel(WhoFrame:GetFrameLevel() + 10)
    browserStatsAllianceHit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Cached Alliance Players", 0, 0.44, 0.87)
        GameTooltip:Show()
    end)
    browserStatsAllianceHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    components.browserStatsAllianceHit = browserStatsAllianceHit

    browserStatsHordeHit = CreateFrame("Frame", nil, WhoFrame)
    browserStatsHordeHit:SetSize(40, 20); browserStatsHordeHit:SetPoint("CENTER", browserStatsHorde); browserStatsHordeHit
        :EnableMouse(true); browserStatsHordeHit:Hide()
    browserStatsHordeHit:SetFrameLevel(WhoFrame:GetFrameLevel() + 10)
    browserStatsHordeHit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Cached Horde Players", 1, 0.13, 0.13)
        GameTooltip:Show()
    end)
    browserStatsHordeHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    components.browserStatsHordeHit = browserStatsHordeHit

    -- Settings Panel
    settings = CreateFrame("Frame", "WhorkaroundSettingsPanel", WhoFrame)
    settings:SetPoint("TOPLEFT", WhoFrame, "TOPLEFT", 14, -70)
    settings:SetPoint("BOTTOMRIGHT", WhoFrame, "BOTTOMRIGHT", -38, 79)
    settings:SetFrameStrata(WhoFrame:GetFrameStrata())
    settings:SetFrameLevel(WhoFrame:GetFrameLevel() + 50)
    settings:EnableMouse(true)
    settings:Hide()

    local bg = settings:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetTexture(0, 0, 0, 0.85)

    ---------------------------------------------------------
    -- PIGGYBACK LOGIC (Helpers moved up for SyncUI scope)
    ---------------------------------------------------------
    local currentSortKey = "seen"
    local currentSortOrder = "DESC"

    local function GetRelativeTime(ts)
        if not ts or ts == 0 then return "Unknown" end
        local diff = time() - ts
        if diff < 60 then
            return "Just now"
        elseif diff < 3600 then
            return math.floor(diff / 60) .. "m ago"
        elseif diff < 86400 then
            return math.floor(diff / 3600) .. "h ago"
        else
            return math.floor(diff / 86400) .. "d ago"
        end
    end

    -- Formats a level value (number, "?", or nil/0) for display.
    local function DisplayLevel(lvl)
        if type(lvl) == "number" and lvl > 0 then return tostring(lvl) end
        if lvl == "?" then return "?" end
        return "??"
    end

    -- Browser Memory Optimization: Recyclable table pool
    local browserData = {}
    local browserPool = {}
    local function GetPoolTable()
        local t = table.remove(browserPool) or {}
        return t
    end
    local function ReleasePoolTables()
        for i = #browserData, 1, -1 do
            local t = table.remove(browserData)
            wipe(t)
            table.insert(browserPool, t)
        end
    end

    local function Whorkaround_WhoList_Update()
        if not tab1 or not tab1:GetChecked() then return end

        local rawQuery = WhoFrameEditBox:GetText() or ""
        local query = rawQuery:lower()
        
        -- Parse search mode and field prefix
        local isExactMatch = false
        local fieldPrefix = nil
        local searchTerm = query
        
        -- Detect exact match: "query"
        if query:match('^"(.*)"$') then
            isExactMatch = true
            searchTerm = query:match('^"(.*)"$')
        -- Detect field prefix: g:value, r:value, z:value, c:value, n:value
        elseif query:match("^([gnrcz]):(.+)$") then
            fieldPrefix, searchTerm = query:match("^([gnrcz]):(.+)$")
        end
        
        -- Level range matching (e.g., "10-20")
        local minL, maxL = query:match("(%d+)%-(%d+)")
        if minL and maxL then minL, maxL = tonumber(minL), tonumber(maxL) end

        ReleasePoolTables()
        if Whorkaround_DB then
            for name, entry in pairs(Whorkaround_DB) do
                local level = entry.level or 0
                local levelStr = tostring(level)
                local match = false
                
                -- Level range search
                if minL and maxL then
                    if level >= minL and level <= maxL then match = true end
                -- Empty query matches all
                elseif query == "" then
                    match = true
                -- Field-prefixed search
                elseif fieldPrefix then
                    if fieldPrefix == "g" then
                        match = (entry.guild and (isExactMatch and entry.guild:lower() == searchTerm or entry.guild:lower():find(searchTerm)))
                    elseif fieldPrefix == "r" then
                        match = (entry.race and (isExactMatch and entry.race:lower() == searchTerm or entry.race:lower():find(searchTerm)))
                    elseif fieldPrefix == "z" then
                        match = (entry.zone and (isExactMatch and entry.zone:lower() == searchTerm or entry.zone:lower():find(searchTerm)))
                    elseif fieldPrefix == "c" then
                        match = (entry.class and (isExactMatch and entry.class:lower() == searchTerm or entry.class:lower():find(searchTerm)))
                    elseif fieldPrefix == "n" then
                        match = (isExactMatch and name:lower() == searchTerm or name:lower():find(searchTerm))
                    end
                -- Exact match mode: check all fields for exact matches
                elseif isExactMatch then
                    match = (name:lower() == searchTerm or
                             (entry.class and entry.class:lower() == searchTerm) or
                             (entry.zone and entry.zone:lower() == searchTerm) or
                             (entry.guild and entry.guild:lower() == searchTerm) or
                             (entry.race and entry.race:lower() == searchTerm))
                -- Fuzzy match mode: substring search across all fields
                else
                    match = (name:lower():find(searchTerm) or
                             (entry.class and entry.class:lower():find(searchTerm)) or
                             (entry.zone and entry.zone:lower():find(searchTerm)) or
                             (entry.guild and entry.guild:lower():find(searchTerm)) or
                             (entry.race and entry.race:lower():find(searchTerm)) or
                             levelStr:find(searchTerm))
                end

                if match then
                    local t = GetPoolTable()
                    t.name = name
                    t.level = entry.level or 0
                    t.class = entry.class
                    t.zone = entry.zone
                    t.race = entry.race
                    t.guild = entry.guild
                    t.faction = entry.faction
                    t.seen = entry.lastSeen or 0
                    table.insert(browserData, t)
                end
            end
        end

        table.sort(browserData, function(a, b)
            if currentSortKey == "seen" then
                if a.seen == b.seen then return a.name:lower() < b.name:lower() end
                return a.seen > b.seen
            end
            -- Level stores mixed types (number or "?"); always compare numerically.
            if currentSortKey == "level" then
                local numA = tonumber(a.level) or 0
                local numB = tonumber(b.level) or 0
                if currentSortOrder == "ASC" then
                    if numA == numB then return a.seen > b.seen end
                    return numA < numB
                else
                    if numA == numB then return a.seen > b.seen end
                    return numA > numB
                end
            end
            local valA = a[currentSortKey] or ""
            local valB = b[currentSortKey] or ""
            if type(valA) == "string" then valA = valA:lower() end
            if type(valB) == "string" then valB = valB:lower() end

            if currentSortOrder == "ASC" then
                if valA == valB then return a.seen > b.seen end
                return valA < valB
            else
                if valA == valB then return a.seen > b.seen end
                return valA > valB
            end
        end)

        local numWhos = #browserData
        local offset = FauxScrollFrame_GetOffset(WhoListScrollFrame)
        FauxScrollFrame_Update(WhoListScrollFrame, numWhos, 17, 16)

        -- Force the scrollbar to be active and have the correct range
        local scrollBar = WhoListScrollFrameScrollBar
        if numWhos > 17 then
            scrollBar:SetMinMaxValues(0, (numWhos - 17) * 16)
            scrollBar:Show()
        else
            scrollBar:SetMinMaxValues(0, 0)
            scrollBar:Hide()
        end

        WhoFrameTotals:SetText(string.format("%d People Found", numWhos))

        -- Update Faction Counters in Browser
        local aCount, hCount = 0, 0
        for _, d in ipairs(browserData) do
            if d.faction == "Alliance" then
                aCount = aCount + 1
            elseif d.faction == "Horde" then
                hCount = hCount + 1
            end
        end
        browserStatsAlliance:SetText("|cff0070dd" .. aCount .. "|r")
        browserStatsHorde:SetText("|cffff2020" .. hCount .. "|r")

        local dCol = UIDropDownMenu_GetSelectedValue(WhoFrameDropDown)

        for i = 1, 17 do
            local button = _G["WhoFrameButton" .. i]
            if not button then break end
            local nameText = _G["WhoFrameButton" .. i .. "Name"]
            local levelText = _G["WhoFrameButton" .. i .. "Level"]
            local classText = _G["WhoFrameButton" .. i .. "Class"]
            local variableText = _G["WhoFrameButton" .. i .. "Variable"]

            local d = browserData[i + offset]
            if d then
                local displayName = d.name:gsub("^%l", string.upper)
                local displayClass = (d.class or "Unknown"):lower():gsub("(%a)([%w_']*)",
                    function(first, rest) return first:upper() .. rest end)
                local classKey = d.class and d.class:upper():gsub(" ", "") or ""
                
                local r, g, b = 1, 1, 1
                if Whorkaround_Settings and Whorkaround_Settings.factionColors then
                    if d.faction == "Horde" then
                        r, g, b = 1, 0.13, 0.13
                    elseif d.faction == "Alliance" then
                        r, g, b = 0, 0.44, 0.87
                    else
                        r, g, b = 0.7, 0.7, 0.7
                    end
                else
                    local color = RAID_CLASS_COLORS[classKey]
                    if color then r, g, b = color.r, color.g, color.b end
                end
                
                nameText:SetText(displayName); nameText:SetTextColor(r, g, b)
                levelText:SetText(DisplayLevel(d.level))
                classText:SetText(displayClass)

                if Whorkaround_Settings and Whorkaround_Settings.factionColors then
                    local c = RAID_CLASS_COLORS[classKey] or { r = 1, g = 1, b = 1 }
                    classText:SetTextColor(c.r, c.g, c.b)
                else
                    classText:SetTextColor(1, 1, 1)
                end

                -- Support for ElvUI Class Icons
                if button.icon then
                    if classKey ~= "" and _G.CLASS_ICON_TCOORDS[classKey] then
                        button.icon:Show()
                        button.icon:SetTexCoord(unpack(_G.CLASS_ICON_TCOORDS[classKey]))
                    else
                        button.icon:Hide()
                    end
                end

                if dCol == "guild" then
                    variableText:SetJustifyH("LEFT")
                    variableText:SetText(d.guild or "")
                elseif dCol == "race" then
                    variableText:SetJustifyH("CENTER")
                    local raceDisplay = d.race and ({
                        ["NightElf"]  = "Night Elf",
                        ["BloodElf"]  = "Blood Elf",
                        ["Scourge"]   = "Undead",
                    })[d.race] or d.race or ""
                    variableText:SetText(raceDisplay)
                elseif dCol == "seen" then
                    variableText:SetJustifyH("CENTER")
                    variableText:SetText(GetRelativeTime(d.seen or 0))
                else
                    variableText:SetJustifyH("LEFT")
                    variableText:SetText(d.zone or "")
                end

                button.playerName = d.name
                button.whoName = d.name  -- keep Blizzard's native click from writing nil to WhoFrame.selectedName
                local isSelected = WhoFrame.selectedName and d.name:lower() == WhoFrame.selectedName:lower()
                if isSelected then button:LockHighlight() else button:UnlockHighlight() end
                button:Show()
            else
                button:UnlockHighlight()
                button:Hide()
            end
        end

        -- Enable action buttons only when a player is selected
        if WhoFrame.selectedName and WhoFrame.selectedName ~= "" then
            WhoFrameAddFriendButton:Enable()
            WhoFrameGroupInviteButton:Enable()
        else
            WhoFrameAddFriendButton:Disable()
            WhoFrameGroupInviteButton:Disable()
        end
    end



    local function UpdateSortArrows()
        for i = 1, 4 do
            local arrow = _G["WhoFrameColumnHeader" .. i .. "SortArrow"]
            if arrow then
                local colKey = (i == 1 and "name") or (i == 3 and "level") or (i == 4 and "class") or ""
                if i == 2 then
                    local dCol = UIDropDownMenu_GetSelectedValue(WhoFrameDropDown)
                    colKey = (dCol == "guild" and "guild" or (dCol == "race" and "race" or (dCol == "seen" and "seen" or "zone")))
                end
                if currentSortKey == colKey then
                    arrow:Show()
                    if currentSortOrder == "ASC" then
                        arrow:SetTexCoord(0, 0.5625, 0, 1)
                    else
                        arrow:SetTexCoord(0, 0.5625,
                            1, 0)
                    end
                else
                    arrow:Hide()
                end
            end
        end
    end

    Whorkaround.SyncBrowser = function(self, force)
        if not tab1 or not tab1:GetChecked() or not WhoFrame:IsVisible() then return end
        
        -- If the user is actively filtering, skip background syncs to avoid resetting the list
        -- while they are trying to find someone. Manual typing still triggers live-updates.
        local query = WhoFrameEditBox:GetText()
        if not force and query and query ~= "" then return end

        Whorkaround_WhoList_Update()
    end

    -- Refresh browser immediately when toggling faction colors
    browserFactionColors:HookScript("OnClick", function()
        if tab1 and tab1:GetChecked() then
            Whorkaround_WhoList_Update()
        end
    end)

    local function CycleSort(key)
        if currentSortKey == key then
            if currentSortOrder == "ASC" then
                currentSortOrder = "DESC"
            else
                currentSortKey = "seen"; currentSortOrder = "DESC"
            end
        else
            currentSortKey = key; currentSortOrder = "ASC"
        end
        UpdateSortArrows(); Whorkaround_WhoList_Update()
    end

    local function Column_OnClick(self)
        if tab1 and tab1:GetChecked() then
            local name = self:GetName()
            if name == "WhoFrameColumnHeader1" then
                CycleSort("name")
            elseif name == "WhoFrameColumnHeader3" then
                CycleSort("level")
            elseif name == "WhoFrameColumnHeader4" then
                CycleSort("class")
            elseif name == "WhoFrameColumnHeader2" then
                local col = UIDropDownMenu_GetSelectedValue(WhoFrameDropDown)
                CycleSort(col == "guild" and "guild" or
                    (col == "race" and "race" or (col == "seen" and "seen" or "zone")))
            end
        end
    end

    -- Custom Dropdown for Browser Mode
    local function Whorkaround_DropDown_Initialize()
        local info = UIDropDownMenu_CreateInfo()
        local selected = UIDropDownMenu_GetSelectedValue(WhoFrameDropDown)
        info.func = function(self)
            UIDropDownMenu_SetSelectedValue(WhoFrameDropDown, self.value)
            Whorkaround_WhoList_Update()
        end

        info.text = "Zone"; info.value = "zone"
        info.checked = (selected == "zone")
        UIDropDownMenu_AddButton(info)

        info.text = "Race"; info.value = "race"
        info.checked = (selected == "race")
        UIDropDownMenu_AddButton(info)

        info.text = "Guild"; info.value = "guild"
        info.checked = (selected == "guild")
        UIDropDownMenu_AddButton(info)

        info.text = "Last Seen"; info.value = "seen"
        info.checked = (selected == "seen")
        UIDropDownMenu_AddButton(info)
    end

    local function Whorkaround_OnVerticalScroll(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, 16, Whorkaround_WhoList_Update)
    end
    local nativeScrollScript
    local nativeEditBoxScripts = {}

    local function SyncUI()
        if not FriendsFrame:IsVisible() or (not WhoFrame:IsVisible() and not (settings and settings:IsVisible())) then return end
        if not tab1 or not tab2 or not settings or not browserFactionColors then return end
        local browserActive = tab1:GetChecked()
        local settingsActive = tab2:GetChecked()

        if settingsActive then
            settings:Show()
            browserFactionColors:Hide()
            WhoFrameColumnHeader1:Hide(); WhoFrameColumnHeader2:Hide(); WhoFrameColumnHeader3:Hide(); WhoFrameColumnHeader4
                :Hide()
            WhoListScrollFrame:Hide(); WhoFrameEditBox:Hide(); WhoFrameWhoButton:Hide()
            WhoFrameAddFriendButton:Hide(); WhoFrameGroupInviteButton:Hide()
            WhoFrameTotals:Hide()
            browserStatsAlliance:Hide(); browserStatsHorde:Hide()
            browserStatsAllianceHit:Hide(); browserStatsHordeHit:Hide()
        else
            settings:Hide()
            browserFactionColors:Hide()
            if browserActive then
                browserFactionColors:Show()
                if not nativeScrollScript then nativeScrollScript = WhoListScrollFrame:GetScript("OnVerticalScroll") end
                WhoListScrollFrame:SetScript("OnVerticalScroll", Whorkaround_OnVerticalScroll)

                -- Hijack EditBox Scripts
                if not nativeEditBoxScripts.OnTextChanged then
                    nativeEditBoxScripts.OnTextChanged = WhoFrameEditBox:GetScript("OnTextChanged")
                    nativeEditBoxScripts.OnEnterPressed = WhoFrameEditBox:GetScript("OnEnterPressed")
                    nativeEditBoxScripts.OnEscapePressed = WhoFrameEditBox:GetScript("OnEscapePressed")
                end
                WhoFrameEditBox:SetScript("OnTextChanged", function() Whorkaround_WhoList_Update() end)
                WhoFrameEditBox:SetScript("OnEnterPressed", function(self)
                    local raw = self:GetText()
                    -- Strip hyperlink formatting (spell/item/etc links) so they are never
                    -- mistaken for player names.
                    local plain = raw:gsub("|H[^|]+|h%[[^%]]+%]|h", "")
                                     :gsub("|c%x+", ""):gsub("|r", "")
                                     :gsub("^%s+", ""):gsub("%s+$", "")
                    if plain ~= "" and not plain:find(" ") then Whorkaround:Query(plain) end
                    Whorkaround_WhoList_Update(); self:ClearFocus()
                end)
                WhoFrameEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

                -- Search help tooltip
                WhoFrameEditBox:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Search Syntax:", 1, 1, 1)
                    GameTooltip:AddLine("Fuzzy: |cffffd100John|r - searches all fields", nil, nil, nil, true)
                    GameTooltip:AddLine("Exact: |cffffd100\"John\"|r - exact field match", nil, nil, nil, true)
                    GameTooltip:AddLine("Prefixes: |cffffd100g:|rGuild, |cffffd100r:|rRace, |cffffd100z:|rZone, |cffffd100c:|rClass, |cffffd100n:|rName", nil, nil, nil, true)
                    GameTooltip:AddLine("Level: |cffffd10010-20|r - level range", nil, nil, nil, true)
                    GameTooltip:Show()
                end)
                WhoFrameEditBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
                local cur = UIDropDownMenu_GetSelectedValue(WhoFrameDropDown)
                if cur ~= "zone" and cur ~= "seen" and cur ~= "race" and cur ~= "guild" then UIDropDownMenu_SetSelectedValue(WhoFrameDropDown, "zone") end
                -- Explicitly claim the dropdown init function now so ToggleDropDownMenu
                -- never runs WhoFrameDropDown_Initialize (avoids the OnMouseUp crash).
                UIDropDownMenu_Initialize(WhoFrameDropDown, Whorkaround_DropDown_Initialize)

                WhoFrameColumnHeader1:Show(); WhoFrameColumnHeader2:Show(); WhoFrameColumnHeader3:Show(); WhoFrameColumnHeader4
                    :Show()
                WhoListScrollFrame:Show();
                WhoListScrollFrameScrollBar:Show();
                WhoFrameEditBox:Show(); WhoFrameWhoButton:Show()
                WhoFrameAddFriendButton:Show(); WhoFrameGroupInviteButton:Show()
                WhoFrameTotals:Show()
                browserStatsAlliance:Show(); browserStatsHorde:Show()
                browserStatsAllianceHit:Show(); browserStatsHordeHit:Show()
                -- Only show separator if NOT ElvUI or if ElvUI skinning is disabled
                local E = IsAddOnLoaded("ElvUI") and _G.ElvUI and _G.ElvUI[1]
                if not E or (E.private and E.private.skins and E.private.skins.blizzard and (not E.private.skins.blizzard.enable or not E.private.skins.blizzard.friends)) then
                    browserStatsSeparator:Show()
                else
                    browserStatsSeparator:Hide()
                end
                UpdateSortArrows(); Whorkaround_WhoList_Update()
            else
                if nativeScrollScript then WhoListScrollFrame:SetScript("OnVerticalScroll", nativeScrollScript) end

                -- Restore EditBox Scripts
                if nativeEditBoxScripts.OnTextChanged then
                    WhoFrameEditBox:SetScript("OnTextChanged", nativeEditBoxScripts.OnTextChanged)
                    WhoFrameEditBox:SetScript("OnEnterPressed", nativeEditBoxScripts.OnEnterPressed)
                    WhoFrameEditBox:SetScript("OnEscapePressed", nativeEditBoxScripts.OnEscapePressed)
                    nativeEditBoxScripts = {} -- Reset so we can re-capture if Blizzard changes them
                end

                UIDropDownMenu_Initialize(WhoFrameDropDown, WhoFrameDropDown_Initialize)

                WhoFrameColumnHeader1:Show(); WhoFrameColumnHeader2:Show(); WhoFrameColumnHeader3:Show(); WhoFrameColumnHeader4
                    :Show()
                WhoListScrollFrame:Show(); WhoFrameEditBox:Show(); WhoFrameWhoButton:Show()
                WhoFrameAddFriendButton:Show(); WhoFrameGroupInviteButton:Show()
                WhoFrameTotals:Show()
                browserStatsAlliance:Hide(); browserStatsHorde:Hide()
                browserStatsAllianceHit:Hide(); browserStatsHordeHit:Hide()
                browserStatsSeparator:Hide()
                WhoList_Update()
            end
        end
    end

    settings:SetScript("OnHide", function()
        SyncUI()
    end)

    local header = settings:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 20, -15); header:SetText("Whorkaround Options")

    local version = GetAddOnMetadata("Whorkaround", "Version") or "1.4.11"
    local verText = settings:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    verText:SetPoint("LEFT", header, "RIGHT", 10, 0); verText:SetText("v" .. version); verText:SetTextColor(0.5, 0.5, 0.5)

    local tabBox = CreateEditBox(settings, "Output Chat Tab(s)", "outputTab",
        "Enter tab names separated by commas (e.g. General, Log). Leave blank for default.", "WhorkaroundOutputTabEB")
    tabBox:SetPoint("TOPLEFT", 17, -60)
    tabBox:SetWidth(145) -- Wider for tab names (Narrowed by 10px)
    components.tabBox = tabBox

    local autoOpen = CreateCheckBox(settings, "Auto-show DB", "overrideWho",
        "Automatically toggles the database view when opening the Social panel.")
    autoOpen:SetPoint("TOPLEFT", 182, -55) -- Centered in column
    components.autoOpen = autoOpen

    local proxyCheck = CreateCheckBox(settings, "Proxy Mode", "allowProxy",
        "Allows other users to query players through you.")
    proxyCheck:SetPoint("TOPLEFT", 17, -100)
    components.proxyCheck = proxyCheck

    local debugCheck = CreateCheckBox(settings, "Enable Debug", "debug",
        "Prints detailed background actions to chat (Network, Proxy, Cleanup).")
    debugCheck:SetPoint("BOTTOMLEFT", 182, 55) -- Bottom right, alongside DB Stats cluster
    debugCheck:HookScript("OnClick", function(self)
        Whorkaround.DebugMode = (self:GetChecked() == 1)
    end)
    components.debugCheck = debugCheck

    local scannerCheck = CreateCheckBox(settings, "Ambient Scanner", "enableScanner",
        "Passively gathers player info from the combat log (Zero FPS impact).")
    scannerCheck:SetPoint("TOPLEFT", 182, -100) -- Column 2, below Auto-show DB
    components.scannerCheck = scannerCheck

    local chatLinksCheck = CreateCheckBox(settings, "Mention Links", "mentionHyperlinks",
        "Enables [Name] and @Name mentions in chat.\n\nType [Name] or @Name in any chat box to create a clickable, class-coloured player link. Shift-clicking an existing player link also inserts [Name] into the edit box.\n\nDisabled by default.")
    chatLinksCheck:SetPoint("TOPLEFT", 17, -220) -- Column 1, below Proxy Cooldown slider
    components.chatLinksCheck = chatLinksCheck

    -- Debug Level Dropdown (Arrow Button)
    local debugLevelMenu = CreateFrame("Frame", "WhorkaroundDebugLevelMenu", settings, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(debugLevelMenu, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Queries Only"
        info.func = function() Whorkaround_Settings.debugLevel = 1 end
        info.checked = (Whorkaround_Settings.debugLevel == 1)
        UIDropDownMenu_AddButton(info)

        info.text = "Verbose (All)"
        info.func = function() Whorkaround_Settings.debugLevel = 2 end
        info.checked = (Whorkaround_Settings.debugLevel == 2)
        UIDropDownMenu_AddButton(info)
    end)

    local debugLevelBtn = CreateFrame("Button", nil, settings)
    debugLevelBtn:SetSize(20, 20)
    debugLevelBtn:SetPoint("LEFT", debugCheck.text, "RIGHT", 2, 0)
    debugLevelBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    debugLevelBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
    debugLevelBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

    debugLevelBtn:SetScript("OnClick", function(self)
        ToggleDropDownMenu(1, nil, debugLevelMenu, self, -130, 0)
    end)
    debugLevelBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Debug Verbosity", 1, 1, 1)
        GameTooltip:AddLine("Queries: Only show network and database actions.\nVerbose: Show every scanner pulse and internal event.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    debugLevelBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    components.debugLevelBtn = debugLevelBtn

    -- Proxy State Dropdown (Arrow Button)
    local proxyModeMenu = CreateFrame("Frame", "WhorkaroundProxyModeMenu", settings, "UIDropDownMenuTemplate")
    local proxyModeBtn = CreateFrame("Button", nil, settings)
    proxyModeBtn:SetSize(20, 20)
    proxyModeBtn:SetPoint("LEFT", proxyCheck.text, "RIGHT", 12, 0)
    proxyModeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    proxyModeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
    proxyModeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    
    UIDropDownMenu_Initialize(proxyModeMenu, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Always"
        info.func = function() Whorkaround_Settings.proxyOutCombat = false end
        info.checked = (Whorkaround_Settings.proxyOutCombat == false)
        UIDropDownMenu_AddButton(info)

        info.text = "Out of Combat"
        info.func = function() Whorkaround_Settings.proxyOutCombat = true end
        info.checked = (Whorkaround_Settings.proxyOutCombat == true)
        UIDropDownMenu_AddButton(info)
    end)

    proxyModeBtn:SetScript("OnClick", function()
        -- GROW LEFT: Offset by -130 to keep menu under the column
        ToggleDropDownMenu(1, nil, proxyModeMenu, proxyModeBtn, -130, 0)
    end)
    components.proxyModeBtn = proxyModeBtn

    local proxyCooldown = CreateSlider(settings, "Cooldown", "proxyCooldown", 3, 30, 1, "Sec",
        "Limits how often you act as a proxy. Higher values reduce CPU usage but help the network less.")
    proxyCooldown:SetPoint("TOPLEFT", 17, -165)
    components.proxyCooldown = proxyCooldown

    local retentionSlider = CreateSlider(settings, "DB Purge after", "retentionWeeks", 1, 4, 1, "Weeks",
        "Automatically removes players from your local database if they haven't been seen in this many weeks.")
    retentionSlider:SetPoint("TOPLEFT", 182, -165)
    components.retentionSlider = retentionSlider

    -- Footer Status Row (Vertical Stack)
    local statsHeader = settings:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statsHeader:SetPoint("BOTTOMLEFT", 17, 65); statsHeader:SetText("Database Status")

    local statsTotalLabel = settings:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statsTotalLabel:SetPoint("TOPLEFT", statsHeader, "BOTTOMLEFT", 0, -5); statsTotalLabel:SetTextColor(0.53, 0.53, 0.53)
    statsTotal = statsTotalLabel
    components.statsTotal = statsTotal

    statsNetwork = settings:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statsNetwork:SetPoint("TOPLEFT", statsTotal, "BOTTOMLEFT", 0, -8)
    statsNetwork:SetTextColor(0.53, 0.53, 0.53)
    components.statsNetwork = statsNetwork

    -- Maintenance Dropdown (Hidden anchor frame)
    local maintenanceDropDown = CreateFrame("Frame", "WhorkaroundMaintenanceDropDown", settings, "UIDropDownMenuTemplate")

    UIDropDownMenu_Initialize(maintenanceDropDown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.text = "|cffff2020Clear Database|r"
        info.notCheckable = true
        info.func = function() StaticPopup_Show("WHORKAROUND_CONFIRM_CLEAR") end
        UIDropDownMenu_AddButton(info)

        info.text = "Close Menu"
        info.notCheckable = true
        info.func = function() CloseDropDownMenus() end
        UIDropDownMenu_AddButton(info)
    end, "MENU")

    -- The "Arrow" Button
    local maintenanceBtn = CreateFrame("Button", nil, settings)
    maintenanceBtn:SetSize(24, 24)
    maintenanceBtn:SetPoint("LEFT", statsHeader, "RIGHT", 5, 0)
    maintenanceBtn:SetNormalTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    maintenanceBtn:GetNormalTexture():SetRotation(math.rad(-90)) -- Point down

    maintenanceBtn:SetScript("OnClick", function(self)
        ToggleDropDownMenu(1, nil, maintenanceDropDown, self, 0, 0)
    end)

    maintenanceBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Database Maintenance", 1, 1, 1)
        GameTooltip:AddLine("Click to open management options.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    maintenanceBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    components.maintenanceBtn = maintenanceBtn

    local function SetStatTooltip(frame, label, color, count)
        frame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:SetText(label, color.r, color.g, color.b)
            GameTooltip:AddLine(string.format("Total Players: %d", count), 1, 1, 1)
            GameTooltip:Show()
        end)
        frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    local function UpdateStats()
        if not Whorkaround_DB then
            statsTotal:SetText("No data available."); return
        end
        local total = 0
        for _ in pairs(Whorkaround_DB) do total = total + 1 end
        statsTotal:SetText(string.format("Total Players: %d", total))
        -- Network peer counts (populated by Comm.lua passively)
        local peerCount, proxyCount = 0, 0
        for _ in pairs(Whorkaround.networkPeers or {}) do peerCount = peerCount + 1 end
        for _ in pairs(Whorkaround.proxyPeers or {}) do proxyCount = proxyCount + 1 end
        if peerCount > 0 then
            statsNetwork:SetText(string.format("Network: %d peer%s seen (%d prox%s)",
                peerCount, peerCount == 1 and "" or "s",
                proxyCount, proxyCount == 1 and "y" or "ies"))
        else
            statsNetwork:SetText("Network: Searching...")
        end
    end
    Whorkaround.UpdateStats = UpdateStats
    settings:SetScript("OnShow", UpdateStats)



    -- Notify skinning module about local components
    if Whorkaround.SkinGUIComponents then
        Whorkaround:SkinGUIComponents(components)
    end

    WhoFrameColumnHeader1:HookScript("OnClick", Column_OnClick)
    WhoFrameColumnHeader2:HookScript("OnClick", Column_OnClick)
    WhoFrameColumnHeader3:HookScript("OnClick", Column_OnClick)
    WhoFrameColumnHeader4:HookScript("OnClick", Column_OnClick)

    local tooltipNameOrigFont = nil  -- saved original font for name-line resize

    local function WhoButton_OnEnter_Hook(self)
        if not tab1 or not tab1:GetChecked() or not self.playerName then return end
        local d = Whorkaround_DB and Whorkaround_DB[self.playerName:lower()]
        if not d then return end

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

        -- Normalize capitalization
        local displayName = self.playerName:gsub("^%l", string.upper)
        local displayClass = (d.class or "Unknown"):lower():gsub("^%l", string.upper)
        local prettyRace = ({
            NightElf = "Night Elf", BloodElf = "Blood Elf", Scourge = "Undead",
        })[d.race] or d.race

        local classKey = d.class and d.class:upper() or ""
        local classColor = RAID_CLASS_COLORS[classKey] or { r = 1, g = 1, b = 1 }

        -- Name (slightly larger font — saved/restored per-tooltip so other tooltips are unaffected)
        GameTooltip:AddLine(displayName, classColor.r, classColor.g, classColor.b)
        local nameText = _G["GameTooltipTextLeft1"]
        if nameText then
            local fontPath, fontSize, fontFlags = nameText:GetFont()
            if fontPath then
                tooltipNameOrigFont = { fontPath, fontSize, fontFlags }
                nameText:SetFont(fontPath, (fontSize or 12) + 1, fontFlags or "")
            end
        end

        -- Guild (below name, before level)
        if d.guild and d.guild ~= "" then
            GameTooltip:AddLine("<" .. d.guild .. ">", 0.1, 1, 0.1)
        end

        -- Level + Race + Class on one line
        if prettyRace then
            GameTooltip:AddLine(string.format("Level %s %s %s", DisplayLevel(d.level), prettyRace, displayClass), 1, 1, 1)
        else
            GameTooltip:AddLine(string.format("Level %s %s", DisplayLevel(d.level), displayClass), 1, 1, 1)
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Zone:", d.zone or "Unknown", 1, 0.82, 0, 1, 1, 1)

        if d.faction and d.faction ~= "" then
            local fR, fG, fB = 1, 1, 1
            if d.faction == "Alliance" then fR, fG, fB = 0, 0.44, 0.87
            elseif d.faction == "Horde" then fR, fG, fB = 1, 0.13, 0.13 end
            GameTooltip:AddDoubleLine("Faction:", d.faction, 1, 0.82, 0, fR, fG, fB)
        end

        GameTooltip:AddDoubleLine("Last Seen:", GetRelativeTime(d.lastSeen or 0), 1, 0.82, 0, 1, 1, 1)

        if d.source then
            local sourceLabels = {
                Scanner     = "Combat Log",
                Sighting    = "Tooltip",
                WhorkComm   = "Network",
                FriendsList = "Friends List",
                GuildRoster = "Guild Roster",
            }
            GameTooltip:AddDoubleLine("Source:", sourceLabels[d.source] or d.source, 0.5, 0.5, 0.5, 0.7, 0.7, 0.7)
        end

        GameTooltip:Show()
    end

    local function WhoButton_OnClick_Hook(self, button)
        if tab1 and tab1:GetChecked() and self.playerName then
            if button == "LeftButton" and IsShiftKeyDown() then
                local d = Whorkaround_DB and Whorkaround_DB[self.playerName:lower()]
                if d then
                    local displayName = self.playerName:gsub("^%l", string.upper)
                    local link = string.format("|Hplayer:%s|h[%s]|h", self.playerName, displayName)
                    local eb = ChatEdit_GetActiveWindow() or (LastSayName and _G[LastSayName .. "EditBox"]) or
                        _G["ChatFrameEditBox"]
                    if eb and eb:IsVisible() then
                        eb:Insert(link)
                    else
                        print(string.format("%s: Level %s %s %s - %s", link, DisplayLevel(d.level), d.faction or "", d.class, d.zone))
                    end
                end
            elseif button == "LeftButton" then
                WhoFrame.selectedWho = self.playerName
                WhoFrame.selectedName = self.playerName
                WhoFrameAddFriendButton:Enable()
                WhoFrameGroupInviteButton:Enable()
                Whorkaround_WhoList_Update()
            end
        end
    end

    for i = 1, 17 do
        local btn = _G["WhoFrameButton" .. i]
        btn:HookScript("OnClick", WhoButton_OnClick_Hook)
        btn:HookScript("OnEnter", WhoButton_OnEnter_Hook)
        btn:HookScript("OnLeave", function()
            if tooltipNameOrigFont then
                local nameText = _G["GameTooltipTextLeft1"]
                if nameText then nameText:SetFont(tooltipNameOrigFont[1], tooltipNameOrigFont[2], tooltipNameOrigFont[3] or "") end
                tooltipNameOrigFont = nil
            end
            GameTooltip:Hide()
        end)
    end

    -- Mouse wheel support for the list
    WhoFrame:EnableMouseWheel(true)
    WhoFrame:SetScript("OnMouseWheel", function(self, delta)
        if tab1 and tab1:GetChecked() then
            local scrollBar = WhoListScrollFrameScrollBar
            if scrollBar and scrollBar:IsShown() then
                local min, max = scrollBar:GetMinMaxValues()
                local val = scrollBar:GetValue()
                if delta > 0 then
                    scrollBar:SetValue(math.max(min, val - 32))
                else
                    scrollBar:SetValue(math.min(max, val + 32))
                end
            end
        end
    end)



    hooksecurefunc("UIDropDownMenu_SetSelectedValue", function(frame)
        if frame == WhoFrameDropDown and tab1 and tab1:GetChecked() then Whorkaround_WhoList_Update() end
    end)

    -- Prevent Blizzard from resetting WhoFrameDropDown's init function while browser mode is active.
    -- Without this, WhoList_Update() and similar Blizzard calls reset the init function to the
    -- native WhoFrameDropDown_Initialize, causing our custom one to be bypassed or doubled up.
    local whorkaroundDropDownLock = false
    hooksecurefunc("UIDropDownMenu_Initialize", function(frame, initFunction)
        if whorkaroundDropDownLock then return end
        if frame == WhoFrameDropDown and initFunction ~= Whorkaround_DropDown_Initialize then
            if tab1 and tab1:GetChecked() then
                whorkaroundDropDownLock = true
                UIDropDownMenu_Initialize(WhoFrameDropDown, Whorkaround_DropDown_Initialize)
                whorkaroundDropDownLock = false
            end
        end
    end)

    -- Replace WhoFrameDropDown_Initialize entirely. hooksecurefunc only fires AFTER the
    -- original, which crashes in Epoch because GetWhoInfo() returns nil (no /who results).
    -- Direct replacement ensures the native function never runs in browser mode.
    do
        local _orig = WhoFrameDropDown_Initialize
        WhoFrameDropDown_Initialize = function(level)
            if tab1 and tab1:GetChecked() then
                Whorkaround_DropDown_Initialize(level)
            elseif _orig then
                _orig(level)
            end
        end
    end

    tab1 = CreateFrame("CheckButton", "WhorkaroundSideTab1", FriendsFrame)
    tab1:SetSize(32, 32); tab1:SetPoint("TOPLEFT", FriendsFrame, "TOPRIGHT", -32, -42)
    tab1:SetNormalTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
    tab1:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    tab1:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    tab1:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
    local tab1Bg = tab1:CreateTexture(nil, "BACKGROUND"); tab1Bg:SetSize(64, 64); tab1Bg:SetPoint("TOPLEFT", -3, 11); tab1Bg
        :SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    tab1:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Database Browser", 1, 1, 1); GameTooltip:Show()
    end)
    tab1:SetScript("OnLeave", function() GameTooltip:Hide() end)

    tab1:SetScript("OnClick", function(self)
        if self:GetChecked() then
            tab2:SetChecked(false)
            settings:Hide()
            WhoListScrollFrame:Hide(); WhoFrameEditBox:Hide(); WhoFrameWhoButton:Hide()
            UIDropDownMenu_SetSelectedValue(WhoFrameDropDown, "seen")
            Whorkaround_WhoList_Update()
        else
            WhoListScrollFrame:Show(); WhoFrameEditBox:Show(); WhoFrameWhoButton:Show()
        end
        SyncUI()
    end)

    tab2 = CreateFrame("CheckButton", "WhorkaroundSideTab2", FriendsFrame)
    tab2:SetSize(32, 32); tab2:SetPoint("TOPLEFT", tab1, "BOTTOMLEFT", 0, -18)
    tab2:SetNormalTexture("Interface\\Icons\\INV_Misc_Gear_01")
    tab2:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    tab2:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    tab2:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
    local tab2Bg = tab2:CreateTexture(nil, "BACKGROUND"); tab2Bg:SetSize(64, 64); tab2Bg:SetPoint("TOPLEFT", -3, 11); tab2Bg
        :SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    tab2:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Whorkaround Options", 1, 1, 1); GameTooltip
            :Show()
    end)
    tab2:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tab2:SetScript("OnClick", function(self)
        if self:GetChecked() then tab1:SetChecked(false) end
        SyncUI()
    end)



    Whorkaround.ToggleButton = tab1

    -- Persistent Visibility Lockdown
    local function Lockdown()
        if tab2 and tab2:GetChecked() then
            WhoFrameColumnHeader1:Hide(); WhoFrameColumnHeader2:Hide(); WhoFrameColumnHeader3:Hide(); WhoFrameColumnHeader4
                :Hide()
            WhoListScrollFrame:Hide(); WhoFrameEditBox:Hide(); WhoFrameWhoButton:Hide()
            WhoFrameAddFriendButton:Hide(); WhoFrameGroupInviteButton:Hide()
            WhoFrameTotals:Hide()
            if browserStatsAlliance then
                browserStatsAlliance:Hide(); browserStatsAllianceHit:Hide()
                browserStatsHorde:Hide(); browserStatsHordeHit:Hide()
                browserStatsSeparator:Hide()
            end
        end
    end
    hooksecurefunc(WhoFrameEditBox, "Show", Lockdown)
    hooksecurefunc(WhoListScrollFrame, "Show", Lockdown)
    hooksecurefunc(WhoFrameWhoButton, "Show", Lockdown)

    -- Hijack the Refresh/Who button: in browser mode, query the selected player to refresh their DB entry.
    -- Same-faction: goes through the normal Query() pipeline (guild roster → friends list → cache).
    -- Cross-faction: sends a WhorkComm network request to proxies.
    WhoFrameWhoButton:HookScript("OnClick", function()
        if not (tab1 and tab1:GetChecked()) then return end
        local name = WhoFrame.selectedName
        if not name or name == "" then
            -- No selection: just refresh the view
            Whorkaround:SyncBrowser(true)
            return
        end
        local cleanName = name:lower():gsub("^%s*(.-)%s*$", "%1")
        local d = Whorkaround_DB and Whorkaround_DB[cleanName]
        local playerFaction = UnitFactionGroup("player") or "Unknown"
        local targetFaction = d and d.faction
        if targetFaction and targetFaction ~= playerFaction and targetFaction ~= "Unknown" then
            -- Cross-faction: request via network proxies
            local tag = (targetFaction == "Horde") and "H" or "A"
            if not Whorkaround.networkWaiters[cleanName] then
                Whorkaround.networkWaiters[cleanName] = { startTime = GetTime(), silent = false }
                Whorkaround.bestNetworkHits[cleanName] = nil
                Whorkaround:Request(name, tag)
                print("|cff1abc9cWhorkaround:|r Querying network for |cffffffff" .. name:gsub("^%l", string.upper) .. "|r...")
            end
        else
            -- Same-faction (or unknown): use normal query pipeline
            Whorkaround:Query(name)
        end
    end)

    WhoFrame:HookScript("OnUpdate", function(self)
        if not tab2 or not tab2:GetChecked() then return end
        Lockdown()
    end)

    Whorkaround.SetGUIState = function(show)
        if show then tab2:SetChecked(true) else tab2:SetChecked(false) end
        SyncUI()
    end

    local wasWhoShown = false
    hooksecurefunc("FriendsFrame_Update", function()
        local isWhoShown = WhoFrame:IsVisible()
        if isWhoShown then
            tab1:Show(); tab2:Show()
            -- If we just switched to the Who tab, apply auto-open setting
            if not wasWhoShown and Whorkaround_Settings and Whorkaround_Settings.overrideWho then
                tab1:SetChecked(true)
                tab2:SetChecked(false)
                SyncUI()
            end
        else
            tab1:SetChecked(false)
            tab2:SetChecked(false)
            tab1:Hide(); tab2:Hide()
            SyncUI()
        end
        wasWhoShown = isWhoShown
    end)

    WhoFrame:HookScript("OnHide", function()
        if tab1 then tab1:SetChecked(false) end
        if tab2 then tab2:SetChecked(false) end
        SyncUI()
    end)

    WhoFrame:HookScript("OnShow", function()
        SyncUI()
    end)

    -- Replace WhoList_Update so Blizzard's code never touches our browser's scroll state.
    -- When browser mode is active we simply call our own renderer; Blizzard's version is
    -- never reached, which also prevents the GetWhoInfo(out-of-range) crash.
    -- In native mode we use pcall so that Epoch's FriendsFrame.lua calling GetWhoInfo beyond
    -- the result count (or GetNumWhos being absent) cannot hard-crash the client.
    do
        local _origWhoList_Update = WhoList_Update
        WhoList_Update = function()
            if tab1 and tab1:GetChecked() then
                Whorkaround_WhoList_Update()
            else
                -- Reset any residual browser scroll offset so Blizzard's index math stays in range.
                WhoListScrollFrame.offset = 0
                local ok = pcall(_origWhoList_Update)
                if not ok then
                    -- Epoch's GetWhoInfo crashed (no results or missing API guard).
                    -- Clear stale buttons manually so the frame doesn't show stale data.
                    for i = 1, 17 do
                        local btn = _G["WhoFrameButton" .. i]
                        if btn then btn:Hide() end
                    end
                    if WhoFrameTotals then WhoFrameTotals:SetText("0 People Found") end
                    if WhoFrameGroupInviteButton then WhoFrameGroupInviteButton:Disable() end
                    if WhoFrameAddFriendButton then WhoFrameAddFriendButton:Disable() end
                end
            end
        end
    end

    -- Apply ElvUI Skinning if available
    if Whorkaround.ApplyElvUISkin then
        Whorkaround:ApplyElvUISkin()
    end
end

-- Hook into Social Frame
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(self)
    Whorkaround:InitGUI()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
end)
