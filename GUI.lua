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

local function CreateEditBox(parent, label, setting, tooltip)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(200, 45)
    
    local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", 0, 0); text:SetText(label)
    
    local eb = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    eb:SetSize(180, 20); eb:SetPoint("TOPLEFT", 0, -15); eb:SetAutoFocus(false)
    
    eb:SetScript("OnShow", function(self) self:SetText(Whorkaround_Settings[setting] or "") end)
    eb:SetScript("OnEnterPressed", function(self)
        Whorkaround_Settings[setting] = self:GetText()
        self:ClearFocus()
        print("|cff1abc9cWhorkaround:|r " .. label .. " set to: |cffffd100" .. (Whorkaround_Settings[setting] ~= "" and Whorkaround_Settings[setting] or "Default") .. "|r")
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    if tooltip then
        eb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        eb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    
    return container
end

local function CreateSlider(parent, label, setting, minVal, maxVal, step)
    local slider = CreateFrame("Slider", "WhorkaroundRetentionSlider", parent, "OptionsSliderTemplate")
    slider:SetWidth(180); slider:SetMinMaxValues(minVal, maxVal); slider:SetValueStep(step or 1)
    _G[slider:GetName() .. "Low"]:SetText(minVal); _G[slider:GetName() .. "High"]:SetText(maxVal)
    
    local text = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("BOTTOM", slider, "TOP", 0, 5)
    
    local function UpdateText(val)
        text:SetText(string.format("%s: %d %s", label, val, val == 1 and "Week" or "Weeks"))
    end

    slider:SetScript("OnShow", function(self)
        local val = Whorkaround_Settings[setting] or maxVal
        self:SetValue(val); UpdateText(val)
    end)

    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        Whorkaround_Settings[setting] = value
        UpdateText(value)
    end)
    
    return slider
end

function Whorkaround:InitGUI()
    if self.GUI then return end
    local components = {}
    
    local function CreateInlineEditBox(parent, label, setting, tooltip)
        local container = CreateFrame("Frame", nil, parent)
        container:SetSize(250, 26)
        local text = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", 0, 0); text:SetText(label)
        local eb = CreateFrame("EditBox", "WhorkaroundFreqEditBox", container, "InputBoxTemplate")
        eb:SetSize(30, 20); eb:SetPoint("LEFT", text, "RIGHT", 10, 0); eb:SetAutoFocus(false); eb:SetJustifyH("CENTER")
        eb:SetScript("OnShow", function(self) self:SetText(Whorkaround_Settings[setting] or "1.0") end)
        eb:SetScript("OnEnterPressed", function(self)
            local val = tonumber(self:GetText())
            if val and val >= 0.1 then Whorkaround_Settings[setting] = val else self:SetText(Whorkaround_Settings[setting] or "1.0") end
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

    local tab1, tab2

    -- Settings Panel
    local settings = CreateFrame("Frame", "WhorkaroundSettingsPanel", WhoFrame)
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
        if diff < 60 then return "Just now"
        elseif diff < 3600 then return math.floor(diff/60) .. "m ago"
        elseif diff < 86400 then return math.floor(diff/3600) .. "h ago"
        else return math.floor(diff/86400) .. "d ago" end
    end

    local function Whorkaround_WhoList_Update()
        if not tab1 or not tab1:GetChecked() then return end
        
        local query = (WhoFrameEditBox:GetText() or ""):lower()
        local data = {}
        if Whorkaround_DB then
            for name, entry in pairs(Whorkaround_DB) do
                if query == "" or name:lower():find(query) or (entry.class and entry.class:lower():find(query)) or (entry.zone and entry.zone:lower():find(query)) then
                    table.insert(data, { name = name, level = entry.level or 0, class = entry.class, zone = entry.zone, guild = entry.guild, faction = entry.faction, seen = entry.lastSeen or 0 })
                end
            end
        end
        table.sort(data, function(a, b)
            if currentSortKey == "seen" then
                if a.seen == b.seen then return a.name:lower() < b.name:lower() end
                return a.seen > b.seen
            end
            local valA, valB = a[currentSortKey] or "", b[currentSortKey] or ""
            if type(valA) == "string" then valA, valB = valA:lower(), valB:lower() end
            if currentSortOrder == "ASC" then
                if valA == valB then return a.seen > b.seen end
                return valA < valB
            else
                if valA == valB then return a.seen > b.seen end
                return valA > valB
            end
        end)

        local numWhos = #data
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
        local dCol = UIDropDownMenu_GetSelectedValue(WhoFrameDropDown)
        
        for i = 1, 17 do
            local button = _G["WhoFrameButton"..i]
            if not button then break end
            local nameText = _G["WhoFrameButton"..i.."Name"]
            local levelText = _G["WhoFrameButton"..i.."Level"]
            local classText = _G["WhoFrameButton"..i.."Class"]
            local variableText = _G["WhoFrameButton"..i.."Variable"]
            
            local d = data[i + offset]
            if d then
                local displayName = d.name:gsub("^%l", string.upper)
                local displayClass = (d.class or "Unknown"):lower():gsub("(%a)([%w_']*)", function(first, rest) return first:upper()..rest end)
                local classKey = d.class and d.class:upper():gsub(" ", "") or ""
                local color
                if Whorkaround_Settings and Whorkaround_Settings.factionColors then
                    -- Faction-based coloring
                    if d.faction == "Horde" then
                        color = {r=1, g=0.13, b=0.13}
                    elseif d.faction == "Alliance" then
                        color = {r=0, g=0.44, b=0.87}
                    else
                        color = {r=0.7, g=0.7, b=0.7}
                    end
                else
                    -- Class-based coloring (default)
                    color = RAID_CLASS_COLORS[classKey] or {r=1, g=1, b=1}
                end
                nameText:SetText(displayName); nameText:SetTextColor(color.r, color.g, color.b)
                levelText:SetText((d.level or 0) > 0 and d.level or "??")
                classText:SetText(displayClass)
                
                -- Support for ElvUI Class Icons
                if button.icon then
                    if classKey ~= "" and _G.CLASS_ICON_TCOORDS[classKey] then
                        button.icon:Show()
                        button.icon:SetTexCoord(unpack(_G.CLASS_ICON_TCOORDS[classKey]))
                    else
                        button.icon:Hide()
                    end
                end
                
                if dCol == "guild" then variableText:SetText(d.guild or "")
                elseif dCol == "race" then variableText:SetText(d.race or "")
                elseif dCol == "seen" then variableText:SetText(GetRelativeTime(d.seen or 0))
                else variableText:SetText(d.zone or "") end
                
                button.playerName = d.name
                button:Show()
            else button:Hide() end
        end
    end



    local function UpdateSortArrows()
        for i = 1, 4 do
            local arrow = _G["WhoFrameColumnHeader"..i.."SortArrow"]
            if arrow then
                local colKey = (i == 1 and "name") or (i == 3 and "level") or (i == 4 and "class") or ""
                if i == 2 then
                    local dCol = UIDropDownMenu_GetSelectedValue(WhoFrameDropDown)
                    colKey = (dCol == "guild" and "guild" or (dCol == "race" and "race" or (dCol == "seen" and "seen" or "zone")))
                end
                if currentSortKey == colKey then
                    arrow:Show()
                    if currentSortOrder == "ASC" then arrow:SetTexCoord(0, 0.5625, 0, 1) else arrow:SetTexCoord(0, 0.5625, 1, 0) end
                else arrow:Hide() end
            end
        end
    end

    Whorkaround.SyncBrowser = function(force)
        if not tab1 or not tab1:GetChecked() or not WhoFrame:IsVisible() then return end
        Whorkaround_WhoList_Update()
    end
    
    local function CycleSort(key)
        if currentSortKey == key then
            if currentSortOrder == "ASC" then currentSortOrder = "DESC" else currentSortKey = "seen"; currentSortOrder = "DESC" end
        else currentSortKey = key; currentSortOrder = "ASC" end
        UpdateSortArrows(); Whorkaround_WhoList_Update()
    end

    local function Column_OnClick(self)
        if tab1 and tab1:GetChecked() then
            local name = self:GetName()
            if name == "WhoFrameColumnHeader1" then CycleSort("name")
            elseif name == "WhoFrameColumnHeader3" then CycleSort("level")
            elseif name == "WhoFrameColumnHeader4" then CycleSort("class")
            elseif name == "WhoFrameColumnHeader2" then
                local col = UIDropDownMenu_GetSelectedValue(WhoFrameDropDown)
                CycleSort(col == "guild" and "guild" or (col == "race" and "race" or (col == "seen" and "seen" or "zone")))
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
        if not tab1 or not tab2 or not settings then return end
        local browserActive = tab1:GetChecked()
        local settingsActive = tab2:GetChecked()

        if settingsActive then
            settings:Show()
            WhoFrameColumnHeader1:Hide(); WhoFrameColumnHeader2:Hide(); WhoFrameColumnHeader3:Hide(); WhoFrameColumnHeader4:Hide()
            WhoListScrollFrame:Hide(); WhoFrameEditBox:Hide(); WhoFrameWhoButton:Hide()
            WhoFrameAddFriendButton:Hide(); WhoFrameGroupInviteButton:Hide()
            WhoFrameTotals:Hide()
        else
            settings:Hide()
            if browserActive then
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
                    local text = self:GetText()
                    if text ~= "" and not text:find(" ") then Whorkaround:Query(text) end
                    Whorkaround_WhoList_Update(); self:ClearFocus()
                end)
                WhoFrameEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

                UIDropDownMenu_Initialize(WhoFrameDropDown, Whorkaround_DropDown_Initialize)
                local cur = UIDropDownMenu_GetSelectedValue(WhoFrameDropDown)
                if cur ~= "zone" and cur ~= "seen" then UIDropDownMenu_SetSelectedValue(WhoFrameDropDown, "zone") end
                
                WhoFrameColumnHeader1:Show(); WhoFrameColumnHeader2:Show(); WhoFrameColumnHeader3:Show(); WhoFrameColumnHeader4:Show()
                WhoListScrollFrame:Show(); 
                WhoListScrollFrameScrollBar:Show();
                WhoFrameEditBox:Show(); WhoFrameWhoButton:Show()
                WhoFrameAddFriendButton:Show(); WhoFrameGroupInviteButton:Show()
                WhoFrameTotals:Show()
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
                
                WhoFrameColumnHeader1:Show(); WhoFrameColumnHeader2:Show(); WhoFrameColumnHeader3:Show(); WhoFrameColumnHeader4:Show()
                WhoListScrollFrame:Show(); WhoFrameEditBox:Show(); WhoFrameWhoButton:Show()
                WhoFrameAddFriendButton:Show(); WhoFrameGroupInviteButton:Show()
                WhoFrameTotals:Show()
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

    local tabBox = CreateEditBox(settings, "Output Chat Tab(s)", "outputTab", "Enter tab names separated by commas (e.g. General, Log). Leave blank for default.")
    tabBox:SetPoint("TOPLEFT", 20, -45)
    components.tabBox = tabBox

    local autoOpen = CreateCheckBox(settings, "Auto-open database browser", "overrideWho", "Automatically toggles the database view when opening the Social panel.")
    autoOpen:SetPoint("TOPLEFT", tabBox, "BOTTOMLEFT", 0, -10)
    components.autoOpen = autoOpen

    local proxyCheck = CreateCheckBox(settings, "Enable Proxy Mode", "allowProxy", "Allows other users to query players through you.")
    proxyCheck:SetPoint("TOPLEFT", autoOpen, "BOTTOMLEFT", 0, -5)
    components.proxyCheck = proxyCheck

    local factionColorCheck = CreateCheckBox(settings, "Use Faction Colors in Browser", "factionColors", "Colors player names by faction (Horde/Alliance) instead of class in the database browser.")
    factionColorCheck:SetPoint("TOPLEFT", proxyCheck, "BOTTOMLEFT", 0, -5)
    components.factionColorCheck = factionColorCheck

    local retentionSlider = CreateSlider(settings, "Keep Cached players for", "retentionWeeks", 1, 4, 1)
    retentionSlider:SetPoint("TOPLEFT", factionColorCheck, "BOTTOMLEFT", 10, -30)
    components.retentionSlider = retentionSlider

    -- Stats Display (Moved to bottom edge)
    local statsHeader = settings:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statsHeader:SetPoint("BOTTOMLEFT", 20, 40); statsHeader:SetText("Database Statistics")
    
    local statsTotal = settings:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statsTotal:SetPoint("TOPLEFT", statsHeader, "BOTTOMLEFT", 0, -2); statsTotal:SetTextColor(0.53, 0.53, 0.53)
    
    local statsFactions = settings:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statsFactions:SetPoint("TOPLEFT", statsTotal, "BOTTOMLEFT", 0, -8)

    local statsNetwork = settings:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    statsNetwork:SetPoint("TOPLEFT", statsFactions, "BOTTOMLEFT", 0, -8)
    statsNetwork:SetTextColor(0.53, 0.53, 0.53)
    
    -- Interaction Hitboxes for Tooltips
    local aHit = CreateFrame("Frame", nil, settings)
    aHit:SetSize(90, 30); aHit:SetPoint("LEFT", statsFactions, "LEFT", -10, 0); aHit:EnableMouse(true)
    
    local hHit = CreateFrame("Frame", nil, settings)
    hHit:SetSize(90, 30); hHit:SetPoint("RIGHT", statsFactions, "RIGHT", 10, 0); hHit:EnableMouse(true)

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
        if not Whorkaround_DB then statsTotal:SetText("No data available."); statsFactions:SetText(""); return end
        local total, alliance, horde = 0, 0, 0
        for name, data in pairs(Whorkaround_DB) do
            total = total + 1
            if data.faction == "Alliance" then alliance = alliance + 1
            elseif data.faction == "Horde" then horde = horde + 1 end
        end
        statsTotal:SetText(string.format("Total Players: %d", total))
        local aIcon = "|TInterface\\PVPFrame\\PVP-Currency-Alliance:20:20:0:5|t"
        local hIcon = "|TInterface\\PVPFrame\\PVP-Currency-Horde:20:20:0:5|t"
        statsFactions:SetText(string.format("%s |cff0070dd%d|r      %s |cffff2020%d|r", aIcon, alliance, hIcon, horde))
        SetStatTooltip(aHit, "Alliance", {r=0, g=0.44, b=0.87}, alliance)
        SetStatTooltip(hHit, "Horde", {r=1, g=0.12, b=0.12}, horde)
        -- Network peer counts (populated by Comm.lua passively)
        local peerCount, proxyCount = 0, 0
        for _ in pairs(Whorkaround.networkPeers or {}) do peerCount = peerCount + 1 end
        for _ in pairs(Whorkaround.proxyPeers or {}) do proxyCount = proxyCount + 1 end
        if peerCount > 0 then
            statsNetwork:SetText(string.format("Network: %d peer%s seen  (|cff9b59b6%d prox%s|r)",
                peerCount, peerCount == 1 and "" or "s",
                proxyCount, proxyCount == 1 and "y" or "ies"))
        else
            statsNetwork:SetText("Network: No peers seen this session")
        end
    end
    Whorkaround.UpdateStats = UpdateStats
    settings:SetScript("OnShow", UpdateStats)

    local clearBtn = CreateButton(settings, "Clear Database", 130, 22)
    clearBtn:SetPoint("BOTTOMRIGHT", -10, 10)
    components.clearBtn = clearBtn

    -- Notify skinning module about local components
    if Whorkaround.SkinGUIComponents then
        Whorkaround:SkinGUIComponents(components)
    end
    
    WhoFrameColumnHeader1:HookScript("OnClick", Column_OnClick)
    WhoFrameColumnHeader2:HookScript("OnClick", Column_OnClick)
    WhoFrameColumnHeader3:HookScript("OnClick", Column_OnClick)
    WhoFrameColumnHeader4:HookScript("OnClick", Column_OnClick)
    
    local function WhoButton_OnClick_Hook(self, button)
        if tab1 and tab1:GetChecked() and self.playerName then
            if button == "LeftButton" and IsShiftKeyDown() then
                local d = Whorkaround_DB and Whorkaround_DB[self.playerName:lower()]
                if d then
                    local displayName = self.playerName:gsub("^%l", string.upper)
                    local link = string.format("|Hplayer:%s|h[%s]|h", self.playerName, displayName)
                    local eb = ChatEdit_GetActiveWindow() or (LastSayName and _G[LastSayName.."EditBox"]) or _G["ChatFrameEditBox"]
                    if eb and eb:IsVisible() then eb:Insert(link)
                    else print(string.format("%s: Level %d %s %s - %s", link, d.level, d.faction or "", d.class, d.zone)) end
                end
            elseif button == "LeftButton" then
                WhoFrame.selectedWho = self.playerName
                WhoFrame.selectedName = self.playerName
                Whorkaround_WhoList_Update()
            end
        end
    end
    for i=1, 17 do _G["WhoFrameButton"..i]:HookScript("OnClick", WhoButton_OnClick_Hook) end

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

    -- Dropdown Hijack
    hooksecurefunc("WhoFrameDropDown_Initialize", function()
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Last Seen"
        info.value = "seen"
        info.func = function(self)
            UIDropDownMenu_SetSelectedValue(WhoFrameDropDown, self.value)
            Whorkaround_WhoList_Update()
        end
        UIDropDownMenu_AddButton(info)
    end)

    tab1 = CreateFrame("CheckButton", "WhorkaroundSideTab1", FriendsFrame)
    tab1:SetSize(32, 32); tab1:SetPoint("TOPLEFT", FriendsFrame, "TOPRIGHT", -32, -42)
    tab1:SetNormalTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
    tab1:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    tab1:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    tab1:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
    local tab1Bg = tab1:CreateTexture(nil, "BACKGROUND"); tab1Bg:SetSize(64, 64); tab1Bg:SetPoint("TOPLEFT", -3, 11); tab1Bg:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    tab1:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Database Browser", 1, 1, 1); GameTooltip:Show()
    end)
    tab1:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tab1:SetScript("OnClick", function(self)
        if self:GetChecked() then tab2:SetChecked(false) end
        SyncUI()
    end)

    tab2 = CreateFrame("CheckButton", "WhorkaroundSideTab2", FriendsFrame)
    tab2:SetSize(32, 32); tab2:SetPoint("TOPLEFT", tab1, "BOTTOMLEFT", 0, -18)
    tab2:SetNormalTexture("Interface\\Icons\\INV_Misc_Gear_01")
    tab2:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    tab2:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    tab2:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
    local tab2Bg = tab2:CreateTexture(nil, "BACKGROUND"); tab2Bg:SetSize(64, 64); tab2Bg:SetPoint("TOPLEFT", -3, 11); tab2Bg:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    tab2:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Whorkaround Options", 1, 1, 1); GameTooltip:Show()
    end)
    tab2:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tab2:SetScript("OnClick", function(self)
        if self:GetChecked() then tab1:SetChecked(false) end
        SyncUI()
    end)

    clearBtn:SetScript("OnClick", function() StaticPopup_Show("WHORKAROUND_CONFIRM_CLEAR") end)
    
    Whorkaround.ToggleButton = tab1
    
    -- Persistent Visibility Lockdown
    local function Lockdown()
        if tab2 and tab2:GetChecked() then
            WhoFrameColumnHeader1:Hide(); WhoFrameColumnHeader2:Hide(); WhoFrameColumnHeader3:Hide(); WhoFrameColumnHeader4:Hide()
            WhoListScrollFrame:Hide(); WhoFrameEditBox:Hide(); WhoFrameWhoButton:Hide()
            WhoFrameAddFriendButton:Hide(); WhoFrameGroupInviteButton:Hide()
            WhoFrameTotals:Hide()
        end
    end
    hooksecurefunc(WhoFrameEditBox, "Show", Lockdown)
    hooksecurefunc(WhoListScrollFrame, "Show", Lockdown)
    hooksecurefunc(WhoFrameWhoButton, "Show", Lockdown)

    WhoFrame:HookScript("OnUpdate", function(self)
        if tab2 and tab2:GetChecked() then Lockdown() end
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

    hooksecurefunc("WhoList_Update", function()
        if tab1 and tab1:GetChecked() then
            Whorkaround_WhoList_Update()
        end
    end)

    -- Apply ElvUI Skinning if available
    if Whorkaround.ApplyElvUISkin then
        Whorkaround:ApplyElvUISkin()
    end
end

-- Hook into Social Frame
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function()
    Whorkaround:InitGUI()
end)
