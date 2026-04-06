local addonName, GBCR = ...

GBCR.UI.Search = {}
local UI_Search = GBCR.UI.Search

local Globals = GBCR.Globals
local find = Globals.find
local math_min = Globals.math_min

local After = Globals.After
local ClearCursor = Globals.ClearCursor
local CreateFrame = Globals.CreateFrame
local GameTooltip = Globals.GameTooltip
local GetCursorInfo = Globals.GetCursorInfo
local Item = Globals.Item
local NewTimer = Globals.NewTimer

local Constants = GBCR.Constants
local searchResultLimit = Constants.LIMITS.SEARCH_RESULTS

local function onClose(self)
    self.isOpen = false
    self.searchText = nil
    self.renderGeneration = (self.renderGeneration or 0) + 1

    if self.searchField then
        self.searchField:SetText("")
    end

    if self.searchResults then
        self.searchResults:ReleaseChildren()
        self.searchResults:DoLayout()
    end

    if self.window then
        self.window:SetStatusText("")
        self.window:Hide()
    end
end

local function drawContent(self)
    GBCR.Output:Debug("UI", "UI_Search:DrawContent called")

    if not self.window or not self.window:IsVisible() then
		GBCR.Output:Debug("SEARCH", "UI_Search:DrawContent: early exit since window is not visible")

        return
    end

    self.searchField:SetFocus()

    GBCR.Search:BuildSearchData()
    local searchData = self.searchData
    local searchText = self.searchText

	if not self.searchResults or not searchText or not searchData then
		GBCR.Output:Debug("SEARCH", "UI_Search:DrawContent: early exit due to missing data")

		return
	end

	if string.len(searchText) < 3 then
		GBCR.Output:Debug("SEARCH", "UI_Search:DrawContent: early exit until at least 3 letters")

		return
	end

    self.renderGeneration = (self.renderGeneration or 0) + 1
    local currentGeneration = self.renderGeneration

    self.searchResults:ReleaseChildren()

	GBCR.Output:Debug("SEARCH", "Search for '%s': corpus has %d entries", searchText, #searchData.corpus)

    local count = 0
    local matchedNames = 0
    local lookup = searchData.lookup
    local corpus = searchData.corpus
    local options = GBCR.Options
    local output = GBCR.Output
    local ui = GBCR.UI
    local inventory = GBCR.Inventory
    local aceGUI = GBCR.Libs.AceGUI
    local debugEnabled = options:IsDebugEnabled() and options:IsCategoryEnabled("SEARCH")
    local searchLower = searchText:lower()
    local chunkSize = 20

    local function renderChunk(startPosition)
        if self.renderGeneration ~= currentGeneration then
            return
        end

        local endPosition = math_min(startPosition + chunkSize - 1, #corpus)

        for i = startPosition, endPosition do
            local entry = corpus[i]

            if find(entry.lower, searchLower, 1, true) then
                local itemName = entry.name
                matchedNames = matchedNames + 1

                if debugEnabled then
                    output:Debug("SEARCH", "Match #%d: '%s' contains '%s'", matchedNames, itemName, searchText)
                end

                local lookupList = lookup[itemName]
                if not lookupList and debugEnabled then
                    output:Debug("SEARCH", "Search display: '%s' matched search but has no lookup entries", itemName)
                else
                    if debugEnabled then
                        output:Debug("SEARCH", "Search display: '%s' matched search, has %d lookup entries", itemName, #lookupList)
                    end

                    for l = 1, #lookupList do
                        local lookupData = lookupList[l]
                        local resultItem = lookupData.item
                        local bankAlt = lookupData.alt

                        if not resultItem.itemInfo then
                            if debugEnabled then
                                output:Debug("SEARCH", "Search display: lazy loading of GetInfo for %s", resultItem.itemLink)
                            end

                            resultItem.itemInfo = inventory:GetInfo(resultItem.itemId, resultItem.itemLink)
                        end

                        if debugEnabled then
                            output:Debug("SEARCH", "Search display: showing %s with %d items for %s", resultItem.itemInfo and resultItem.itemInfo.name or "Unknown", resultItem.itemCount or 0, bankAlt)
                        end

                        local itemWidget = ui:DrawItem(resultItem, self.searchResults, 30, 35, 30, 30, 0, 5)
                        if itemWidget then
                            itemWidget:SetCallback("OnClick", GBCR.UI.OnClick)
                        end

                        local label = aceGUI:Create("Label")
                        label:SetText(bankAlt)
                        label.label:SetSize(170, 30)
                        label.label:SetJustifyV("MIDDLE")
                        self.searchResults:AddChild(label)

                        count = count + 1

                        if count >= searchResultLimit then
                            if debugEnabled then
                                output:Debug("SEARCH", "Results exceed limit (results=%s, limit=%s), breaking loop", count, searchResultLimit)
                            end

                            local plural = (count ~= 1 and "s" or "")
                            self.window:SetStatusText(count .. "+ result" .. plural)
                            self.searchResults:DoLayout()

                            return
                        end

                        -- Detect placeholder item and refresh asynchronously
                        if resultItem.itemInfo.name:match("^Item %d+") then
                            local loader = resultItem.itemLink and Item:CreateFromItemLink(resultItem.itemLink) or Item:CreateFromItemID(resultItem.itemId)
                            if loader then
                                local itemId = resultItem.itemId
                                local itemLink = resultItem.itemLink

                                loader:ContinueOnItemLoad(function()
                                    GBCR.UI.OnItemLoaded(itemId, itemLink, itemWidget)
                                end)
                            end
                        end
                    end
                end
            end
        end

        if endPosition < #corpus and count < searchResultLimit then
            After(0, function() renderChunk(endPosition + 1) end)
        else
            GBCR.Output:Debug("SEARCH", "Search complete: matched %d names, displayed %d result widgets", matchedNames, count)

            local plural = (count ~= 1 and "s" or "")
            self.window:SetStatusText(count .. " result" .. plural)

            self.searchResults:DoLayout()
        end
    end

    renderChunk(1)
end

local function drawWindow(self)
    local aceGUI = GBCR.Libs.AceGUI

    local searchWindow = aceGUI:Create("Frame")
    searchWindow:Hide()
    searchWindow:SetCallback("OnClose", function()
		onClose(UI_Search)
    end)
    searchWindow:SetTitle("Search")
    searchWindow:SetLayout("Flow")
    searchWindow:EnableResize(false)
    searchWindow.frame:SetSize(250, 500)
    self.window = searchWindow

    local searchLabel = searchWindow.frame:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
    searchLabel:SetTextColor(1,.82,0)
    searchLabel:SetPoint("TOPLEFT", searchWindow.frame, "TOPLEFT", 17, -19)
    searchLabel:SetHeight(44)
    searchLabel:SetText("Item name")
    self.searchLabel = searchLabel

    local instructions = "Type at least 3 letters to search"
    local searchInput = CreateFrame("EditBox", "GBankClassicSearch", searchWindow.frame, "SearchBoxTemplate")
    searchInput:SetPoint("TOPLEFT", searchWindow.frame, "TOPLEFT", 24, -51)
    searchInput:SetSize(210, 20)
    searchInput.Instructions:SetText(instructions)
    searchInput:SetScript("OnEditFocusLost", function(input)
        if input:GetText() == "" then
            UI_Search.searchField.Instructions:SetText(instructions)
        end
    end)
	searchInput:SetScript("OnEnter", function()
		GameTooltip:SetOwner(searchInput, "ANCHOR_BOTTOM")
		GameTooltip:ClearLines()
		GameTooltip:AddLine("Search all guild banks")
		GameTooltip:AddLine("Find items across all bank characters.", 0.9, 0.9, 0.9, true)
		GameTooltip:AddLine("Type at least 3 letters.", 0.9, 0.9, 0.9, true)
		GameTooltip:AddLine("Or drag an item here.", 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)
	searchInput:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
    local searchTimer
    searchInput:SetScript("OnTextChanged", function(input)
        local text = input:GetText()
        if text and text ~= "" then
            UI_Search.searchField.Instructions:SetText("")
        else
            UI_Search.searchField.Instructions:SetText(instructions)
        end
        UI_Search.searchText = text

        if text == "" then
            self.searchResults:ReleaseChildren()
            self.searchResults:DoLayout()
            self.searchField:SetFocus()
            self.window:SetStatusText("")

            return
        end

        if searchTimer then
            searchTimer:Cancel()
        end
        searchTimer = NewTimer(Constants.TIMER_INTERVALS.SEARCH_DEBOUNCE, function()
            drawContent(UI_Search)
        end)
    end)
    searchInput:SetScript("OnEnterPressed", function(input)
        local searchedText = input:GetText()
        UI_Search.searchText = searchedText
        if searchedText ~= "" then
            UI_Search.searchField:ClearFocus()
        end
    end)
    searchInput:SetScript("OnReceiveDrag", function()
        local type, _, info = GetCursorInfo()

        if info then
            local itemName = info:match("%[(.+)%]")

            if type == "item" and itemName then
                UI_Search.searchText = itemName
                UI_Search.searchField:SetText(itemName)
                ClearCursor()
                UI_Search.searchField:ClearFocus()
            end
        end
    end)
    self.searchField = searchInput

    local scrollGroup = aceGUI:Create("SimpleGroup")
    scrollGroup:SetLayout("Fill")
    scrollGroup:SetFullWidth(true)
    scrollGroup:SetFullHeight(true)
    searchWindow:AddChild(scrollGroup)

    local resultGroup = aceGUI:Create("ScrollFrame")
    resultGroup:SetLayout("Table")
    resultGroup:SetUserData("table", {
        columns = {
            {
                width = 30,
                align = "middle",
            },
            {
                align = "start",
            },
        },
        spaceH = 5,
    })
    resultGroup.scrollframe:ClearAllPoints()
    resultGroup.scrollframe:SetPoint("TOPLEFT", 4, -51)
    resultGroup.scrollbar:ClearAllPoints()
    resultGroup.scrollbar:SetPoint("TOPLEFT", resultGroup.scrollframe, "TOPRIGHT", 2, -12)
    resultGroup.scrollbar:SetPoint("BOTTOMLEFT", resultGroup.scrollframe, "BOTTOMRIGHT", 2, 22)
    scrollGroup:AddChild(resultGroup)
    self.searchResults = resultGroup
end

local function openWindow(self)
	if self.isOpen then
		return
	end

    self.isOpen = true

    if not self.window then
        drawWindow(self)
    end

    GBCR.Search:BuildSearchData()

    self.window:Show()

    if GBCR.UI.Inventory.isOpen and GBCR.UI.Inventory.window then
        self.window:ClearAllPoints()
        self.window:SetPoint("TOPRIGHT", GBCR.UI.Inventory.window.frame, "TOPLEFT", 0, 0)
    end

	GBCR.UI:ClampFrameToScreen(self.window)

    GBCR.UI:ForceDraw()
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
    drawWindow(self)
end

-- Export functions for other modules
UI_Search.DrawContent = drawContent
UI_Search.Close = closeWindow
UI_Search.Toggle = toggleWindow
UI_Search.Init = init