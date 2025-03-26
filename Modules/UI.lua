GBankClassic_UI = LibStub("AceGUI-3.0")

function GBankClassic_UI:Init()
    GBankClassic_UI_Minimap:Init()
    GBankClassic_UI_Inventory:Init()
    GBankClassic_UI_Donations:Init()
    GBankClassic_UI_Search:Init()
    GBankClassic_UI_Mail:Init()
end

function GBankClassic_UI:Controller()
    --this is used to process escape to exit events
    local controller = CreateFrame("Frame","GBankClassic",UIParent)
    controller:SetScript("OnHide", function()
        GBankClassic_UI_Inventory:Close()
    end)
    --insert to global escape table
    table.insert(UISpecialFrames, "GBankClassic")
end

--handle all events
function GBankClassic_UI:EventHandler(self, event, ...)
    if event == "OnClick" then
        if IsShiftKeyDown() then
            ChatEdit_InsertLink(self.link)
        elseif IsControlKeyDown() then
            DressUpItemLink(self.link)
        else
            PickupItem(self.link)
        end
    end
    if event == "OnDragStart" then
        PickupItem(self.link)
    end
end

function GBankClassic_UI:DrawItem(item, parent, size, height, imageSize, imageHeight, labelXOffset, labelYOffset)
    if not size then
        size = 40
    end

    if not height then
        height = 40
    end

    if not imageSize then
        imageSize = 40
    end

    if not imageHeight then
        imageHeight = 40
    end

    if not labelXOffset then
        labelYOffset = 0
    end

    if not labelYOffset then
        labelYOffset = 0
    end

    local slot = GBankClassic_UI:Create("Icon")
    local label = slot.label
    local image = slot.image
    local frame = slot.frame

    image:SetPoint("TOP",image:GetParent(),"TOP",0,0)
    if item.Count > 1 then
        slot:SetLabel(item.Count)
        --format the label
        local fontName,fontHeight = label:GetFont()
        label:SetFont(fontName, fontHeight, "OUTLINE")
        --clear the set points
        label:ClearAllPoints()
        label:SetPoint("BOTTOMRIGHT",label:GetParent(),"BOTTOMRIGHT", labelXOffset, labelYOffset) --use this to position label
        label:SetHeight(14)
        label:SetShadowColor(0,0,0)
    else
        slot:SetLabel(" ")
    end
    slot:SetImage(item.Info.icon)
    slot:SetImageSize(imageSize, imageHeight)
    slot:SetWidth(size)
    slot:SetHeight(height)

    if item.Link then
        slot:SetCallback("OnEnter", function() GBankClassic_UI:ShowItemTooltip(item.Link) end)
        slot:SetCallback("OnLeave", function() GBankClassic_UI:HideTooltip() end)

        --handle on click or drag
        slot:SetCallback("OnClick", function (self, event)
            GBankClassic_UI:EventHandler(self, event)
        end)
        frame:RegisterForDrag("LeftButton");
        frame:SetScript("OnDragStart", function (_)
            GBankClassic_UI:EventHandler(slot, "OnDragStart")
        end)
    end

    slot.info = item.Info
    slot.link = item.Link

    --border highlight
    local border = frame:CreateTexture(nil,"OVERLAY")
    border:SetAllPoints(image)
    border:SetTexCoord(0, 0, 0,1,1, 0,1,1)
    border:SetBlendMode("BLEND")
    border:SetTexture("Interface\\Common\\WhiteIconFrame")
    --fix issue where rarity doesn't return immediately
    if item.Info.rarity then
        local r, g, b = GetItemQualityColor(item.Info.rarity)
        border:SetVertexColor(r,g,b)
    end

    slot.border = border
    parent:AddChild(slot)
end


function GBankClassic_UI:ShowItemTooltip(link)
    if not link then return end
    GameTooltip:SetOwner(WorldFrame, "ANCHOR_CURSOR")
    GameTooltip:SetHyperlink(link)
    GameTooltip:Show()
end

function GBankClassic_UI:HideTooltip()
    GameTooltip:Hide()
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
end

function GBankClassic_UI:OnInsertLink(link)
    if GBankClassic_UI_Search.searchField and GBankClassic_UI_Search.searchField.editbox:HasFocus() then
        GBankClassic_UI_Search.SearchText = link
        GBankClassic_UI_Search:DrawContent()
    end
end
