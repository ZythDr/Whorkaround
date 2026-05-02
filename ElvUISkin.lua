local Whorkaround = select(2, ...)

-- Skin internal components (Defined at root so it captures InitGUI calls)
function Whorkaround:SkinGUIComponents(components)
    if not ElvUI then return end
    local E, L, V, P, G = unpack(ElvUI)
    local S = E:GetModule("Skins")

    -- Respect ElvUI's "Blizzard Skins" and "Friends" skin settings
    if not E.private.skins.blizzard.enable or not E.private.skins.blizzard.friends then return end

    if components.maintenanceBtn then S:HandleNextPrevButton(components.maintenanceBtn, "down") end
    if components.proxyModeBtn then S:HandleNextPrevButton(components.proxyModeBtn, "down") end
    if components.debugLevelBtn then S:HandleNextPrevButton(components.debugLevelBtn, "down") end

    if components.tabBox then
        local eb = components.tabBox
        S:HandleEditBox(eb)
        eb:SetTextInsets(8, 8, 0, 0)
        if eb.backdrop then
            eb.backdrop:SetFrameLevel(eb:GetFrameLevel() - 1)
        end
    end

    -- Checkboxes (Generic handling for all other editboxes found in containers)
    for _, comp in pairs(components) do
        if type(comp) == "table" and comp.IsObjectType and comp:IsObjectType("EditBox") then
            S:HandleEditBox(comp)
            comp:SetTextInsets(8, 8, 0, 0)
            if comp.backdrop then
                comp.backdrop:SetFrameLevel(comp:GetFrameLevel() - 1)
            end
        end
    end

    -- Checkboxes
    if components.scannerCheck then S:HandleCheckBox(components.scannerCheck) end
    if components.debugCheck then S:HandleCheckBox(components.debugCheck) end
    if components.autoOpen then S:HandleCheckBox(components.autoOpen) end
    if components.proxyCheck then S:HandleCheckBox(components.proxyCheck) end
    if components.browserFactionColors then S:HandleCheckBox(components.browserFactionColors) end
    if components.factionColorCheck then S:HandleCheckBox(components.factionColorCheck) end


    if components.proxyCooldown then
        S:HandleSliderFrame(components.proxyCooldown)
    end
    if components.retentionSlider then
        S:HandleSliderFrame(components.retentionSlider)
    end
    -- Store components for later repositioning in ApplyElvUISkin
    Whorkaround.skinnedComponents = components
end

function Whorkaround:ApplyElvUISkin()
    if not ElvUI then return end
    local E, L, V, P, G = unpack(ElvUI)
    local S = E:GetModule("Skins")

    -- Respect ElvUI's "Blizzard Skins" and "Friends" skin settings
    if not E.private.skins.blizzard.enable or not E.private.skins.blizzard.friends then return end

    -- Skin Side Tabs
    for i = 1, 2 do
        local tab = _G["WhorkaroundSideTab" .. i]
        if tab then
            -- Save icon texture before stripping
            local iconTex = i == 1 and "Interface\\Icons\\INV_Misc_Spyglass_03" or "Interface\\Icons\\INV_Misc_Gear_01"

            tab:StripTextures()
            tab:SetTemplate("Default")
            tab:StyleButton()

            -- Re-apply icon
            tab:SetNormalTexture(iconTex)
            local icon = tab:GetNormalTexture()
            if icon then
                icon:SetTexCoord(unpack(E.TexCoords))
                icon:SetInside()
            end

            -- Position correction for ElvUI (Anchor to the backdrop edge, not the frame edge)
            local anchor = FriendsFrame.backdrop or FriendsFrame
            local xOffset = FriendsFrame.backdrop and (E.PixelMode and -1 or 1) or (E.PixelMode and -31 or -29)

            tab:ClearAllPoints()
            if i == 1 then
                tab:SetPoint("TOPLEFT", anchor, "TOPRIGHT", xOffset, -36)
            elseif i == 2 then
                tab:SetPoint("TOPLEFT", _G["WhorkaroundSideTab1"], "BOTTOMLEFT", 0, -(E.PixelMode and 2 or 4))
            end
        end
    end

    -- Skin Settings Panel
    local settings = _G["WhorkaroundSettingsPanel"]
    if settings then
        settings:StripTextures()
        settings:SetTemplate("Transparent")
    end

    -- Handle Browser Faction Counters repositioning for ElvUI
    local bAlliance = Whorkaround.skinnedComponents and Whorkaround.skinnedComponents.browserStatsAlliance
    local bHorde = Whorkaround.skinnedComponents and Whorkaround.skinnedComponents.browserStatsHorde
    if bAlliance and bHorde then
        bAlliance:ClearAllPoints()
        bAlliance:SetPoint("LEFT", WhoFrameTotals, "LEFT", -13, 0)
        bHorde:ClearAllPoints()
        bHorde:SetPoint("RIGHT", WhoFrameTotals, "RIGHT", 10, 0)
    end

    -- Handle Browser Faction Colors repositioning for ElvUI (Mirrored to left side)
    local browserFC = Whorkaround.skinnedComponents and Whorkaround.skinnedComponents.browserFactionColors
    if browserFC then
        browserFC:ClearAllPoints()
        browserFC:SetPoint("TOPLEFT", WhoFrame, "TOPLEFT", 24, -22)
        browserFC.text:ClearAllPoints()
        browserFC.text:SetPoint("LEFT", browserFC, "RIGHT", 2, 0)
    end
end
