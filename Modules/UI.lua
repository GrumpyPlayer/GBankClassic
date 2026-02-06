local Globals = GBankClassic_Globals
local upvalues = Globals.GetUpvalues("LibStub")
local LibStub = upvalues.LibStub
local upvalues = Globals.GetUpvalues("CreateFrame", "IsShiftKeyDown", "ChatEdit_InsertLink", "IsControlKeyDown", "DressUpItemLink", "PickupItem", "GetItemInfo", "GetItemQualityColor", "GameTooltip_SetDefaultAnchor")
local CreateFrame = upvalues.CreateFrame
local IsShiftKeyDown = upvalues.IsShiftKeyDown
local ChatEdit_InsertLink = upvalues.ChatEdit_InsertLink
local IsControlKeyDown = upvalues.IsControlKeyDown
local DressUpItemLink = upvalues.DressUpItemLink
local PickupItem = upvalues.PickupItem
local GetItemInfo = upvalues.GetItemInfo
local GetItemQualityColor = upvalues.GetItemQualityColor
local GameTooltip_SetDefaultAnchor = upvalues.GameTooltip_SetDefaultAnchor
local upvalues = Globals.GetUpvalues("UIParent", "UISpecialFrames", "WorldFrame", "GameTooltip")
local UIParent = upvalues.UIParent
local UISpecialFrames = upvalues.UISpecialFrames
local WorldFrame = upvalues.WorldFrame
local GameTooltip = upvalues.GameTooltip

GBankClassic_UI = LibStub("AceGUI-3.0")

local UI = GBankClassic_UI

function UI:Init()
    GBankClassic_UI_Minimap:Init()
    GBankClassic_UI_Inventory:Init()
    GBankClassic_UI_Donations:Init()
	-- GBankClassic_UI_Requests:Init()
    GBankClassic_UI_Search:Init()
end

function UI:Controller()
    local controller = CreateFrame("Frame", "GBankClassic", UIParent)
    controller:SetScript("OnHide", function()
        GBankClassic_UI_Inventory:Close()
    end)
    table.insert(UISpecialFrames, "GBankClassic")
end

function UI:EventHandler(self, event, ...)
    if event == "OnClick" then
        if IsShiftKeyDown() then
            ChatEdit_InsertLink(self.link)
        elseif IsControlKeyDown() then
			if self.link then
				DressUpItemLink(self.link)
			end
        else
			if self.link then
				PickupItem(self.link)
			end
        end
    end
    if event == "OnDragStart" then
		if self.link then
			PickupItem(self.link)
		end
    end
end

function UI:DrawItem(item, parent, size, height, imageSize, imageHeight, labelXOffset, labelYOffset)
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

    local slot = self:Create("Icon")
    local label = slot.label
    local image = slot.image
    local frame = slot.frame

    image:SetPoint("TOP", image:GetParent(), "TOP", 0, 0)
    if item.Count > 1 then
        slot:SetLabel(item.Count)
        local fontName, fontHeight = label:GetFont()
        label:SetFont(fontName, fontHeight, "OUTLINE")
        label:ClearAllPoints()
        label:SetPoint("BOTTOMRIGHT", label:GetParent(), "BOTTOMRIGHT", labelXOffset, labelYOffset)
        label:SetHeight(14)
        label:SetShadowColor(0, 0, 0)
    else
        slot:SetLabel(" ")
    end
	
	-- Generate link on-demand if needed (synchronous from cache if available)
	if item.ID and not item.Link then
		GBankClassic_Guild:ReconstructItemLink(item)
	end

	-- Get icon if available, otherwise try to fetch from item ID
	local icon = (item.Info and item.Info.icon) or select(10, GetItemInfo(item.ID or 0))
	if icon then
		slot:SetImage(icon)
	end
    slot:SetImageSize(imageSize, imageHeight)
    slot:SetWidth(size)
    slot:SetHeight(height)

    if item.Link then
        slot:SetCallback("OnEnter", function()
            self:ShowItemTooltip(item.Link) 
        end)
        slot:SetCallback("OnLeave", function()
            self:HideTooltip()
        end)
        slot:SetCallback("OnClick", function(self, event)
            UI:EventHandler(self, event)
        end)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function(_)
            self:EventHandler(slot, "OnDragStart")
        end)
    end
    slot.info = item.Info
    slot.link = item.Link

    local border = frame:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints(image)
    border:SetTexCoord(0, 0, 0, 1, 1, 0, 1, 1)
    border:SetBlendMode("BLEND")
    border:SetTexture("Interface\\Common\\WhiteIconFrame")
    if item.Info.rarity then
        local r, g, b = GetItemQualityColor(item.Info.rarity)
        border:SetVertexColor(r, g, b)
    end
    slot.border = border

    parent:AddChild(slot)

	return slot
end

function UI:ShowItemTooltip(link)
    if not link then
        return
    end
    
    GameTooltip:SetOwner(WorldFrame, "ANCHOR_CURSOR")
    GameTooltip:SetHyperlink(link)
    GameTooltip:Show()
end

function UI:HideTooltip()
    GameTooltip:Hide()
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
end

function UI:OnInsertLink(link)
    if GBankClassic_UI_Search.searchField and GBankClassic_UI_Search.searchField.editbox:HasFocus() then
        GBankClassic_UI_Search.SearchText = link
        GBankClassic_UI_Search:DrawContent()
    end
end