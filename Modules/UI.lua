local addonName, GBCR = ...

GBCR.UI = {}
local UI = GBCR.UI

local Globals = GBCR.Globals
local date = Globals.date
local string_format = Globals.string_format
local tostring = Globals.tostring
local type = Globals.type
local wipe = Globals.wipe

local After = Globals.After
local ChatEdit_InsertLink = Globals.ChatEdit_InsertLink
local debugprofilestop = Globals.debugprofilestop
local DressUpItemLink = Globals.DressUpItemLink
local GameTooltip = Globals.GameTooltip
local GameTooltip_SetDefaultAnchor = Globals.GameTooltip_SetDefaultAnchor
local GetCoinTextureString = Globals.GetCoinTextureString
local GetItemQualityColor = Globals.GetItemQualityColor
local IsControlKeyDown = Globals.IsControlKeyDown
local IsShiftKeyDown = Globals.IsShiftKeyDown
local PickupItem = Globals.PickupItem
local UIParent = Globals.UIParent
local WorldFrame = Globals.WorldFrame

local Constants = GBCR.Constants
local colorBlue = Constants.COLORS.BLUE
local filterClassMap = Constants.FILTER.CLASS_MAP
local miscClass = Constants.FILTER.MISC_CLASSES
local rarityMap = Constants.FILTER.RARITY_MAP
local slotMap = Constants.FILTER.SLOT_MAP

-- Clears the contents of the debug output (with /bank debugclear) as seen in the seperate debug output window (/bank debuglog); called by GBCR.Constants
local function clearDebugContent(self)
    wipe(GBCR.Output.debugMessageBuffer)

    if GBCR.UI.Debug.content then
        GBCR.UI.Debug.content:SetText("")
    end

    GBCR.Output:Response("Debug output cleared.")
end

-- Called each time a new debug message needs to be logged to refresh the output window only once every x seconds (fixed delay); called by GBCR.Output
local function queueDebugLogRefresh(self)
    if GBCR.UI.Debug.isRefreshPending then
        return
    end

    GBCR.UI.Debug.isRefreshPending = true

    After(Constants.TIMER_INTERVALS.DEBUG_LOG_REFRESH, function()
        GBCR.UI.Debug.isRefreshPending = false

        if GBCR.UI.Debug.isOpen then
            GBCR.UI.Debug:DrawContent()
        end
    end)
end

-- Immediately draws all open UI windows and cancels any pending delayed refreshes; called when opening windows
local function forceDraw(self)
    GBCR.Output:Debug("UI", "UI:ForceDraw called")

    self.uiRefreshGeneration = (self.uiRefreshGeneration or 0) + 1

    if GBCR.UI.Inventory.isOpen then
        GBCR.UI.Inventory:DrawContent()
    end

    if GBCR.UI.Search.isOpen then
        GBCR.Search:BuildSearchData()
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
end

-- Called each time data changes to queue a UI refresh with native debouncing total prevent double-refreshes; called by GBCR.Events, GBCR.Protocol, GBCR.Guild, and GBCR.Inventory
local function queueUIRefresh(self)
    GBCR.Output:Debug("UI", "UI:QueueUIRefresh called")

    self.uiRefreshGeneration = (self.uiRefreshGeneration or 0) + 1
    local currentGen = self.uiRefreshGeneration

    After(Constants.TIMER_INTERVALS.UI_REFRESH, function()
        -- TODO: can we avoid always refreshing the current tab any time any data changes and instead detect if the changed data is for the currently displayed guild bank alt (GBCR.UI.Inventory.currentTab)?
        -- could we pass the altName that just updated into queueUIRefresh(self, updatedAltName) and only trigger GBCR.UI.Inventory:DrawContent() if updatedAltName == GBCR.UI.Inventory.currentTab?
        if self.uiRefreshGeneration ~= currentGen then
            return
        end

        forceDraw(self)
    end)
end

-- Restores the UI to their default sizes and positions; called by GBCR.Core, GBCR.Constants, and GBCR.UI.Minimap
local function restoreUI(self)
	local optionsDB = GBCR.Options:GetOptionsDB()
	if not optionsDB then
		return
	end

    local function resetWindow(module, moduleDefaultsKey)
        if not module.window then
			return
        end

        local window = module.window
        local frame = window.frame
        local defaults = optionsDB.defaults.profile.framePositions[moduleDefaultsKey]
		local newStatus = { width = defaults.width, height = defaults.height }

		if moduleDefaultsKey == "debug" then
			newStatus.left = UIParent:GetWidth() - defaults.width - 200
			newStatus.top = defaults.height + 50
		end

		optionsDB.profile.framePositions[moduleDefaultsKey] = newStatus
        window:SetStatusTable(optionsDB.profile.framePositions[moduleDefaultsKey])
        window:ApplyStatus()

        frame:ClearAllPoints()
        if moduleDefaultsKey == "inventory" then
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        else
            frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -200, 50)
        end
    end

    resetWindow(GBCR.UI.Inventory, "inventory")
    resetWindow(GBCR.UI.Debug, "debug")

	GBCR.Output:Response("The user interface window size and position have been reset to their defaults.")
end

-- To be able to drag and drop a link into the search field in the UI and search for that item name extracted from the item link; called by GBCR.Events
local function onInsertLink(self, itemLink)
    if GBCR.UI.Search.searchField and GBCR.UI.Search.searchField:HasFocus() then
        GBCR.UI.Search.searchText = itemLink
        GBCR.UI.Search:DrawContent()
    end
end

-- Helper function to count the number of active filters
local function getActiveFilterCount(self)
    local count = 0

    if self.filterType and self.filterType ~= "any" then
        count = count + 1
    end
    if self.filterSlot and self.filterSlot ~= "any" then
        count = count + 1
    end
    if self.filterRarity and self.filterRarity ~= "any" then
        count = count + 1
    end

    return count
end

-- Updates the status text at the bottom of the main UI (search and donation status text is handled seperately); called by GBCR.UI.Inventory
local function updateStatusText(self, filteredCount, totalCount, goldAmount, versionTimestamp)
    filteredCount = filteredCount or 0
    totalCount = totalCount or 0

    local activeFilters = getActiveFilterCount(self)
    local pluralFilters = (activeFilters ~= 1 and "s" or "")
    local filterText = activeFilters > 0 and Globals:Colorize(colorBlue, string_format(" (%d filter%s active)", activeFilters, pluralFilters)) or ""
    local pluralItems = (totalCount ~= 1 and "s" or "")

    if activeFilters > 0 then
        self.resetFiltersButton:SetDisabled(false)
        self.window:SetStatusText(string_format("Showing %d of %d item%s%s", filteredCount, totalCount, pluralItems, filterText))
        self.filteredCount = filteredCount
        self.totalCount = totalCount
    else
        self.resetFiltersButton:SetDisabled(true)

        local defaultStatus
        if type(versionTimestamp) == "number" and versionTimestamp > 0 then
            defaultStatus = string_format("%s%s", GetCoinTextureString(goldAmount), string_format(" as of %s", date("%b %d, %Y %H:%M", versionTimestamp)))
        else
            defaultStatus = "No available data"
        end
        self.window:SetStatusText(defaultStatus)
    end
end

-- Refresh the data displayed in one tab of the UI for a specific guild bank alt (one per tab); called by GBCR.UI.Inventory
local function refreshCurrentTab(self)
    GBCR.Output:Debug("UI", "UI_Inventory:RefreshCurrentTab called")

    local group = GBCR.UI.Inventory.tabGroup
    if not group then
        return
    end

    local current = group.localstatus.selected
    if not current then
        return
    end

    GBCR.UI.Inventory.tabLoaded = false

    group:ReleaseChildren()
    group:Fire("OnGroupSelected", current)
end

-- Reset all filters and see the default data for a given guild bank alt; called by GBCR.UI.Inventory
local function resetFilters(self)
    self.resetFiltersButton:SetDisabled(true)

    self.filterType = "any"
    self.filterSlot = "any"
    self.filterRarity = "any"

    if self.filterTypeDropdown then
        self.filterTypeDropdown:SetValue("any")
    end
    if self.filterSlotDropdown then
        self.filterSlotDropdown:SetValue("any")
    end
    if self.filterRarityDropdown then
        self.filterRarityDropdown:SetValue("any")
    end

    refreshCurrentTab(self)
end

-- Filter data for a given guild bank alt based on the filters; called by GBCR.UI.Inventory
local function passesFilters(self, item)
    if not item or not item.itemInfo then
        return true
    end

    local info = item.itemInfo

    if self.filterType and self.filterType ~= "any" then
        local class = info.class or 0
        local filterType = self.filterType

        if filterType == "misc" then
            if not miscClass[class] then
                return false
            end
        else
            local expectedClass = filterClassMap[filterType]
            if expectedClass and class ~= expectedClass then
                return false
            end
        end
    end

    if self.filterSlot and self.filterSlot ~= "any" then
        local targetSlot = slotMap[self.filterSlot]
        local equipId = info.equipId or 0

        if targetSlot and targetSlot ~= equipId then
            if self.filterSlot == "bag" and equipId ~= 0 then
                return false
            elseif self.filterSlot ~= "bag" and equipId ~= targetSlot then
                return false
            end
        end
    end

    if self.filterRarity and self.filterRarity ~= "any" then
        local rarity = info.rarity or 1
        local targetRarity = rarityMap[self.filterRarity]

        if targetRarity and rarity ~= targetRarity then
            return false
        end
    end

    return true
end

-- Show the item tooltip in the main UI but throttle these frequency; called by GBCR.UI.Inventory
local function showItemTooltip(self, itemLink)
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

-- Hide the item tooltips and reset the throttle frquencye; called by GBCR.UI.Inventory
local function hideTooltip(self)
    self.currentTooltipLink = nil
    self.tooltipThrottle = nil
    GameTooltip:Hide()
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
end

-- Callback handler to pick up an item to drop it in the search; called by GBCR.UI.Inventory
local function onDragStart(frameOrId)
    local dragId = type(frameOrId) == "table" and frameOrId.dragItemId or frameOrId
    if dragId then
        PickupItem(dragId)
    end
end

-- Callback handler to hover over an item to display the item tooltip; called by GBCR.UI.Inventory
local function onEnter(widget)
    local item = widget:GetUserData("item")
    if item and item.itemInfo then
        showItemTooltip(GBCR.UI, item.itemLink)
    end
end

-- Callback handler to stop displaying the item tooltip; called by GBCR.UI.Inventory
local function onLeave(widget)
    hideTooltip(GBCR.UI)
end

-- Callback handler to try out how a piece of armor or weapon would look like on the current character; called by GBCR.UI.Inventory and GBCR.UI.Search
local function onClick(widget, event)
    if IsShiftKeyDown() or IsControlKeyDown() then
        GBCR.UI:EventHandler(widget, event)
    end
end

-- Callback handler to draw the border of item in the color of the quality of that item; called by GBCR.UI.Search
local function onItemLoaded(itemId, itemLink, widget)
    local itemInfo = GBCR.Inventory:GetInfo(itemId, itemLink)
    if itemInfo and widget then
        widget:SetImage(itemInfo.icon)
        local r, g, b = GetItemQualityColor(itemInfo.rarity)
        if widget.border then
            widget.border:SetVertexColor(r, g, b)
        end
    end
end

-- Handle interaction with links in the main and search UI to create a link to share in the chat or to preview how gear would ike on the current character; called by GBCR.UI.Inventry and GBCR.UI.Search
local function eventHandler(self, widget, event)
    if event == "OnClick" then
        if IsShiftKeyDown() then
            ChatEdit_InsertLink(widget.itemLink)
        elseif IsControlKeyDown() then
			if widget.itemLink then
				DressUpItemLink(widget.itemLink)
			end
        else
            onDragStart(widget.itemId)
        end
    elseif event == "OnDragStart" then
		onDragStart(widget.itemId)
    end
end

-- Draws an icon for each search result and each item a given guild bank alt owns in their inventory; called by GBCR.UI.Inventry and GBCR.UI.Search
local function drawItem(self, item, parent, size, height, imageSize, imageHeight, labelXOffset, labelYOffset)
    size = size or 40
    height = height or 40
    imageSize = imageSize or 40
    imageHeight = imageHeight or 40
    labelXOffset = labelXOffset or 0
    labelYOffset = labelYOffset or 0

    local slot = GBCR.Libs.AceGUI:Create("Icon")
    local label = slot.label
    local image = slot.image
    local frame = slot.frame

    image:SetPoint("TOP", image:GetParent(), "TOP", 0, 0)

    if item.itemCount > 1 then
        local fontName, fontHeight = label:GetFont()

        slot:SetLabel(item.itemCount)
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
            showItemTooltip(self, item.itemLink)
        end)
        slot:SetCallback("OnLeave", function()
            hideTooltip(self)
        end)
        slot:SetCallback("OnClick", function(event)
            eventHandler(self, slot, event)
        end)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function()
            eventHandler(self, slot, "OnDragStart")
        end)
    end
    slot.info = item.itemInfo
    slot.itemLink = item.itemLink
    slot.itemId = item.itemId

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

-- Prevent UI windows from being drawn outside of the screen boundaries while still allowing them to be dragged out of view; called by GBCR.UI.Inventry, GBCR.UI.Search, GBCR.UI.Donations, and GBCR.UI.Debug
local function clampFrameToScreen(self, frame)
	if not frame then
		return
	end

	local actualFrame = frame.frame or frame
	if not actualFrame or not actualFrame.GetRect then
		return
	end

	local left, bottom, width, height = actualFrame:GetRect()
	if not left or not bottom or not width or not height then
		return
	end

	local right = left + width
	local top = bottom + height
	local screenWidth = UIParent:GetWidth()
	local screenHeight = UIParent:GetHeight()
	local xOffset = 0
	local yOffset = 0

	if left < 0 then
		xOffset = -left
	elseif right > screenWidth then
		xOffset = screenWidth - right
	end

	if bottom < 0 then
		yOffset = -bottom
	elseif top > screenHeight then
		yOffset = screenHeight - top
	end

	if xOffset ~= 0 or yOffset ~= 0 then
		actualFrame:ClearAllPoints()
		actualFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left + xOffset, bottom + yOffset)
	end
end

-- Initialize GBCR.UI.Inventory, GBCR.UI.Search and GBCR.UI.Donations; called by GBCR.Core
local function init(self)
    GBCR.UI.Minimap:Init()
    GBCR.UI.Inventory:Init()
    GBCR.UI.Search:Init()
    GBCR.UI.Donations:Init()
end

-- Export functions for other modules
UI.ClearDebugContent = clearDebugContent
UI.QueueDebugLogRefresh = queueDebugLogRefresh
UI.ForceDraw = forceDraw
UI.QueueUIRefresh = queueUIRefresh
UI.RestoreUI = restoreUI
UI.OnInsertLink = onInsertLink
UI.UpdatedStatusText = updateStatusText
UI.RefreshCurrentTab = refreshCurrentTab
UI.ResetFilters = resetFilters
UI.PassesFilters = passesFilters
UI.ShowItemTooltip = showItemTooltip
UI.HideTooltip = hideTooltip
UI.OnDragStart = onDragStart
UI.OnEnter = onEnter
UI.OnLeave = onLeave
UI.OnClick = onClick
UI.OnItemLoaded = onItemLoaded
UI.EventHandler = eventHandler
UI.DrawItem = drawItem
UI.ClampFrameToScreen = clampFrameToScreen
UI.Init = init