local Whorkaround = select(2, ...)

-- Skin internal components (Defined at root so it captures InitGUI calls)
function Whorkaround:SkinGUIComponents(components)
    if not IsAddOnLoaded("ElvUI") then return end
    local E, L, V, P, G = unpack(ElvUI)
    local S = E:GetModule("Skins")

    if components.maintenanceMenu then S:HandleDropDownBox(components.maintenanceMenu) end
    if components.retentionSlider then S:HandleSliderFrame(components.retentionSlider) end
    
    if components.tabBox then
        -- tabBox is a container, find the EditBox inside
        for _, child in ipairs({components.tabBox:GetChildren()}) do
            if child:IsObjectType("EditBox") then 
                S:HandleEditBox(child)
                child:StripTextures()
                child:CreateBackdrop("Default")
            end
        end
    end
    
    -- Checkboxes
    if components.autoOpen then S:HandleCheckBox(components.autoOpen) end
    if components.proxyCheck then S:HandleCheckBox(components.proxyCheck) end
    if components.factionColorCheck then S:HandleCheckBox(components.factionColorCheck) end
end

function Whorkaround:ApplyElvUISkin()
    if not IsAddOnLoaded("ElvUI") then return end
    local E, L, V, P, G = unpack(ElvUI)
    local S = E:GetModule("Skins")

    -- Skin Side Tabs
    for i = 1, 2 do
        local tab = _G["WhorkaroundSideTab"..i]
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
        settings:SetTemplate("Default") -- Use solid template for readability
        
        -- Add a secondary inner backdrop for extra contrast if needed
        if not settings.innerBackdrop then
            local ib = CreateFrame("Frame", nil, settings)
            ib:SetAllPoints()
            ib:SetFrameLevel(settings:GetFrameLevel() - 1)
            ib:SetTemplate("Transparent") -- Layered for that "double background" look
            settings.innerBackdrop = ib
        end
    end
end
