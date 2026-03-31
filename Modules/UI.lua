local addonName, GBCR = ...

GBCR.UI = {}
local UI = GBCR.UI

local Globals = GBCR.Globals
local debugprofilestop = Globals.debugprofilestop
local CreateFrame = Globals.CreateFrame
local IsShiftKeyDown = Globals.IsShiftKeyDown
local ChatEdit_InsertLink = Globals.ChatEdit_InsertLink
local IsControlKeyDown = Globals.IsControlKeyDown
local DressUpItemLink = Globals.DressUpItemLink
local PickupItem = Globals.PickupItem
local GetItemQualityColor = Globals.GetItemQualityColor
local GameTooltip_SetDefaultAnchor = Globals.GameTooltip_SetDefaultAnchor
local After = Globals.After
local UIParent = Globals.UIParent
local UISpecialFrames = Globals.UISpecialFrames
local WorldFrame = Globals.WorldFrame
local GameTooltip = Globals.GameTooltip

local Constants = GBCR.Constants

function UI:Init()
    GBCR.UI.Minimap:Init()
    GBCR.UI.Inventory:Init()
    GBCR.UI.Search:Init()
    GBCR.UI.Donations:Init()
end

function UI:QueueUIRefresh()
    -- GBCR.Output:Debug("UI", "UI:QueueUIRefresh called (callstack=%s)", debugstack()) --TODO
    GBCR.Output:Debug("UI", "UI:QueueUIRefresh called")
    if self.isRefreshPending then
        return
    end

    self.isRefreshPending = true

    After(2.5, function()
        -- TODO: can we avoid always refreshing the current tab any time any data changes and instead detect if the changed data is for the currently displayed guild bank alt (GBCR.UI.Inventory.currentTab)?
        self.isRefreshPending = false
        -- GBCR.Output:Debug("UI", "Refreshing open UI windows (GBCR.UI.Inventory.isOpen=%s, GBCR.UI.Search.isOpen=%s, GBCR.UI.Search.searchText=%s, GBCR.UI.Donations.isOpen=%s, callstack=%s).", tostring(GBCR.UI.Inventory.isOpen), tostring(GBCR.UI.Search.isOpen), GBCR.UI.Search.searchText or "", tostring(GBCR.UI.Donations.isOpen), debugstack()) --TODO
        GBCR.Output:Debug("UI", "Refreshing open UI windows (GBCR.UI.Inventory.isOpen=%s, GBCR.UI.Search.isOpen=%s, GBCR.UI.Search.searchText=%s, GBCR.UI.Donations.isOpen=%s).", tostring(GBCR.UI.Inventory.isOpen), tostring(GBCR.UI.Search.isOpen), GBCR.UI.Search.searchText or "", tostring(GBCR.UI.Donations.isOpen))

        if GBCR.UI.Inventory.isOpen then
            GBCR.UI.Inventory:DrawContent()
        end
        if GBCR.UI.Search.isOpen then
            GBCR.UI.Search:BuildSearchData()
            GBCR.UI.Search:DrawContent()
            if GBCR.UI.Search.searchField then
                local onEnterPressed = GBCR.UI.Search.searchField:GetScript("OnEnterPressed")
                if onEnterPressed then
                    onEnterPressed(GBCR.UI.Search.searchField)
                end
            end
        end
        if GBCR.UI.Donations.isOpen then
            GBCR.UI.Donations:DrawContent()
        end
    end)
end

function UI:Controller()
    local controller = CreateFrame("Frame", "GBankClassic", UIParent)
    controller:SetScript("OnHide", function()
        GBCR.UI.Inventory:Close()
    end)
    table.insert(UISpecialFrames, "GBankClassic")
end

function UI:EventHandler(self, event)
    if event == "OnClick" then
        if IsShiftKeyDown() then
            ChatEdit_InsertLink(self.itemLink)
        elseif IsControlKeyDown() then
			if self.itemLink then
				DressUpItemLink(self.itemLink)
			end
        else
			if self.itemLink then
				PickupItem(self.itemLink)
			end
        end
    end
    if event == "OnDragStart" then
		if self.itemLink then
			PickupItem(self.itemLink)
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

    local slot = GBCR.Libs.AceGUI:Create("Icon")
    local label = slot.label
    local image = slot.image
    local frame = slot.frame

    image:SetPoint("TOP", image:GetParent(), "TOP", 0, 0)
    if item.itemCount > 1 then
        slot:SetLabel(item.itemCount)
        local fontName, fontHeight = label:GetFont()
        label:SetFont(fontName, fontHeight, "OUTLINE")
        label:ClearAllPoints()
        label:SetPoint("BOTTOMRIGHT", label:GetParent(), "BOTTOMRIGHT", labelXOffset, labelYOffset)
        label:SetHeight(14)
        label:SetShadowColor(0, 0, 0)
    else
        slot:SetLabel(" ")
    end

	-- Generate itemLink on-demand if needed (synchronous from cache if available)
	if item.itemId and not item.itemLink then
		GBCR.Protocol:ReconstructItemLink(item)
	end

    -- Icon already loaded by GetItems
    local icon = item.itemInfo and item.itemInfo.icon
	if icon then
		slot:SetImage(icon)
	end
    slot:SetImageSize(imageSize, imageHeight)
    slot:SetWidth(size)
    slot:SetHeight(height)

    if item.itemLink then
        slot:SetCallback("OnEnter", function()
            self:ShowItemTooltip(item.itemLink)
        end)
        slot:SetCallback("OnLeave", function()
            self:HideTooltip()
        end)
        slot:SetCallback("OnClick", function(event)
            self:EventHandler(event)
        end)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function()
            self:EventHandler(slot, "OnDragStart")
        end)
    end
    slot.info = item.itemInfo
    slot.itemLink = item.itemLink

    local border = frame:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints(image)
    border:SetTexCoord(0, 0, 0, 1, 1, 0, 1, 1)
    border:SetBlendMode("BLEND")
    border:SetTexture("Interface\\Common\\WhiteIconFrame")
    if item.itemInfo.rarity then
        local r, g, b = GetItemQualityColor(item.itemInfo.rarity)
        border:SetVertexColor(r, g, b)
    end
    slot.border = border

    parent:AddChild(slot)

	return slot
end

function UI:ShowItemTooltip(itemLink)
    if not itemLink then
        return
    end

    local now = debugprofilestop()
    if self.currentTooltipLink == itemLink and (now - (self.tooltipThrottle or 0)) < Constants.TIMER_INTERVALS.TOOLTIP_THROTTLE_MS then
        return
    end

    self.tooltipThrottle = now
    self.currentTooltipLink = itemLink

    GameTooltip:SetOwner(WorldFrame, "ANCHOR_CURSOR")
    GameTooltip:SetHyperlink(itemLink)
    GameTooltip:Show()
end

function UI:HideTooltip()
    self.currentTooltipLink = nil
    self.tooltipThrottle = nil
    GameTooltip:Hide()
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
end

function UI:OnInsertLink(itemLink)
    if GBCR.UI.Search.searchField and GBCR.UI.Search.searchField:HasFocus() then
        GBCR.UI.Search.searchText = itemLink
        GBCR.UI.Search:DrawContent()
    end
end

function UI:ClampFrameToScreen(frame)
	if not frame then
		return
	end

	-- Get the actual frame object (handle both AceGUI widgets and raw frames)
	local actualFrame = frame.frame or frame
	if not actualFrame or not actualFrame.GetRect then
		return
	end

	-- Get frame dimensions
	local left, bottom, width, height = actualFrame:GetRect()
	if not left or not bottom or not width or not height then
		return
	end

	local right = left + width
	local top = bottom + height

	-- Get screen dimensions
	local screenWidth = UIParent:GetWidth()
	local screenHeight = UIParent:GetHeight()

	-- Calculate adjustments needed
	local xOffset = 0
	local yOffset = 0

	-- Check horizontal bounds
	if left < 0 then
		xOffset = -left
	elseif right > screenWidth then
		xOffset = screenWidth - right
	end

	-- Check vertical bounds
	if bottom < 0 then
		yOffset = -bottom
	elseif top > screenHeight then
		yOffset = screenHeight - top
	end

	-- Apply adjustments if needed
	if xOffset ~= 0 or yOffset ~= 0 then
		actualFrame:ClearAllPoints()
		actualFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left + xOffset, bottom + yOffset)
	end
end