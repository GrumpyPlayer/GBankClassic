local addonName, GBCR = ...

GBCR.UI.Inventory = {}
local UI_Inventory = GBCR.UI.Inventory

local Globals = GBCR.Globals
local math_min = Globals.math_min
local string_format = Globals.string_format
local type = Globals.type
local wipe = Globals.wipe

local After = Globals.After
local CreateFrame = Globals.CreateFrame
local GameTooltip = Globals.GameTooltip

local Constants = GBCR.Constants
local colorGray = Constants.COLORS.GRAY
local colorGreen = Constants.COLORS.GREEN
local colorOrange = Constants.COLORS.ORANGE
local colorYellow = Constants.COLORS.YELLOW

local function onClose(self)
    self.isOpen = false
    self.renderGeneration = (self.renderGeneration or 0) + 1

    GBCR.UI.Donations:Close()
    GBCR.UI.Search:Close()

    if self.window then
        self.window:Hide()
    end
end

local function drawContent(self)
    GBCR.Output:Debug("UI", "UI_Inventory:DrawContent called")

    local savedVariables = GBCR.Database.savedVariables
	local rosterGuildBankAlts = GBCR.Guild:GetRosterGuildBankAlts()
	if not savedVariables or not rosterGuildBankAlts then
		onClose(self)
		GBCR.Protocol:PerformSync()
		GBCR.Output:Response("Database is empty; wait for sync.")

		return
	end

    if self.currentTab then
        if not (savedVariables.alts and savedVariables.alts[self.currentTab]) then
            self.currentTab = nil
            self.tabLoaded = false
        end
    end

    local tabs = {}
    local firstTab = nil
    local firstTabMoney = nil
    local firstTabVersion = nil

    for i = 1, #rosterGuildBankAlts do
        local guildBankAltName = rosterGuildBankAlts[i]
		local alt = savedVariables.alts[guildBankAltName]

        if alt and type(alt) == "table" then
            if not firstTab then
                firstTab = guildBankAltName
                firstTabMoney = alt.money or 0
                firstTabVersion = alt.version or 0
            end

            tabs[i] = { value = guildBankAltName, text = guildBankAltName }
        end
    end

	if #tabs == 0 then
		onClose(self)
		GBCR.Protocol:PerformSync()
		GBCR.Output:Response("Database is empty; wait for sync.")

		return
	end

    self.tabGroup:ReleaseChildren()
    self.tabGroup.localstatus = {}
    self.tabGroup:SetTabs(tabs)
    GBCR.UI.UpdatedStatusText(UI_Inventory, self.filteredCount or "", self.totalCount or "", firstTabMoney, firstTabVersion)

    self.tabGroup:SetCallback("OnGroupSelected", function(group)
        local tab = group.localstatus.selected
        local aceGUI = GBCR.Libs.AceGUI

        if self.currentTab == tab and self.tabLoaded then
            return
        end

        self.currentTab = tab
        self.tabLoaded = false

        self.renderGeneration = (self.renderGeneration or 0) + 1
        local currentGeneration = self.renderGeneration

        GBCR.Output:Debug("ITEM", "Loading tab %s", tab)

        self.tabGroup:ReleaseChildren()

        local g = aceGUI:Create("SimpleGroup")
        g:SetFullWidth(true)
        g:SetFullHeight(true)
        g:SetLayout("Flow")
        self.tabGroup:AddChild(g)

        local alt = savedVariables.alts[tab]
        local scroll = aceGUI:Create("ScrollFrame")
        scroll:SetLayout("Flow")
        scroll:SetFullHeight(true)
        scroll:SetFullWidth(true)
        g:AddChild(scroll)

        scroll.callbackProcessed = false

        local items = alt.items
        GBCR.Output:Debug("ITEM", "Inventory tab %s: using alt.items (%d items)", tab, #items)

        GBCR.UI.UpdatedStatusText(UI_Inventory, "", "", alt.money or 0, alt.version or 0)

        if items and #items > 0 then
            GBCR.Inventory:GetItems(items, function(list)
                if scroll.callbackProcessed or self.currentTab ~= tab or self.renderGeneration ~= currentGeneration then
                    return
                end

                scroll.callbackProcessed = true
                scroll:ReleaseChildren()

                local listCount = list and #list or 0
                GBCR.Output:Debug("ITEM", "Inventory tab %s: GetItems callback received %d items", tab, listCount)

                self.tabLoaded = true

                wipe(self.cachedFilteredList)
                local filteredCount = 0

                for i = 1, listCount do
                    local item = list[i]
                    if GBCR.UI.PassesFilters(self, item) then
                        filteredCount = filteredCount + 1
                        self.cachedFilteredList[filteredCount] = item
                    end
                end
                GBCR.Inventory:Sort(self.cachedFilteredList, GBCR.Options:GetSortMode())

                GBCR.UI.UpdatedStatusText(UI_Inventory, filteredCount, listCount, alt.money or 0, alt.version or 0)

                if filteredCount == 0 then
                    local noResultsLabel = aceGUI:Create("Label")
                    local isLocal = (GBCR.Guild:GetNormalizedPlayer() == tab)

                    if isLocal and listCount == 0 then
                        noResultsLabel:SetText(string_format("%s\n\nNo data has been scanned yet, or no items found.\n\nTo populate your guild bank data:\n1. %s of your data via the addon options.\n2. Visit the %s to scan your bank and bags.\n3. Close your bank.\n4. Open and close your %s.\n5. If other guild members are online, %s for the share to complete.\n", Globals:Colorize(colorOrange, "This is you!"), Globals:Colorize(colorGreen, "Enable reporting and scanning"), Globals:Colorize(colorGreen, "bank"), Globals:Colorize(colorGreen, "mailbox"), Globals:Colorize(colorGreen, "wait")))
                    else
                        noResultsLabel:SetText(Globals:Colorize(colorGray, "No items match current filters."))
                    end

                    noResultsLabel:SetFullWidth(true)
                    scroll:AddChild(noResultsLabel)
                else
                    local output = GBCR.Output
                    local ui = GBCR.UI
                    local currentIndex = 1
                    local renderBatchSize = Constants.LIMITS.BATCH_SIZE

                    local function renderBatch()
                        if self.renderGeneration ~= currentGeneration then
                            return
                        end

                        local limit = math_min(currentIndex + renderBatchSize - 1, filteredCount)

                        for i = currentIndex, limit do
                            local item = self.cachedFilteredList[i]
                            output:Debug("ITEM", "Inventory tab %s: displaying %s with count %d (itemId: %d)", tab, item.itemInfo.name, item.itemCount or 0, item.itemId)

                            local itemWidget = ui:DrawItem(item, scroll)
                            if itemWidget then
                                itemWidget:SetUserData("item", item)
                                itemWidget:SetCallback("OnEnter", GBCR.UI.OnEnter)
                                itemWidget:SetCallback("OnLeave", GBCR.UI.OnLeave)
                                itemWidget:SetCallback("OnClick", GBCR.UI.OnClick)

                                local itemWidgetFrame = itemWidget.frame
                                itemWidgetFrame:RegisterForDrag("LeftButton")
                                itemWidgetFrame.dragItemId = item.itemId
                                itemWidgetFrame:SetScript("OnDragStart", GBCR.UI.OnDragStart)
                            end
                        end

                        currentIndex = limit + 1
                        if currentIndex <= filteredCount then
                            After(0, renderBatch)
                        else
                            scroll:DoLayout()
                        end
                    end

                    renderBatch()
                end
            end)
        else
            scroll:ReleaseChildren()
            local emptyLabel = aceGUI:Create("Label")
            emptyLabel:SetText(Globals:Colorize(colorGray, "No items found for this guild bank alt."))
            emptyLabel:SetFullWidth(true)
            scroll:AddChild(emptyLabel)
        end
    end)

	local currentTab = self.tabGroup.localstatus and self.tabGroup.localstatus.selected
	if currentTab and savedVariables.alts[currentTab] then
        if self.currentTab ~= currentTab then
            self.currentTab = nil
            self.tabGroup:SelectTab(currentTab)
        end
	else
        self.currentTab = nil
		self.tabGroup:SelectTab(firstTab)
	end
end

local function drawWindow(self)
    local aceGUI = GBCR.Libs.AceGUI
    local optionsDB = GBCR.Options:GetOptionsDB()

    local window = aceGUI:Create("Frame")
    window:Hide()
    window:SetCallback("OnClose", function()
        onClose(UI_Inventory)
    end)
    window:SetTitle(GBCR.Core.addonHeader)
    window:SetLayout("Flow")
    window:SetStatusTable(optionsDB.profile.framePositions.inventory)
    window.frame:SetResizeBounds(500, 500)
    window.frame:EnableKeyboard(true)
    window.frame:SetPropagateKeyboardInput(true)
    window.frame:SetScript("OnKeyDown", function(widget, event)
        GBCR.UI:EventHandler(widget, event)
    end)
    self.window = window

	local statusbg = window.statustext:GetParent()
	statusbg:ClearAllPoints()
	statusbg:SetPoint("BOTTOMLEFT",  window.frame, "BOTTOMLEFT",  15, 15)
	statusbg:SetPoint("BOTTOMRIGHT", window.frame, "BOTTOMRIGHT", -163, 15)

	local helpIcon = CreateFrame("Frame", nil, window.frame)
	helpIcon:SetSize(24, 24)
	helpIcon:SetPoint("BOTTOMRIGHT", window.frame, "BOTTOMRIGHT", -133, 15)
	helpIcon:EnableMouse(true)

	local helpText = helpIcon:CreateTexture(nil, "OVERLAY")
	helpText:SetAllPoints(helpIcon)
	helpText:SetTexture("Interface\\Common\\help-i")
	helpIcon:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:ClearLines()
		GameTooltip:AddLine(GBCR.Core.addonHeader)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(Globals:Colorize(colorYellow, "How it works:"), 1, 1, 1, false)
		GameTooltip:AddLine("Each tab shows one bank character.", 0.9, 0.9, 0.9, true)
		GameTooltip:AddLine("You only see items from the selected tab.", 0.9, 0.9, 0.9, true)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(Globals:Colorize(colorYellow, "Search items:"), 1, 1, 1, false)
		GameTooltip:AddLine("Displays first " .. Constants.LIMITS.SEARCH_RESULTS .. " matches across all bank characters.", 0.9, 0.9, 0.9, true)
		GameTooltip:AddLine("Type at least 3 letters.", 0.9, 0.9, 0.9, true)
		GameTooltip:AddLine("Or drag an item into the search box.", 0.9, 0.9, 0.9, true)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(Globals:Colorize(colorYellow, "Sort and filter:"), 1, 1, 1, false)
		GameTooltip:AddLine("Use sort and filters to find items faster.", 0.9, 0.9, 0.9, true)
		GameTooltip:AddLine("Reset filters when done.", 0.9, 0.9, 0.9, true)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(Globals:Colorize(colorYellow, "Donate:"), 1, 1, 1, false)
		GameTooltip:AddLine("Send items or gold by mail to the character in the tab.", 0.9, 0.9, 0.9, true)
		GameTooltip:AddLine("View top 30 donors based on total vendor value of items and gold.", 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)
	helpIcon:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

    local buttonContainer = aceGUI:Create("SimpleGroup")
    buttonContainer:SetLayout("Table")
    buttonContainer:SetUserData("table", {
        columns = {
            { width = 0.25, align = "bottomleft" },
            { width = 0.25, align = "start" },
            { width = 0.25, align = "bottomleft" },
            { width = 0.25, align = "end" },
        },
    })
    buttonContainer:SetFullWidth(true)
    window:AddChild(buttonContainer)

    local searchButton = aceGUI:Create("Button")
    searchButton:SetText("Search")
    searchButton:SetCallback("OnClick", function()
        GBCR.UI.Search:Toggle()
    end)
	searchButton:SetCallback("OnEnter", function()
		GameTooltip:SetOwner(searchButton.frame, "ANCHOR_BOTTOM")
		GameTooltip:ClearLines()
		GameTooltip:AddLine("Search all guild banks")
		GameTooltip:AddLine("Find items by name across all bank characters.", 0.9, 0.9, 0.9, true)
		GameTooltip:AddLine("Type at least 3 letters.", 0.9, 0.9, 0.9, true)
		GameTooltip:AddLine("Or drag an item into the search box.", 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)
	searchButton:SetCallback("OnLeave", function()
		GameTooltip:Hide()
	end)
    searchButton:SetWidth(160)
    searchButton:SetHeight(24)
    buttonContainer:AddChild(searchButton)

    local sortDropdown = aceGUI:Create("Dropdown")
    sortDropdown:SetLabel("Sort")
    sortDropdown:SetList(Constants.SORT_LIST, Constants.SORT_ORDER)
    sortDropdown:SetWidth(160)
    sortDropdown:SetFullWidth(false)
    sortDropdown:SetValue(GBCR.Options:GetSortMode())
    sortDropdown:SetCallback("OnValueChanged", function(_, _, value)
        GBCR.Options:SetSortMode(value)
        self.renderGeneration = (self.renderGeneration or 0) + 1
        GBCR.UI:RefreshCurrentTab()
    end)
    self.sortDropdown = sortDropdown
    buttonContainer:AddChild(sortDropdown)

	local requestsButton = aceGUI:Create("Button")
	requestsButton:SetText("Requests")
    requestsButton:SetDisabled(true)
	requestsButton:SetCallback("OnEnter", function()
		GameTooltip:SetOwner(requestsButton.frame, "ANCHOR_BOTTOM")
		GameTooltip:ClearLines()
		GameTooltip:AddLine("Request items")
		GameTooltip:AddLine("Coming soon.", 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)
	requestsButton:SetCallback("OnLeave", function()
		GameTooltip:Hide()
	end)
	requestsButton:SetWidth(160)
	requestsButton:SetHeight(24)
	buttonContainer:AddChild(requestsButton)

    local donationsButton = aceGUI:Create("Button")
    donationsButton:SetText("Donations")
    donationsButton:SetCallback("OnClick", function()
        GBCR.UI.Donations:Toggle()
    end)
	donationsButton:SetCallback("OnEnter", function()
		GameTooltip:SetOwner(donationsButton.frame, "ANCHOR_BOTTOM")
		GameTooltip:ClearLines()
		GameTooltip:AddLine("Top 30 donors")
		GameTooltip:AddLine("Based on total vendor value of items and gold.", 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)
	donationsButton:SetCallback("OnLeave", function()
		GameTooltip:Hide()
	end)
    donationsButton:SetWidth(160)
    donationsButton:SetHeight(24)
    buttonContainer:AddChild(donationsButton)

    local filterContainer = aceGUI:Create("SimpleGroup")
    filterContainer:SetLayout("Table")
    filterContainer:SetUserData("table", {
        columns = {
            { width = 0.25, align = "start" },
            { width = 0.25, align = "start" },
            { width = 0.25, align = "start" },
            { width = 0.25, align = "end" },
        },
    })
    filterContainer:SetFullWidth(true)
    window:AddChild(filterContainer)

    local filterTypeDropdown = aceGUI:Create("Dropdown")
    filterTypeDropdown:SetLabel("Type")
    filterTypeDropdown:SetList(Constants.FILTER.TYPE_LIST, Constants.FILTER.TYPE_ORDER)
    filterTypeDropdown:SetWidth(160)
    filterTypeDropdown:SetValue("any")
    filterTypeDropdown:SetCallback("OnValueChanged", function(_, _, value)
        UI_Inventory.filterType = value
        self.renderGeneration = (self.renderGeneration or 0) + 1
        GBCR.UI:RefreshCurrentTab()
    end)
    self.filterTypeDropdown = filterTypeDropdown
    filterContainer:AddChild(filterTypeDropdown)

    local filterSlotDropdown = aceGUI:Create("Dropdown")
    filterSlotDropdown:SetLabel("Slot")
    filterSlotDropdown:SetList(Constants.FILTER.SLOT_LIST, Constants.FILTER.SLOT_ORDER)
    filterSlotDropdown:SetWidth(160)
    filterSlotDropdown:SetValue("any")
    filterSlotDropdown:SetCallback("OnValueChanged", function(_, _, value)
        UI_Inventory.filterSlot = value
        self.renderGeneration = (self.renderGeneration or 0) + 1
        GBCR.UI:RefreshCurrentTab()
    end)
    self.filterSlotDropdown = filterSlotDropdown
    filterContainer:AddChild(filterSlotDropdown)

    local filterRarityDropdown = aceGUI:Create("Dropdown")
    filterRarityDropdown:SetLabel("Quality")
    filterRarityDropdown:SetList(Constants.FILTER.RARITY_LIST, Constants.FILTER.RARITY_ORDER)
    filterRarityDropdown:SetWidth(160)
    filterRarityDropdown:SetValue("any")
    filterRarityDropdown:SetCallback("OnValueChanged", function(_, _, value)
        UI_Inventory.filterRarity = value
        self.renderGeneration = (self.renderGeneration or 0) + 1
        GBCR.UI:RefreshCurrentTab()
    end)
    self.filterRarityDropdown = filterRarityDropdown
    filterContainer:AddChild(filterRarityDropdown)

    local resetButton = aceGUI:Create("Button")
    resetButton:SetText("Reset filters")
    resetButton:SetWidth(160)
    resetButton:SetHeight(24)
    resetButton:SetCallback("OnClick", function()
        self.renderGeneration = (self.renderGeneration or 0) + 1
        GBCR.UI.ResetFilters(UI_Inventory)
    end)
	resetButton:SetCallback("OnEnter", function()
		GameTooltip:SetOwner(resetButton.frame, "ANCHOR_BOTTOM")
		GameTooltip:ClearLines()
		GameTooltip:AddLine("Reset filters")
		GameTooltip:AddLine("Show all items again.", 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)
	resetButton:SetCallback("OnLeave", function()
		GameTooltip:Hide()
	end)
    resetButton:SetDisabled(true)
    self.resetFiltersButton = resetButton
    filterContainer:AddChild(resetButton)

    local tabGroup = aceGUI:Create("TabGroup")
    tabGroup:SetLayout("Flow")
    tabGroup:SetFullWidth(true)
    tabGroup:SetFullHeight(true)
    window:AddChild(tabGroup)
    self.tabGroup = tabGroup

    GBCR.UI.ResetFilters(self)
end

local function openWindow(self)
	if self.isOpen then
		return
	end

    self.isOpen = true

    if not self.window then
        drawWindow(self)
    end

    self.window:Show()

	GBCR.UI:ClampFrameToScreen(self.window)

    GBCR.UI:ForceDraw()

    GBCR.Protocol:PerformSync()
end

local function closeWindow(self)
	if not self.isOpen or not self.window then
		return
	end

    onClose(self)
end

local function toggleWindow(self)
    if self.isOpen then
        closeWindow(self)
    else
        openWindow(self)
    end
end

local function init(self)
    self.filterType = "any"
    self.filterSlot = "any"
    self.filterRarity = "any"

    self.cachedFilteredList = {}
    self.renderGeneration = 0

    drawWindow(self)
end

-- Export functions for other modules
UI_Inventory.DrawContent = drawContent
UI_Inventory.Close = closeWindow
UI_Inventory.Toggle = toggleWindow
UI_Inventory.Init = init