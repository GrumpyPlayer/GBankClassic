local addonName, GBCR = ...

GBCR.UI.Search = {}
local UI_Search = GBCR.UI.Search

local Globals = GBCR.Globals
local GetCursorInfo = Globals.GetCursorInfo
local ClearCursor = Globals.ClearCursor
local IsShiftKeyDown = Globals.IsShiftKeyDown
local IsControlKeyDown = Globals.IsControlKeyDown
local CreateFrame = Globals.CreateFrame
local GameTooltip = Globals.GameTooltip
local Item = Globals.Item

function UI_Search:Init()
    self:DrawWindow()
end

function UI_Search:Toggle()
    if self.isOpen then
        self:Close()
    else
        self:Open()
    end
end

function UI_Search:Open()
	if self.isOpen then
		return
	end

    self.isOpen = true

    if not self.Window then
        self:DrawWindow()
    end

	-- Rebuild search data when guild roster version changes
	-- Track roster version to detect when new data arrives (after /wipe, sync, etc.)
	local currentVersion = GBCR.Database.savedVariables and GBCR.Database.savedVariables.roster and GBCR.Database.savedVariables.roster.version or 0
	local needsRebuild = not self.searchDataBuilt or (self.lastRosterVersion ~= currentVersion)
	if needsRebuild then
		GBCR.Output:Debug("SEARCH", "Rebuilding search data (version changed: %s -> %s)", tostring(self.lastRosterVersion or "nil"), tostring(currentVersion))
		self:BuildSearchData()
		self.searchDataBuilt = true
		self.lastRosterVersion = currentVersion
	end

    self.Window:Show()
    if GBCR.UI.Inventory.isOpen and GBCR.UI.Inventory.Window then
        self.Window:ClearAllPoints()
        self.Window:SetPoint("TOPRIGHT", GBCR.UI.Inventory.Window.frame, "TOPLEFT", 0, 0)
    end

	GBCR.UI:ClampFrameToScreen(self.Window)

    self:DrawContent()

    self.searchField:SetFocus()
end

function UI_Search:Close()
	if not self.isOpen then
		return
	end
	if not self.Window then
		return
	end

    self:OnClose()
end

function UI_Search:OnClose()
    self.isOpen = false
    if self.Window then
        self.Window:Hide()
    end
end

function UI_Search:DrawWindow()
    local searchWindow = GBCR.Libs.AceGUI:Create("Frame")
    searchWindow:Hide()
    searchWindow:SetCallback("OnClose", function()
        self:OnClose()
    end)
    searchWindow:SetTitle("Search")
    searchWindow:SetLayout("Flow")
    searchWindow:EnableResize(false)
    searchWindow.frame:SetSize(250, 500)
    self.Window = searchWindow

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
            self.searchField.Instructions:SetText(instructions)
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
		GBCR.UI:HideTooltip()
	end)
    searchInput:SetScript("OnTextChanged", function(input)
        local text = input:GetText()
        if text and text ~= "" then
            UI_Search.searchField.Instructions:SetText("")
        else
            UI_Search.searchField.Instructions:SetText(instructions)
        end
        UI_Search.searchText = text
        UI_Search:DrawContent()
    end)
    searchInput:SetScript("OnEnterPressed", function(input)
        UI_Search.searchText = input:GetText()
        UI_Search:DrawContent()
        UI_Search.searchField:ClearFocus()
    end)
    searchInput:SetScript("OnReceiveDrag", function()
        local type, _, info = GetCursorInfo()
        local itemName = info:match("%[(.+)%]")
        if type == "item" and itemName then
            UI_Search.searchText = itemName
            UI_Search:DrawContent()
            ClearCursor()
            UI_Search.searchField:ClearFocus()
        end
    end)
    self.searchField = searchInput

    local scrollGroup = GBCR.Libs.AceGUI:Create("SimpleGroup")
    scrollGroup:SetLayout("Fill")
    scrollGroup:SetFullWidth(true)
    scrollGroup:SetFullHeight(true)
    searchWindow:AddChild(scrollGroup)

    local resultGroup = GBCR.Libs.AceGUI:Create("ScrollFrame")
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
    self.Results = resultGroup
end

function UI_Search:DrawContent()
    GBCR.Output:Debug("UI", "UI_Search:DrawContent called")
	if not self.Results then
		return
	end

    self.Results:ReleaseChildren()
    self.Window:SetStatusText("")
    self.Results:DoLayout()

	if not self.searchText then
		return
	end

    if self.searchText then
        self.searchField:SetText(self.searchText)
        local searchLength = string.len(self.searchText)
        self.searchField:SetCursorPosition(searchLength)
    end

    local search = self.searchText
    if search and string.sub(search, 0, 2) == "|c" then
        self.searchField:SetText("")
        local item = Item:CreateFromItemLink(search)
		if item and item.itemId then
			item:ContinueOnItemLoad(function()
				local name = item:GetItemName()
				if name then
					self.searchText = name
					self.searchField:SetText(name)
					self:DrawContent()
					self.searchField:ClearFocus()
				end
			end)
		end

		return
    end

    local searchText = search:lower()
	if string.len(searchText) < 3 then
		return
	end

    local searchData = self.SearchData
	if not searchData then
		return
	end

	GBCR.Output:Debug("SEARCH", "Search for '%s': Corpus has %d entries", searchText, #searchData.Corpus)

    local count = 0
	local matchedNames = 0
    for _, v in pairs(searchData.Corpus) do
        if v then
            local result = string.find(v:lower(), searchText)
            if result ~= nil then
				matchedNames = matchedNames + 1
				GBCR.Output:Debug("SEARCH", "Match #%d: '%s' contains '%s'", matchedNames, v, searchText)
                local lookupList = searchData.Lookup[v]
                if not lookupList then
					GBCR.Output:Debug("SEARCH", "Search display: '%s' matched search but has NO lookup entries", v)
                else
					local lookupCount = Globals:Count(lookupList)
					GBCR.Output:Debug("SEARCH", "Search display: '%s' matched search, has %d lookup entries", v, lookupCount)
                    for _, vv in pairs(lookupList) do
						local resultItem = vv.item
						local bankAlt = vv.alt
						GBCR.Output:Debug("SEARCH", "Search display: showing %s with %d items for %s", resultItem.itemInfo and resultItem.itemInfo.name or "Unknown", resultItem.Count or 0, bankAlt)
						local itemWidget = GBCR.UI:DrawItem(resultItem, self.Results, 30, 35, 30, 30, 0, 5)
						if itemWidget then
							itemWidget:SetCallback("OnClick", function(self, event)
								if IsShiftKeyDown() or IsControlKeyDown() then
									GBCR.UI:EventHandler(self, event)

									return
								end
							end)
						end

                        local label = GBCR.Libs.AceGUI:Create("Label")
                        label:SetText(bankAlt)
                        label.label:SetSize(170, 30)
                        label.label:SetJustifyV("MIDDLE")
                        self.Results:AddChild(label)

                        count = count + 1
                    end
                end
            end
        end
    end

	GBCR.Output:Debug("SEARCH", "Search complete: matched %d names, displayed %d result widgets", matchedNames, count)

    local plural = (count ~= 1 and "s" or "")
    self.Window:SetStatusText(count .. " result" .. plural)

    self.Results:DoLayout()
end

function UI_Search:BuildSearchData()
    -- TODO: ideally this is only done for the guild bank alts with changed data instead of always rebuild the entire corpus for the smallest change
	GBCR.Output:Debug("SEARCH", "BuildSearchData called - clearing and rebuilding search data")
    self.SearchData = {
        Corpus = {},
        Lookup = {},
    }

    local info = GBCR.Database.savedVariables
	local roster_alts = GBCR.Guild:GetRosterGuildBankAlts()
	if not info or not roster_alts then
		GBCR.Output:Debug("SEARCH", "BuildSearchData: no info or roster_alts, returning early")

		return
	end

	local rosterCount = #roster_alts
	GBCR.Output:Debug("SEARCH", "BuildSearchData: processing %d roster alts", rosterCount)

    local items = {}
	for i = 1, #roster_alts do
        local guildBankAltName = roster_alts[i]
		local norm = GBCR.Guild:NormalizeName(guildBankAltName) or guildBankAltName
        local alt = info.alts[norm]
		GBCR.Output:Debug("SEARCH", "Search corpus loop: processing guildBankAltName=%s, norm=%s, has alt=%s", guildBankAltName, norm, tostring(alt ~= nil))
        if alt and type(alt) == "table" then
			if alt.items and next(alt.items) ~= nil then
				local beforeCount = #items
				items = GBCR.Inventory:Aggregate(items, alt.items)
				local afterCount = #items
				GBCR.Output:Debug("SEARCH", "Search corpus: using alt.items for %s (%d items before, %d after aggregation)", guildBankAltName, beforeCount, afterCount)
			end
        end
    end

    local itemNames = {}
	local corpusNamesSeen = {}

	-- Count items in hash table
	local itemCount = Globals:Count(items)
	GBCR.Output:Debug("SEARCH", "About to validate %d items before GetItems", itemCount)

	-- Validate and filter items before passing to GetItems
	local validItems = {}
	local invalidCount = 0
	for key, item in pairs(items) do
		if item and item.itemId and item.itemId > 0 then
			table.insert(validItems, item)
		else
			invalidCount = invalidCount + 1
			GBCR.Output:Debug("SEARCH", "WARNING: Skipping invalid item at key %s (itemId: %s, itemLink: %s)", tostring(key), tostring(item and item.itemId or "nil item"), tostring(item and item.itemLink or "nil"))
		end
	end

	GBCR.Output:Debug("SEARCH", "Passing %d valid items to GetItems (%d invalid skipped)", #validItems, invalidCount)

	GBCR.Inventory:GetItems(validItems, function(list)
		local listCount = Globals:Count(list)
		GBCR.Output:Debug("SEARCH", "GetItems callback fired with %d items", listCount)
        for _, v in pairs(list) do
            -- Skip malformed list entries
			if v and v.itemId and v.itemInfo and v.itemInfo.name then
				local itemIdentity = tostring(v.itemId)

				-- For weapons/armor, include link key to catch suffix differences
				if v.itemLink and GBCR.Inventory:NeedsLink(v.itemLink) then
					local linkKey = GBCR.Inventory:GetItemKey(v.itemLink)
					if linkKey and linkKey ~= "" then
						itemIdentity = linkKey
					end
				end

				-- Map item identity to name (for lookup table building later)
				if not itemNames[itemIdentity] then
					itemNames[itemIdentity] = v.itemInfo.name
				end

				-- Only add each unique name to corpus once
				if not corpusNamesSeen[v.itemInfo.name] then
					corpusNamesSeen[v.itemInfo.name] = true
					table.insert(self.SearchData.Corpus, v.itemInfo.name)
					GBCR.Output:Debug("SEARCH", "Corpus: added unique name '%s' (itemId: %d)", v.itemInfo.name, v.itemId)
				else
					GBCR.Output:Debug("SEARCH", "Corpus: skipping duplicate name '%s' (itemId: %d already in corpus)", v.itemInfo.name, v.itemId)
				end
			end
        end

        for i = 1, #roster_alts do
            local player = roster_alts[i]
            local altItems = {}
			local norm = GBCR.Guild:NormalizeName(player) or player
            local alt = info.alts[norm]
			GBCR.Output:Debug("SEARCH", "Search results loop: processing player=%s, norm=%s, has alt=%s", player, norm, tostring(alt ~= nil))
            if alt and type(alt) == "table" then
				if alt.items and next(alt.items) ~= nil then
					for _, item in pairs(alt.items) do
						table.insert(altItems, item)
					end
					GBCR.Output:Debug("SEARCH", "Search results: using alt.items for %s", player)
				end
            end

            for _, itemEntry in pairs(altItems) do
				local itemIdentity = tostring(itemEntry.itemId)

				-- For weapons/armor, include link key to catch suffix differences
				if itemEntry.itemLink and GBCR.Inventory:NeedsLink(itemEntry.itemLink) then
					local linkKey = GBCR.Inventory:GetItemKey(itemEntry.itemLink)
					if linkKey and linkKey ~= "" then
						itemIdentity = linkKey
					end
				end

                local name = itemNames[itemIdentity]
                if name then
					GBCR.Output:Debug("SEARCH", "Search results: adding %s with count %d for player %s to lookup", name, itemEntry.itemId or 0, player)
                    if not self.SearchData.Lookup[name] then
                        self.SearchData.Lookup[name] = {}
                    end
                    local found = false
                    for _, existingEntry in pairs(self.SearchData.Lookup[name]) do
						if existingEntry.alt == player and existingEntry.item.itemLink and itemEntry.itemLink and existingEntry.item.itemLink == itemEntry.itemLink then
                            found = true
							GBCR.Output:Debug("SEARCH", "Search results: duplicate found - skipping %s (itemId: %d) for %s", name, itemEntry.itemId, player)
                            break
						elseif existingEntry.alt == player and not existingEntry.item.itemLink and not itemEntry.itemLink and existingEntry.item.itemId == itemEntry.itemId then
                            found = true
							GBCR.Output:Debug("SEARCH", "Search results: duplicate found - skipping %s (itemId: %d) for %s", name, itemEntry.itemId, player)
                            break
                        end
                    end
                    if not found then
                        local itemInfo = GBCR.Inventory:GetInfo(itemEntry.itemId, itemEntry.itemLink)
                        table.insert(self.SearchData.Lookup[name], { alt = player, item = { itemId = itemEntry.itemId, itemCount = itemEntry.itemCount, itemLink = itemEntry.itemLink, itemInfo = itemInfo } })
                    end
                end
            end
        end
    end)
end